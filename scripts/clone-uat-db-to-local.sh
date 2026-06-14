#!/bin/bash
#
# Clone UAT database into local MySQL (database only).
#
# This is a thin wrapper over scripts/clone-uat-to-dev.sh with --db-only,
# plus an optional --replace mode to recreate the local target schema.
#
# Usage:
#   ./scripts/clone-uat-db-to-local.sh [--schema NAME] [--replace]
#
# Examples:
#   ./scripts/clone-uat-db-to-local.sh
#   ./scripts/clone-uat-db-to-local.sh --schema ducklin_pos_local
#   ./scripts/clone-uat-db-to-local.sh --schema ducklin_pos_local --replace
#
# Environment (optional):
#   UAT_DB_PASSWORD   UAT pos_user password (prompted if not set)
#   DEV_DB_HOST       Local MySQL host (default: 127.0.0.1)
#   DEV_DB_PORT       Local MySQL port (default: 3306)
#   DEV_DB_USER       Local MySQL user (default: root)
#   DEV_DB_PASSWORD   Local MySQL password
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_SCRIPT="$SCRIPT_DIR/clone-uat-to-dev.sh"

if [ ! -f "$BASE_SCRIPT" ]; then
  echo "[ERROR] Missing base script: $BASE_SCRIPT"
  exit 1
fi

SCHEMA="${DEV_DB_NAME:-pos_system}"
REPLACE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --schema|-s)
      shift
      [ $# -gt 0 ] || { echo "[ERROR] Missing value for --schema"; exit 1; }
      SCHEMA="$1"
      ;;
    --replace)
      REPLACE=1
      ;;
    -*)
      echo "[ERROR] Unknown option: $1"
      echo "Usage: ./scripts/clone-uat-db-to-local.sh [--schema NAME] [--replace]"
      exit 1
      ;;
    *)
      SCHEMA="$1"
      ;;
  esac
  shift
done

DEV_DB_HOST="${DEV_DB_HOST:-127.0.0.1}"
DEV_DB_PORT="${DEV_DB_PORT:-3306}"
DEV_DB_USER="${DEV_DB_USER:-root}"

echo "[INFO] Target local DB: $DEV_DB_USER@$DEV_DB_HOST:$DEV_DB_PORT/$SCHEMA"

# --- Step 1: Rename current local schema to backup schema (date suffix) ---
# MySQL doesn't support "RENAME DATABASE", so we emulate by:
#   1) creating backup schema
#   2) moving all tables with RENAME TABLE old.t -> backup.t
#   3) recreating the original schema for fresh import
BACKUP_SCHEMA="${SCHEMA}_$(date +%Y%m%d_%H%M%S)"

if [ -n "${DEV_DB_PASSWORD:-}" ]; then
  export MYSQL_PWD="$DEV_DB_PASSWORD"
fi

SCHEMA_EXISTS=$(mysql -N -s -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" \
  -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${SCHEMA}';")

if [ "${SCHEMA_EXISTS:-0}" -gt 0 ]; then
  TABLES=$(mysql -N -s -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" \
    -e "SELECT table_name FROM information_schema.tables WHERE table_schema='${SCHEMA}' AND table_type='BASE TABLE';")

  if [ -n "$TABLES" ]; then
    echo "[INFO] Backing up existing schema '$SCHEMA' -> '$BACKUP_SCHEMA' ..."
    mysql -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" \
      -e "CREATE DATABASE \`$BACKUP_SCHEMA\`;"

    while IFS= read -r t; do
      [ -n "$t" ] || continue
      mysql -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" \
        -e "RENAME TABLE \`$SCHEMA\`.\`$t\` TO \`$BACKUP_SCHEMA\`.\`$t\`;"
    done <<< "$TABLES"

    # Recreate source schema name so import target always exists/fresh.
    mysql -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" \
      -e "DROP DATABASE \`$SCHEMA\`; CREATE DATABASE \`$SCHEMA\`;"

    echo "[INFO] Backup complete. Previous local data moved to: $BACKUP_SCHEMA"
  else
    echo "[INFO] Schema '$SCHEMA' exists but has no base tables; skipping backup rename."
  fi
else
  echo "[INFO] Schema '$SCHEMA' does not exist yet; no backup rename needed."
fi

unset MYSQL_PWD || true

if [ "$REPLACE" = "1" ]; then
  echo "[WARN] --replace enabled: database '$SCHEMA' will be dropped and recreated locally."
  read -r -p "Type '$SCHEMA' to continue: " confirm
  if [ "$confirm" != "$SCHEMA" ]; then
    echo "[INFO] Cancelled."
    exit 1
  fi

  if [ -n "${DEV_DB_PASSWORD:-}" ]; then
    export MYSQL_PWD="$DEV_DB_PASSWORD"
  fi
  mysql -h "$DEV_DB_HOST" -P "$DEV_DB_PORT" -u "$DEV_DB_USER" -e "DROP DATABASE IF EXISTS \`$SCHEMA\`; CREATE DATABASE \`$SCHEMA\`;"
  unset MYSQL_PWD || true
  echo "[INFO] Recreated local schema '$SCHEMA'."
fi

exec "$BASE_SCRIPT" --db-only --schema "$SCHEMA"

