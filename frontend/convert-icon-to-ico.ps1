# PowerShell script to convert PNG icon to ICO format for Windows
# Run from the frontend directory:
#   powershell -ExecutionPolicy Bypass -File convert-icon-to-ico.ps1
#   powershell -ExecutionPolicy Bypass -File convert-icon-to-ico.ps1 -PngPath assets\images\app_icon_uat.png

param(
    [string]$PngPath = "assets\images\app_icon.png",
    [string]$IcoPath = "windows\runner\resources\app_icon.ico"
)

$ErrorActionPreference = 'Stop'

function Write-Ok([string]$Message) { Write-Host $Message -ForegroundColor Green }
function Write-Fail([string]$Message) { Write-Host $Message -ForegroundColor Red }

Write-Host 'Converting PNG to ICO for Windows...' -ForegroundColor Cyan

if (-not (Test-Path $PngPath)) {
    Write-Fail "ERROR: PNG not found: $PngPath"
    exit 1
}

$resourcesDir = Split-Path $IcoPath -Parent
if (-not (Test-Path $resourcesDir)) {
    New-Item -ItemType Directory -Path $resourcesDir -Force | Out-Null
}

if (Get-Command magick -ErrorAction SilentlyContinue) {
    Write-Host 'Using ImageMagick...' -ForegroundColor Gray
    & magick convert $PngPath -define icon:auto-resize=256,48,32,16 $IcoPath
    if ($LASTEXITCODE -eq 0 -and (Test-Path $IcoPath)) {
        Write-Ok "ICO saved: $IcoPath"
        exit 0
    }
    Write-Host 'ImageMagick failed, using built-in converter...' -ForegroundColor Yellow
}

function New-IcoFromPng {
    param(
        [string]$SourcePng,
        [string]$DestinationIco,
        [int[]]$Sizes = @(256, 48, 32, 16)
    )

    Add-Type -AssemblyName System.Drawing

    $pngBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $SourcePng))
    $sourceStream = New-Object System.IO.MemoryStream(,$pngBytes)
    $sourceImage = [System.Drawing.Image]::FromStream($sourceStream)

    $entries = New-Object System.Collections.Generic.List[Object]
    try {
        foreach ($size in $Sizes) {
            $dimension = [Math]::Min($size, 256)
            $bitmap = New-Object System.Drawing.Bitmap($dimension, $dimension)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($sourceImage, 0, 0, $dimension, $dimension)
            $graphics.Dispose()

            $pngStream = New-Object System.IO.MemoryStream
            $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $data = $pngStream.ToArray()
            $pngStream.Dispose()
            $bitmap.Dispose()

            $entries.Add([PSCustomObject]@{
                Width  = $dimension
                Height = $dimension
                Data   = $data
            })
        }
    } finally {
        $sourceImage.Dispose()
        $sourceStream.Dispose()
    }

    $stream = [System.IO.File]::Create($DestinationIco)
    $writer = New-Object System.IO.BinaryWriter($stream)

    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$entries.Count)

        $offset = 6 + (16 * $entries.Count)
        foreach ($entry in $entries) {
            $widthByte = [byte][Math]::Min($entry.Width, 255)
            $heightByte = [byte][Math]::Min($entry.Height, 255)
            $writer.Write($widthByte)
            $writer.Write($heightByte)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$entry.Data.Length)
            $writer.Write([UInt32]$offset)
            $offset += $entry.Data.Length
        }

        foreach ($entry in $entries) {
            $writer.Write($entry.Data)
        }
    } finally {
        $writer.Close()
        $stream.Close()
    }
}

try {
    New-IcoFromPng -SourcePng $PngPath -DestinationIco $IcoPath
    if (-not (Test-Path $IcoPath)) {
        throw 'ICO file was not created'
    }
    $length = (Get-Item $IcoPath).Length
    if ($length -lt 100) {
        throw "ICO file looks too small ($length bytes)"
    }
    Write-Ok "ICO saved: $IcoPath ($length bytes)"
} catch {
    Write-Fail "ERROR: Failed to create ICO: $($_.Exception.Message)"
    Write-Host 'Install ImageMagick: winget install ImageMagick.ImageMagick' -ForegroundColor Yellow
    exit 1
}
