#!/bin/bash

# Manual macOS Icon Setup Script
# This script manually copies and resizes the icon for macOS

set -e

ICON_SOURCE="assets/images/app_icon.png"
ICON_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"

echo "=== Setting up macOS app icon ==="
echo ""

# Check if icon source exists
if [ ! -f "$ICON_SOURCE" ]; then
    echo "❌ Error: Icon source not found at: $ICON_SOURCE"
    echo ""
    echo "Please save your icon image (1024x1024 PNG) to:"
    echo "  $ICON_SOURCE"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "✅ Found icon source: $ICON_SOURCE"
echo ""

# Check if sips (macOS built-in image tool) is available
if ! command -v sips &> /dev/null; then
    echo "❌ Error: sips command not found. This script requires macOS."
    exit 1
fi

# Create icon directory if it doesn't exist
mkdir -p "$ICON_DIR"

echo "Generating icon sizes..."

# Generate all required icon sizes using sips
sips -z 16 16 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_16.png" > /dev/null 2>&1
sips -z 32 32 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_32.png" > /dev/null 2>&1
sips -z 64 64 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_64.png" > /dev/null 2>&1
sips -z 128 128 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_128.png" > /dev/null 2>&1
sips -z 256 256 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_256.png" > /dev/null 2>&1
sips -z 512 512 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_512.png" > /dev/null 2>&1
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICON_DIR/app_icon_1024.png" > /dev/null 2>&1

echo "✅ Icons generated successfully!"
echo ""
echo "Icon files created in: $ICON_DIR"
echo ""
echo "Next steps:"
echo "  1. Run: flutter clean"
echo "  2. Run: flutter build macos --release --dart-define=ENV=uat --dart-define=API_BASE_URL=\"https://pos-backend-28040503481.europe-west1.run.app/api/v1\""
echo "  3. Or run: ./scripts/frontend/deploy-flutter-uat-macos.sh"
echo ""

