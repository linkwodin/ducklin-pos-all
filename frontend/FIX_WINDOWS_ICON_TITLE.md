# Fixing Windows Icon and Title Issues

## Issue 1: Title Showing as Garbled Text (亂碼)

The title is now fixed using Unicode escape sequences. However, if you still see garbled text, ensure:

1. **The source files are saved with UTF-8 encoding:**
   - `windows/runner/main.cpp` - Should be UTF-8
   - `windows/runner/Runner.rc` - Should be UTF-8 with BOM (for resource compiler)

2. **Rebuild the app:**
   ```cmd
   flutter clean
   flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
   ```

## Issue 2: Icon Not Showing (Default Flutter Icon)

The icon file exists but might be the default Flutter icon. To fix:

### Step 1: Generate ICO from PNG

**On Windows machine**, run from the `frontend` directory:

```powershell
.\convert-icon-to-ico.ps1
```

Or manually:

1. **Using ImageMagick (if installed):**
   ```cmd
   magick convert assets\images\app_icon.png -define icon:auto-resize=256,128,64,48,32,16 windows\runner\resources\app_icon.ico
   ```

2. **Using Online Converter:**
   - Go to https://convertio.co/png-ico/ or https://www.icoconverter.com/
   - Upload `assets/images/app_icon.png`
   - Download the ICO file
   - Save it as `windows/runner/resources/app_icon.ico`

### Step 2: Verify Icon File

Check that the icon file exists and is valid:

```cmd
dir windows\runner\resources\app_icon.ico
```

The file should be larger than 1KB. Try opening it to verify it's a valid icon.

### Step 3: Clean and Rebuild

```cmd
flutter clean
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

### Step 4: Verify

After rebuilding:

1. **Window title**: Should show "德靈海味 POS" (not garbled)
2. **App icon**: 
   - Right-click `build\windows\runner\Release\pos_system.exe` → Properties
   - Should show custom icon in the Properties dialog
   - Taskbar should show custom icon when running

## Troubleshooting

### Title Still Garbled?

1. Make sure `main.cpp` is saved with UTF-8 encoding
2. The code now uses Unicode escape sequences (`\u5FB7\u9748\u6D77\u5473`) which should work regardless of file encoding
3. Rebuild with `flutter clean` first

### Icon Still Not Showing?

1. **Verify icon file exists:**
   ```cmd
   dir windows\runner\resources\app_icon.ico
   ```

2. **Check Runner.rc references the icon:**
   ```rc
   IDI_APP_ICON            ICON                    "resources\\app_icon.ico"
   ```

3. **Verify icon is valid:**
   - Try opening `windows\runner\resources\app_icon.ico` in Windows
   - It should display as an icon, not as a broken file

4. **Check resource.h defines the ID:**
   ```cpp
   #define IDI_APP_ICON                    101
   ```

5. **Rebuild completely:**
   ```cmd
   flutter clean
   flutter build windows --release
   ```

6. **Check if icon is embedded:**
   - After build, check `build\windows\runner\Release\pos_system.exe`
   - Right-click → Properties → should show icon in the dialog

## Quick Fix Script

Create `fix-windows-icon-title.bat` in the `frontend` directory:

```batch
@echo off
chcp 65001 >nul
echo Fixing Windows icon and title...

echo.
echo Step 1: Converting icon...
if exist "assets\images\app_icon.png" (
    if exist "convert-icon-to-ico.ps1" (
        powershell -ExecutionPolicy Bypass -File "convert-icon-to-ico.ps1"
    ) else (
        echo WARNING: convert-icon-to-ico.ps1 not found!
        echo Please convert assets\images\app_icon.png to ICO format manually
        echo and save as windows\runner\resources\app_icon.ico
    )
) else (
    echo WARNING: app_icon.png not found!
)

echo.
echo Step 2: Cleaning build...
flutter clean

echo.
echo Step 3: Rebuilding...
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"

echo.
echo Done! Check build\windows\runner\Release\pos_system.exe
pause
```

## Notes

- The title now uses Unicode escape sequences which should work regardless of file encoding
- The icon must be a valid ICO file with multiple resolutions for best results
- Always run `flutter clean` before rebuilding when changing icons or resources

