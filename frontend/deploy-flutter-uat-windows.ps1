# Flutter App UAT Deployment Script for Windows (PowerShell)
# Builds Flutter app and uploads to GCP Storage for download

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Info {
    Write-Host "[INFO] $args" -ForegroundColor Green
}

function Write-Warn {
    Write-Host "[WARN] $args" -ForegroundColor Yellow
}

function Write-Error {
    Write-Host "[ERROR] $args" -ForegroundColor Red
}

# Configuration
# Note: This script should be run from the frontend directory
$REGION = if ($env:REGION) { $env:REGION } else { "europe-west1" }
$UAT_BACKEND_URL = "https://pos-backend-28040503481.europe-west1.run.app/api/v1"
$VERSION = "1.0.0"

# Get GCP project ID
try {
    $PROJECT_ID = gcloud config get-value project 2>$null
    if (-not $PROJECT_ID) {
        Write-Error "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    }
} catch {
    Write-Error "Failed to get GCP project. Make sure gcloud is installed and configured."
    exit 1
}

$BUCKET_NAME = "$PROJECT_ID-pos-flutter-uat"

Write-Info "Starting Flutter app deployment to UAT..."
Write-Info "Using project: $PROJECT_ID"
Write-Info "Using region: $REGION"
Write-Info "UAT Backend URL: $UAT_BACKEND_URL"

# Check prerequisites
Write-Info "Checking prerequisites..."

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    exit 1
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not installed. Please install it from https://flutter.dev/docs/get-started/install"
    exit 1
}

# Build Flutter app
Write-Info "Building Flutter app for UAT..."
# Script should be run from frontend directory, so we're already here

try {
    Write-Info "Getting Flutter dependencies..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get Flutter dependencies"
    }

    Write-Info "Cleaning previous builds..."
    flutter clean

    Write-Info "Building Windows app..."
    flutter build windows --release `
        --dart-define=ENV=uat `
        --dart-define=API_BASE_URL="$UAT_BACKEND_URL"
    
    if ($LASTEXITCODE -ne 0) {
        throw "Windows build failed"
    }

    $exePath = "build\windows\runner\Release\pos_system.exe"
    if (-not (Test-Path $exePath)) {
        throw "Windows build failed - pos_system.exe not found"
    }

    Write-Info "Windows app built successfully!"

    # Package Windows app
    Write-Info "Packaging Windows app..."
    $TIMESTAMP = Get-Date -Format "yyyyMMdd-HHmmss"
    $ZIP_NAME = "pos-system-uat-windows-$VERSION-$TIMESTAMP.zip"
    
    $releaseDir = Join-Path $PWD "build\windows\runner\Release"
    $zipPath = Join-Path $PWD $ZIP_NAME
    
    Push-Location $releaseDir
    try {
        Compress-Archive -Path * -DestinationPath $zipPath -Force
        if (-not (Test-Path $zipPath)) {
            throw "Failed to create ZIP file"
        }
    } finally {
        Pop-Location
    }

    Write-Info "Windows app packaged successfully!"

    # Deploy to GCP
    Write-Info "Deploying Flutter app to GCP Storage..."

    # Check if bucket exists
    $bucketExists = gsutil ls -b "gs://$BUCKET_NAME" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating bucket: $BUCKET_NAME"
        gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION "gs://$BUCKET_NAME"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create bucket"
        }
        
        Write-Info "Making bucket publicly readable..."
        gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME"
        
        Write-Info "Setting CORS policy..."
        $corsJson = @'
[{"origin": ["*"], "method": ["GET", "HEAD"], "responseHeader": ["Content-Type", "Content-Disposition"], "maxAgeSeconds": 3600}]
'@
        $corsJson | Out-File -FilePath "$env:TEMP\cors.json" -Encoding UTF8
        gsutil cors set "$env:TEMP\cors.json" "gs://$BUCKET_NAME"
        Remove-Item "$env:TEMP\cors.json"
    } else {
        Write-Info "Bucket already exists: $BUCKET_NAME"
        Write-Info "Ensuring bucket is publicly readable..."
        gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME" 2>$null
    }

    # Upload Windows app
    Write-Info "Uploading Windows app..."
    $fullZipPath = Resolve-Path $zipPath -ErrorAction Stop
    gsutil cp $fullZipPath "gs://$BUCKET_NAME/$ZIP_NAME"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload Windows app"
    }

    gsutil cp $fullZipPath "gs://$BUCKET_NAME/pos-system-uat-windows-latest.zip"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload latest Windows app"
    }

    gsutil setmeta -h "Content-Type:application/zip" `
        -h "Content-Disposition:attachment; filename=`"$ZIP_NAME`"" `
        "gs://$BUCKET_NAME/$ZIP_NAME"
    
    gsutil setmeta -h "Content-Type:application/zip" `
        -h "Content-Disposition:attachment; filename=`"pos-system-uat-windows-latest.zip`"" `
        "gs://$BUCKET_NAME/pos-system-uat-windows-latest.zip"

    Write-Info "Windows app uploaded successfully!"
    Write-Info "Download URL: https://storage.googleapis.com/$BUCKET_NAME/$ZIP_NAME"
    Write-Info "Latest URL: https://storage.googleapis.com/$BUCKET_NAME/pos-system-uat-windows-latest.zip"

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Flutter app deployed successfully!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Download page: https://storage.googleapis.com/$BUCKET_NAME/index.html"
    Write-Host "Latest Windows App: https://storage.googleapis.com/$BUCKET_NAME/pos-system-uat-windows-latest.zip"
    Write-Host ""

} catch {
    Write-Error $_.Exception.Message
    exit 1
}

