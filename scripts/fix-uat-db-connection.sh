#!/bin/bash
# Fix UAT Cloud Run database connection: set DATABASE_URL and Cloud SQL instance.
# Run from repo root. Requires gcloud and project ducklin-uk-uat.

set -e
PROJECT_ID="${GCP_PROJECT_ID:-ducklin-uk-uat}"
REGION="europe-west1"
SERVICE_NAME="pos-backend"
CONNECTION_NAME="${PROJECT_ID}:${REGION}:pos-database"
# Password URL-encoded: ] = %5D, < = %3C
DATABASE_URL="mysql://pos_user:BDcm%5DR1bGe%3CDrNq0@/pos_system?unix_socket=/cloudsql/${CONNECTION_NAME}"

echo "Project: $PROJECT_ID"
echo "Service: $SERVICE_NAME"
echo "Cloud SQL instance: $CONNECTION_NAME"

# Warn if Cloud SQL instance doesn't exist (connection name might differ)
if ! gcloud sql instances describe pos-database --project="$PROJECT_ID" &>/dev/null; then
  echo "WARNING: Cloud SQL instance 'pos-database' not found in $PROJECT_ID. If your instance has another name, set CONNECTION_NAME and re-run."
fi

echo "Updating Cloud Run service with DATABASE_URL and Cloud SQL connection..."
gcloud run services update "$SERVICE_NAME" \
  --region="$REGION" \
  --update-env-vars="DATABASE_URL=$DATABASE_URL" \
  --add-cloudsql-instances="$CONNECTION_NAME" \
  --project="$PROJECT_ID"

echo "Done. Wait ~1 minute for the new revision, then:"
echo "  curl -s https://pos-backend-28040503481.europe-west1.run.app/health"
echo "  curl -s 'https://pos-backend-28040503481.europe-west1.run.app/api/v1/products'"
