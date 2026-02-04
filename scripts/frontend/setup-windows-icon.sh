#!/bin/bash

# Manual Windows Icon Setup Script
# Converts PNG icon to ICO format for Windows

set -e

ICON_SOURCE="assets/images/app_icon.png"
ICON_DEST="windows/runner/resources/app_icon.ico"

echo "=== Setting up Windows app icon ==="
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

# Check if ImageMagick or sips is available for conversion
if command -v convert &> /dev/null; then
    echo "Using ImageMagick to convert icon..."
    # Create ICO with multiple sizes
    convert "$ICON_SOURCE" \
        \( -clone 0 -resize 16x16 \) \
        \( -clone 0 -resize 32x32 \) \
        \( -clone 0 -resize 48x48 \) \
        \( -clone 0 -resize 256x256 \) \
        -delete 0 \
        "$ICON_DEST"
    echo "✅ Icon converted successfully using ImageMagick"
elif command -v sips &> /dev/null; then
    echo "Using sips to convert icon (macOS)..."
    # sips can convert but ICO format might not be supported
    # For now, just copy and let Windows handle it, or use online converter
    echo "⚠️  sips doesn't support ICO format directly"
    echo "Please use ImageMagick or an online converter to create app_icon.ico"
    echo "Or copy the PNG and rename it (Windows will handle it):"
    echo "  cp $ICON_SOURCE $ICON_DEST"
    exit 1
else
    echo "❌ Error: Neither ImageMagick nor sips found"
    echo ""
    echo "Please install ImageMagick:"
    echo "  brew install imagemagick"
    echo ""
    echo "Or manually convert app_icon.png to app_icon.ico and place it at:"
    echo "  $ICON_DEST"
    exit 1
fi

if [ -f "$ICON_DEST" ]; then
    echo ""
    echo "✅ Windows icon created at: $ICON_DEST"
    echo ""
    echo "Next steps:"
    echo "  1. Build Windows app: flutter build windows --release --dart-define=ENV=uat"
    echo "  2. Or deploy: ./deploy-flutter-uat-windows.sh (if exists)"
else
    echo "❌ Failed to create icon file"
    exit 1
fi

