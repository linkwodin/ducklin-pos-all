# Fixing Icon and Name Not Showing

If you've downloaded the app and the icon/name still shows as "pos_system", try these steps:

## Step 1: Verify the Download

Make sure you downloaded the **latest** version:
```
https://storage.googleapis.com/ducklin-uk-uat-pos-flutter-uat/pos-system-uat-macos-latest.zip
```

The latest build should be from **Feb 3, 2026 03:45** or later.

## Step 2: Clear macOS Icon Cache

macOS aggressively caches app icons. Clear the cache:

```bash
cd frontend
./scripts/frontend/clear-macos-icon-cache.sh
```

Or manually:
```bash
# Kill Finder
killall Finder

# Clear system icon cache (requires password)
sudo rm -rf /Library/Caches/com.apple.iconservices.store
sudo killall -9 com.apple.iconservices
sudo killall -9 com.apple.iconservices.store

# Clear user icon cache
rm -rf ~/Library/Caches/com.apple.iconservices.*
```

## Step 3: Move App to Applications Folder

1. Extract the downloaded ZIP file
2. Move "德靈海味 POS.app" to `/Applications` folder
3. Wait a few seconds for macOS to refresh icons

## Step 4: Force Icon Refresh

If the icon still doesn't update:

1. **Get Info** on the app (right-click → Get Info)
2. Click on the icon in the Get Info window
3. Press `Cmd+C` to copy
4. Close Get Info
5. Open Get Info again
6. Press `Cmd+V` to paste (this forces a refresh)

Or use Terminal:
```bash
# Touch the app to force refresh
touch "/Applications/德靈海味 POS.app"

# Rebuild Launch Services database
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```

## Step 5: Verify App Bundle Name

Check if the app bundle has the correct name:

```bash
ls -la "/Applications/德靈海味 POS.app"
```

If it shows "pos_system.app" instead, you downloaded an old version.

## Step 6: Check App Info

Right-click the app → Get Info, and verify:
- **Name**: Should show "德靈海味 POS"
- **Icon**: Should show your custom wave pattern icon

## Troubleshooting

### Icon still shows Flutter logo
- The icon cache is very persistent
- Try restarting your Mac
- Or delete the app, clear cache, then reinstall

### Name still shows "pos_system"
- You might have an old version
- Delete the old app completely
- Download the latest from the bucket
- Extract and move to Applications

### App won't open
- Right-click → Open (first time only, to bypass Gatekeeper)
- Or: System Settings → Privacy & Security → Allow the app

## Verification Commands

```bash
# Check app bundle name
ls -la "/Applications/" | grep -i "德靈\|pos"

# Check icon files in app bundle
ls -la "/Applications/德靈海味 POS.app/Contents/Resources/AppIcon.icns" 2>/dev/null || \
ls -la "/Applications/德靈海味 POS.app/Contents/Resources/" | grep -i icon

# Check Info.plist
defaults read "/Applications/德靈海味 POS.app/Contents/Info.plist" CFBundleName
defaults read "/Applications/德靈海味 POS.app/Contents/Info.plist" CFBundleIconFile
```

## Latest Build Info

- **Build Date**: Feb 3, 2026 03:45:37
- **App Name**: 德靈海味 POS
- **App Bundle**: 德靈海味 POS.app
- **Size**: ~59.6MB (80MB zipped)
- **Download**: https://storage.googleapis.com/ducklin-uk-uat-pos-flutter-uat/pos-system-uat-macos-latest.zip

