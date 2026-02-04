@echo off
REM Fix Windows Desktop Project Configuration
REM Run this from the frontend directory

echo ========================================
echo Fixing Windows Desktop Project
echo ========================================
echo.

echo Step 1: Enabling Windows desktop support...
flutter config --enable-windows-desktop
if errorlevel 1 (
    echo ERROR: Failed to enable Windows desktop support
    pause
    exit /b 1
)

echo.
echo Step 2: Regenerating Windows project files...
flutter create --platforms=windows .
if errorlevel 1 (
    echo ERROR: Failed to create Windows project
    pause
    exit /b 1
)

echo.
echo Step 3: Cleaning build cache...
flutter clean
if errorlevel 1 (
    echo WARNING: Clean failed, continuing anyway...
)

echo.
echo Step 4: Getting dependencies...
flutter pub get
if errorlevel 1 (
    echo ERROR: Failed to get dependencies
    pause
    exit /b 1
)

echo.
echo ========================================
echo Windows project configured successfully!
echo ========================================
echo.
echo Next steps:
echo   1. Build: flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
echo   2. Run: flutter run -d windows
echo.
pause

