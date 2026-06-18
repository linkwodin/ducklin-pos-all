# Repair corrupted Windows Flutter build (LNK1123, CVT1103, bad vcxproj).
# Run from repo root:
#   scripts\frontend\repair-windows-build.bat

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..')
$FrontendDir = Join-Path $RepoRoot 'frontend'

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not on PATH.'
}

Set-Location $FrontendDir

Write-Info 'Restoring windows source files if a prior build left backups...'
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

Write-Info 'Regenerating Windows platform files...'
flutter create --platforms=windows .
if ($LASTEXITCODE -ne 0) { throw 'flutter create --platforms=windows failed' }

Write-Info 'flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

Write-Host ''
Write-Info 'Repair complete. Run BUILD-AND-DEPLOY-WINDOWS.bat again.'
Write-Info 'Repo path: C:\dev\ducklin-pos-all'
Write-Warn 'Ensure Visual Studio 2022 has "Desktop development with C++" installed.'
