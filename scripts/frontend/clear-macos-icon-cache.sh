#!/bin/bash

# Script to clear macOS icon cache to force icon refresh

echo "=== Clearing macOS Icon Cache ==="
echo ""
echo "This will clear macOS icon cache so the new app icon appears."
echo "You may need to enter your password."
echo ""

# Kill Finder to clear its cache
echo "Killing Finder to clear icon cache..."
killall Finder 2>/dev/null || true

# Clear icon cache
echo "Clearing icon cache..."
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
sudo killall -9 com.apple.iconservices 2>/dev/null || true
sudo killall -9 com.apple.iconservices.store 2>/dev/null || true

# Clear user icon cache
rm -rf ~/Library/Caches/com.apple.iconservices.* 2>/dev/null || true

echo ""
echo "✅ Icon cache cleared!"
echo ""
echo "Next steps:"
echo "  1. Move the app to /Applications folder (if not already there)"
echo "  2. Restart Finder (it should restart automatically)"
echo "  3. The new icon should appear within a few seconds"
echo ""

