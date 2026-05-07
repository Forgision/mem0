# Mem0 OSS: `/api/auth/refresh` login/session refresh failure

**Service:** Mem0 OSS Dashboard
**Environment:** `https://mem0.ocsys.duckdns.org`
**Date observed:** 2026-05-06
**Severity:** High — users can log in, but session refresh breaks and the UI eventually loses authentication
**Status:** Fixed in the `fix/refresh-route` branch

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

## Errors observed (chronological)

### Error 1: 405 Method Not Allowed on `PUT /api/auth/refresh`
When NGINX split `/api/*` to FastAPI directly, the browser's `PUT` request (meant for the Next.js BFF cookie store) hit FastAPI which only accepts `POST`.

### Error 2: 404 on `POST /api/auth/login`
After routing all traffic through the dashboard (fixing Error 1), the Next.js dashboard had no route handler for `/api/auth/login`. Only `/api/auth/refresh` and `/api/health` had BFF routes. All other `/api/*` paths returned 404.

### Error 3: 404 on `POST /auth/login` (no `/api` prefix)
When `NEXT_PUBLIC_API_URL` was set to bare domain `https://mem0.ocsys.duckdns.org` (missing `/api` suffix), the axios client built URLs without the `/api` prefix. The request hit the middleware which redirected to `/login?next=/auth/login` (307), then the page route returned 405. In other cases Next.js returned 404 directly because no route matched `/auth/login`.

---

## Root cause analysis

### Architecture
```text
Browser → Next.js Dashboard (BFF)
           ├─ /api/auth/refresh  → specific BFF route (POST/PUT/DELETE for cookie mgmt)
           ├─ /api/health         → specific route (static response)
           └─ /api/*              → catch-all proxy → FastAPI backend
```

### Why each error happened

**Error 1 (405):** NGINX bypassed the dashboard BFF and sent `/api/*` directly to FastAPI. The browser's `PUT /api/auth/refresh` (meant to store a cookie in the BFF) hit FastAPI which only has `POST /auth/refresh`.

**Error 2 (404):** Routing fixed to go through dashboard, but dashboard only had BFF routes for refresh and health. No handler for login, register, me, memories, etc.

**Error 3 (404/405):** `NEXT_PUBLIC_API_URL` set to bare domain without `/api` suffix. Browser sent requests to `/auth/login` instead of `/api/auth/login`. The catch-all proxy only handles `/api/*`.

---

## Code changes applied (DO NOT REVERT)

### 1. Catch-all API proxy: `server/dashboard/src/app/api/[...path]/route.ts`
**New file.** Proxies all unhandled `/api/*` requests to FastAPI backend via `API_INTERNAL_URL`.

Why: The dashboard BFF only had specific routes for `/api/auth/refresh` and `/api/health`. All other API calls (login, register, memories, etc.) had no handler → 404. This catch-all forwards them to the FastAPI backend while specific BFF routes keep priority.

Route priority in Next.js:
- `/api/auth/refresh/route.ts` (specific) → handles cookie-based token refresh
- `/api/health/route.ts` (specific) → returns static health response
- `/api/[...path]/route.ts` (catch-all) → proxies everything else to FastAPI

### 2. Middleware update: `server/dashboard/src/middleware.ts`
Changed `PUBLIC_PATHS` from `["/_next", "/api/auth", "/api/health", ...]` to `["/_next", "/api", ...]`.

Why: Only `/api/auth` and `/api/health` were public paths. Other API calls like `/api/memories`, `/api/auth/login` went through the auth check and got redirected to `/login` (a page redirect, not an API response). Widening to `/api` lets all API paths pass through — API endpoints handle their own auth via JWT.

### 3. Configurable env: `server/docker-compose.yaml` + `server/.env.example`
- `DASHBOARD_URL` now reads from `.env` (was hardcoded)
- `DASHBOARD_PORT` configurable, defaults to 3000
- `NEXT_PUBLIC_API_URL` configurable via `.env`
- Dashboard service uses `env_file` for full `.env` passthrough

---

## Required deployment configuration

### `.env` settings
```env
NEXT_PUBLIC_API_URL=/api
DASHBOARD_URL=https://mem0.ocsys.duckdns.org
API_INTERNAL_URL=http://mem0:8000
```

**Critical:** `NEXT_PUBLIC_API_URL` MUST include the `/api` prefix. The dashboard's `entrypoint.sh` does runtime sed substitution on `.next/` files to replace the build-time placeholder. Setting it without `/api` causes the browser to send requests to `/auth/login` instead of `/api/auth/login`, bypassing both the middleware public path check and the catch-all proxy.

### NGINX Proxy Manager
Route ALL traffic through the dashboard only:
- `mem0.ocsys.duckdns.org` → `10.250.1.13:3333`
- Do **not** split `/api` at the NPM layer

---

## Validation checklist

1. Set `NEXT_PUBLIC_API_URL=/api` in `.env`
2. Restart dashboard container (`docker compose up -d mem0-dashboard`)
3. Confirm browser calls `https://mem0.ocsys.duckdns.org/api/...`
4. Confirm `POST /api/auth/login` returns 200 (not 404)
5. Confirm `POST /api/auth/refresh` returns 200 (not 405)
6. Confirm session refresh works after page reload

---

## Notes for future changes

- `NEXT_PUBLIC_API_URL` must always end with `/api` — the catch-all proxy only handles `/api/*` paths
- The catch-all proxy must not be removed — it handles all non-BFF API routes (login, register, memories, entities, etc.)
- The middleware `PUBLIC_PATHS` must include `/api` (not just `/api/auth` and `/api/health`)
- If adding new BFF routes under `/api/`, they automatically take priority over the catch-all
- Keep the public browser origin stable; avoid mixing `localhost`, WireGuard IPs, and the public domain in production
