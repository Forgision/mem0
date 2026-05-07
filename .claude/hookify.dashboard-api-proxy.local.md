---
name: protect-dashboard-api-routing
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: dashboard/src/app/api/\[\.\.\.path\]/route\.ts
  - field: old_text
    operator: regex_match
    pattern: .
action: warn
---

**DO NOT modify or remove the catch-all API proxy without understanding the impact.**

This file is a critical fix for Mem0 OSS dashboard auth routing. Removing or breaking it will cause:
- 404 on `POST /api/auth/login` (login broken)
- 404 on all non-BFF API routes (memories, entities, api-keys, etc.)

The catch-all proxies unhandled `/api/*` requests to the FastAPI backend. Specific BFF routes (`/api/auth/refresh`, `/api/health`) keep priority.

See `bug.md` in the repo root for full context.
