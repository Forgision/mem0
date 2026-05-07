---
name: protect-dashboard-middleware-public-paths
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: dashboard/src/middleware\.ts
  - field: new_text
    operator: regex_match
    pattern: PUBLIC_PATHS
action: warn
---

**Careful modifying PUBLIC_PATHS in dashboard middleware.**

The value must include `"/api"` (not just `"/api/auth"` and `"/api/health"`). If narrowed back, API calls like `/api/memories`, `/api/auth/login` will hit the auth check and get redirected to `/login` (a page redirect) instead of being proxied to FastAPI.

See `bug.md` in the repo root for full context.
