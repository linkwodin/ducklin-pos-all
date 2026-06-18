# Repair corrupted Windows Flutter build (LNK1123, CVT1103, bad ICO / vcxproj).
# Run from repo root: scripts\frontend\repair-windows-build.bat

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..')
$FrontendDir = Join-Path $RepoRoot 'frontend'

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Green }

. (Join-Path $ScriptDir 'import-vs-dev-env.ps1')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not on PATH.'
}

Set-Location $FrontendDir

Write-Info 'Restoring source backups from failed builds...'
foreach ($bak in @(
        'windows\runner\Runner.rc.buildbak',
        'windows\runner\main.cpp.buildbak'
    )) {
    $path = Join-Path $FrontendDir $bak
    if (Test-Path $path) {
        $target = $path -replace '\.buildbak$', ''
        Move-Item -Force $path $target
        Write-Info "Restored $target"
    }
}

Write-Info 'Regenerating app_icon.ico (Dart tool)...'
Push-Location $FrontendDir
try {
    dart run tool/generate_app_icon_ico.dart
    if ($LASTEXITCODE -ne 0) {
        & (Join-Path $FrontendDir 'convert-icon-to-ico.ps1')
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Icon conversion failed'
    }
} finally {
    Pop-Location
}

Write-Info 'flutter clean'
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
flutter clean 2>&1 | ForEach-Object { Write-Host $_ }
$ErrorActionPreference = $oldEap

foreach ($path in @('build\windows', '.dart_tool\flutter_build')) {
    $full = Join-Path $FrontendDir $path
    if (Test-Path $full) {
        Write-Info "Removing $path"
        Remove-Item -Recurse -Force $full
    }
}

Write-Info 'Regenerating Windows platform files (only if missing)...'
if (-not (Test-Path (Join-Path $FrontendDir 'windows\CMakeLists.txt'))) {
    flutter create --platforms=windows .
    if ($LASTEXITCODE -ne 0) { throw 'flutter create --platforms=windows failed' }
    dart run tool/generate_app_icon_ico.dart
    if ($LASTEXITCODE -ne 0) { throw 'Icon conversion failed' }
}

Write-Info 'flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

Import-VisualStudioDevEnvironment | Out-Null

Write-Host ''
Write-Info 'Repair complete. Run BUILD-AND-DEPLOY-WINDOWS.bat again.'
Write-Info 'Repo path: C:\dev\ducklin-pos-all'
Write-Host ''
Write-Host 'If LNK1123 persists, open "x64 Native Tools Command Prompt for VS 2022" and run:' -ForegroundColor Yellow
Write-Host '  cd C:\dev\ducklin-pos-all\frontend' -ForegroundColor Yellow
Write-Host '  flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL=https://pos-backend-28040503481.europe-west1.run.app/api/v1' -ForegroundColor Yellow
