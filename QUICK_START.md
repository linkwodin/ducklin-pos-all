# Quick Start Deployment Guide

This is a simplified guide to get your POS system deployed to GCP quickly.

## Prerequisites

1. Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
2. Login: `gcloud auth login`
3. Create/select project: `gcloud config set project YOUR_PROJECT_ID`

## Step 1: Initial Setup (One-time)

Run the setup script to create all necessary GCP resources:

```bash
./scripts/setup-gcp.sh
```

This will:
- Enable required APIs
- Create Cloud SQL database instance
- Create Cloud Storage buckets
- Set up secrets

## Step 2: Initialize Database

After the database is created, run the schema:

```bash
# Get the database IP
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")

# Run schema (you'll be prompted for password)
mysql -h $DB_IP -u pos_user -p pos_system < database/schema.sql
```

## Step 3: Deploy Backend

```bash
./scripts/deploy.sh backend
```

Or manually:

```bash
cd backend
gcloud builds submit --config=cloudbuild.yaml
```

## Step 4: Deploy Frontend

```bash
./scripts/deploy.sh frontend
```

Or manually:

```bash
cd management-frontend
npm install
npm run build
gsutil -m rsync -r -d dist/ gs://YOUR_PROJECT_ID-pos-frontend/
```

## Step 5: Get URLs

```bash
# Backend URL
gcloud run services describe pos-backend --region=europe-west1 --format="value(status.url)"

# Frontend URL
echo "https://storage.googleapis.com/YOUR_PROJECT_ID-pos-frontend/index.html"
```

## Step 6: Update Frontend API URL

Before deploying frontend, update the API URL:

1. Edit `management-frontend/src/services/api.ts`
2. Change the base URL to your Cloud Run backend URL
3. Rebuild and redeploy

## Troubleshooting

### Backend not starting
- Check logs: `gcloud logging read "resource.type=cloud_run_revision" --limit=50`
- Verify database connection name in Cloud Run service
- Check environment variables

### Frontend not loading
- Verify bucket exists: `gsutil ls gs://YOUR_PROJECT_ID-pos-frontend/`
- Check bucket permissions
- Verify index.html exists

### Database connection issues
- Verify Cloud SQL instance is running
- Check connection name format: `PROJECT_ID:REGION:INSTANCE_NAME`
- Verify service account has Cloud SQL Client role

## Next Steps

1. Set up custom domain (optional)
2. Configure SSL certificates
3. Set up monitoring and alerts
4. Configure backups

For detailed information, see [DEPLOYMENT.md](./DEPLOYMENT.md)

