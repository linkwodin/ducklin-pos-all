#!/bin/bash
#
# Create production GCP project (ducklin-uk-prod), mirror UAT infrastructure,
# clone UAT data, and deploy backend.
#
# Usage:
#   ./scripts/setup-prod-from-uat.sh
#   ./scripts/setup-prod-from-uat.sh --skip-clone    # infra only
#   ./scripts/setup-prod-from-uat.sh --skip-deploy   # infra + clone, no Cloud Build
#
# Environment:
#   PROD_PROJECT_ID     (default: ducklin-uk-prod)
#   UAT_PROJECT_ID      (default: ducklin-uk-uat)
#   BILLING_ACCOUNT_ID  (default: ducklin uk billing account)
#   REGION              (default: europe-west1)
#   PROD_DB_PASSWORD    (generated if unset; saved to Secret Manager)
#   UAT_DB_PASSWORD     (for clone; prompt if unset)
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

PROD_PROJECT_ID="${PROD_PROJECT_ID:-ducklin-uk-prod}"
UAT_PROJECT_ID="${UAT_PROJECT_ID:-ducklin-uk-uat}"
REGION="${REGION:-europe-west1}"
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:-01004A-7AEB39-B0D3A5}"
INSTANCE="pos-database"
DATABASE="pos_system"
DB_USER="pos_user"
SKIP_CLONE=0
SKIP_DEPLOY=0
SKIP_INFRA=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-clone) SKIP_CLONE=1 ;;
    --skip-deploy) SKIP_DEPLOY=1 ;;
    --skip-infra) SKIP_INFRA=1 ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

urlencode() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

gen_password() {
  python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(24)))'
}

require_gcloud() {
  if ! command -v gcloud &>/dev/null; then
    print_error "gcloud CLI is required."
    exit 1
  fi
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    print_error "Run: gcloud auth login"
    exit 1
  fi
}

create_project() {
  if gcloud projects describe "$PROD_PROJECT_ID" &>/dev/null; then
    print_warn "Project $PROD_PROJECT_ID already exists."
  else
    print_info "Creating GCP project $PROD_PROJECT_ID ..."
    gcloud projects create "$PROD_PROJECT_ID" --name="$PROD_PROJECT_ID"
  fi

  print_info "Linking billing account $BILLING_ACCOUNT_ID ..."
  gcloud billing projects link "$PROD_PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID" || print_warn "Billing may already be linked."

  gcloud config set project "$PROD_PROJECT_ID"
  print_info "Active project: $PROD_PROJECT_ID"
}

enable_apis() {
  print_info "Enabling APIs ..."
  gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    sqladmin.googleapis.com \
    storage-component.googleapis.com \
    storage-api.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    containerregistry.googleapis.com \
    firebase.googleapis.com \
    cloudfunctions.googleapis.com \
    --project="$PROD_PROJECT_ID"
}

create_buckets() {
  for suffix in pos-uploads pos-frontend pos-frontend-uat; do
    local bucket="${PROD_PROJECT_ID}-${suffix}"
    if ! gsutil ls -b "gs://$bucket" &>/dev/null; then
      print_info "Creating bucket gs://$bucket"
      gsutil mb -p "$PROD_PROJECT_ID" -c STANDARD -l "$REGION" "gs://$bucket"
    fi
    if [[ "$suffix" == *uploads* ]]; then
      gsutil iam ch allUsers:objectViewer "gs://$bucket" 2>/dev/null || true
    fi
    if [[ "$suffix" == *frontend* ]]; then
      gcloud storage buckets update "gs://$bucket" \
        --web-main-page-suffix=index.html \
        --web-error-page=index.html 2>/dev/null || true
      gsutil iam ch allUsers:objectViewer "gs://$bucket" 2>/dev/null || true
    fi
  done
}

create_cloud_sql() {
  if gcloud sql instances describe "$INSTANCE" --project="$PROD_PROJECT_ID" &>/dev/null; then
    print_warn "Cloud SQL instance $INSTANCE already exists in prod."
    if [ -z "${PROD_DB_PASSWORD:-}" ]; then
      PROD_DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password --project="$PROD_PROJECT_ID" 2>/dev/null || true)"
      if [ -n "$PROD_DB_PASSWORD" ]; then
        print_info "Loaded prod pos_user password from Secret Manager (db-password)."
      fi
    fi
    return
  fi

  if [ -z "${PROD_DB_ROOT_PASSWORD:-}" ]; then
    PROD_DB_ROOT_PASSWORD="$(gen_password)"
    print_info "Generated prod MySQL root password (stored in Secret Manager: db-root-password)."
  fi
  if [ -z "${PROD_DB_PASSWORD:-}" ]; then
    PROD_DB_PASSWORD="$(gen_password)"
    print_info "Generated prod pos_user password (stored in Secret Manager: db-password)."
  fi

  print_info "Creating Cloud SQL instance (this may take several minutes) ..."
  gcloud sql instances create "$INSTANCE" \
    --database-version=MYSQL_8_0 \
    --tier=db-f1-micro \
    --region="$REGION" \
    --root-password="$PROD_DB_ROOT_PASSWORD" \
    --storage-type=SSD \
    --storage-size=20GB \
    --backup-start-time=03:00 \
    --project="$PROD_PROJECT_ID"

  gcloud sql databases create "$DATABASE" --instance="$INSTANCE" --project="$PROD_PROJECT_ID"
  gcloud sql users create "$DB_USER" \
    --instance="$INSTANCE" \
    --password="$PROD_DB_PASSWORD" \
    --project="$PROD_PROJECT_ID"
}

store_secrets() {
  local connection="${PROD_PROJECT_ID}:${REGION}:${INSTANCE}"
  if [ -z "${PROD_DB_PASSWORD:-}" ]; then
    PROD_DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password --project="$PROD_PROJECT_ID" 2>/dev/null || true)"
  fi
  if [ -z "${PROD_DB_PASSWORD:-}" ]; then
    print_error "PROD_DB_PASSWORD is not set and db-password secret is missing."
    exit 1
  fi
  local encoded_pw
  encoded_pw="$(urlencode "$PROD_DB_PASSWORD")"
  local database_url="mysql://${DB_USER}:${encoded_pw}@/${DATABASE}?unix_socket=/cloudsql/${connection}"

  if [ -z "${JWT_SECRET:-}" ]; then
    JWT_SECRET="$(gen_password)$(gen_password)"
  fi

  upsert_secret() {
    local name="$1"
    local value="$2"
    if gcloud secrets describe "$name" --project="$PROD_PROJECT_ID" &>/dev/null; then
      printf '%s' "$value" | gcloud secrets versions add "$name" --data-file=- --project="$PROD_PROJECT_ID"
    else
      printf '%s' "$value" | gcloud secrets create "$name" --data-file=- --project="$PROD_PROJECT_ID"
    fi
  }

  upsert_secret jwt-secret "$JWT_SECRET"
  upsert_secret db-password "$PROD_DB_PASSWORD"
  upsert_secret db-connection "$database_url"
  if [ -n "${PROD_DB_ROOT_PASSWORD:-}" ]; then
    upsert_secret db-root-password "$PROD_DB_ROOT_PASSWORD"
  fi

  local project_number
  project_number="$(gcloud projects describe "$PROD_PROJECT_ID" --format='value(projectNumber)')"
  local sa="${project_number}-compute@developer.gserviceaccount.com"
  for secret in jwt-secret db-password db-connection; do
    gcloud secrets add-iam-policy-binding "$secret" \
      --member="serviceAccount:${sa}" \
      --role="roles/secretmanager.secretAccessor" \
      --project="$PROD_PROJECT_ID" &>/dev/null || true
  done

  gcloud projects add-iam-policy-binding "$PROD_PROJECT_ID" \
    --member="serviceAccount:${sa}" \
    --role="roles/cloudsql.client" \
    --condition=None &>/dev/null || true

  export PROD_DATABASE_URL="$database_url"
  print_info "Secrets stored (jwt-secret, db-password, db-connection)."
}

enable_public_sql_ip() {
  print_info "Ensuring Cloud SQL has a public IP for clone import ..."
  gcloud sql instances patch "$INSTANCE" \
    --assign-ip \
    --project="$PROD_PROJECT_ID" || true
}

init_firebase() {
  if ! command -v firebase &>/dev/null; then
    print_warn "Firebase CLI not installed; skip Firebase init. Run: npm i -g firebase-tools"
    return
  fi
  print_info "Adding Firebase to $PROD_PROJECT_ID ..."
  firebase projects:addfirebase "$PROD_PROJECT_ID" 2>/dev/null || print_warn "Firebase may already be enabled."
}

deploy_backend() {
  print_info "Deploying backend via Cloud Build (prod uses db-connection secret) ..."
  cd "$REPO_ROOT/backend"
  gcloud builds submit --config=cloudbuild.yaml \
    --project="$PROD_PROJECT_ID"
  cd "$REPO_ROOT"

  local backend_url
  backend_url="$(gcloud run services describe pos-backend --region="$REGION" --project="$PROD_PROJECT_ID" --format='value(status.url)' 2>/dev/null || true)"
  if [ -n "$backend_url" ]; then
    print_info "Patching BASE_URL to $backend_url"
    gcloud run services update pos-backend \
      --region="$REGION" \
      --project="$PROD_PROJECT_ID" \
      --update-env-vars="BASE_URL=${backend_url}" \
      --update-secrets="DATABASE_URL=db-connection:latest,JWT_SECRET=jwt-secret:latest" || true
  fi
}

write_prod_env_file() {
  local backend_url
  backend_url="$(gcloud run services describe pos-backend --region="$REGION" --project="$PROD_PROJECT_ID" --format='value(status.url)' 2>/dev/null || echo "https://pos-backend-CHANGE_ME.europe-west1.run.app")"
  local env_file="$REPO_ROOT/management-frontend/.env.production"
  cat > "$env_file" <<EOF
VITE_API_URL=${backend_url}/api/v1
VITE_AI_PLAYBOOK_URL=/api/ai-playbook
EOF
  print_info "Wrote $env_file"
}

main() {
  require_gcloud
  print_info "=== Production setup from UAT ==="
  print_info "Prod: $PROD_PROJECT_ID | UAT: $UAT_PROJECT_ID | Region: $REGION"
  echo

  create_project
  if [ "$SKIP_INFRA" = "0" ]; then
    enable_apis
    create_buckets
    create_cloud_sql
    enable_public_sql_ip
    store_secrets
    init_firebase
  else
    print_info "Skipping infra (--skip-infra); loading prod DB password from Secret Manager ..."
    PROD_DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password --project="$PROD_PROJECT_ID" 2>/dev/null || true)"
  fi

  if [ "$SKIP_CLONE" = "0" ]; then
    print_info "Cloning UAT database and uploads into prod ..."
    PROD_PROJECT_ID="$PROD_PROJECT_ID" UAT_PROJECT_ID="$UAT_PROJECT_ID" \
    PROD_DB_PASSWORD="$PROD_DB_PASSWORD" \
    AUTO_CONFIRM=1 \
    "$SCRIPT_DIR/clone-uat-to-prod.sh" || print_warn "Clone step failed — check logs."
  fi

  if [ "$SKIP_DEPLOY" = "0" ]; then
    deploy_backend
    write_prod_env_file
  fi

  print_info "=== Production setup complete ==="
  print_info "Project:     $PROD_PROJECT_ID"
  print_info "Cloud SQL:   ${PROD_PROJECT_ID}:${REGION}:${INSTANCE}"
  print_info "Uploads:     gs://${PROD_PROJECT_ID}-pos-uploads"
  print_info "Next steps:"
  print_info "  1. Deploy management portal: PROD_PROJECT_ID=$PROD_PROJECT_ID ./scripts/deploy-firebase.sh production"
  print_info "  2. Configure SMTP on Cloud Run (Console → pos-backend → Variables)"
  print_info "  3. Point custom DNS at prod Firebase / Cloud Run when ready"
  print_info "  4. Build Flutter with: --dart-define=ENV=production --dart-define=API_BASE_URL=<backend>/api/v1"
}

main "$@"
