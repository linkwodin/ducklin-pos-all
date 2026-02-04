# Setting Up App Icon

## Step 1: Save the Icon Image

1. Save your icon image (the one with "德靈海味" text and wave pattern) as:
   ```
   frontend/assets/images/app_icon.png
   ```

2. The image should be:
   - **1024x1024 pixels** (square, recommended)
   - PNG format with transparent background (if possible)
   - High quality

## Step 2: Generate Icons

After saving the icon image, run:

```bash
cd frontend
flutter pub get
flutter pub run flutter_launcher_icons
```

This will generate all the required icon sizes for:
- Android (various densities)
- macOS (various sizes)
- Windows (various sizes)

## Step 3: Rebuild the App

After generating icons, rebuild the app:

```bash
flutter clean
flutter pub get
flutter run -d macos
```

## Notes

- The icon will appear in:
  - macOS: Dock, Applications folder, About dialog
  - Android: App launcher, notification bar
  - Windows: Taskbar, Start menu, window title bar
- If you need to update the icon later, just replace `app_icon.png` and run `flutter pub run flutter_launcher_icons` again

