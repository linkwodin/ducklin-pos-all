# UAT Environment Configuration

This document contains the configuration for the UAT (User Acceptance Testing) environment.

## Database Configuration

- **User**: `pos_user`
- **Password**: `BDcm]R1bGe<DrNq0`
- **Database**: `pos_system`
- **Instance**: `pos-database`

## Connection Strings

### For Cloud Run (Unix Socket)
```
mysql://pos_user:BDcm]R1bGe<DrNq0@/pos_system?unix_socket=/cloudsql/PROJECT_ID:europe-west1:pos-database
```

### For Direct Connection (IP)
```
mysql://pos_user:BDcm]R1bGe<DrNq0@DB_IP/pos_system
```

To get the database IP:
```bash
gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)"
```

## Backend Configuration

### Environment Variables for Cloud Run

```bash
DATABASE_URL=mysql://pos_user:BDcm]R1bGe<DrNq0@/pos_system?unix_socket=/cloudsql/PROJECT_ID:europe-west1:pos-database
STORAGE_PROVIDER=gcp
GCP_BUCKET_NAME=PROJECT_ID-pos-uploads
ENVIRONMENT=uat
BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app
```

### Deploy Backend with UAT Config

```bash
cd backend

gcloud run deploy pos-backend-uat \
  --source . \
  --region=europe-west1 \
  --platform=managed \
  --allow-unauthenticated \
  --set-env-vars="STORAGE_PROVIDER=gcp,GCP_BUCKET_NAME=$PROJECT_ID-pos-uploads,ENVIRONMENT=uat,BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app" \
  --set-secrets="JWT_SECRET=jwt-secret:latest" \
  --add-cloudsql-instances=$PROJECT_ID:europe-west1:pos-database \
  --memory=512Mi \
  --cpu=1 \
  --timeout=300 \
  --max-instances=10
```

## Flutter App Configuration

### Update API Service

Edit `frontend/lib/services/api_service.dart`:

```dart
class ApiService {
  // UAT Environment
  static const String baseUrl = 'https://YOUR-UAT-BACKEND-URL.run.app/api/v1';
  
  // Or use environment variable
  // static const String baseUrl = String.fromEnvironment(
  //   'API_BASE_URL',
  //   defaultValue: 'https://YOUR-UAT-BACKEND-URL.run.app/api/v1',
  // );
  
  // ... rest of the code
}
```

### Build Flutter App for UAT

```bash
cd frontend

# For macOS
flutter build macos --release --dart-define=API_BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1

# For iOS
flutter build ios --release --dart-define=API_BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1

# For Android
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1
```

## React Frontend Configuration

### Update API Service

Edit `management-frontend/src/services/api.ts`:

```typescript
// UAT Environment
const API_BASE_URL = import.meta.env.VITE_API_URL || 'https://YOUR-UAT-BACKEND-URL.run.app/api/v1';
```

### Build and Deploy Frontend for UAT

```bash
cd management-frontend

# Set API URL for UAT
export VITE_API_URL=https://YOUR-UAT-BACKEND-URL.run.app/api/v1

# Build
npm run build

# Deploy to UAT bucket
gsutil -m rsync -r -d dist/ gs://$PROJECT_ID-pos-frontend-uat/
```

## Secret Manager (Optional but Recommended)

Store the database password in Secret Manager instead of hardcoding:

```bash
# Store database password
echo -n "BDcm]R1bGe<DrNq0" | gcloud secrets create db-password-uat --data-file=-

# Grant access to Cloud Run service account
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding db-password-uat \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"
```

Then use it in Cloud Run:
```bash
--set-secrets="DATABASE_PASSWORD=db-password-uat:latest"
```

## Quick Setup Commands

### 1. Get Database Connection Info
```bash
PROJECT_ID=$(gcloud config get-value project)
CONNECTION_NAME=$(gcloud sql instances describe pos-database --format="value(connectionName)")
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")

echo "Connection Name: $CONNECTION_NAME"
echo "Database IP: $DB_IP"
echo "Connection String: mysql://pos_user:BDcm]R1bGe<DrNq0@$DB_IP/pos_system"
```

### 2. Test Database Connection
```bash
mysql -h $DB_IP -u pos_user -p'BDcm]R1bGe<DrNq0' pos_system -e "SELECT 1;"
```

### 3. Initialize Database Schema
```bash
DB_IP=$(gcloud sql instances describe pos-database --format="value(ipAddresses[0].ipAddress)")
mysql -h $DB_IP -u pos_user -p'BDcm]R1bGe<DrNq0' pos_system < database/schema.sql
```

## Notes

- ⚠️ **Security**: Consider storing passwords in Secret Manager for production
- 🔒 **Access**: Ensure Cloud Run service account has Cloud SQL Client role
- 🌍 **Region**: All resources are in `europe-west1`
- 🔄 **Updates**: Update API URLs in both Flutter and React apps when backend URL changes

