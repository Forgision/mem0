# Local Dev `make run` Command

**Date:** 2026-05-16
**Status:** Draft

## Context

All existing Makefile targets run services inside Docker containers. Local development requires rebuilding images for every code change. A `make run` target enables hot-reload development: Qdrant in Docker, backend and frontend running natively.

## Design

### New Files

| File | Purpose |
|------|---------|
| `openmemory/scripts/run-dev.sh` | Start Qdrant + backend + frontend |
| `openmemory/scripts/stop-dev.sh` | Stop all processes |
| `openmemory/logs/.gitignore` | Ignore `*.log`, `*.pid` |

### `make run`

Calls `bash openmemory/scripts/run-dev.sh`. The script:

1. Determines `OPENMEMORY_DIR` from its own path (`$(dirname "$0")/..`)
2. Creates `logs/` dir if missing
3. **Truncates** log files (`logs/backend.log`, `logs/frontend.log`) — fresh each run
4. Starts Qdrant: `docker compose -f docker-compose-dev.yml up -d om-store`
5. Waits for Qdrant healthcheck (polls `localhost:6333`)
6. Starts backend: `uvicorn main:app --port 8765 --reload` — stdout+stderr to `logs/backend.log`
7. Saves backend PID to `logs/backend.pid`
8. Starts frontend: `pnpm dev` — stdout+stderr to `logs/frontend.log`
9. Saves frontend PID to `logs/frontend.pid`
10. Prints status: PIDs, log paths, `make stop` hint
11. Optional: tails both logs in background so terminal shows live output

### `make stop`

Calls `bash openmemory/scripts/stop-dev.sh`. The script:

1. Reads PID files from `logs/*.pid`
2. Kills each PID (SIGTERM, then SIGKILL after timeout)
3. Stops Qdrant: `docker compose -f docker-compose-dev.yml stop om-store`
4. Removes PID files

### Environment

- Backend reads `openmemory/api/.env` — must have `QDRANT_HOST=localhost`
- Frontend reads `openmemory/ui/.env` — must have `NEXT_PUBLIC_API_URL=http://localhost:8765`
- Scripts warn if required env vars are missing (don't block startup)

### Makefile Changes

```makefile
run: ## Start Qdrant (Docker) + backend + frontend locally
	@bash openmemory/scripts/run-dev.sh

stop: ## Stop local dev processes
	@bash openmemory/scripts/stop-dev.sh
```

### Log Behavior

- Fresh (truncated) on each `make run`
- Separate files: `backend.log`, `frontend.log`
- Location: `openmemory/logs/`
- `.gitignore` excludes all `*.log` and `*.pid`

### Error Handling

- If Qdrant is already running, skip start (idempotent)
- If backend/frontend PIDs exist and are alive, warn before starting new ones
- If `uvicorn` or `pnpm` not found, print error with install instructions
- On startup failure, kill any already-started processes before exiting

## Verification

1. `make run` — Qdrant container starts, backend serves on :8765, frontend serves on :3000
2. Edit a Python file — backend auto-reloads (uvicorn --reload)
3. Edit a TS file — frontend hot-reloads (next dev)
4. `make stop` — all processes stopped, PID files cleaned
5. Logs written to `openmemory/logs/`, fresh on each run
