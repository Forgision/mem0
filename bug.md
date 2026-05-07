# Mem0 OSS: `/api/auth/refresh` login/session refresh failure

**Service:** Mem0 OSS Dashboard
**Environment:** `https://mem0.ocsys.duckdns.org`
**Date observed:** 2026-05-06
**Severity:** High — users can log in, but session refresh breaks and the UI eventually loses authentication
**Status:** Fixed in the `sach` branch / deployment pattern below

> Secrets and token values below are redacted in this record.

---

## Current setup

### System A
- Ubuntu ARM server
- WireGuard subnet: `10.250.1.0/24`
- NGINX Proxy Manager hosted here

### System B
- Ubuntu ARM server
- Mem0 OSS hosted here
- WireGuard IP: `10.250.1.13`
- Public domain through NGINX Proxy Manager: `https://mem0.ocsys.duckdns.org`

### Client
- WireGuard IP: `10.250.1.17`

### Topology in use
- Browser reaches Mem0 through NGINX Proxy Manager on System A
- NGINX Proxy Manager reaches System B over WireGuard
- Dashboard is exposed on host port `3333`
- API is exposed on host port `8888`

---

## Compose / environment snapshot

### Docker Compose
```yaml
name: mem0-dev

services:
  mem0:
    build:
      context: ..
      dockerfile: server/dev.Dockerfile
    ports:
      - "8888:8000"
    env_file:
      - .env
    networks:
      - mem0_network
    volumes:
      - ./history:/app/history
      - .:/app
    depends_on:
      postgres:
        condition: service_healthy
    command: >
      sh -c "rm -rf /app/packages && pip install -q --force-reinstall --no-deps mem0ai && alembic upgrade head && uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
    environment:
      - PYTHONDONTWRITEBYTECODE=1
      - PYTHONUNBUFFERED=1
      - PYTHONPATH=
      - DASHBOARD_URL=${DASHBOARD_URL:-https://mem0.ocsys.duckdns.org}
      - APP_DB_NAME=${APP_DB_NAME:-mem0_app}
      - JWT_SECRET=${JWT_SECRET}
      - AUTH_DISABLED=${AUTH_DISABLED:-true}
      - MEM0_TELEMETRY=${MEM0_TELEMETRY:-false}

  postgres:
    image: ankane/pgvector:v0.5.1
    restart: on-failure
    shm_size: "128mb"
    networks:
      - mem0_network
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-d", "postgres", "-U", "postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    volumes:
      - postgres_db:/var/lib/postgresql/data
      - ./init-db.sh:/docker-entrypoint-initdb.d/init-db.sh
    ports:
      - "8432:5432"

  mem0-dashboard:
    build: ./dashboard
    ports:
      - "3333:3000"
    networks:
      - mem0_network
    environment:
      - NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL:-https://mem0.ocsys.duckdns.org/api}
      - API_INTERNAL_URL=http://mem0:8000
      - NEXT_PUBLIC_INSTANCE_NAME=Mem0
    depends_on:
      mem0:
        condition: service_started
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://mem0-dashboard:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  postgres_db:

networks:
  mem0_network:
    driver: bridge
```

### `.env`
```env
OPENAI_API_KEY=<redacted>
OPENAI_BASE_URL=https://gm.ocsys.duckdns.org/v1

POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_COLLECTION_NAME=mem0

ADMIN_API_KEY=<redacted>
JWT_SECRET=<redacted>

AUTH_DISABLED=false
DASHBOARD_URL=https://mem0.ocsys.duckdns.org
NEXT_PUBLIC_API_URL=https://mem0.ocsys.duckdns.org/api
APP_DB_NAME=mem0_app

MEM0_DEFAULT_LLM_MODEL=gemini-2.5-flash-lite
MEM0_DEFAULT_EMBEDDER_MODEL=gemini-embedding-001
MEM0_TELEMETRY=false
REQUEST_LOG_RETENTION_DAYS=30
```

---

## Symptom

The browser can reach the app, but login/session refresh fails during `/api/auth/refresh`.

A representative failing request is:

```bash
curl.exe "https://mem0.ocsys.duckdns.org/api/auth/refresh" ^
  -X PUT ^
  -H "Origin: https://mem0.ocsys.duckdns.org" ^
  -H "Content-Type: application/json" ^
  --data-raw "{\"refresh_token\":\"<redacted>\"}"
```

Observed result:
- `405 Method Not Allowed` when using `PUT`
- If the client uses `POST` but sends no refresh token body, `422 Unprocessable Entity` can occur
- The session does not refresh cleanly, so the UI eventually loses auth state

---

## Root cause

### 1) Wrong HTTP method for the refresh route
The Mem0 auth refresh endpoint is implemented as `POST /auth/refresh`, not `PUT`. When the browser or client sends `PUT`, FastAPI returns `405 Method Not Allowed`.

### 2) NGINX routing was sending `/api/*` directly to the backend
The NGINX Proxy Manager config was proxying `/api/` straight to the FastAPI container at `10.250.1.13:8888`. That bypasses the dashboard-side API behavior and makes the browser depend on the backend route shape and method support directly.

### 3) Origin and cookie/auth coupling
Mem0’s server CORS is tied to `DASHBOARD_URL`, so the browser must use one stable public origin. Split-origin or mixed localhost/public URLs will trigger CORS or auth state problems.

### 4) Client build-time API URL mismatch
`NEXT_PUBLIC_*` values are baked into the dashboard at build time. Changing `NEXT_PUBLIC_API_URL` in `.env` without rebuilding the dashboard can leave the browser calling the old endpoint.

---

## What the server code is doing

### `server/main.py`
- Enables FastAPI CORS middleware
- CORS origin is derived from `DASHBOARD_URL`
- This means the browser must use the same public dashboard origin that the server expects

### `server/routers/auth.py`
- Refresh endpoint is `POST /auth/refresh`
- The route does **not** accept `PUT` in the baseline flow
- The refresh request expects a valid `refresh_token` payload

### Dashboard-side client flow
- Browser-visible requests should go through the dashboard origin
- Public API URL should be same-origin (`/api`) rather than a separate host/port
- If the dashboard bundle is not rebuilt after changing `NEXT_PUBLIC_API_URL`, the browser can continue to call an outdated endpoint

---

## Why the earlier NPM split caused trouble

The old NPM split looked like this:

```text
Browser → NGINX
  ├─ / → dashboard:3000
  └─ /api/* → fastapi:8888
```

That pattern is fragile for Mem0 because:
- browser requests become cross-path / cross-origin sensitive
- auth refresh is method-sensitive
- refresh payloads must be preserved exactly
- cookie and CORS assumptions must stay aligned across dashboard and API

---

## Robust fix

The safest fix is to make the browser see **one public origin only** and keep Mem0’s dashboard in control of the API flow.

### Recommended architecture
```text
Browser → NGINX → Dashboard:3000
                     ├─ /api/auth/refresh → dashboard BFF / auth route
                     └─ /api/* → dashboard catch-all proxy → FastAPI (internal)
```

### Required changes

#### 1) Keep the public API path same-origin
Set the dashboard API URL to a relative path:

```env
NEXT_PUBLIC_API_URL=/api
```

Then rebuild the dashboard image so the client bundle picks it up.

#### 2) Point dashboard CORS to the public dashboard URL
```env
DASHBOARD_URL=https://mem0.ocsys.duckdns.org
```

#### 3) Keep internal backend access separate from browser access
```env
API_INTERNAL_URL=http://mem0:8000
```

#### 4) Make the refresh handler tolerant during rollout
For maximum compatibility, the refresh endpoint should accept the current client behavior and the corrected one:
- `POST` as the intended method
- temporary `PUT` compatibility if an older client is still sending it
- refresh token read from body, with cookie fallback if used in the dashboard flow

#### 5) Route only the dashboard through NPM at the edge
In NGINX Proxy Manager, forward the public host to the dashboard service only:
- `mem0.ocsys.duckdns.org` → `10.250.1.13:3333`
- do **not** split `/api` at the NPM layer

---

## Safer NGINX Proxy Manager configuration

### Edge proxy host
- Domain: `mem0.ocsys.duckdns.org`
- Forward hostname/IP: `10.250.1.13`
- Forward port: `3333`

### No custom `/api` location in NPM
The dashboard should own `/api/*` behavior.

If a custom location is still present, the minimal proxy must preserve headers and path:

```nginx
location /api/ {
    proxy_pass http://10.250.1.13:8888/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffering off;
}
```

But the stronger fix is to remove this split and let the dashboard handle `/api/*` itself.

---

## Validation checklist

1. Rebuild the dashboard after setting `NEXT_PUBLIC_API_URL=/api`
2. Confirm the browser calls `https://mem0.ocsys.duckdns.org/api/...`
3. Confirm `/api/auth/refresh` uses `POST`
4. Confirm the dashboard origin matches `DASHBOARD_URL`
5. Confirm refresh succeeds after a page reload
6. Confirm login no longer falls back to a broken refresh cycle

---

## Outcome

After the fix:
- no more `405` from sending `PUT` to refresh
- no more origin mismatch between dashboard and backend
- no more split-origin auth fragility
- session refresh remains stable after reload

---

## Notes for future changes

- Any change to `NEXT_PUBLIC_API_URL` requires rebuilding the dashboard image
- If a proxy ever forwards the browser directly to FastAPI for `/api/auth/refresh`, the method and payload must still match the backend route exactly
- Keep the public browser origin stable; avoid mixing `localhost`, WireGuard IPs, and the public domain in production
