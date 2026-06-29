#!/bin/bash

# POS System GCP Deployment Script
# This script automates the deployment process to Google Cloud Platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION=${REGION:-europe-west1}
UAT_PROJECT_ID="${UAT_PROJECT_ID:-ducklin-uk-uat}"
PROD_PROJECT_ID="${PROD_PROJECT_ID:-ducklin-uk-prod}"
BACKEND_DIR="backend"
FRONTEND_DIR="management-frontend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_warn "Docker is not installed. Some features may not work."
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        print_error "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    print_info "Using project: $PROJECT_ID"
    print_info "Using region: $REGION"
}

deploy_backend() {
    local GCP_PROJECT="${1:-$PROJECT_ID}"
    if [ -z "$GCP_PROJECT" ]; then
        print_error "No GCP project. Pass project id or run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi

    print_info "Deploying backend to Cloud Run (project: $GCP_PROJECT)..."
    
    # Ensure PDF fonts (Arial/Liberation Sans, Noto) are present so the Docker image includes them
    FONTS_DIR="$BACKEND_DIR/pdf-assets/fonts"
    if [ ! -f "$FONTS_DIR/Arial.ttf" ]; then
        print_info "Downloading PDF fonts (Arial substitute) into $FONTS_DIR..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
        if [ -f "$REPO_ROOT/scripts/download-arial-font.sh" ]; then
            "$REPO_ROOT/scripts/download-arial-font.sh"
        else
            print_warn "scripts/download-arial-font.sh not found; ensure $FONTS_DIR has Arial.ttf and Noto fonts for PDFs."
        fi
    else
        print_info "PDF fonts present in $FONTS_DIR"
    fi
    
    cd "$BACKEND_DIR"
    
    # Check if cloudbuild.yaml exists
    if [ ! -f "cloudbuild.yaml" ]; then
        print_error "cloudbuild.yaml not found in backend directory"
        exit 1
    fi
    
    # Note: Cloud SQL connection is managed separately via fix scripts
    # (see cloudbuild.yaml comment for details)
    # Note: Region is hardcoded to europe-west1 in cloudbuild.yaml
    gcloud builds submit --config=cloudbuild.yaml --project="$GCP_PROJECT"
    
    print_info "Backend deployed successfully!"
    local backend_url
    backend_url="$(gcloud run services describe pos-backend --region="$REGION" --project="$GCP_PROJECT" --format='value(status.url)' 2>/dev/null || true)"
    if [ -n "$backend_url" ]; then
        print_info "Backend URL: $backend_url"
    fi
    cd ..
}

deploy_firebase() {
    local ENV="${1:-uat}"
    if [ ! -f "$SCRIPT_DIR/deploy-firebase.sh" ]; then
        print_error "deploy-firebase.sh not found"
        exit 1
    fi
    "$SCRIPT_DIR/deploy-firebase.sh" "$ENV"
}

deploy_all_uat() {
    print_info "Deploying all UAT: backend ($UAT_PROJECT_ID) + Firebase Hosting..."
    deploy_backend "$UAT_PROJECT_ID"
    deploy_firebase "uat"
}

deploy_all_prod() {
    print_info "Deploying all PRODUCTION: backend ($PROD_PROJECT_ID) + Firebase Hosting..."
    deploy_backend "$PROD_PROJECT_ID"
    deploy_firebase "production"
}

deploy_frontend() {
    local ENV=${1:-production}  # Default to production, can be 'uat' or 'production'
    
    # Convert to uppercase (macOS compatible)
    ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')
    print_info "Deploying frontend to Cloud Storage ($ENV_UPPER)..."
    
    cd "$FRONTEND_DIR"
    
    # Determine API URL and bucket name based on environment
    if [ "$ENV" == "uat" ]; then
        # Use Cloud Run URL until custom domain is ready
        # API_URL="https://pos-api-uat.ducklincompany.co.uk/api/v1"  # Custom domain (DNS pending)
        API_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"  # Cloud Run URL
        BUCKET_NAME="$PROJECT_ID-pos-frontend-uat"
        BUILD_CMD="build:uat"
    else
        # Get backend URL for production
        BACKEND_URL=$(gcloud run services describe pos-backend --region=$REGION --format="value(status.url)" 2>/dev/null || echo "")
        if [ -n "$BACKEND_URL" ]; then
            API_URL="$BACKEND_URL/api/v1"
            print_info "Backend URL: $BACKEND_URL"
        else
            print_warn "Could not get backend URL. Using default API URL."
            API_URL="/api/v1"
        fi
        BUCKET_NAME="$PROJECT_ID-pos-frontend"
        BUILD_CMD="build"
    fi
    
    # Create/update .env file for the environment
    ENV_FILE=".env.$ENV"
    if [ "$ENV" == "uat" ]; then
        if [ ! -f "$ENV_FILE" ]; then
            print_info "Creating $ENV_FILE file..."
            echo "VITE_API_URL=$API_URL" > "$ENV_FILE"
        else
            print_info "Updating $ENV_FILE file..."
            if grep -q "VITE_API_URL" "$ENV_FILE"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s|VITE_API_URL=.*|VITE_API_URL=$API_URL|" "$ENV_FILE"
                else
                    sed -i "s|VITE_API_URL=.*|VITE_API_URL=$API_URL|" "$ENV_FILE"
                fi
            else
                echo "VITE_API_URL=$API_URL" >> "$ENV_FILE"
            fi
        fi
        print_info "Using API URL: $API_URL"
    fi
    
    # Check if node_modules exists
    if [ ! -d "node_modules" ]; then
        print_info "Installing dependencies..."
        npm install
    fi
    
    # Clean build directory and Vite cache to ensure fresh build
    print_info "Cleaning previous build..."
    rm -rf dist
    rm -rf node_modules/.vite
    
    # Build frontend
    print_info "Building frontend..."
    npm run $BUILD_CMD
    
    # Verify build output has relative paths
    if grep -q 'src="/assets/' dist/index.html 2>/dev/null; then
        print_error "Build failed: index.html still has absolute paths!"
        print_error "This means vite.config.ts base setting isn't being applied."
        print_error "Please check vite.config.ts has: base: './'"
        exit 1
    fi
    
    # Check if dist directory exists
    if [ ! -d "dist" ]; then
        print_error "Build failed - dist directory not found"
        exit 1
    fi
    
    print_info "Build completed successfully!"
    
    # Check if bucket exists
    if ! gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        print_info "Creating bucket: $BUCKET_NAME"
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"
    else
        print_info "Bucket already exists: $BUCKET_NAME"
    fi
    
    # Configure bucket for web hosting (always set, even if bucket exists)
    print_info "Configuring bucket for web hosting (SPA routing)..."
    WEB_CONFIGURED=false
    
    # Try Method 1: gcloud storage buckets update (newer, more reliable)
    if gcloud storage buckets update "gs://$BUCKET_NAME" \
        --web-main-page-suffix=index.html \
        --web-error-page=index.html 2>/dev/null; then
        print_info "✅ Bucket routing configured using gcloud storage"
        WEB_CONFIGURED=true
    # Try Method 2: gsutil web set (older method)
    elif gsutil web set -m index.html -e index.html "gs://$BUCKET_NAME" 2>/dev/null; then
        print_info "✅ Bucket routing configured using gsutil"
        WEB_CONFIGURED=true
    fi
    
    if [ "$WEB_CONFIGURED" = false ]; then
        print_warn "⚠️  Could not automatically configure bucket routing"
        print_warn "Please configure manually in GCP Console:"
        print_warn "  1. Go to: https://console.cloud.google.com/storage/browser/$BUCKET_NAME?project=$PROJECT_ID"
        print_warn "  2. Click 'Configuration' tab"
        print_warn "  3. Edit 'Website configuration'"
        print_warn "  4. Set 'Main page suffix' and 'Error page' to: index.html"
        print_warn ""
        print_warn "Or run manually:"
        print_warn "  gcloud storage buckets update gs://$BUCKET_NAME \\"
        print_warn "    --web-main-page-suffix=index.html \\"
        print_warn "    --web-error-page=index.html"
    fi
    
    # Make bucket publicly readable
    print_info "Making bucket publicly readable..."
    gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME" 2>/dev/null || print_warn "Could not set public access (may already be set)"
    
    # Set CORS if needed
    if [ "$ENV" == "uat" ]; then
        print_info "Setting CORS policy..."
        echo '[{"origin": ["*"], "method": ["GET", "HEAD"], "responseHeader": ["Content-Type"], "maxAgeSeconds": 3600}]' > /tmp/cors.json
        gsutil cors set /tmp/cors.json "gs://$BUCKET_NAME" 2>/dev/null || print_warn "Could not set CORS policy"
        rm -f /tmp/cors.json
    fi
    
    # Upload files
    print_info "Uploading files to bucket..."
    gsutil -m rsync -r -d dist/ "gs://$BUCKET_NAME/"
    
    # Set cache control
    if [ "$ENV" == "uat" ]; then
        # UAT: no cache for HTML, long cache for assets
        print_info "Setting cache control..."
        gsutil -m setmeta -h "Cache-Control:no-cache, no-store, must-revalidate" "gs://$BUCKET_NAME/*.html"
        gsutil -m setmeta -h "Cache-Control:public, max-age=31536000, immutable" "gs://$BUCKET_NAME/assets/**"
    else
        # Production: standard cache
        gsutil -m setmeta -h "Cache-Control:public, max-age=3600" "gs://$BUCKET_NAME/**"
    fi
    
    print_info "Frontend deployed successfully!"
    print_info "Frontend URL: https://storage.googleapis.com/$BUCKET_NAME/index.html"
    cd ..
}

# Main execution
main() {
    print_info "Starting deployment to GCP..."
    
    check_prerequisites
    
    # Ask what to deploy
    if [ "$1" == "backend" ]; then
        if [ "$2" == "prod" ] || [ "$2" == "production" ]; then
            deploy_backend "$PROD_PROJECT_ID"
        elif [ "$2" == "uat" ]; then
            deploy_backend "$UAT_PROJECT_ID"
        else
            deploy_backend "$PROJECT_ID"
        fi
    elif [ "$1" == "backend-prod" ] || [ "$1" == "backend-production" ]; then
        deploy_backend "$PROD_PROJECT_ID"
    elif [ "$1" == "backend-uat" ]; then
        deploy_backend "$UAT_PROJECT_ID"
    elif [ "$1" == "frontend" ]; then
        deploy_frontend "${2:-production}"  # Second argument is environment (uat or production)
    elif [ "$1" == "frontend-uat" ]; then
        deploy_frontend "uat"
    elif [ "$1" == "frontend-firebase" ] || [ "$1" == "firebase" ]; then
        deploy_firebase "${2:-uat}"
    elif [ "$1" == "all" ] && { [ "$2" == "uat" ]; }; then
        deploy_all_uat
    elif [ "$1" == "all" ] && { [ "$2" == "prod" ] || [ "$2" == "production" ]; }; then
        deploy_all_prod
    elif [ "$1" == "all-prod" ] || [ "$1" == "all-production" ]; then
        deploy_all_prod
    elif [ "$1" == "all-uat" ]; then
        deploy_all_uat
    elif [ "$1" == "all" ] || [ -z "$1" ]; then
        deploy_backend
        deploy_frontend "production"
    else
        print_error "Invalid argument: $1"
        print_info "Usage: ./scripts/deploy.sh [target] [uat|prod|production]"
        print_info "  UAT:"
        print_info "    ./scripts/deploy.sh all uat               # Backend ($UAT_PROJECT_ID) + Firebase UAT"
        print_info "    ./scripts/deploy.sh all-uat                 # Same as all uat"
        print_info "    ./scripts/deploy.sh backend uat             # Backend only (UAT project)"
        print_info "    ./scripts/deploy.sh frontend-uat            # GCS frontend (UAT)"
        print_info "    ./scripts/deploy.sh firebase uat            # Firebase Hosting (UAT)"
        print_info "  Production:"
        print_info "    ./scripts/deploy.sh all prod                # Backend ($PROD_PROJECT_ID) + Firebase prod"
        print_info "    ./scripts/deploy.sh all-prod                # Same as all prod"
        print_info "    ./scripts/deploy.sh backend prod              # Backend only (prod project)"
        print_info "    ./scripts/deploy.sh firebase production       # Firebase Hosting (prod)"
        print_info "  Other:"
        print_info "    ./scripts/deploy.sh backend                 # Backend (current gcloud project)"
        print_info "    ./scripts/deploy.sh frontend                  # GCS frontend (current project)"
        print_info "    ./scripts/deploy.sh all                       # Backend + GCS (current project)"
        exit 1
    fi
    
    print_info "Deployment completed!"
}

# Run main function
main "$@"

