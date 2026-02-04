# PowerShell script to convert PNG icon to ICO format for Windows
# Run this from the frontend directory

$pngPath = "assets\images\app_icon.png"
$icoPath = "windows\runner\resources\app_icon.ico"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Converting PNG to ICO for Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if PNG exists
if (-not (Test-Path $pngPath)) {
    Write-Host "ERROR: PNG file not found: $pngPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please make sure the app_icon.png file exists in assets\images\" -ForegroundColor Yellow
    exit 1
}

# Check if resources directory exists
$resourcesDir = "windows\runner\resources"
if (-not (Test-Path $resourcesDir)) {
    Write-Host "Creating resources directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $resourcesDir -Force | Out-Null
}

# Try using ImageMagick if available
$magickPath = Get-Command magick -ErrorAction SilentlyContinue
if ($magickPath) {
    Write-Host "Using ImageMagick to convert icon..." -ForegroundColor Green
    Write-Host "Command: magick convert $pngPath -define icon:auto-resize=256,128,64,48,32,16 $icoPath" -ForegroundColor Gray
    
    & magick convert $pngPath -define icon:auto-resize=256,128,64,48,32,16 $icoPath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "SUCCESS: Icon converted successfully!" -ForegroundColor Green
        Write-Host "ICO file saved to: $icoPath" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "ImageMagick conversion failed. Trying alternative method..." -ForegroundColor Yellow
    }
}

# Alternative: Use .NET to create a simple ICO
Write-Host "Using .NET method to create ICO..." -ForegroundColor Yellow
Write-Host "Note: This creates a basic ICO. For best results, use ImageMagick or an online converter." -ForegroundColor Yellow
Write-Host ""

try {
    Add-Type -AssemblyName System.Drawing
    
    # Load the PNG image
    $pngImage = [System.Drawing.Image]::FromFile((Resolve-Path $pngPath))
    
    # Create a bitmap from the PNG
    $bitmap = New-Object System.Drawing.Bitmap($pngImage)
    
    # Create ICO file (simplified - Windows will use the first frame)
    # Note: This is a basic conversion. For multi-resolution ICO, use ImageMagick or online tool
    $icoStream = [System.IO.File]::Create($icoPath)
    
    # Write ICO header
    $icoHeader = [byte[]](0x00, 0x00, 0x01, 0x00, 0x01, 0x00)
    $icoStream.Write($icoHeader, 0, $icoHeader.Length)
    
    # Get image dimensions (max 256x256 for ICO)
    $width = [Math]::Min($bitmap.Width, 256)
    $height = [Math]::Min($bitmap.Height, 256)
    
    # Write directory entry
    $widthByte = [byte][Math]::Min($width, 255)
    $heightByte = [byte][Math]::Min($height, 255)
    $dirEntry = [byte[]]($widthByte, $heightByte, 0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00, 0x00)
    $icoStream.Write($dirEntry, 0, $dirEntry.Length)
    
    # Resize and save bitmap data
    $resizedBitmap = New-Object System.Drawing.Bitmap($bitmap, $width, $height)
    $memoryStream = New-Object System.IO.MemoryStream
    $resizedBitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngData = $memoryStream.ToArray()
    
    # Write PNG data
    $icoStream.Write($pngData, 0, $pngData.Length)
    
    $icoStream.Close()
    $pngImage.Dispose()
    $bitmap.Dispose()
    $resizedBitmap.Dispose()
    $memoryStream.Dispose()
    
    Write-Host ""
    Write-Host "SUCCESS: Basic ICO file created!" -ForegroundColor Green
    Write-Host "ICO file saved to: $icoPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: For best results with multiple resolutions, use:" -ForegroundColor Yellow
    Write-Host "  - ImageMagick: magick convert $pngPath -define icon:auto-resize=256,128,64,48,32,16 $icoPath" -ForegroundColor Yellow
    Write-Host "  - Online converter: https://convertio.co/png-ico/" -ForegroundColor Yellow
    
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to create ICO file" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Please use one of these alternatives:" -ForegroundColor Yellow
    Write-Host "  1. Install ImageMagick and run:" -ForegroundColor Yellow
    Write-Host "     magick convert $pngPath -define icon:auto-resize=256,128,64,48,32,16 $icoPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Use online converter:" -ForegroundColor Yellow
    Write-Host "     https://convertio.co/png-ico/" -ForegroundColor Cyan
    Write-Host "     Then save the downloaded file as: $icoPath" -ForegroundColor Yellow
    exit 1
}

