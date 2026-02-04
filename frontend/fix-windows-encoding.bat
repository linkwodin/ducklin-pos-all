@echo off
REM Fix Windows Encoding and Icon Issues
REM Run this from the frontend directory

chcp 65001 >nul
echo ========================================
echo Fixing Windows Encoding and Icon
echo ========================================
echo.

echo Step 1: Checking icon file...
if not exist "windows\runner\resources\app_icon.ico" (
    echo.
    echo WARNING: app_icon.ico not found!
    echo.
    echo Please convert assets\images\app_icon.png to ICO format:
    echo   1. Use online converter: https://convertio.co/png-ico/
    echo   2. Or use ImageMagick: magick convert assets\images\app_icon.png -define icon:auto-resize=256,128,64,48,32,16 windows\runner\resources\app_icon.ico
    echo   3. Save as: windows\runner\resources\app_icon.ico
    echo.
    pause
) else (
    echo Icon file found: windows\runner\resources\app_icon.ico
)

echo.
echo Step 2: IMPORTANT - Save Runner.rc with UTF-8 BOM encoding
echo.
echo Please open windows\runner\Runner.rc in a text editor and:
echo   - In VS Code: Click encoding in bottom right ^> "Save with Encoding" ^> "UTF-8 with BOM"
echo   - In Notepad++: Encoding ^> "Convert to UTF-8-BOM"
echo.
echo This is required for Chinese characters to display correctly!
echo.
pause

echo.
echo Step 3: Cleaning build...
flutter clean
if errorlevel 1 (
    echo WARNING: Clean failed, continuing anyway...
)

echo.
echo Step 4: Rebuilding Windows app...
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
if errorlevel 1 (
    echo.
    echo ERROR: Build failed!
    echo.
    echo Make sure:
    echo   1. Runner.rc is saved with UTF-8 BOM encoding
    echo   2. app_icon.ico exists in windows\runner\resources\
    echo   3. Visual Studio 2022 with C++ tools is installed
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo ========================================
echo.
echo Check: build\windows\runner\Release\pos_system.exe
echo   - Window title should show: 德靈海味 POS
echo   - Icon should be visible in taskbar and file properties
echo.
pause

