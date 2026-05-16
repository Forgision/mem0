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

dc() {
    if docker compose -f "$COMPOSE_FILE" "$@" 2>/dev/null; then
        :
    else
        sudo docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

kill_tree() {
    local pid="$1"
    # Kill entire process group (children + parent)
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
    if [ -n "$children" ]; then
        for child in $children; do
            kill_tree "$child"
        done
    fi
    kill "$pid" 2>/dev/null || true
}

kill_tree_force() {
    local pid="$1"
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
    if [ -n "$children" ]; then
        for child in $children; do
            kill_tree_force "$child"
        done
    fi
    kill -9 "$pid" 2>/dev/null || true
}

kill_pid_file() {
    local pid_file="$1"
    local name="$2"
    if [ -f "$pid_file" ]; then
        PID=$(cat "$pid_file")
        if kill -0 "$PID" 2>/dev/null; then
            info "Stopping $name (PID $PID)..."
            kill_tree "$PID"
            for i in $(seq 1 10); do
                if ! kill -0 "$PID" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            if kill -0 "$PID" 2>/dev/null; then
                warn "$name did not stop gracefully, force killing..."
                kill_tree_force "$PID"
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

kill_pid_file "$LOGS_DIR/backend.pid" "backend"
kill_pid_file "$LOGS_DIR/frontend.pid" "frontend"

info "Stopping Qdrant..."
dc stop om-store 2>/dev/null || true
info "Qdrant stopped"

info "All services stopped"
