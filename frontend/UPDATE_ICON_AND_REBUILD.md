# Updating App Icon and Name

## Current Status

The app name has been updated to "德靈海味 POS" in the configuration, but you need to:

1. **Add your custom icon image**
2. **Generate the icon files**
3. **Rebuild and redeploy**

## Step 1: Save Your Icon Image

Save your icon image (the one with "德靈海味" text and wave pattern) as:
```
frontend/assets/images/app_icon.png
```

**Requirements:**
- Size: **1024x1024 pixels** (square)
- Format: PNG
- Transparent background (if possible)

## Step 2: Generate Icons

After saving the icon, run:

```bash
cd frontend
flutter pub get
flutter pub run flutter_launcher_icons
```

This will:
- Generate all required icon sizes for macOS (16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024)
- Update the icon files in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`

## Step 3: Clean and Rebuild

```bash
cd frontend
flutter clean
flutter build macos --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Step 4: Redeploy to Bucket

```bash
cd frontend
./scripts/frontend/deploy-flutter-uat-macos.sh
```

## Quick All-in-One Command

Once you've saved `app_icon.png`:

```bash
cd frontend
flutter pub run flutter_launcher_icons && \
flutter clean && \
flutter build macos --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1" && \
./scripts/frontend/deploy-flutter-uat-macos.sh
```

## Verification

After deployment, download the app and verify:
- ✅ App name shows as "德靈海味 POS" in Finder, Dock, and About dialog
- ✅ Custom icon appears in all locations
- ✅ App connects to UAT backend

## Troubleshooting

### Icon not showing
- Make sure `app_icon.png` is exactly 1024x1024 pixels
- Run `flutter clean` before rebuilding
- Check that icon files were generated in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`

### Name not updating
- The name is set in `macos/Runner/Configs/AppInfo.xcconfig` as `PRODUCT_NAME = 德靈海味 POS`
- Make sure to run `flutter clean` before rebuilding
- Check the built app bundle name: `build/macos/Build/Products/Release/德靈海味 POS.app`

