#!/bin/bash

# GCP Initial Setup Script
# This script sets up the initial GCP infrastructure

# Don't exit on error immediately - let functions handle errors
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION=${REGION:-europe-west1}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_project() {
    print_info "Checking GCP project configuration..."
    
    if [ -z "$PROJECT_ID" ]; then
        print_error "No GCP project set."
        print_info "Please run: gcloud config set project YOUR_PROJECT_ID"
        print_info "Or set PROJECT_ID environment variable: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        print_error "Project '$PROJECT_ID' not found or you don't have access to it."
        print_info "Please verify the project ID or run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    print_info "Using project: $PROJECT_ID"
}

enable_apis() {
    print_info "Enabling required APIs..."
    if ! gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        sqladmin.googleapis.com \
        storage-component.googleapis.com \
        storage-api.googleapis.com \
        secretmanager.googleapis.com \
        artifactregistry.googleapis.com \
        containerregistry.googleapis.com \
        --project="$PROJECT_ID" 2>&1; then
        print_error "Failed to enable APIs. Please check your permissions and try again."
        return 1
    fi
    print_info "APIs enabled successfully"
}

create_database() {
    print_info "Creating Cloud SQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe pos-database --project="$PROJECT_ID" &> /dev/null; then
        print_warn "Cloud SQL instance 'pos-database' already exists. Skipping creation."
        return
    fi
    
    read -sp "Enter database root password: " DB_ROOT_PASSWORD
    echo
    read -sp "Enter database user password: " DB_USER_PASSWORD
    echo
    
    gcloud sql instances create pos-database \
        --database-version=MYSQL_8_0 \
        --tier=db-f1-micro \
        --region="$REGION" \
        --root-password="$DB_ROOT_PASSWORD" \
        --storage-type=SSD \
        --storage-size=20GB \
        --backup-start-time=03:00 \
        --project="$PROJECT_ID"
    
    print_info "Creating database..."
    gcloud sql databases create pos_system --instance=pos-database --project="$PROJECT_ID" || true
    
    print_info "Creating database user..."
    gcloud sql users create pos_user \
        --instance=pos-database \
        --password="$DB_USER_PASSWORD" \
        --project="$PROJECT_ID" || true
    
    CONNECTION_NAME=$(gcloud sql instances describe pos-database --format="value(connectionName)" --project="$PROJECT_ID")
    print_info "Database connection name: $CONNECTION_NAME"
    print_info "Save this connection name for Cloud Run deployment"
}

create_storage_buckets() {
    print_info "Creating Cloud Storage buckets..."
    
    # Uploads bucket
    UPLOADS_BUCKET="$PROJECT_ID-pos-uploads"
    if ! gsutil ls -b "gs://$UPLOADS_BUCKET" &> /dev/null; then
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$UPLOADS_BUCKET"
        gsutil iam ch allUsers:objectViewer "gs://$UPLOADS_BUCKET"
        print_info "Created uploads bucket: $UPLOADS_BUCKET"
    else
        print_warn "Bucket $UPLOADS_BUCKET already exists"
    fi
    
    # Frontend bucket
    FRONTEND_BUCKET="$PROJECT_ID-pos-frontend"
    if ! gsutil ls -b "gs://$FRONTEND_BUCKET" &> /dev/null; then
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$FRONTEND_BUCKET"
        gsutil web set -m index.html -e index.html "gs://$FRONTEND_BUCKET"
        print_info "Created frontend bucket: $FRONTEND_BUCKET"
    else
        print_warn "Bucket $FRONTEND_BUCKET already exists"
    fi
}

create_secrets() {
    print_info "Setting up secrets..."
    
    read -sp "Enter JWT secret: " JWT_SECRET
    echo
    
    # Create or update JWT secret
    if gcloud secrets describe jwt-secret --project="$PROJECT_ID" &> /dev/null; then
        echo -n "$JWT_SECRET" | gcloud secrets versions add jwt-secret --data-file=- --project="$PROJECT_ID"
        print_info "Updated jwt-secret"
    else
        echo -n "$JWT_SECRET" | gcloud secrets create jwt-secret --data-file=- --project="$PROJECT_ID"
        print_info "Created jwt-secret"
    fi
    
    # Grant access to Cloud Run service account
    PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
    SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
    
    gcloud secrets add-iam-policy-binding jwt-secret \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/secretmanager.secretAccessor" \
        --project="$PROJECT_ID" || true
    
    print_info "Secrets configured"
}

main() {
    print_info "Starting GCP setup..."
    print_info "=========================================="
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed."
        print_info "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        print_error "You are not authenticated with gcloud."
        print_info "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check project (this will exit if no project is set)
    if ! check_project; then
        exit 1
    fi
    
    print_info ""
    print_info "This script will:"
    print_info "1. Enable required GCP APIs"
    print_info "2. Create Cloud Storage buckets"
    print_info "3. Set up Secret Manager"
    print_info "4. Optionally create Cloud SQL database"
    print_info ""
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled."
        exit 0
    fi
    
    enable_apis
    create_storage_buckets
    create_secrets
    
    print_info ""
    read -p "Do you want to create the Cloud SQL database? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_database
    else
        print_info "Skipping database creation. You can create it manually later."
    fi
    
    print_info ""
    print_info "=========================================="
    print_info "Setup completed!"
    print_info "=========================================="
    print_info "Next steps:"
    print_info "1. Initialize database schema (if database was created):"
    print_info "   mysql -h <DB_IP> -u pos_user -p pos_system < database/schema.sql"
    print_info "2. Deploy backend: ./scripts/deploy.sh backend"
    print_info "3. Deploy frontend: ./scripts/deploy.sh frontend"
    print_info ""
}

main "$@"

