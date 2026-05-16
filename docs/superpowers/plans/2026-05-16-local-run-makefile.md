# Local Dev `make run` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make run` and `make stop` targets for local hot-reload development — Qdrant in Docker, backend and frontend running natively.

**Architecture:** Two shell scripts manage lifecycle. `run-dev.sh` starts Qdrant via compose, spawns uvicorn and pnpm as background processes with PID tracking and log redirection. `stop-dev.sh` kills tracked PIDs and stops Qdrant. Makefile delegates to scripts.

**Tech Stack:** Bash, Docker Compose, uvicorn, pnpm/Next.js

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `openmemory/scripts/run-dev.sh` | Create | Start Qdrant + backend + frontend |
| `openmemory/scripts/stop-dev.sh` | Create | Stop all processes |
| `openmemory/logs/.gitignore` | Create | Ignore `*.log` and `*.pid` |
| `Makefile` | Modify | Add `run` and `stop` targets |

---

### Task 1: Create `openmemory/logs/.gitignore`

**Files:**
- Create: `openmemory/logs/.gitignore`

- [ ] **Step 1: Create .gitignore**

```
*
!.gitignore
```

This ignores everything in the logs directory except the .gitignore itself.

- [ ] **Step 2: Create the logs directory**

Run: `mkdir -p openmemory/logs`

- [ ] **Step 3: Commit**

```bash
git add openmemory/logs/.gitignore
git commit -m "chore: add logs dir with gitignore for local dev"
```

---

### Task 2: Create `openmemory/scripts/run-dev.sh`

**Files:**
- Create: `openmemory/scripts/run-dev.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$OM_DIR/logs"
COMPOSE_FILE="$OM_DIR/docker-compose-dev.yml"
PID_DIR="$LOGS_DIR"

BACKEND_PID_FILE="$PID_DIR/backend.pid"
FRONTEND_PID_FILE="$PID_DIR/frontend.pid"
BACKEND_LOG="$LOGS_DIR/backend.log"
FRONTEND_LOG="$LOGS_DIR/frontend.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[run]${NC} $*"; }
warn()  { echo -e "${YELLOW}[run]${NC} $*"; }
error() { echo -e "${RED}[run]${NC} $*" >&2; }

cleanup() {
    if [ -f "$BACKEND_PID_FILE" ]; then
        PID=$(cat "$BACKEND_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$BACKEND_PID_FILE"
    fi
    if [ -f "$FRONTEND_PID_FILE" ]; then
        PID=$(cat "$FRONTEND_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$FRONTEND_PID_FILE"
    fi
}

# Cleanup orphaned processes on error
trap cleanup EXIT

mkdir -p "$LOGS_DIR"

# --- Check prerequisites ---
if ! command -v uvicorn &>/dev/null; then
    error "uvicorn not found. Install: uv pip install uvicorn"
    exit 1
fi

if ! command -v pnpm &>/dev/null; then
    error "pnpm not found. Install: npm install -g pnpm"
    exit 1
fi

# --- Check for already-running processes ---
for pid_file in "$BACKEND_PID_FILE" "$FRONTEND_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        OLD_PID=$(cat "$pid_file")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            error "Process $OLD_PID still running (from $(basename "$pid_file")). Run 'make stop' first."
            exit 1
        fi
        rm -f "$pid_file"
    fi
done

# --- Truncate log files ---
: > "$BACKEND_LOG"
: > "$FRONTEND_LOG"

# --- Start Qdrant ---
info "Starting Qdrant..."
if docker compose -f "$COMPOSE_FILE" up -d om-store 2>/dev/null; then
    : # ok
else
    # Fallback with sudo
    sudo docker compose -f "$COMPOSE_FILE" up -d om-store
fi

# Wait for Qdrant healthy
info "Waiting for Qdrant..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:6333/collections >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 30 ]; then
        error "Qdrant did not become healthy in 30 seconds"
        exit 1
    fi
    sleep 1
done
info "Qdrant ready on :6333"

# --- Start backend ---
info "Starting backend (uvicorn)..."
(
    cd "$OM_DIR/api"
    QDRANT_HOST=localhost QDRANT_PORT=6333 uvicorn main:app --port 8765 --reload
) > "$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!
echo "$BACKEND_PID" > "$BACKEND_PID_FILE"
info "Backend PID: $BACKEND_PID — log: $BACKEND_LOG"

# Wait briefly and check it started
sleep 2
if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    error "Backend failed to start. Check $BACKEND_LOG"
    cat "$BACKEND_LOG" >&2
    exit 1
fi

# --- Start frontend ---
info "Starting frontend (pnpm dev)..."
(
    cd "$OM_DIR/ui"
    NEXT_LOCAL_API_URL=http://localhost:8765 pnpm dev
) > "$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!
echo "$FRONTEND_PID" > "$FRONTEND_PID_FILE"
info "Frontend PID: $FRONTEND_PID — log: $FRONTEND_LOG"

# Wait briefly and check it started
sleep 3
if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    error "Frontend failed to start. Check $FRONTEND_LOG"
    cat "$FRONTEND_LOG" >&2
    # Kill backend too
    kill "$BACKEND_PID" 2>/dev/null || true
    rm -f "$BACKEND_PID_FILE"
    exit 1
fi

# --- Done ---
trap - EXIT
echo ""
info "All services running:"
info "  Backend:  http://localhost:8765  (PID $BACKEND_PID)"
info "  Frontend: http://localhost:3000  (PID $FRONTEND_PID)"
info "  Qdrant:   http://localhost:6333"
info "  Logs:     $LOGS_DIR/"
info "  Stop:     make stop"
echo ""

# Tail logs in foreground
warn "Tailing logs (Ctrl+C to detach — services keep running)"
tail -f "$BACKEND_LOG" "$FRONTEND_LOG" 2>/dev/null || true
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x openmemory/scripts/run-dev.sh`

- [ ] **Step 3: Commit**

```bash
git add openmemory/scripts/run-dev.sh
git commit -m "feat: add run-dev.sh script for local development"
```

---

### Task 3: Create `openmemory/scripts/stop-dev.sh`

**Files:**
- Create: `openmemory/scripts/stop-dev.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$OM_DIR/logs"
COMPOSE_FILE="$OM_DIR/docker-compose-dev.yml"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[stop]${NC} $*"; }
warn()  { echo -e "${YELLOW}[stop]${NC} $*"; }
error() { echo -e "${RED}[stop]${NC} $*" >&2; }

kill_pid_file() {
    local pid_file="$1"
    local name="$2"
    if [ -f "$pid_file" ]; then
        PID=$(cat "$pid_file")
        if kill -0 "$PID" 2>/dev/null; then
            info "Stopping $name (PID $PID)..."
            kill "$PID" 2>/dev/null || true
            # Wait up to 5 seconds for graceful shutdown
            for i in $(seq 1 10); do
                if ! kill -0 "$PID" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            # Force kill if still running
            if kill -0 "$PID" 2>/dev/null; then
                warn "$name did not stop gracefully, force killing..."
                kill -9 "$PID" 2>/dev/null || true
            fi
            info "$name stopped"
        else
            warn "$name PID $PID not running (stale pid file)"
        fi
        rm -f "$pid_file"
    else
        warn "No PID file for $name"
    fi
}

# Kill tracked processes
kill_pid_file "$LOGS_DIR/backend.pid" "backend"
kill_pid_file "$LOGS_DIR/frontend.pid" "frontend"

# Stop Qdrant
info "Stopping Qdrant..."
if docker compose -f "$COMPOSE_FILE" stop om-store 2>/dev/null; then
    : # ok
else
    sudo docker compose -f "$COMPOSE_FILE" stop om-store
fi
info "Qdrant stopped"

info "All services stopped"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x openmemory/scripts/stop-dev.sh`

- [ ] **Step 3: Commit**

```bash
git add openmemory/scripts/stop-dev.sh
git commit -m "feat: add stop-dev.sh script for local development"
```

---

### Task 4: Update Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add `run` and `stop` targets**

Add to `.PHONY` line and add new targets. The full updated Makefile:

```makefile
.PHONY: lint format test docs docker-up docker-down upd updc log run stop

lint:
	cd openmemory/api && ruff check .

format:
	cd openmemory/api && ruff format .

test:
	cd openmemory/api && python -m pytest tests/ $(ARGS)

docs:
	cd docs && mintlify dev

docker-up:
	cd openmemory && docker-compose up -d

docker-down:
	cd openmemory && docker-compose down

## Dev only: rebuild + restart all openmemory containers
upd:
	sudo docker compose -f openmemory/docker-compose-dev.yml down && \
	sudo docker rmi mem0/openmemory-mcp mem0/openmemory-ui:latest 2>/dev/null; \
	sudo docker compose -f openmemory/docker-compose-dev.yml build && \
	sudo docker compose -f openmemory/docker-compose-dev.yml up -d

## Dev only: force clean rebuild (no cache)
updc:
	sudo docker compose -f openmemory/docker-compose-dev.yml down && \
	sudo docker rmi mem0/openmemory-mcp mem0/openmemory-ui:latest 2>/dev/null; \
	sudo docker compose -f openmemory/docker-compose-dev.yml build --no-cache && \
	sudo docker compose -f openmemory/docker-compose-dev.yml up -d

## Dev only: tail logs for all openmemory containers
log:
	sudo docker compose -f openmemory/docker-compose-dev.yml logs -f

## Dev only: run Qdrant (Docker) + backend + frontend locally
run:
	@bash openmemory/scripts/run-dev.sh

## Dev only: stop local dev processes
stop:
	@bash openmemory/scripts/stop-dev.sh
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add make run/stop targets for local development"
```

---

### Task 5: Verify end-to-end

- [ ] **Step 1: Run `make run`**

Run: `make run`

Expected output:
- Qdrant starts and becomes healthy
- Backend starts on port 8765
- Frontend starts on port 3000
- Logs tail to terminal

- [ ] **Step 2: Test backend health**

Run: `curl -sf http://localhost:8765/health`

Expected: HTTP 200 response

- [ ] **Step 3: Test frontend**

Open browser to `http://localhost:3000` or run: `curl -sf http://localhost:3000`

Expected: HTML response from Next.js

- [ ] **Step 4: Stop services**

Press Ctrl+C to detach from log tail, then run: `make stop`

Expected:
- Backend and frontend processes killed
- Qdrant container stopped
- PID files removed

- [ ] **Step 5: Verify cleanup**

Run: `ls openmemory/logs/`

Expected: Only `.gitignore` remains (no `.pid` files)

---

## Self-Review Checklist

- [x] **Spec coverage:** Every spec requirement maps to a task
  - Qdrant via compose → Task 2 (step in run-dev.sh)
  - Backend uvicorn --reload → Task 2
  - Frontend pnpm dev → Task 2
  - Log truncation → Task 2
  - PID tracking → Tasks 2, 3
  - make stop → Task 3
  - .gitignore → Task 1
  - Makefile targets → Task 4
  - Error handling (orphan check, prereq check) → Task 2
- [x] **Placeholder scan:** No TBD/TODO/vague steps
- [x] **Type consistency:** All file paths and var names consistent across tasks
