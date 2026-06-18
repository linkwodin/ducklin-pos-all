#!/bin/bash
#
# Give production its own copy of UAT uploads and rewire DB URLs to the prod bucket.
#
# Usage:
#   ./scripts/separate-prod-storage.sh
#   ./scripts/separate-prod-storage.sh --uploads-only
#   ./scripts/separate-prod-storage.sh --db-only
#
# Environment:
#   UAT_PROJECT_ID  (default: ducklin-uk-uat)
#   PROD_PROJECT_ID (default: ducklin-uk-prod)
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

UAT_PROJECT_ID="${UAT_PROJECT_ID:-ducklin-uk-uat}"
PROD_PROJECT_ID="${PROD_PROJECT_ID:-ducklin-uk-prod}"
REGION="${REGION:-europe-west1}"
INSTANCE="pos-database"
DATABASE="pos_system"
DB_USER="pos_user"
SYNC_UPLOADS=1
SYNC_DB=1
PROXY_PID=""

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

stop_proxy() {
  if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
  PROXY_PID=""
}

trap stop_proxy EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --uploads-only) SYNC_DB=0 ;;
    --db-only) SYNC_UPLOADS=0 ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

UAT_BUCKET="${UAT_PROJECT_ID}-pos-uploads"
PROD_BUCKET="${PROD_PROJECT_ID}-pos-uploads"
CONNECTION="${PROD_PROJECT_ID}:${REGION}:${INSTANCE}"

if [ "$SYNC_UPLOADS" = "1" ]; then
  print_info "Syncing uploads gs://$UAT_BUCKET -> gs://$PROD_BUCKET ..."
  gsutil -m rsync -r -d "gs://$UAT_BUCKET/" "gs://$PROD_BUCKET/"
  print_info "Uploads sync complete."
fi

if [ "$SYNC_DB" = "1" ]; then
  if [ -z "${PROD_DB_PASSWORD:-}" ]; then
    PROD_DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password --project="$PROD_PROJECT_ID" 2>/dev/null || true)"
  fi
  if [ -z "${PROD_DB_PASSWORD:-}" ]; then
    print_error "PROD_DB_PASSWORD not set and db-password secret missing."
    exit 1
  fi

  SQL_FILE="$REPO_ROOT/scripts/sql/backfill_prod_storage_urls.sql"
  if [ ! -f "$SQL_FILE" ]; then
    print_error "Missing $SQL_FILE"
    exit 1
  fi

  print_info "Rewiring storage URLs in prod database ($UAT_BUCKET -> $PROD_BUCKET) ..."

  PROXY_PORT=3310
  USE_GCLOUD_IMPORT=0
  if command -v cloud-sql-proxy &>/dev/null; then
    print_info "Starting Cloud SQL Auth Proxy on 127.0.0.1:$PROXY_PORT ..."
    if cloud-sql-proxy "$CONNECTION" --port "$PROXY_PORT" &>/dev/null &
    then
      PROXY_PID=$!
      sleep 3
      if kill -0 "$PROXY_PID" 2>/dev/null; then
        DB_HOST="127.0.0.1"
        DB_PORT="$PROXY_PORT"
      else
        PROXY_PID=""
        USE_GCLOUD_IMPORT=1
      fi
    else
      USE_GCLOUD_IMPORT=1
    fi
  elif command -v cloud_sql_proxy &>/dev/null; then
    print_info "Starting cloud_sql_proxy on 127.0.0.1:$PROXY_PORT ..."
    cloud_sql_proxy -instances="${CONNECTION}=tcp:${PROXY_PORT}" &
    PROXY_PID=$!
    sleep 3
    if kill -0 "$PROXY_PID" 2>/dev/null; then
      DB_HOST="127.0.0.1"
      DB_PORT="$PROXY_PORT"
    else
      PROXY_PID=""
      USE_GCLOUD_IMPORT=1
    fi
  else
    USE_GCLOUD_IMPORT=1
  fi

  if [ "$USE_GCLOUD_IMPORT" = "1" ]; then
    print_warn "Cloud SQL proxy unavailable; importing SQL via gcloud (uses gcloud credentials)."
    GCS_SQL="gs://${PROD_BUCKET}/db-exports/backfill_prod_storage_urls.sql"
    gsutil cp "$SQL_FILE" "$GCS_SQL"
    gcloud sql import sql "$INSTANCE" "$GCS_SQL" \
      --database="$DATABASE" \
      --project="$PROD_PROJECT_ID" \
      --quiet
  else
    export MYSQL_PWD="$PROD_DB_PASSWORD"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DATABASE" < "$SQL_FILE"
    unset MYSQL_PWD
  fi
  print_info "Database URL backfill complete."
fi

print_info "Production storage is now separated from UAT."
