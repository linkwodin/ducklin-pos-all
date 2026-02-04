# UAT Environment Deployment Guide

This guide shows how to deploy and configure the POS system for UAT (User Acceptance Testing) environment.

## Database Configuration

- **User**: `pos_user`
- **Password**: `BDcm]R1bGe<DrNq0`
- **Database**: `pos_system`
- **Instance**: `pos-database`
- **Region**: `europe-west1`

## Step 1: Get Database Connection Info

```bash
PROJECT_ID=$(gcloud config get-value project)
CONNECTION_NAME=$(gcloud sql instances describe pos-database --format="value(connectionName)")
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")

echo "Connection Name: $CONNECTION_NAME"
echo "Database IP: $DB_IP"
```

## Step 2: Initialize Database Schema

```bash
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")
mysql -h $DB_IP -u pos_user -p'BDcm]R1bGe<DrNq0' pos_system < database/schema.sql
```

## Step 3: Deploy Backend to UAT

### Option A: Using Cloud Build

Update `backend/cloudbuild.yaml` to deploy to UAT service, or create a separate build:

```bash
cd backend

# Deploy to UAT
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_REGION=europe-west1,_CLOUD_SQL_CONNECTION=$PROJECT_ID:europe-west1:pos-database
```

### Option B: Direct Deployment

```bash
cd backend

PROJECT_ID=$(gcloud config get-value project)
CONNECTION_NAME="$PROJECT_ID:europe-west1:pos-database"

gcloud run deploy pos-backend-uat \
  --source . \
  --region=europe-west1 \
  --platform=managed \
  --allow-unauthenticated \
  --set-env-vars="STORAGE_PROVIDER=gcp,GCP_BUCKET_NAME=$PROJECT_ID-pos-uploads,ENVIRONMENT=uat" \
  --set-secrets="JWT_SECRET=jwt-secret:latest" \
  --add-cloudsql-instances=$CONNECTION_NAME \
  --memory=512Mi \
  --cpu=1 \
  --timeout=300 \
  --max-instances=10
```

### Set Database URL Secret

Store the database connection string in Secret Manager:

```bash
# Construct database URL
PROJECT_ID=$(gcloud config get-value project)
CONNECTION_NAME="$PROJECT_ID:europe-west1:pos-database"
DATABASE_URL="mysql://pos_user:BDcm]R1bGe<DrNq0@/pos_system?unix_socket=/cloudsql/$CONNECTION_NAME"

# Store in Secret Manager
echo -n "$DATABASE_URL" | gcloud secrets create db-connection-uat --data-file=-

# Grant access
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding db-connection-uat \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"
```

Then update Cloud Run to use the secret:
```bash
gcloud run services update pos-backend-uat \
  --region=europe-west1 \
  --set-secrets="DATABASE_URL=db-connection-uat:latest"
```

### Get Backend URL

```bash
UAT_BACKEND_URL=$(gcloud run services describe pos-backend-uat --region=europe-west1 --format="value(status.url)")
echo "UAT Backend URL: $UAT_BACKEND_URL"
```

## Step 4: Configure Flutter App for UAT

### Update API Configuration

The Flutter app now uses environment-based configuration. Update `frontend/lib/config/api_config.dart`:

```dart
static const String _uatUrl = 'https://YOUR-UAT-BACKEND-URL.run.app/api/v1';
```

### Build Flutter App for UAT

```bash
cd frontend

# For macOS
flutter build macos --release --dart-define=ENV=uat --dart-define=API_BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1

# For iOS
flutter build ios --release --dart-define=ENV=uat --dart-define=API_BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1

# For Android
flutter build apk --release --dart-define=ENV=uat --dart-define=API_BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1
```

## Step 5: Configure React Frontend for UAT

### Update Environment File

Edit `management-frontend/.env.uat`:

```bash
VITE_API_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1
```

### Build Frontend for UAT

```bash
cd management-frontend

# Build for UAT
npm run build:uat

# Or manually set the URL
VITE_API_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1 npm run build
```

### Deploy Frontend to UAT Bucket

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="$PROJECT_ID-pos-frontend-uat"

# Create bucket if it doesn't exist
gsutil mb -p "$PROJECT_ID" -c STANDARD -l europe-west1 "gs://$BUCKET_NAME" || true
gsutil web set -m index.html -e index.html "gs://$BUCKET_NAME"

# Deploy
gsutil -m rsync -r -d dist/ "gs://$BUCKET_NAME/"
gsutil -m setmeta -h "Cache-Control:public, max-age=3600" "gs://$BUCKET_NAME/**"
```

## Quick Reference

### Database Connection String
```
mysql://pos_user:BDcm]R1bGe<DrNq0@/pos_system?unix_socket=/cloudsql/PROJECT_ID:europe-west1:pos-database
```

### Test Database Connection
```bash
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")
mysql -h $DB_IP -u pos_user -p'BDcm]R1bGe<DrNq0' pos_system -e "SELECT 1;"
```

### Environment Variables Summary

**Backend (Cloud Run)**:
- `DATABASE_URL`: Connection string (from Secret Manager)
- `STORAGE_PROVIDER`: `gcp`
- `GCP_BUCKET_NAME`: `PROJECT_ID-pos-uploads`
- `ENVIRONMENT`: `uat`
- `BASE_URL`: UAT backend URL

**Flutter App**:
- `ENV`: `uat`
- `API_BASE_URL`: UAT backend URL

**React Frontend**:
- `VITE_API_URL`: UAT backend URL

## Troubleshooting

### Backend can't connect to database
1. Verify Cloud SQL connection name is correct
2. Check Cloud Run has Cloud SQL connection enabled
3. Verify database user and password
4. Check Cloud SQL instance is running

### Flutter app can't reach backend
1. Verify backend URL is correct
2. Check backend is deployed and running
3. Verify CORS is configured on backend
4. Check network connectivity

### Frontend can't reach backend
1. Verify `VITE_API_URL` is set correctly
2. Rebuild frontend after changing environment variable
3. Check browser console for CORS errors

