# Build and optionally deploy Flutter POS for Windows (UAT or production).
#
# One-click deploy (from repo root):
#   scripts\frontend\build-and-deploy-flutter-uat-windows.bat
#
# Build only:
#   powershell -ExecutionPolicy Bypass -File scripts\frontend\build-flutter-uat-windows.ps1
#
# Deploy after build:
#   powershell -ExecutionPolicy Bypass -File scripts\frontend\build-flutter-uat-windows.ps1 -Deploy
#
# Prerequisites:
#   - Flutter SDK + Visual Studio 2022 (Desktop development with C++)
#   - For -Deploy: gcloud CLI authenticated (gcloud auth login)

param(
    [ValidateSet('uat', 'production')]
    [Alias('Env')]
    [string]$BuildEnv = 'uat',

    [switch]$Deploy,

    [switch]$Clean,

    [string]$ProjectId = ''
)

$ErrorActionPreference = 'Stop'

$UatBackendUrl = if ($env:UAT_BACKEND_URL) { $env:UAT_BACKEND_URL } else { 'https://pos-backend-28040503481.europe-west1.run.app/api/v1' }
$ProdBackendUrl = if ($env:PROD_BACKEND_URL) { $env:PROD_BACKEND_URL } else { 'https://pos-backend-vepqiqvcoa-ew.a.run.app/api/v1' }
$Version = '1.0.0'
$Region = if ($env:REGION) { $env:REGION } else { 'europe-west1' }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..')
$FrontendDir = Join-Path $RepoRoot 'frontend'
$MainCpp = Join-Path $FrontendDir 'windows\runner\main.cpp'
$RunnerRc = Join-Path $FrontendDir 'windows\runner\Runner.rc'
$MainCppBak = ''

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Get-GcloudProject {
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        return ''
    }

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $value = & gcloud config get-value project 2>$null
        if ($null -eq $value) { return '' }
        return "$value".Trim()
    } finally {
        $ErrorActionPreference = $oldEap
    }
}

function Get-PosAppTitle {
    param([string]$TargetEnv)

    # Build Chinese app name without non-ASCII literals (PowerShell 5.1 encoding safe).
    $name = -join (@(0x5FB7, 0x9748, 0x6D77, 0x5473) | ForEach-Object { [char]$_ })
    if ($TargetEnv -eq 'production') {
        return "$name POS"
    }
    return "$name POS UAT"
}

function Restore-WindowsBranding {
    if ($MainCppBak -and (Test-Path $MainCppBak)) {
        Move-Item -Force $MainCppBak $MainCpp
    }
    # Recover from a previous failed build that patched Runner.rc.
    if (Test-Path "$RunnerRc.buildbak") {
        Move-Item -Force "$RunnerRc.buildbak" $RunnerRc
    }
}

function Clear-WindowsBuildCache {
    param([string]$Root)

    Write-Info 'Clearing Windows build cache (fixes corrupt vcxproj / LNK1123)...'
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Push-Location $Root
        flutter clean 2>&1 | ForEach-Object { Write-Host $_ }
    } finally {
        Pop-Location
        $ErrorActionPreference = $oldEap
    }

    foreach ($path in @(
            (Join-Path $Root 'build\windows'),
            (Join-Path $Root '.dart_tool\flutter_build')
        )) {
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
        }
    }
}

function Set-AsciiFileContent {
    param(
        [string]$Path,
        [string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-ReleaseDir {
    param([string]$Root)
    $candidates = @(
        (Join-Path $Root 'build\windows\x64\runner\Release'),
        (Join-Path $Root 'build\windows\runner\Release')
    )
    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir 'pos_system.exe')) {
            return $dir
        }
    }
    return $null
}

function Ensure-GcsBucket {
    param(
        [string]$Bucket,
        [string]$GcpProject,
        [string]$GcpRegion
    )
    gsutil ls -b "gs://$Bucket" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating bucket: gs://$Bucket"
        gsutil mb -p $GcpProject -c STANDARD -l $GcpRegion "gs://$Bucket"
        if ($LASTEXITCODE -ne 0) { throw "Failed to create bucket gs://$Bucket" }
        Write-Info 'Making bucket publicly readable...'
        gsutil iam ch allUsers:objectViewer "gs://$Bucket"
        $corsJson = '[{"origin": ["*"], "method": ["GET", "HEAD"], "responseHeader": ["Content-Type", "Content-Disposition"], "maxAgeSeconds": 3600}]'
        $corsFile = Join-Path $env:TEMP 'pos-flutter-uat-cors.json'
        Set-Content -Path $corsFile -Value $corsJson -Encoding UTF8
        gsutil cors set $corsFile "gs://$Bucket"
        Remove-Item $corsFile -ErrorAction SilentlyContinue
    } else {
        Write-Info "Bucket exists: gs://$Bucket"
        gsutil iam ch allUsers:objectViewer "gs://$Bucket" 2>$null | Out-Null
    }
}

function Publish-WindowsZip {
    param(
        [string]$ReleaseDir,
        [string]$GcpProject,
        [string]$TargetEnv
    )

    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        throw 'gcloud CLI is not installed. Install from https://cloud.google.com/sdk/docs/install'
    }
    if (-not (Get-Command gsutil -ErrorAction SilentlyContinue)) {
        throw 'gsutil is not available. Install Google Cloud SDK.'
    }

    $bucketSuffix = if ($TargetEnv -eq 'production') { 'pos-flutter-prod' } else { 'pos-flutter-uat' }
    $zipPrefix = if ($TargetEnv -eq 'production') { 'pos-system-prod-windows' } else { 'pos-system-uat-windows' }
    $bucketName = "$GcpProject-$bucketSuffix"

    Write-Info "Packaging Release folder..."
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zipName = "$zipPrefix-$Version-$timestamp.zip"
    $zipPath = Join-Path $FrontendDir $zipName

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Push-Location $ReleaseDir
    try {
        Compress-Archive -Path * -DestinationPath $zipPath -Force
    } finally {
        Pop-Location
    }
    if (-not (Test-Path $zipPath)) {
        throw 'Failed to create ZIP file'
    }

    $zipSizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Info "Created $zipName ($zipSizeMb MB)"

    Write-Info "Uploading to gs://$bucketName/ ..."
    Ensure-GcsBucket -Bucket $bucketName -GcpProject $GcpProject -GcpRegion $Region

    gsutil cp $zipPath "gs://$bucketName/$zipName"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upload versioned ZIP' }

    $latestName = "$zipPrefix-latest.zip"
    gsutil cp $zipPath "gs://$bucketName/$latestName"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upload latest ZIP' }

    gsutil setmeta -h 'Content-Type:application/zip' `
        -h "Content-Disposition:attachment; filename=`"$zipName`"" `
        "gs://$bucketName/$zipName" | Out-Null
    gsutil setmeta -h 'Content-Type:application/zip' `
        -h "Content-Disposition:attachment; filename=`"$latestName`"" `
        "gs://$bucketName/$latestName" | Out-Null

    if ($TargetEnv -eq 'uat') {
        $indexHtml = Join-Path $ScriptDir 'uat-downloads-index.html'
        if (Test-Path $indexHtml) {
            Write-Info 'Updating downloads index.html...'
            gsutil -h 'Content-Type:text/html' cp $indexHtml "gs://$bucketName/index.html" | Out-Null
        }
    }

    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host 'Deploy complete!' -ForegroundColor Green
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host "Latest:  https://storage.googleapis.com/$bucketName/$latestName" -ForegroundColor Cyan
    if ($TargetEnv -eq 'uat') {
        Write-Host "Page:    https://storage.googleapis.com/$bucketName/index.html" -ForegroundColor Cyan
    }
    Write-Host ''
}

trap {
    Restore-WindowsBranding
    Write-Err $_.Exception.Message
    exit 1
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Err 'Flutter is not installed or not on PATH.'
    exit 1
}

$backendUrl = if ($BuildEnv -eq 'production') { $ProdBackendUrl } else { $UatBackendUrl }
$appTitle = Get-PosAppTitle -TargetEnv $BuildEnv
$iconPng = if ($BuildEnv -eq 'production') { 'assets\images\app_icon.png' } else { 'assets\images\app_icon_uat.png' }

Set-Location $FrontendDir

Restore-WindowsBranding

Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host " POS Windows build$(if ($Deploy) { ' + deploy' }) ($BuildEnv)" -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''
Write-Info "Backend: $backendUrl"

if ($BuildEnv -eq 'uat') {
    Write-Info 'Generating UAT app icon...'
    dart run tool/generate_uat_icon.dart
}

Write-Info 'Converting icon to ICO...'
$convertScript = Join-Path $FrontendDir 'convert-icon-to-ico.ps1'
& powershell -ExecutionPolicy Bypass -File $convertScript -PngPath $iconPng
if ($LASTEXITCODE -ne 0) { throw 'Icon conversion failed' }

if ($BuildEnv -eq 'uat') {
    Write-Info "Setting Windows window title to: $appTitle"
    $MainCppBak = "$MainCpp.buildbak"
    Copy-Item $MainCpp $MainCppBak -Force

    $cpp = Get-Content $MainCpp -Raw -Encoding UTF8
    $cpp = $cpp -replace 'L"\u5FB7\u9748\u6D77\u5473 POS( UAT)?"', 'L"\u5FB7\u9748\u6D77\u5473 POS UAT"'
    Set-AsciiFileContent -Path $MainCpp -Content $cpp
}

Clear-WindowsBuildCache -Root $FrontendDir

Write-Info 'Getting dependencies...'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

if ($Clean) {
    Write-Info 'Deep clean requested...'
    Clear-WindowsBuildCache -Root $FrontendDir
    flutter pub get
}

Write-Info "Building Windows release ($BuildEnv)..."
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
flutter build windows --release `
    --dart-define=ENV=$BuildEnv `
    --dart-define=API_BASE_URL="$backendUrl"
$buildExit = $LASTEXITCODE
$ErrorActionPreference = $oldEap
if ($buildExit -ne 0) {
    Write-Warn 'For LNK1123 / CVT1103 run: scripts\frontend\repair-windows-build.bat'
    Write-Warn 'Repo should be at C:\dev\ducklin-pos-all (short path). Exclude build folder from antivirus.'
    throw 'flutter build windows failed'
}

Restore-WindowsBranding

$releaseDir = Get-ReleaseDir -Root $FrontendDir
if (-not $releaseDir) {
    throw 'Build finished but pos_system.exe not found under frontend\build\windows'
}

$exePath = Join-Path $releaseDir 'pos_system.exe'
Write-Info 'Build complete!'
Write-Host "  Folder: $releaseDir" -ForegroundColor Cyan
Write-Host "  Exe:    $exePath" -ForegroundColor Cyan

if ($Deploy) {
    $gcpProject = $ProjectId
    if (-not $gcpProject) {
        $gcpProject = Get-GcloudProject
    }
    if (-not $gcpProject) {
        throw 'No GCP project. Run: gcloud config set project ducklin-uk-uat (or ducklin-uk-prod)'
    }
    if ($BuildEnv -eq 'uat' -and $gcpProject -ne 'ducklin-uk-uat') {
        Write-Warn "GCP project is $gcpProject (expected ducklin-uk-uat for UAT downloads)."
    }
    if ($BuildEnv -eq 'production' -and $gcpProject -ne 'ducklin-uk-prod') {
        Write-Warn "GCP project is $gcpProject (expected ducklin-uk-prod for production downloads)."
    }
    Write-Info "Deploying to project: $gcpProject"
    Publish-WindowsZip -ReleaseDir $releaseDir -GcpProject $gcpProject -TargetEnv $BuildEnv
} else {
    Write-Host ''
    Write-Host 'Tip: run with -Deploy to zip and upload to GCS.' -ForegroundColor Yellow
    Write-Host '  scripts\frontend\build-and-deploy-flutter-uat-windows.bat' -ForegroundColor Yellow
}
