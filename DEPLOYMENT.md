# GCP Deployment Guide

This guide will help you deploy the POS system to Google Cloud Platform.

## Prerequisites

1. **Google Cloud Account**: Sign up at [cloud.google.com](https://cloud.google.com)
2. **Google Cloud SDK**: Install [gcloud CLI](https://cloud.google.com/sdk/docs/install)
3. **Docker**: For local testing (optional)
4. **Billing Account**: Enable billing on your GCP project

## Architecture Overview

- **Backend**: Cloud Run (Go API)
- **Database**: Cloud SQL (MySQL)
- **Management Frontend**: Cloud Storage + Cloud CDN (React app)
- **File Storage**: Cloud Storage (for product images)
- **Flutter App**: Distributed via app stores (not deployed to GCP)

## Step 1: Initial Setup

### 1.1 Create a GCP Project

```bash
# Login to GCP
gcloud auth login

# Create a new project (or use existing)
gcloud projects create pos-system --name="POS System"

# Set the project as default
gcloud config set project pos-system

# Enable required APIs
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  sqladmin.googleapis.com \
  storage-component.googleapis.com \
  storage-api.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  containerregistry.googleapis.com
```

### 1.2 Set Project ID Variable

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west1
```

## Step 2: Database Setup (Cloud SQL)

### 2.1 Create Cloud SQL Instance

```bash
gcloud sql instances create pos-database \
  --database-version=MYSQL_8_0 \
  --tier=db-f1-micro \
  --region=$REGION \
  --root-password=CHANGE_THIS_PASSWORD \
  --storage-type=SSD \
  --storage-size=20GB \
  --backup-start-time=03:00
```

**⚠️ Important**: Change `CHANGE_THIS_PASSWORD` to a strong password and save it securely.

### 2.2 Create Database

```bash
gcloud sql databases create pos_system --instance=pos-database
```

### 2.3 Get Connection Name

```bash
gcloud sql instances describe pos-database --format="value(connectionName)"
```

Save this connection name (format: `PROJECT_ID:REGION:pos-database`)

### 2.4 Create Database User

```bash
gcloud sql users create pos_user \
  --instance=pos-database \
  --password=CHANGE_THIS_PASSWORD
```

## Step 3: Cloud Storage Setup

### 3.1 Create Storage Bucket for Files

```bash
gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$PROJECT_ID-pos-uploads

# Make bucket publicly readable (for product images)
gsutil iam ch allUsers:objectViewer gs://$PROJECT_ID-pos-uploads
```

### 3.2 Create Storage Bucket for Frontend

```bash
gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$PROJECT_ID-pos-frontend

# Enable static website hosting
gsutil web set -m index.html -e index.html gs://$PROJECT_ID-pos-frontend
```

## Step 4: Secrets Management

### 4.1 Store Secrets in Secret Manager

```bash
# JWT Secret
echo -n "YOUR_STRONG_JWT_SECRET_HERE" | gcloud secrets create jwt-secret --data-file=-

# Database Password
echo -n "YOUR_DATABASE_PASSWORD" | gcloud secrets create db-password --data-file=-

# Database User
echo -n "pos_user" | gcloud secrets create db-user --data-file=-
```

### 4.2 Grant Cloud Run Access to Secrets

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding jwt-secret \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding db-user \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"
```

## Step 5: Deploy Backend (Cloud Run)

### 5.1 Update Cloud Build Configuration

The `backend/cloudbuild.yaml` is already configured. Review and update if needed.

### 5.2 Build and Deploy

```bash
cd backend

# Submit build to Cloud Build
gcloud builds submit --config=cloudbuild.yaml

# Or deploy manually
gcloud run deploy pos-backend \
  --source . \
  --region=$REGION \
  --platform=managed \
  --allow-unauthenticated \
  --set-env-vars="STORAGE_PROVIDER=gcp,GCP_BUCKET_NAME=$PROJECT_ID-pos-uploads,ENVIRONMENT=production" \
  --set-secrets="JWT_SECRET=jwt-secret:latest,DATABASE_URL=db-connection:latest" \
  --add-cloudsql-instances=$PROJECT_ID:$REGION:pos-database \
  --memory=512Mi \
  --cpu=1 \
  --timeout=300 \
  --max-instances=10
```

### 5.3 Get Backend URL

```bash
BACKEND_URL=$(gcloud run services describe pos-backend --region=$REGION --format="value(status.url)")
echo "Backend URL: $BACKEND_URL"
```

## Step 6: Initialize Database Schema

### 6.1 Connect to Database

```bash
# Get connection name
CONNECTION_NAME=$(gcloud sql instances describe pos-database --format="value(connectionName)")

# Connect using Cloud SQL Proxy (if needed)
# Or use gcloud sql connect
gcloud sql connect pos-database --user=pos_user
```

### 6.2 Run Schema

```bash
# From your local machine
mysql -h <INSTANCE_IP> -u pos_user -p pos_system < database/schema.sql

# Or using Cloud SQL Proxy
cloud_sql_proxy -instances=$CONNECTION_NAME=tcp:3306 &
mysql -h 127.0.0.1 -u pos_user -p pos_system < database/schema.sql
```

## Step 7: Deploy Management Frontend

### 7.1 Build Frontend

```bash
cd management-frontend

# Install dependencies
npm install

# Build for production
npm run build
```

### 7.2 Deploy to Cloud Storage

```bash
# Upload to bucket
gsutil -m rsync -r -d dist/ gs://$PROJECT_ID-pos-frontend/

# Set cache control
gsutil -m setmeta -h "Cache-Control:public, max-age=3600" \
  gs://$PROJECT_ID-pos-frontend/**
```

### 7.3 Configure CORS (if needed)

Create `cors.json`:
```json
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD"],
    "responseHeader": ["Content-Type"],
    "maxAgeSeconds": 3600
  }
]
```

```bash
gsutil cors set cors.json gs://$PROJECT_ID-pos-frontend
```

### 7.4 Set Up Custom Domain (Optional)

```bash
# Create a load balancer or use Cloud CDN
# See: https://cloud.google.com/storage/docs/hosting-static-website
```

## Step 8: Configure Environment Variables

### 8.1 Update Frontend API URL

Before building, update the API service URL in `management-frontend/src/services/api.ts`:

```typescript
const API_BASE_URL = process.env.VITE_API_URL || 'https://YOUR-BACKEND-URL.run.app';
```

Or set it during build:
```bash
VITE_API_URL=$BACKEND_URL npm run build
```

### 8.2 Update Flutter App API URL

Update `frontend/lib/services/api_service.dart`:
```dart
static const String baseUrl = 'https://YOUR-BACKEND-URL.run.app';
```

## Step 9: Set Up Cloud Build Triggers (Optional)

### 9.1 Connect Repository

```bash
# Connect to GitHub/Cloud Source Repositories
gcloud source repos create pos-system
```

### 9.2 Create Build Trigger

```bash
gcloud builds triggers create github \
  --repo-name=pos-system \
  --repo-owner=YOUR_GITHUB_USERNAME \
  --branch-pattern="^main$" \
  --build-config=backend/cloudbuild.yaml
```

## Step 10: Monitoring and Logging

### 10.1 View Logs

```bash
# Backend logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50

# Or in Cloud Console
# https://console.cloud.google.com/logs
```

### 10.2 Set Up Alerts

Create alerting policies in Cloud Console for:
- High error rates
- High latency
- Database connection issues

## Step 11: Security Checklist

- [ ] Change all default passwords
- [ ] Enable Cloud SQL SSL connections
- [ ] Restrict Cloud Storage bucket access
- [ ] Set up VPC connector if needed
- [ ] Enable Cloud Armor for DDoS protection
- [ ] Set up IAM roles properly
- [ ] Enable audit logging
- [ ] Use Secret Manager for all secrets

## Step 12: Cost Optimization

- Use Cloud SQL with appropriate tier
- Enable Cloud CDN for frontend
- Set up autoscaling limits
- Use Cloud Scheduler for cleanup jobs
- Monitor costs in Cloud Console

## Troubleshooting

### Backend not connecting to database

1. Check Cloud SQL connection name
2. Verify Cloud Run has Cloud SQL connection
3. Check database user permissions
4. Verify network connectivity

### Frontend not loading

1. Check bucket permissions
2. Verify index.html exists
3. Check CORS configuration
4. Verify API URL in frontend

### Images not uploading

1. Check Cloud Storage bucket permissions
2. Verify service account has storage access
3. Check bucket name in environment variables

## Useful Commands

```bash
# View Cloud Run services
gcloud run services list

# View Cloud SQL instances
gcloud sql instances list

# View storage buckets
gsutil ls

# View build history
gcloud builds list

# View logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

## Next Steps

1. Set up custom domain
2. Configure SSL certificates
3. Set up CI/CD pipeline
4. Configure monitoring and alerts
5. Set up backup strategy
6. Configure disaster recovery

## Support

For issues, check:
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)

