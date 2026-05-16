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

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[run]${NC} $*"; }
warn()  { echo -e "${YELLOW}[run]${NC} $*"; }
error() { echo -e "${RED}[run]${NC} $*" >&2; }

dc() {
    if docker compose -f "$COMPOSE_FILE" "$@" 2>/dev/null; then
        :
    else
        sudo docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

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

trap cleanup EXIT

mkdir -p "$LOGS_DIR"

# --- Source unified .env ---
if [ -f "$OM_DIR/.env" ]; then
    set -a; source "$OM_DIR/.env"; set +a
fi
export NEXT_PUBLIC_USER="${USER}"

# --- Check prerequisites ---
if ! command -v uvicorn &>/dev/null; then
    error "uvicorn not found. Install: uv pip install uvicorn"
    exit 1
fi

if ! command -v pnpm &>/dev/null; then
    error "pnpm not found. Install: npm install -g pnpm"
    exit 1
fi

# --- Ensure frontend dependencies ---
if [ ! -d "$OM_DIR/ui/node_modules" ]; then
    info "Installing frontend dependencies..."
    (cd "$OM_DIR/ui" && pnpm install)
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

# --- Stop Docker API + UI containers (only Qdrant stays up) ---
info "Stopping Docker API + UI containers..."
dc stop om-mcp om-ui 2>/dev/null || true

# --- Truncate log files ---
: > "$BACKEND_LOG"
: > "$FRONTEND_LOG"

# --- Start Qdrant ---
info "Starting Qdrant..."
dc up -d om-store

info "Waiting for Qdrant ($QDRANT_HOST:$QDRANT_PORT)..."
for i in $(seq 1 30); do
    if curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/collections" >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 30 ]; then
        error "Qdrant did not become healthy in 30 seconds"
        exit 1
    fi
    sleep 1
done
info "Qdrant ready at $QDRANT_HOST:$QDRANT_PORT"

# --- Start backend ---
info "Starting backend (uvicorn)..."
(
    cd "$OM_DIR/api"
    uvicorn main:app --host 0.0.0.0 --port 8765 --reload
) > "$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!
echo "$BACKEND_PID" > "$BACKEND_PID_FILE"
info "Backend PID: $BACKEND_PID — log: $BACKEND_LOG"

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
    pnpm dev
) > "$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!
echo "$FRONTEND_PID" > "$FRONTEND_PID_FILE"
info "Frontend PID: $FRONTEND_PID — log: $FRONTEND_LOG"

sleep 3
if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    error "Frontend failed to start. Check $FRONTEND_LOG"
    cat "$FRONTEND_LOG" >&2
    kill "$BACKEND_PID" 2>/dev/null || true
    rm -f "$BACKEND_PID_FILE"
    exit 1
fi

trap - EXIT
echo ""
info "All services running:"
info "  Backend:  http://localhost:8765  (PID $BACKEND_PID)"
info "  Frontend: http://localhost:3000  (PID $FRONTEND_PID)"
info "  Qdrant:   http://$QDRANT_HOST:$QDRANT_PORT"
info "  Logs:     $LOGS_DIR/"
info "  Stop:     make stop"
echo ""

warn "Tailing logs (Ctrl+C to detach — services keep running)"
tail --pid="$BACKEND_PID" -f "$BACKEND_LOG" "$FRONTEND_LOG" 2>/dev/null || true
