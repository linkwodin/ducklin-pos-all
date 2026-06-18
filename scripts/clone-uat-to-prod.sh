#!/bin/bash
#
# Clone UAT Cloud SQL + uploads bucket into an existing production GCP project.
#
# Prerequisites:
#   - Prod project already has Cloud SQL instance pos-database (empty or replaceable)
#   - gcloud + mysql client + gsutil
#
# Usage:
#   PROD_PROJECT_ID=ducklin-uk-prod ./scripts/clone-uat-to-prod.sh
#   ./scripts/clone-uat-to-prod.sh --db-only
#   ./scripts/clone-uat-to-prod.sh --uploads-only
#
# Environment:
#   UAT_PROJECT_ID      (default: ducklin-uk-uat)
#   PROD_PROJECT_ID     (required unless gcloud project is prod)
#   UAT_DB_PASSWORD     (prompt if unset)
#   PROD_DB_PASSWORD    (prompt if unset; must match pos_user in prod Cloud SQL)
#   UAT_DB_HOST         (default: UAT instance public IP from gcloud)
#   PROD_DB_HOST        (default: prod instance public IP from gcloud)
#   KEEP_DUMP           (default: 1 — keep SQL dump for audit)
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

UAT_PROJECT_ID="${UAT_PROJECT_ID:-ducklin-uk-uat}"
PROD_PROJECT_ID="${PROD_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-europe-west1}"
INSTANCE="pos-database"
DATABASE="pos_system"
DB_USER="pos_user"
SYNC_DB=1
SYNC_UPLOADS=1
KEEP_DUMP="${KEEP_DUMP:-1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --db-only) SYNC_UPLOADS=0 ;;
    --uploads-only) SYNC_DB=0 ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

if [ -z "$PROD_PROJECT_ID" ] || [ "$PROD_PROJECT_ID" = "ducklin-uk-uat" ]; then
  print_error "Set PROD_PROJECT_ID to the production GCP project (not UAT)."
  exit 1
fi

if ! command -v gcloud &>/dev/null; then
  print_error "gcloud CLI is required."
  exit 1
fi
if [ "$SYNC_DB" = "1" ] && [ "${CLONE_METHOD:-gcs}" = "dump" ] && { ! command -v mysqldump &>/dev/null || ! command -v mysql &>/dev/null; }; then
  print_error "mysql client (mysqldump, mysql) is required for CLONE_METHOD=dump."
  exit 1
fi

print_info "UAT project:  $UAT_PROJECT_ID"
print_info "Prod project: $PROD_PROJECT_ID"
echo

if [ -z "${UAT_DB_PASSWORD:-}" ]; then
  read -sp "UAT DB password (pos_user): " UAT_DB_PASSWORD
  echo
fi
if [ "$SYNC_DB" = "1" ] && [ "${CLONE_METHOD:-gcs}" = "dump" ] && [ -z "${PROD_DB_PASSWORD:-}" ]; then
  read -sp "Prod DB password (pos_user): " PROD_DB_PASSWORD
  echo
fi

resolve_db_host() {
  local project="$1"
  gcloud sql instances describe "$INSTANCE" \
    --project="$project" \
    --format="value(ipAddresses[0].ipAddress)" 2>/dev/null || true
}

sql_service_account() {
  local project="$1"
  gcloud sql instances describe "$INSTANCE" \
    --project="$project" \
    --format="value(serviceAccountEmailAddress)" 2>/dev/null || true
}

clone_db_via_gcs() {
  local export_path="gs://${UAT_PROJECT_ID}-pos-uploads/db-exports/uat-to-prod-$(date +%Y%m%d_%H%M%S).sql"
  local uat_sa prod_sa
  uat_sa="$(sql_service_account "$UAT_PROJECT_ID")"
  prod_sa="$(sql_service_account "$PROD_PROJECT_ID")"
  local bucket="gs://${UAT_PROJECT_ID}-pos-uploads"

  print_info "Granting Cloud SQL service accounts access to $bucket ..."
  if [ -n "$uat_sa" ]; then
    gsutil iam ch "serviceAccount:${uat_sa}:objectAdmin" "$bucket"
  fi
  if [ -n "$prod_sa" ]; then
    gsutil iam ch "serviceAccount:${prod_sa}:objectViewer" "$bucket"
  fi

  print_info "Exporting UAT database to $export_path (server-side) ..."
  gcloud sql export sql "$INSTANCE" "$export_path" \
    --database="$DATABASE" \
    --project="$UAT_PROJECT_ID" \
    --offload \
    --quiet

  print_warn "Importing into PROD will replace data in $DATABASE on $PROD_PROJECT_ID."
  if [ "${AUTO_CONFIRM:-0}" != "1" ]; then
    read -p "Continue prod DB import? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_info "Skipped prod DB import. Export kept at: $export_path"
      return 0
    fi
  else
    print_info "AUTO_CONFIRM=1 — proceeding with prod DB import."
  fi

  print_info "Importing $export_path into prod Cloud SQL ..."
  gcloud sql import sql "$INSTANCE" "$export_path" \
    --database="$DATABASE" \
    --project="$PROD_PROJECT_ID" \
    --quiet
  print_info "Prod database clone complete (via GCS)."
}

start_sql_proxy() {
  local connection="$1"
  local port="$2"
  if ! command -v cloud_sql_proxy &>/dev/null; then
    return 1
  fi
  cloud_sql_proxy -instances="${connection}=tcp:${port}" &
  PROXY_PID=$!
  sleep 3
  return 0
}

stop_sql_proxy() {
  if [ -n "${PROXY_PID:-}" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
  PROXY_PID=""
}

clone_db_via_dump() {
  UAT_DB_HOST="${UAT_DB_HOST:-$(resolve_db_host "$UAT_PROJECT_ID")}"
  PROD_DB_HOST="${PROD_DB_HOST:-$(resolve_db_host "$PROD_PROJECT_ID")}"

  if [ -z "$UAT_DB_HOST" ] || [ -z "$PROD_DB_HOST" ]; then
    print_error "Could not resolve Cloud SQL public IP. Set UAT_DB_HOST / PROD_DB_HOST."
    exit 1
  fi

  local uat_host="$UAT_DB_HOST"
  local uat_port="3306"
  local prod_host="$PROD_DB_HOST"
  local prod_port="3306"
  local uat_connection="${UAT_PROJECT_ID}:${REGION}:${INSTANCE}"
  local prod_connection="${PROD_PROJECT_ID}:${REGION}:${INSTANCE}"

  trap stop_sql_proxy EXIT

  if start_sql_proxy "$uat_connection" 3307; then
    print_info "Using Cloud SQL Proxy for UAT export (127.0.0.1:3307)"
    uat_host="127.0.0.1"
    uat_port="3307"
  else
    print_warn "cloud_sql_proxy not found; using UAT public IP $UAT_DB_HOST"
  fi

  DUMP_FILE="$REPO_ROOT/pos_system_uat_to_prod_$(date +%Y%m%d_%H%M%S).sql"
  print_info "Exporting UAT DB from $uat_host ..."
  export MYSQL_PWD="$UAT_DB_PASSWORD"
  if ! mysqldump -h "$uat_host" -P "$uat_port" -u "$DB_USER" \
    --single-transaction --routines --triggers \
    "$DATABASE" > "$DUMP_FILE"; then
    unset MYSQL_PWD
    print_error "mysqldump failed."
    exit 1
  fi
  unset MYSQL_PWD
  stop_sql_proxy
  trap - EXIT

  if [ ! -s "$DUMP_FILE" ]; then
    print_error "UAT dump is empty."
    exit 1
  fi
  print_info "UAT export complete ($(wc -l < "$DUMP_FILE" | tr -d ' ') lines)."

  print_warn "Importing into PROD will replace data in $DATABASE on $PROD_PROJECT_ID."
  if [ "${AUTO_CONFIRM:-0}" != "1" ]; then
    read -p "Continue prod DB import? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_info "Skipped prod DB import. Dump kept at: $DUMP_FILE"
      return 0
    fi
  else
    print_info "AUTO_CONFIRM=1 — proceeding with prod DB import."
  fi

  trap stop_sql_proxy EXIT
  if start_sql_proxy "$prod_connection" 3308; then
    print_info "Using Cloud SQL Proxy for prod import (127.0.0.1:3308)"
    prod_host="127.0.0.1"
    prod_port="3308"
  else
    print_warn "cloud_sql_proxy not found; using prod public IP $PROD_DB_HOST"
  fi

  print_info "Recreating prod database $DATABASE ..."
  export MYSQL_PWD="$PROD_DB_PASSWORD"
  mysql -h "$prod_host" -P "$prod_port" -u "$DB_USER" -e "DROP DATABASE IF EXISTS \`$DATABASE\`; CREATE DATABASE \`$DATABASE\`;"
  print_info "Importing into prod $prod_host ..."
  mysql -h "$prod_host" -P "$prod_port" -u "$DB_USER" "$DATABASE" < "$DUMP_FILE"
  unset MYSQL_PWD
  stop_sql_proxy
  trap - EXIT
  print_info "Prod database clone complete."

  if [ "$KEEP_DUMP" = "1" ]; then
    print_info "Dump kept: $DUMP_FILE"
  else
    rm -f "$DUMP_FILE"
  fi
}

UAT_DB_HOST="${UAT_DB_HOST:-$(resolve_db_host "$UAT_PROJECT_ID")}"
PROD_DB_HOST="${PROD_DB_HOST:-$(resolve_db_host "$PROD_PROJECT_ID")}"

if [ "$SYNC_DB" = "1" ]; then
  CLONE_METHOD="${CLONE_METHOD:-gcs}"
  if [ "$CLONE_METHOD" = "gcs" ]; then
    clone_db_via_gcs || {
      print_warn "GCS clone failed; falling back to mysqldump ..."
      clone_db_via_dump
    }
  else
    clone_db_via_dump
  fi
fi

if [ "$SYNC_UPLOADS" = "1" ]; then
  UAT_BUCKET="${UAT_PROJECT_ID}-pos-uploads"
  PROD_BUCKET="${PROD_PROJECT_ID}-pos-uploads"
  if gsutil ls -b "gs://$UAT_BUCKET" &>/dev/null && gsutil ls -b "gs://$PROD_BUCKET" &>/dev/null; then
    print_info "Syncing uploads gs://$UAT_BUCKET -> gs://$PROD_BUCKET ..."
    gsutil -m rsync -r -d "gs://$UAT_BUCKET/" "gs://$PROD_BUCKET/"
    print_info "Uploads sync complete."
    if [ "${REWIRE_PROD_URLS:-1}" = "1" ] && [ "$PROD_PROJECT_ID" != "$UAT_PROJECT_ID" ]; then
      print_info "Rewiring prod DB storage URLs to $PROD_BUCKET ..."
      REWIRE_PROD_URLS=1 SYNC_UPLOADS=0 "$SCRIPT_DIR/separate-prod-storage.sh" --db-only || \
        print_warn "DB URL rewire failed — run: ./scripts/separate-prod-storage.sh"
    fi
  else
    print_warn "Upload bucket missing on UAT or prod; skipping uploads sync."
  fi
fi

print_info "Clone finished."
