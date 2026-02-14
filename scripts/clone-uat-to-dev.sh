#!/bin/bash
#
# Clone all data from UAT (GCP Cloud SQL + optional uploads bucket) to local dev.
#
# Prerequisites:
#   - gcloud CLI logged in with access to UAT project
#   - mysql client (mysqldump, mysql)
#   - Optional: cloud_sql_proxy for DB export (or use public IP)
#
# Usage:
#   ./scripts/clone-uat-to-dev.sh [OPTIONS] [SCHEMA]
#   SCHEMA           Target dev database/schema name (positional; e.g. ducklin_pos)
#   --schema NAME    Same (overrides DEV_DB_NAME)
#   -s NAME          Short for --schema
#   --db-only        Only clone database (skip uploads sync)
#   --no-uploads     Same as --db-only (alias)
#
# Environment (optional):
#   UAT_PROJECT_ID   GCP project for UAT (default: gcloud config or ducklin-uk-uat)
#   UAT_DB_PASSWORD  UAT pos_user password (will prompt if not set)
#   DEV_DB_HOST      Local MySQL host (default: 127.0.0.1)
#   DEV_DB_PORT      Local MySQL port (default: 3306)
#   DEV_DB_USER      Local MySQL user (default: root)
#   DEV_DB_PASSWORD  Local MySQL password (optional)
#   DEV_DB_NAME      Local database name (default: pos_system; overridden by --schema)
#   UAT_DB_HOST      UAT MySQL host IP (default: 34.76.25.28). When set, connects by IP (no proxy).
#   USE_PROXY        Set to 1 to use Cloud SQL Proxy for export (ignored if UAT_DB_HOST is set)
#   UPLOADS_DIR      Local directory for synced uploads (default: ./dev-uploads)
#   KEEP_DUMP        Set to 1 to keep the SQL dump file and skip the remove prompt
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Defaults
UAT_PROJECT_ID="${UAT_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo 'ducklin-uk-uat')}"
REGION="${REGION:-europe-west1}"
UAT_INSTANCE="pos-database"
UAT_DATABASE="pos_system"
UAT_USER="pos_user"
UAT_DB_HOST="${UAT_DB_HOST:-34.76.25.28}"

DEV_DB_HOST="${DEV_DB_HOST:-127.0.0.1}"
DEV_DB_PORT="${DEV_DB_PORT:-3306}"
DEV_DB_USER="${DEV_DB_USER:-root}"
DEV_DB_NAME="${DEV_DB_NAME:-pos_system}"
USE_PROXY="${USE_PROXY:-1}"
UPLOADS_DIR="${UPLOADS_DIR:-$REPO_ROOT/dev-uploads}"
SYNC_UPLOADS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --db-only|--no-uploads) SYNC_UPLOADS=0 ;;
    --schema|-s)
      shift
      [ $# -gt 0 ] || { print_error "Missing value for --schema"; exit 1; }
      DEV_DB_NAME="$1"
      ;;
    -*)
      print_error "Unknown option: $1. Use --db-only, --no-uploads, --schema NAME (-s NAME)."
      exit 1
      ;;
    *)
      # Positional arg = target schema
      DEV_DB_NAME="$1"
      ;;
  esac
  shift
done

# --- Checks ---
if ! command -v gcloud &>/dev/null; then
  print_error "gcloud CLI is required. Install: https://cloud.google.com/sdk/docs/install"
  exit 1
fi
if ! command -v mysqldump &>/dev/null || ! command -v mysql &>/dev/null; then
  print_error "mysql client (mysqldump, mysql) is required."
  exit 1
fi

print_info "UAT project: $UAT_PROJECT_ID"
print_info "Dev DB: $DEV_DB_USER@$DEV_DB_HOST:$DEV_DB_PORT/$DEV_DB_NAME"
echo

# --- UAT password ---
if [ -z "${UAT_DB_PASSWORD:-}" ]; then
  read -sp "UAT DB password (pos_user): " UAT_DB_PASSWORD
  echo
fi
if [ -z "$UAT_DB_PASSWORD" ]; then
  print_error "UAT DB password is required (set UAT_DB_PASSWORD or enter when prompted)."
  exit 1
fi

# --- Export from UAT ---
DUMP_FILE="$REPO_ROOT/pos_system_uat_$(date +%Y%m%d_%H%M%S).sql"
CONNECTION_NAME="$UAT_PROJECT_ID:$REGION:$UAT_INSTANCE"
PROXY_PID=""

cleanup_proxy() {
  if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
}
trap cleanup_proxy EXIT

# Connect to UAT: use UAT_DB_HOST (IP) if set, else proxy or gcloud lookup
if [ -n "$UAT_DB_HOST" ]; then
  print_info "Using UAT DB host: $UAT_DB_HOST"
  UAT_HOST="$UAT_DB_HOST"
  UAT_PORT="3306"
elif [ "$USE_PROXY" = "1" ] && command -v cloud_sql_proxy &>/dev/null; then
  print_info "Starting Cloud SQL Proxy for $CONNECTION_NAME..."
  cloud_sql_proxy -instances="$CONNECTION_NAME=tcp:3306" &
  PROXY_PID=$!
  sleep 3
  UAT_HOST="127.0.0.1"
  UAT_PORT="3306"
else
  if [ "$USE_PROXY" = "1" ]; then
    print_warn "cloud_sql_proxy not found; falling back to public IP."
  fi
  print_info "Using UAT instance public IP (gcloud lookup)..."
  UAT_HOST=$(gcloud sql instances describe "$UAT_INSTANCE" --project="$UAT_PROJECT_ID" --format="value(ipAddresses[0].ipAddress)" 2>/dev/null) || true
  if [ -z "$UAT_HOST" ]; then
    print_error "Could not get UAT instance IP. Set UAT_DB_HOST=34.76.25.28 or use cloud_sql_proxy."
    exit 1
  fi
  UAT_PORT="3306"
fi

print_info "Exporting UAT database to $DUMP_FILE ..."
# URL-encode password for use in shell (avoid special chars in -p)
export MYSQL_PWD="$UAT_DB_PASSWORD"
mysqldump -h "$UAT_HOST" -P "$UAT_PORT" -u "$UAT_USER" \
  --single-transaction --routines --triggers \
  "$UAT_DATABASE" > "$DUMP_FILE"
unset MYSQL_PWD

if [ ! -s "$DUMP_FILE" ]; then
  print_error "Dump file is empty. Export failed."
  exit 1
fi
print_info "Export complete ($(wc -l < "$DUMP_FILE") lines)."

# --- Import into dev ---
print_info "Importing into dev database $DEV_DB_NAME ..."
if [ -n "${DEV_DB_PASSWORD:-}" ]; then
  export MYSQL_PWD="$DEV_DB_PASSWORD"
fi
mysql -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" -e "CREATE DATABASE IF NOT EXISTS \`$DEV_DB_NAME\`;"
mysql -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" "$DEV_DB_NAME" < "$DUMP_FILE"
unset MYSQL_PWD
print_info "Dev database imported successfully."

# --- Optional: sync uploads bucket to local ---
if [ "$SYNC_UPLOADS" = "1" ]; then
  UAT_BUCKET="${UAT_PROJECT_ID}-pos-uploads"
  if gsutil ls -b "gs://$UAT_BUCKET" &>/dev/null; then
    print_info "Syncing UAT uploads (gs://$UAT_BUCKET) to $UPLOADS_DIR ..."
    mkdir -p "$UPLOADS_DIR"
    gsutil -m rsync -r -d "gs://$UAT_BUCKET/" "$UPLOADS_DIR/" || print_warn "Uploads sync had errors (check gsutil access)."
    print_info "Uploads synced. To serve locally, point STORAGE_PROVIDER=local and a local path, or keep using GCP bucket."
  else
    print_warn "Bucket gs://$UAT_BUCKET not found or no access; skipping uploads sync."
  fi
else
  print_info "Skipping uploads sync (--db-only)."
fi

# --- Cleanup dump (optional: keep for debugging)
if [ "${KEEP_DUMP:-0}" = "1" ]; then
  print_info "Dump kept: $DUMP_FILE"
else
  read -p "Remove dump file $DUMP_FILE? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$DUMP_FILE"
    print_info "Dump file removed."
  else
    print_info "Dump kept: $DUMP_FILE"
  fi
fi

print_info "Done. Dev database is ready; ensure backend DATABASE_URL points to $DEV_DB_USER@$DEV_DB_HOST:$DEV_DB_PORT/$DEV_DB_NAME"
