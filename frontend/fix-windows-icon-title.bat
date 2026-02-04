@echo off
chcp 65001 >nul
echo ========================================
echo Fixing Windows Icon and Title
echo ========================================
echo.

echo Step 1: Converting icon from PNG to ICO...
if exist "assets\images\app_icon.png" (
    if exist "convert-icon-to-ico.ps1" (
        echo Running PowerShell script to convert icon...
        powershell -ExecutionPolicy Bypass -File "convert-icon-to-ico.ps1"
        if errorlevel 1 (
            echo.
            echo WARNING: Icon conversion failed!
            echo Please convert assets\images\app_icon.png to ICO format manually
            echo and save as windows\runner\resources\app_icon.ico
            echo.
            echo You can use:
            echo   1. ImageMagick: magick convert assets\images\app_icon.png -define icon:auto-resize=256,128,64,48,32,16 windows\runner\resources\app_icon.ico
            echo   2. Online converter: https://convertio.co/png-ico/
            pause
        )
    ) else (
        echo WARNING: convert-icon-to-ico.ps1 not found!
        echo Please convert assets\images\app_icon.png to ICO format manually
        echo and save as windows\runner\resources\app_icon.ico
        pause
    )
) else (
    echo WARNING: app_icon.png not found at assets\images\app_icon.png!
    pause
)

echo.
echo Step 2: Verifying icon file...
if exist "windows\runner\resources\app_icon.ico" (
    echo Icon file found: windows\runner\resources\app_icon.ico
) else (
    echo ERROR: Icon file not found!
    echo Please create windows\runner\resources\app_icon.ico
    pause
    exit /b 1
)

echo.
echo Step 3: Cleaning previous build...
flutter clean
if errorlevel 1 (
    echo ERROR: flutter clean failed!
    pause
    exit /b 1
)

echo.
echo Step 4: Rebuilding Windows app...
echo This may take a few minutes...
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
if errorlevel 1 (
    echo ERROR: Build failed!
    pause
    exit /b 1
)

echo.
echo ========================================
echo Done!
echo ========================================
echo.
echo Check the built app at:
echo   build\windows\runner\Release\pos_system.exe
echo.
echo Verify:
echo   1. Window title should show: 德靈海味 POS
echo   2. Right-click exe -> Properties -> should show custom icon
echo   3. Taskbar should show custom icon when running
echo.
pause

