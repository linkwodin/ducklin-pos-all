#!/bin/bash

# Flutter App UAT Deployment Script for macOS
# Builds Flutter app and uploads to GCP Storage for download

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGION=${REGION:-europe-west1}
UAT_BACKEND_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
VERSION="1.0.0"

# Get GCP project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR]${NC} No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

BUCKET_NAME="$PROJECT_ID-pos-flutter-uat"

echo -e "${GREEN}[INFO]${NC} Starting Flutter app deployment to UAT..."
echo -e "${GREEN}[INFO]${NC} Using project: $PROJECT_ID"
echo -e "${GREEN}[INFO]${NC} Using region: $REGION"
echo -e "${GREEN}[INFO]${NC} UAT Backend URL: $UAT_BACKEND_URL"
echo ""

# Check prerequisites
echo -e "${GREEN}[INFO]${NC} Checking prerequisites..."

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Flutter is not installed. Please install it from https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Get Flutter version
FLUTTER_VERSION=$(flutter --version | head -1)
echo -e "${GREEN}[INFO]${NC} Flutter: $FLUTTER_VERSION"
echo ""

# Get the project root directory (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

# Change to frontend directory
if [ ! -d "$FRONTEND_DIR" ]; then
    echo -e "${RED}[ERROR]${NC} Frontend directory not found: $FRONTEND_DIR"
    exit 1
fi

cd "$FRONTEND_DIR"

if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}[ERROR]${NC} pubspec.yaml not found in frontend directory"
    exit 1
fi

# Check if icon needs to be generated
if [ -f "assets/images/app_icon.png" ]; then
    echo -e "${GREEN}[INFO]${NC} Icon source found, generating macOS icons..."
    if [ -f "$SCRIPT_DIR/setup-macos-icon.sh" ]; then
        "$SCRIPT_DIR/setup-macos-icon.sh" > /dev/null 2>&1 || echo -e "${YELLOW}[WARN]${NC} Icon generation skipped or failed (continuing anyway)"
    else
        echo -e "${YELLOW}[WARN]${NC} Icon setup script not found, skipping icon generation"
    fi
    echo ""
fi

# Clean previous builds
echo -e "${GREEN}[INFO]${NC} Cleaning previous builds..."
flutter clean
echo ""

# Get dependencies
echo -e "${GREEN}[INFO]${NC} Getting Flutter dependencies..."
flutter pub get
echo ""

# Build Flutter app for macOS (release mode)
echo -e "${GREEN}[INFO]${NC} Building Flutter app for macOS (UAT)..."
echo -e "${GREEN}[INFO]${NC} Environment: UAT"
echo -e "${GREEN}[INFO]${NC} Backend URL: $UAT_BACKEND_URL"
echo ""

flutter build macos --release \
    --dart-define=ENV=uat \
    --dart-define=API_BASE_URL="$UAT_BACKEND_URL"

# Find the app bundle (name may vary based on PRODUCT_NAME)
APP_BUNDLE=$(find build/macos/Build/Products/Release -name "*.app" -type d | head -1)
if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}[ERROR]${NC} Build failed - app bundle not found"
    exit 1
fi

APP_NAME=$(basename "$APP_BUNDLE" .app)
echo -e "${GREEN}[INFO]${NC} Found app bundle: $APP_NAME.app"

echo -e "${GREEN}[INFO]${NC} Build completed successfully"
echo ""

# Create timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create zip file
echo -e "${GREEN}[INFO]${NC} Creating distribution package..."
ZIP_NAME="pos-system-uat-macos-${VERSION}-${TIMESTAMP}.zip"
ZIP_PATH="$(pwd)/../${ZIP_NAME}"

# Create zip from the app bundle
cd build/macos/Build/Products/Release
zip -r "$ZIP_PATH" "$APP_NAME.app" > /dev/null 2>&1
ZIP_EXIT_CODE=$?
cd - > /dev/null

if [ $ZIP_EXIT_CODE -ne 0 ] || [ ! -f "$ZIP_PATH" ]; then
    echo -e "${RED}[ERROR]${NC} Failed to create zip file (exit code: $ZIP_EXIT_CODE)"
    echo -e "${RED}[ERROR]${NC} ZIP path: $ZIP_PATH"
    echo -e "${RED}[ERROR]${NC} App bundle: $APP_BUNDLE"
    exit 1
fi

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo -e "${GREEN}[INFO]${NC} Created package: $ZIP_NAME ($ZIP_SIZE)"
echo ""

# Check/create bucket
echo -e "${GREEN}[INFO]${NC} Checking GCP Storage bucket..."
if ! gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
    echo -e "${GREEN}[INFO]${NC} Creating bucket: $BUCKET_NAME"
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"
    
    # Make bucket publicly readable
    echo -e "${GREEN}[INFO]${NC} Making bucket publicly readable..."
    gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME"
else
    echo -e "${GREEN}[INFO]${NC} Bucket already exists: $BUCKET_NAME"
fi
echo ""

# Upload to GCP Storage
echo -e "${GREEN}[INFO]${NC} Uploading to GCP Storage..."
FULL_ZIP_PATH=$(realpath "$ZIP_PATH")
gsutil cp "$FULL_ZIP_PATH" "gs://$BUCKET_NAME/$ZIP_NAME"

# Also upload as latest
echo -e "${GREEN}[INFO]${NC} Setting as latest version..."
gsutil cp "$FULL_ZIP_PATH" "gs://$BUCKET_NAME/pos-system-uat-macos-latest.zip"

# Set metadata for download
echo -e "${GREEN}[INFO]${NC} Setting download metadata..."
gsutil setmeta -h "Content-Type:application/zip" \
    -h "Content-Disposition:attachment; filename=\"pos-system-uat-macos-latest.zip\"" \
    "gs://$BUCKET_NAME/pos-system-uat-macos-latest.zip"

echo ""
echo -e "${GREEN}[INFO]${NC} ✅ Deployment completed successfully!"
echo ""
echo -e "${GREEN}[INFO]${NC} Download URLs:"
echo -e "  Versioned: https://storage.googleapis.com/$BUCKET_NAME/$ZIP_NAME"
echo -e "  Latest:    https://storage.googleapis.com/$BUCKET_NAME/pos-system-uat-macos-latest.zip"
echo ""
echo -e "${GREEN}[INFO]${NC} To download:"
echo -e "  gsutil cp gs://$BUCKET_NAME/pos-system-uat-macos-latest.zip ~/Downloads/"
echo ""

