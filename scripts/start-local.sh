#!/usr/bin/env bash
#
# Start local POS stack: MySQL + backend API + management frontend dev server.
#
# Usage: ./START-LOCAL.sh   or   ./scripts/start-local.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.local.yml"
BIN_DIR="$REPO_ROOT/bin"
BACKEND_BIN="$BIN_DIR/pos-backend"
PID_FILE="$REPO_ROOT/.local-dev.pids"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_step() { echo -e "${BLUE}==>${NC} $1"; }

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  else
    echo "docker-compose"
  fi
}

cleanup() {
  echo ""
  print_info "Stopping local services..."
  if [ -f "$PID_FILE" ]; then
    while read -r pid _; do
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
  exit 0
}

trap cleanup INT TERM

cd "$REPO_ROOT"

if [ ! -f "$REPO_ROOT/backend/.env" ]; then
  echo "backend/.env not found. Run ./INSTALL-LOCAL.sh first."
  exit 1
fi

print_step "Starting MySQL"
COMPOSE="$(compose_cmd)"
$COMPOSE -f "$COMPOSE_FILE" up -d

print_step "Starting backend API on :8868"
mkdir -p "$BIN_DIR"
if [ ! -x "$BACKEND_BIN" ]; then
  (cd "$REPO_ROOT/backend" && go build -o "$BACKEND_BIN" .)
fi
(
  cd "$REPO_ROOT/backend"
  exec "$BACKEND_BIN"
) &
BACKEND_PID=$!
echo "$BACKEND_PID backend" > "$PID_FILE"

sleep 2
if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
  echo "Backend failed to start. Check backend/.env and MySQL."
  exit 1
fi

print_step "Starting management frontend on :3000"
print_info "Press Ctrl+C to stop backend and frontend"
echo ""
echo "  Management UI:  http://localhost:3000"
echo "  Backend API:    http://localhost:8868/api/v1"
echo "  Login:          admin / admin123"
echo ""

(
  cd "$REPO_ROOT/management-frontend"
  npm run dev
) &
FRONTEND_PID=$!
echo "$FRONTEND_PID frontend" >> "$PID_FILE"

wait "$FRONTEND_PID"
