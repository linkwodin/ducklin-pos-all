#!/bin/bash

# Script to set up the app icon for 德靈海味 POS
# This script will generate all required icon sizes from a source image

set -e

ICON_SOURCE="assets/images/app_icon.png"
ICON_DIR="assets/images"

echo "=== Setting up app icon for 德靈海味 POS ==="
echo ""

# Check if icon source exists
if [ ! -f "$ICON_SOURCE" ]; then
    echo "❌ Error: Icon source not found at: $ICON_SOURCE"
    echo ""
    echo "Please save your icon image (1024x1024 PNG recommended) to:"
    echo "  $ICON_SOURCE"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "✅ Found icon source: $ICON_SOURCE"
echo ""

# Install dependencies if needed
echo "Installing dependencies..."
flutter pub get

# Generate icons
echo ""
echo "Generating app icons for all platforms..."
flutter pub run flutter_launcher_icons

echo ""
echo "✅ App icons generated successfully!"
echo ""
echo "Next steps:"
echo "  1. Run: flutter clean"
echo "  2. Run: flutter run -d macos"
echo ""
echo "The app will now show '德靈海味 POS' as the title and use your custom icon."

