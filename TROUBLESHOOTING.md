# Troubleshooting Cloud Run Deployment

## Container Failed to Start on Port 8080

### Common Causes:

1. **Database Connection Failure**
   - The app crashes during startup if it can't connect to the database
   - Check Cloud Run logs for database connection errors

2. **Missing Environment Variables**
   - `DATABASE_URL` must be set correctly
   - Cloud SQL connection must be configured

3. **Startup Timeout**
   - Database connection might be taking too long
   - Solution: Enable CPU boost and increase timeout

### Solutions:

#### 1. Check Cloud Run Logs

```bash
# View recent logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=pos-backend" --limit=50 --format=json

# Or view in Cloud Console
# https://console.cloud.google.com/run
```

#### 2. Verify Database Connection

```bash
# Get Cloud SQL connection name
CONNECTION_NAME=$(gcloud sql instances describe pos-database --format="value(connectionName)")

# Verify it's set in Cloud Run
gcloud run services describe pos-backend --region=europe-west1 --format="value(spec.template.spec.containers[0].env)"
```

#### 3. Set Database URL Correctly

The database URL format for Cloud SQL Unix socket:
```
mysql://pos_user:BDcm]R1bGe<DrNq0@/pos_system?unix_socket=/cloudsql/PROJECT_ID:europe-west1:pos-database
```

Store it in Secret Manager:
```bash
PROJECT_ID=$(gcloud config get-value project)
CONNECTION_NAME="$PROJECT_ID:europe-west1:pos-database"
DATABASE_URL="mysql://pos_user:BDcm]R1bGe<DrNq0@/pos_system?unix_socket=/cloudsql/$CONNECTION_NAME"

echo -n "$DATABASE_URL" | gcloud secrets create db-connection --data-file=-

# Grant access
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding db-connection \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"
```

Then update Cloud Run:
```bash
gcloud run services update pos-backend \
  --region=europe-west1 \
  --set-secrets="DATABASE_URL=db-connection:latest"
```

#### 4. Increase Startup Timeout

```bash
gcloud run services update pos-backend \
  --region=europe-west1 \
  --timeout=300 \
  --cpu-boost
```

#### 5. Test Database Connection Locally

```bash
# Get database IP
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")

# Test connection
mysql -h $DB_IP -u pos_user -p'BDcm]R1bGe<DrNq0' pos_system -e "SELECT 1;"
```

#### 6. Verify Cloud SQL Connection in Cloud Run

```bash
# Check if Cloud SQL connection is enabled
gcloud run services describe pos-backend \
  --region=europe-west1 \
  --format="value(spec.template.spec.containers[0].env)"
```

### Debugging Steps:

1. **Check if database exists and is accessible:**
   ```bash
   gcloud sql databases list --instance=pos-database
   gcloud sql users list --instance=pos-database
   ```

2. **Verify Cloud Run service account has Cloud SQL Client role:**
   ```bash
   PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
   SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
   
   gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member="serviceAccount:$SERVICE_ACCOUNT" \
     --role="roles/cloudsql.client"
   ```

3. **Test the container locally:**
   ```bash
   # Build image
   docker build -t pos-backend-test ./backend
   
   # Run with environment variables
   docker run -p 8080:8080 \
     -e PORT=8080 \
     -e DATABASE_URL="mysql://pos_user:BDcm]R1bGe<DrNq0@DB_IP/pos_system" \
     -e STORAGE_PROVIDER=local \
     pos-backend-test
   ```

4. **Check startup logs:**
   ```bash
   gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=pos-backend AND severity>=ERROR" --limit=20
   ```

### Quick Fix Command:

```bash
# Get connection info
PROJECT_ID=$(gcloud config get-value project)
CONNECTION_NAME="$PROJECT_ID:europe-west1:pos-database"

# Update Cloud Run with proper settings
gcloud run services update pos-backend \
  --region=europe-west1 \
  --timeout=300 \
  --cpu-boost \
  --set-env-vars="STORAGE_PROVIDER=gcp,GCP_BUCKET_NAME=$PROJECT_ID-pos-uploads,ENVIRONMENT=production" \
  --add-cloudsql-instances=$CONNECTION_NAME
```

### Common Error Messages:

- **"Failed to initialize database"**: Database URL is wrong or database is not accessible
- **"Connection refused"**: Cloud SQL connection not configured in Cloud Run
- **"Access denied"**: Database user/password is incorrect
- **"Container failed to start"**: App crashed during startup (check logs)

