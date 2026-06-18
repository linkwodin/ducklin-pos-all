# Convert PNG to ICO for Windows builds.
# Prefer Dart (same toolchain as Flutter); fallback to ImageMagick if installed.

param(
    [string]$PngPath = 'assets\images\app_icon.png',
    [string]$IcoPath = 'windows\runner\resources\app_icon.ico'
)

$ErrorActionPreference = 'Stop'

function Write-Ok([string]$Message) { Write-Host $Message -ForegroundColor Green }
function Write-Fail([string]$Message) { Write-Host $Message -ForegroundColor Red }

function Resolve-FullPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path $Path).Path
    }
    return (Resolve-Path (Join-Path (Get-Location) $Path)).Path
}

Write-Host 'Converting PNG to ICO for Windows...' -ForegroundColor Cyan

try {
    $pngFull = Resolve-FullPath $PngPath
} catch {
    Write-Fail "ERROR: PNG not found: $PngPath"
    exit 1
}

if ([System.IO.Path]::IsPathRooted($IcoPath)) {
    $icoFull = $IcoPath
} else {
    $icoFull = Join-Path (Get-Location) $IcoPath
}

$icoDir = Split-Path $icoFull -Parent
if (-not (Test-Path $icoDir)) {
    New-Item -ItemType Directory -Path $icoDir -Force | Out-Null
}

if (Test-Path $icoFull) {
    Remove-Item $icoFull -Force -ErrorAction SilentlyContinue
}

# 1) Dart tool (reliable; uses Flutter project image package)
if (Get-Command dart -ErrorAction SilentlyContinue) {
    Write-Host 'Using dart tool/generate_app_icon_ico.dart ...' -ForegroundColor Gray
    dart run tool/generate_app_icon_ico.dart $pngFull $icoFull
    if ($LASTEXITCODE -eq 0 -and (Test-Path $icoFull)) {
        $length = (Get-Item $icoFull).Length
        Write-Ok "ICO saved: $icoFull ($length bytes)"
        exit 0
    }
    Write-Host 'Dart ICO tool failed, trying ImageMagick...' -ForegroundColor Yellow
}

# 2) ImageMagick fallback
if (Get-Command magick -ErrorAction SilentlyContinue) {
    Write-Host 'Using ImageMagick...' -ForegroundColor Gray
    & magick convert $pngFull -define icon:auto-resize=256,48,32,16 $icoFull
    if ($LASTEXITCODE -eq 0 -and (Test-Path $icoFull)) {
        Write-Ok "ICO saved: $icoFull"
        exit 0
    }
}

Write-Fail 'ERROR: Could not create ICO.'
Write-Host 'Ensure Dart/Flutter is on PATH (dart run tool/generate_app_icon_ico.dart).' -ForegroundColor Yellow
Write-Host 'Optional: winget install ImageMagick.ImageMagick' -ForegroundColor Yellow
exit 1
