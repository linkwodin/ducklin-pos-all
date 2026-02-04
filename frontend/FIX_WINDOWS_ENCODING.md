# Fixing Windows Encoding and Icon Issues

## Issue 1: Title Showing as Garbled Text (亂碼)

The Windows resource file needs to be saved with UTF-8 BOM encoding for Chinese characters to display correctly.

### Solution:

1. **On Windows machine**, open `windows/runner/Runner.rc` in a text editor that supports encoding (like Visual Studio Code or Notepad++)

2. **Save the file with UTF-8 BOM encoding:**
   - In VS Code: Click encoding in bottom right → "Save with Encoding" → "UTF-8 with BOM"
   - In Notepad++: Encoding → "Convert to UTF-8-BOM"

3. **Verify the file has the correct content:**
   ```rc
   #pragma code_page(65001)  // UTF-8
   ...
   VALUE "ProductName", "德靈海味 POS" "\0"
   VALUE "FileDescription", "德靈海味 POS" "\0"
   ```

4. **Rebuild the app:**
   ```cmd
   flutter clean
   flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
   ```

## Issue 2: Icon Not Working

The icon file needs to be a proper ICO format file.

### Solution:

1. **Convert PNG to ICO:**
   
   **Option A: Use ImageMagick (if installed on Windows)**
   ```cmd
   magick convert assets\images\app_icon.png -define icon:auto-resize=256,128,64,48,32,16 windows\runner\resources\app_icon.ico
   ```
   
   **Option B: Use Online Converter**
   - Go to https://convertio.co/png-ico/ or https://www.icoconverter.com/
   - Upload `assets/images/app_icon.png`
   - Download the ICO file
   - Save it as `windows/runner/resources/app_icon.ico`

   **Option C: Use PowerShell (Windows 10+)**
   ```powershell
   # This requires .NET, creates a simple ICO
   Add-Type -AssemblyName System.Drawing
   $img = [System.Drawing.Image]::FromFile("assets\images\app_icon.png")
   $ico = New-Object System.Drawing.Icon
   # Note: PowerShell method is complex, use Option A or B instead
   ```

2. **Verify the icon file exists:**
   ```cmd
   dir windows\runner\resources\app_icon.ico
   ```

3. **Check Runner.rc references the icon:**
   ```rc
   IDI_APP_ICON            ICON                    "resources\\app_icon.ico"
   ```

4. **Rebuild:**
   ```cmd
   flutter clean
   flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
   ```

## Quick Fix Script for Windows

Create `fix-windows-encoding.bat`:

```batch
@echo off
chcp 65001 >nul
echo Fixing Windows encoding and icon...

echo.
echo Step 1: Checking icon file...
if not exist "windows\runner\resources\app_icon.ico" (
    echo WARNING: app_icon.ico not found!
    echo Please convert assets\images\app_icon.png to ICO format
    echo and save as windows\runner\resources\app_icon.ico
    pause
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

## Verification

After rebuilding, check:
1. **Window title**: Should show "德靈海味 POS" (not garbled)
2. **App icon**: Right-click exe → Properties → should show custom icon
3. **Taskbar**: Should show custom icon when running

## Troubleshooting

### Still showing garbled text?
- Make sure `Runner.rc` is saved with UTF-8 BOM
- Check that `#pragma code_page(65001)` is at the top
- Rebuild with `flutter clean` first

### Icon still not showing?
- Verify `app_icon.ico` exists and is valid (try opening it)
- Check file size (should be > 1KB)
- Make sure path in `Runner.rc` is correct: `"resources\\app_icon.ico"`

