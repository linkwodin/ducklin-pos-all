#!/usr/bin/env bash
#
# One-click local install for the POS system.
# Sets up MySQL (Docker), backend, management frontend, and seeds a default admin.
#
# Usage (from repo root):
#   ./INSTALL-LOCAL.sh
#   ./scripts/install-local.sh [--start] [--with-flutter] [--skip-docker]
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.local.yml"
ENV_FILE="$REPO_ROOT/backend/.env"
ENV_EXAMPLE="$REPO_ROOT/backend/.env.local.example"
BIN_DIR="$REPO_ROOT/bin"

START_AFTER=0
WITH_FLUTTER=0
SKIP_DOCKER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --start) START_AFTER=1 ;;
    --with-flutter) WITH_FLUTTER=1 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    -h|--help)
      echo "Usage: $0 [--start] [--with-flutter] [--skip-docker]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()  { echo -e "\n${BLUE}==>${NC} $1"; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print_error "Missing required command: $1"
    exit 1
  fi
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    print_error "Docker Compose is required. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi
}

wait_for_mysql() {
  local compose
  compose="$(compose_cmd)"
  print_info "Waiting for MySQL to become healthy..."
  local i=0
  while [ "$i" -lt 60 ]; do
    if $compose -f "$COMPOSE_FILE" ps --status running 2>/dev/null | grep -q mysql; then
      if $compose -f "$COMPOSE_FILE" exec -T mysql mysqladmin ping -h 127.0.0.1 -uroot -ppos_local_root --silent 2>/dev/null; then
        print_info "MySQL is ready."
        return 0
      fi
    fi
    sleep 2
    i=$((i + 1))
  done
  print_error "MySQL did not become ready in time. Check: docker compose -f docker-compose.local.yml logs mysql"
  exit 1
}

generate_jwt_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    date +%s | shasum -a 256 | cut -d' ' -f1
  fi
}

ensure_env_file() {
  mkdir -p "$REPO_ROOT/backend/uploads/assets/fonts" "$REPO_ROOT/backend/uploads/assets/images"
  if [ -f "$ENV_FILE" ]; then
    print_info "Using existing backend/.env"
    return
  fi
  if [ ! -f "$ENV_EXAMPLE" ]; then
    print_error "Missing $ENV_EXAMPLE"
    exit 1
  fi
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  local secret
  secret="$(generate_jwt_secret)"
  if [[ "$OSTYPE" == darwin"* ]]; then
    sed -i '' "s|^JWT_SECRET=.*|JWT_SECRET=$secret|" "$ENV_FILE"
  else
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$secret|" "$ENV_FILE"
  fi
  print_info "Created backend/.env from local template"
}

ensure_pdf_assets() {
  local fonts_dir="$REPO_ROOT/backend/pdf-assets/fonts"
  local logo_src="$REPO_ROOT/backend/pdf-assets/images/pdf_logo.png"
  local logo_dst="$REPO_ROOT/backend/uploads/assets/images/pdf_logo.png"
  if [ ! -f "$fonts_dir/Arial.ttf" ] && [ -f "$REPO_ROOT/scripts/download-arial-font.sh" ]; then
    print_info "Downloading PDF fonts..."
    bash "$REPO_ROOT/scripts/download-arial-font.sh" || print_warn "PDF font download failed (PDFs may still work with bundled Noto fonts)"
  fi
  if [ -f "$logo_src" ] && [ ! -f "$logo_dst" ]; then
    cp "$logo_src" "$logo_dst"
    print_info "Copied default PDF logo to uploads/"
  fi
}

cd "$REPO_ROOT"

echo ""
echo "========================================"
echo "  POS System — Local One-Click Install"
echo "========================================"
echo ""

print_step "Checking prerequisites"
need_cmd docker
need_cmd go
need_cmd node
need_cmd npm

GO_VERSION="$(go version | awk '{print $3}' | sed 's/go//')"
print_info "Go: $GO_VERSION"
print_info "Node: $(node -v)"
print_info "npm: $(npm -v)"

if [ "$SKIP_DOCKER" -eq 0 ]; then
  print_step "Starting MySQL (Docker)"
  if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Start Docker Desktop and run this script again."
    exit 1
  fi
  COMPOSE="$(compose_cmd)"
  $COMPOSE -f "$COMPOSE_FILE" up -d
  wait_for_mysql
else
  print_warn "Skipping Docker MySQL (--skip-docker). Ensure MySQL is running and DATABASE_URL in backend/.env is correct."
fi

print_step "Configuring backend environment"
ensure_env_file
ensure_pdf_assets

print_step "Installing backend dependencies"
(
  cd "$REPO_ROOT/backend"
  go mod download
  print_info "Building backend binary..."
  mkdir -p "$BIN_DIR"
  go build -o "$BIN_DIR/pos-backend" .
)

print_step "Installing management frontend dependencies"
(
  cd "$REPO_ROOT/management-frontend"
  npm install
)

if [ "$WITH_FLUTTER" -eq 1 ]; then
  print_step "Installing POS (Flutter) dependencies"
  if command -v flutter >/dev/null 2>&1; then
    (cd "$REPO_ROOT/frontend" && flutter pub get)
    print_info "Flutter POS app is configured for http://127.0.0.1:8868/api/v1 (development mode)"
  else
    print_warn "Flutter not found — skipped. Install from https://docs.flutter.dev/get-started/install"
  fi
fi

print_step "Creating database schema and default admin user"
(
  cd "$REPO_ROOT/backend"
  go run ./cmd/seed-local
)

echo ""
echo "========================================"
print_info "Installation complete!"
echo "========================================"
echo ""
echo "  MySQL:            127.0.0.1:3306 (user pos_user / pos_local_pass, db pos_system)"
echo "  Backend API:      http://localhost:8868/api/v1"
echo "  Management UI:    http://localhost:3000"
echo "  Default login:    admin / admin123"
echo ""
echo "  Start everything:  ./START-LOCAL.sh"
echo "  Stop MySQL:        docker compose -f docker-compose.local.yml down"
echo ""

if [ "$START_AFTER" -eq 1 ]; then
  exec "$SCRIPT_DIR/start-local.sh"
fi
