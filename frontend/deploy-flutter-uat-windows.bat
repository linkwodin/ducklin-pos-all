@echo off
REM Flutter App UAT Deployment Script for Windows
REM Builds Flutter app and uploads to GCP Storage for download

setlocal enabledelayedexpansion

REM Configuration
REM Note: This script should be run from the frontend directory
set REGION=europe-west1
set UAT_BACKEND_URL=https://pos-backend-28040503481.europe-west1.run.app/api/v1

REM Get GCP project ID
for /f "tokens=*" %%i in ('gcloud config get-value project 2^>nul') do set PROJECT_ID=%%i
if "%PROJECT_ID%"=="" (
    echo [ERROR] No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID
    exit /b 1
)

set BUCKET_NAME=%PROJECT_ID%-pos-flutter-uat

echo [INFO] Starting Flutter app deployment to UAT...
echo [INFO] Using project: %PROJECT_ID%
echo [INFO] Using region: %REGION%
echo [INFO] UAT Backend URL: %UAT_BACKEND_URL%

REM Check prerequisites
echo [INFO] Checking prerequisites...

where gcloud >nul 2>&1
if errorlevel 1 (
    echo [ERROR] gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install
    exit /b 1
)

where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter is not installed. Please install it from https://flutter.dev/docs/get-started/install
    exit /b 1
)

REM Build Flutter app
echo [INFO] Building Flutter app for UAT...
REM Script should be run from frontend directory, so we're already here

echo [INFO] Getting Flutter dependencies...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] Failed to get Flutter dependencies
    exit /b 1
)

echo [INFO] Cleaning previous builds...
call flutter clean

echo [INFO] Building Windows app...
call flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL=%UAT_BACKEND_URL%
if errorlevel 1 (
    echo [ERROR] Windows build failed
    exit /b 1
)

if not exist "build\windows\runner\Release\pos_system.exe" (
    echo [ERROR] Windows build failed - pos_system.exe not found
    exit /b 1
)

echo [INFO] Windows app built successfully!

REM Package Windows app
echo [INFO] Packaging Windows app...
set TIMESTAMP=%date:~-4%%date:~3,2%%date:~0,2%-%time:~0,2%%time:~3,2%%time:~6,2%
set TIMESTAMP=!TIMESTAMP: =0!
set VERSION=1.0.0

cd build\windows\runner\Release
powershell -Command "Compress-Archive -Path * -DestinationPath ..\..\..\..\pos-system-uat-windows-%VERSION%-%TIMESTAMP%.zip -Force"
cd ..\..\..\..

if not exist "pos-system-uat-windows-%VERSION%-%TIMESTAMP%.zip" (
    echo [ERROR] Failed to create ZIP file
    exit /b 1
)

echo [INFO] Windows app packaged successfully!

REM Deploy to GCP
echo [INFO] Deploying Flutter app to GCP Storage...

REM Check if bucket exists
gsutil ls -b gs://%BUCKET_NAME% >nul 2>&1
if errorlevel 1 (
    echo [INFO] Creating bucket: %BUCKET_NAME%
    gsutil mb -p %PROJECT_ID% -c STANDARD -l %REGION% gs://%BUCKET_NAME%
    if errorlevel 1 (
        echo [ERROR] Failed to create bucket
        exit /b 1
    )
    
    echo [INFO] Making bucket publicly readable...
    gsutil iam ch allUsers:objectViewer gs://%BUCKET_NAME%
    
    echo [INFO] Setting CORS policy...
    echo [{"origin": ["*"], "method": ["GET", "HEAD"], "responseHeader": ["Content-Type", "Content-Disposition"], "maxAgeSeconds": 3600}] > %TEMP%\cors.json
    gsutil cors set %TEMP%\cors.json gs://%BUCKET_NAME%
    del %TEMP%\cors.json
) else (
    echo [INFO] Bucket already exists: %BUCKET_NAME%
    echo [INFO] Ensuring bucket is publicly readable...
    gsutil iam ch allUsers:objectViewer gs://%BUCKET_NAME% >nul 2>&1
)

REM Upload Windows app
echo [INFO] Uploading Windows app...
set ZIP_NAME=pos-system-uat-windows-%VERSION%-%TIMESTAMP%.zip
gsutil cp pos-system-uat-windows-%VERSION%-%TIMESTAMP%.zip gs://%BUCKET_NAME%\%ZIP_NAME%
if errorlevel 1 (
    echo [ERROR] Failed to upload Windows app
    exit /b 1
)

gsutil cp pos-system-uat-windows-%VERSION%-%TIMESTAMP%.zip gs://%BUCKET_NAME%\pos-system-uat-windows-latest.zip
if errorlevel 1 (
    echo [ERROR] Failed to upload latest Windows app
    exit /b 1
)

gsutil setmeta -h "Content-Type:application/zip" -h "Content-Disposition:attachment; filename=\"%ZIP_NAME%\"" gs://%BUCKET_NAME%\%ZIP_NAME%
gsutil setmeta -h "Content-Type:application/zip" -h "Content-Disposition:attachment; filename=\"pos-system-uat-windows-latest.zip\"" gs://%BUCKET_NAME%\pos-system-uat-windows-latest.zip

echo [INFO] Windows app uploaded successfully!
echo [INFO] Download URL: https://storage.googleapis.com/%BUCKET_NAME%/%ZIP_NAME%
echo [INFO] Latest URL: https://storage.googleapis.com/%BUCKET_NAME%/pos-system-uat-windows-latest.zip

echo.
echo ==========================================
echo Flutter app deployed successfully!
echo ==========================================
echo Download page: https://storage.googleapis.com/%BUCKET_NAME%/index.html
echo Latest Windows App: https://storage.googleapis.com/%BUCKET_NAME%/pos-system-uat-windows-latest.zip
echo.

endlocal

