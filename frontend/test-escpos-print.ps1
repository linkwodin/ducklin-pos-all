# PowerShell script to create and print a test ESC/POS file
# Usage: .\test-escpos-print.ps1 -PortName "USB001"

param(
    [Parameter(Mandatory=$true)]
    [string]$PortName
)

Write-Host "Creating ESC/POS test file..."

# ESC/POS commands for a simple test print
# ESC @ = Initialize printer
# ESC a 1 = Center align
# ESC ! 16 = Double height and width
# ESC d 2 = Feed 2 lines
# ESC i = Cut paper

$escPosBytes = @(
    # Initialize printer
    0x1B, 0x40,
    # Center align
    0x1B, 0x61, 0x01,
    # Double height and width
    0x1B, 0x21, 0x10,
    # Print "Printer Test"
    [System.Text.Encoding]::ASCII.GetBytes("Printer Test"),
    # Line feed
    0x0A,
    # Normal size
    0x1B, 0x21, 0x00,
    # Center align
    0x1B, 0x61, 0x01,
    # Print "If you can read this,"
    [System.Text.Encoding]::ASCII.GetBytes("If you can read this,"),
    0x0A,
    # Print "your printer is working!"
    [System.Text.Encoding]::ASCII.GetBytes("your printer is working!"),
    0x0A, 0x0A,
    # Feed 2 lines
    0x1B, 0x64, 0x02,
    # Cut paper
    0x1D, 0x56, 0x00
)

# Flatten the byte array
$allBytes = @()
foreach ($item in $escPosBytes) {
    if ($item -is [byte[]]) {
        $allBytes += $item
    } else {
        $allBytes += [byte]$item
    }
}

# Create temp file
$tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "escpos_test_$(Get-Date -Format 'yyyyMMddHHmmss').raw")
[System.IO.File]::WriteAllBytes($tempFile, $allBytes)

Write-Host "Test file created: $tempFile"
Write-Host "File size: $($allBytes.Length) bytes"
Write-Host ""
Write-Host "Sending to printer port: $PortName"

# Copy to printer port
try {
    cmd /c copy /b "$tempFile" "$PortName"
    Write-Host ""
    Write-Host "SUCCESS: Data sent to printer!"
    Write-Host "Check your printer - it should print a test receipt."
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to send data: $_"
    exit 1
} finally {
    # Clean up temp file
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
        Write-Host "Temp file cleaned up."
    }
}

Write-Host ""
Write-Host "If nothing printed:"
Write-Host "1. Check printer is online and has paper"
Write-Host "2. Verify port name is correct (check Windows Settings > Printers)"
Write-Host "3. Try opening the port in another application to see if it's accessible"
Write-Host "4. Check printer logs for errors"

