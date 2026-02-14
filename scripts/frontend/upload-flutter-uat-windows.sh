#!/bin/bash

# Upload existing Windows POS build to UAT (GCP Storage).
# Use when you've already built on Windows and copied the build to build/POS.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REGION=${REGION:-europe-west1}
VERSION="1.0.0"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR]${NC} No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

BUCKET_NAME="$PROJECT_ID-pos-flutter-uat"

# Default: frontend/build/POS; override with first argument
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
BUILD_DIR="${1:-$FRONTEND_DIR/build/POS}"

if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${RED}[ERROR]${NC} Windows build directory not found: $BUILD_DIR"
    echo "Usage: $0 [path-to-POS-folder]"
    echo "Default: frontend/build/POS"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Uploading Windows POS build to UAT..."
echo -e "${GREEN}[INFO]${NC} Project: $PROJECT_ID"
echo -e "${GREEN}[INFO]${NC} Build dir: $BUILD_DIR"
echo ""

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ZIP_NAME="pos-system-uat-windows-${VERSION}-${TIMESTAMP}.zip"
ZIP_PATH="$PROJECT_ROOT/$ZIP_NAME"

echo -e "${GREEN}[INFO]${NC} Creating zip..."
cd "$BUILD_DIR"
zip -r "$ZIP_PATH" . -x "*.DS_Store" > /dev/null 2>&1
cd - > /dev/null

if [ ! -f "$ZIP_PATH" ]; then
    echo -e "${RED}[ERROR]${NC} Failed to create zip"
    exit 1
fi

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo -e "${GREEN}[INFO]${NC} Created $ZIP_NAME ($ZIP_SIZE)"
echo ""

echo -e "${GREEN}[INFO]${NC} Uploading to gs://$BUCKET_NAME/..."
gsutil cp "$ZIP_PATH" "gs://$BUCKET_NAME/$ZIP_NAME"
gsutil cp "$ZIP_PATH" "gs://$BUCKET_NAME/pos-system-uat-windows-latest.zip"

echo -e "${GREEN}[INFO]${NC} Setting metadata..."
gsutil setmeta -h "Content-Type:application/zip" \
    -h "Content-Disposition:attachment; filename=\"pos-system-uat-windows-latest.zip\"" \
    "gs://$BUCKET_NAME/pos-system-uat-windows-latest.zip"

# Update downloads index page
INDEX_HTML="$SCRIPT_DIR/uat-downloads-index.html"
if [ -f "$INDEX_HTML" ]; then
    echo -e "${GREEN}[INFO]${NC} Updating index.html..."
    gsutil -h "Content-Type:text/html" cp "$INDEX_HTML" "gs://$BUCKET_NAME/index.html"
fi

rm -f "$ZIP_PATH"

echo ""
echo -e "${GREEN}[INFO]${NC} ✅ Windows UAT upload complete!"
echo ""
echo -e "${GREEN}[INFO]${NC} Download URLs:"
echo -e "  Versioned: https://storage.googleapis.com/$BUCKET_NAME/$ZIP_NAME"
echo -e "  Latest:    https://storage.googleapis.com/$BUCKET_NAME/pos-system-uat-windows-latest.zip"
echo ""
