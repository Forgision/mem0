# Fix CORS Issues Using Next.js Rewrites

**Date:** 2026-05-15
**Status:** Approved
**Scope:** `openmemory/ui`, `openmemory/docker-compose.yml`

---

## Problem

When the OpenMemory UI is accessed from a non-localhost origin (e.g., deployed server, LAN IP), the browser blocks API calls to the backend (`:8765`) due to CORS policy.

The backend has `allow_origins=["*"]` with `allow_credentials=True`, which browsers reject — the spec forbids wildcard origin with credentials. It works on localhost because browsers relax same-site rules for `localhost ↔ localhost`.

## Solution

Use **Next.js rewrites** to proxy `/api/*` requests from the browser to the uvicorn backend. Since both the UI and API are served from the same origin (the Next.js server), no CORS preflight is triggered.

MCP clients continue to connect directly to uvicorn on `:8765` — no changes needed there.

```
Browser ──→ Next.js (:3000)
              ├─ /api/*  → rewrite to uvicorn :8765 (same-origin proxy)
              └─ /*      → serve UI (SSR/static)

MCP clients ──→ uvicorn (:8765) directly
```

## Why This Approach

| Alternative | Why not |
|---|---|
| Nginx reverse proxy (one container) | Adds nginx + supervisord overhead, complex Dockerfile |
| Fix CORS on backend (`allow_origins` to specific origin) | Must configure per deployment, still cross-origin |
| Caddy reverse proxy | Heavier image, overkill for this |

Next.js rewrites are built-in, zero-dependency, and run at the edge/server level — no extra processes needed.

## Changes

### 1. `openmemory/ui/next.config.mjs` — Add rewrites

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8765/api/:path*",
      },
    ];
  },
};

export default nextConfig;
```

This is also applied to `next.config.dev.mjs` for local development.

### 2. Hook files — Change URL fallback to empty string

Each hook file has a line like:

```typescript
const URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8765";
```

Change to:

```typescript
const URL = process.env.NEXT_PUBLIC_API_URL || "";
```

This makes all axios calls use relative paths (e.g., `/api/v1/memories`), which the Next.js rewrite proxies to uvicorn.

**Files to change:**

| File | 
|---|
| `ui/hooks/useConfig.ts` |
| `ui/hooks/useMemoriesApi.ts` |
| `ui/hooks/useAppsApi.ts` |
| `ui/hooks/useFiltersApi.ts` |
| `ui/hooks/useStats.ts` |

Additional files that reference `NEXT_PUBLIC_API_URL` should also be checked:

| File | Action |
|---|---|
| `ui/components/dashboard/Install.tsx` | Check usage, update if needed |
| `ui/components/form-view.tsx` | Check usage, update if needed |

### 3. `openmemory/docker-compose.yml` — Remove NEXT_PUBLIC_API_URL

```yaml
openmemory-ui:
  build:
    context: ui/
    dockerfile: Dockerfile
  image: mem0/openmemory-ui:latest
  ports:
    - "3000:3000"
  environment:
    - NEXT_PUBLIC_USER_ID=${USER}
  # NEXT_PUBLIC_API_URL removed — browser calls are same-origin via rewrites
```

### 4. `openmemory/ui/entrypoint.sh` — No change needed

The `sed` loop replaces all `NEXT_PUBLIC_` env vars. Since we're removing `NEXT_PUBLIC_API_URL` from the compose env, there's nothing to replace. Other vars like `NEXT_PUBLIC_USER_ID` continue to work.

## What Does NOT Change

- **Backend code** — No changes to `api/main.py` or any router
- **MCP endpoints** — MCP clients still connect to `:8765` directly
- **Dockerfile** — No new stages, no nginx, no supervisord
- **Qdrant** — Separate service, untouched
- **Redux store** — No structural changes

## How Rewrites Work (for context)

Next.js rewrites are **server-side** — the browser never sees the destination. Flow:

1. Browser requests `GET /api/v1/memories`
2. Next.js server matches `/api/:path*` rewrite rule
3. Next.js server proxies request to `http://localhost:8765/api/v1/memories`
4. Response is returned to the browser — same origin, no CORS

This works for all HTTP methods (GET, POST, PUT, DELETE) and preserves request bodies and headers.

## Deployment Impact

- Users access the UI on port `:3000` as before
- API calls from the browser go through port `:3000` (rewritten)
- MCP clients continue to connect to port `:8765` directly
- Both ports must remain exposed

## Testing

1. Deploy with docker-compose
2. Open UI in browser from a non-localhost origin
3. Verify memories load (no CORS errors in console)
4. Verify MCP client can still connect to `:8765/mcp/...`
5. Verify config, stats, and filter pages work
