# Windows Printing Commands

This document shows all the Windows commands used for printing ESC/POS data to USB printers.

## Overview

The code tries multiple methods in order uFntil one succeeds. Here are all the commands:

## Method 1: List Printers (Verification)

### Command 1: WMIC - List all printers
```cmd
wmic printer get name
```

**Purpose**: Verify the printer exists in Windows

**Example Output**:
```
Name
HP LaserJet Pro
Canon PIXMA
```

---

## Method 2: Get Printer Port

### Command 2a: PowerShell - Get printer port
```powershell
powershell -Command "$printer = Get-Printer -Name \"Printer Name\" -ErrorAction SilentlyContinue; if ($printer) { Write-Output $printer.PortName } else { Write-Error \"Printer not found\" }"
```

**Purpose**: Get the port name for the printer (e.g., USB001, COM3, LPT1)

**Example Output**:
```
USB001
```

### Command 2b: WMIC - Get printer port (fallback)
```cmd
wmic printer where "name=\"Printer Name\"" get portname
```

**Purpose**: Alternative method to get printer port if PowerShell fails

**Example Output**:
```
PortName
USB001
```

---

## Method 3: Print to COM Port (if printer uses COM port)

### Command 3a: Direct File Write (for COM ports)
```
Direct file write to: COM1, COM2, COM3, etc.
```

**Purpose**: Write raw bytes directly to COM port file

**Note**: This is done programmatically, not via command line

### Command 3b: PowerShell Serial Port (for COM ports)
```powershell
powershell -Command "$port = New-Object System.IO.Ports.SerialPort(\"COM3\", 9600, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One); $port.Open(); $bytes = [System.IO.File]::ReadAllBytes(\"C:\\path\\to\\file.raw\"); $port.Write($bytes, 0, $bytes.Length); $port.Close()"
```

**Purpose**: Send raw bytes to COM port via PowerShell SerialPort class

**Parameters**:
- `COM3`: The COM port number
- `9600`: Baud rate
- `[System.IO.Ports.Parity]::None`: No parity
- `8`: Data bits
- `[System.IO.Ports.StopBits]::One`: One stop bit

---

## Method 4: Print to USB/Other Ports

### Command 4a: Copy Command (for USB001, LPT1, etc.)
```cmd
cmd /c copy /b "C:\path\to\file.raw" "USB001"
```

**Purpose**: Copy raw binary file directly to printer port

**Parameters**:
- `/b`: Binary mode (important for raw data)
- `"C:\path\to\file.raw"`: Path to temporary file with ESC/POS data
- `"USB001"`: Printer port name (or LPT1, etc.)

**Example**:
```cmd
cmd /c copy /b "C:\Users\John\AppData\Local\Temp\escpos_1234567890.raw" "USB001"
```

### Command 4b: PowerShell WriteAllBytes (for USB001, LPT1, etc.)
**⚠️ NOTE**: This method may not work reliably - `WriteAllBytes` may create a file instead of writing to the port. Use `copy /b` method instead.

```powershell
# Create temp file first
$bytes = [System.IO.File]::ReadAllBytes("C:\path\to\file.raw")
$tempFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllBytes($tempFile, $bytes)

# Then use copy command to send to port
cmd /c copy /b "$tempFile" "USB001"

# Clean up
Remove-Item $tempFile
```

**Better alternative - Use FileStream directly**:
```powershell
$bytes = [System.IO.File]::ReadAllBytes("C:\path\to\file.raw")
$stream = [System.IO.File]::OpenWrite("USB001")
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
$stream.Close()
```

**Example**:
```powershell
$bytes = [System.IO.File]::ReadAllBytes("C:\Users\John\AppData\Local\Temp\escpos_1234567890.raw")
$stream = [System.IO.File]::OpenWrite("USB001")
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
$stream.Close()
```

### Command 4c: PowerShell Raw Stream (final fallback)
```powershell
powershell -Command "Add-Type -AssemblyName System.Drawing; $printerName = \"Printer Name\"; $filePath = \"C:\\path\\to\\file.raw\"; $bytes = [System.IO.File]::ReadAllBytes($filePath); $printer = Get-Printer -Name $printerName -ErrorAction Stop; $port = $printer.PortName; $stream = [System.IO.File]::OpenWrite($port); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush(); $stream.Close()"
```

**Purpose**: Get printer port and write raw bytes using .NET FileStream

---

## Manual Testing Commands

You can test these commands manually in PowerShell or Command Prompt:

### 1. List all printers:
```powershell
Get-Printer | Select-Object Name, PortName
```

### 2. Get specific printer port:
```powershell
Get-Printer -Name "Your Printer Name" | Select-Object PortName
```

### 3. Test copy command (replace with your port):

**⚠️ IMPORTANT**: Plain text files won't work with ESC/POS printers! They need ESC/POS commands.

**Option A: Use the test script** (recommended):
```powershell
.\test-escpos-print.ps1 -PortName "USB001"
```

**Option B: Manual test with ESC/POS commands**:

**In PowerShell**:
```powershell
# Create ESC/POS test file
$bytes = [byte[]](0x1B, 0x40, 0x1B, 0x61, 0x01, 0x1B, 0x21, 0x10)
$bytes += [System.Text.Encoding]::ASCII.GetBytes("Printer Test")
$bytes += [byte[]](0x0A, 0x1B, 0x21, 0x00, 0x1B, 0x61, 0x01)
$bytes += [System.Text.Encoding]::ASCII.GetBytes("If you can read this,")
$bytes += [byte[]](0x0A)
$bytes += [System.Text.Encoding]::ASCII.GetBytes("your printer is working!")
$bytes += [byte[]](0x0A, 0x0A, 0x1B, 0x64, 0x02, 0x1D, 0x56, 0x00)
[System.IO.File]::WriteAllBytes("test.raw", $bytes)

# Send to printer
cmd /c copy /b test.raw USB001
```

**Note**: 
- In PowerShell, `copy` is an alias for `Copy-Item` which has different syntax. Always use `cmd /c copy` in PowerShell.
- Plain text files (like `echo Test > test.txt`) will NOT work with ESC/POS printers - they need binary ESC/POS commands.

### 4. Test PowerShell write (replace with your port):

**⚠️ IMPORTANT**: `WriteAllBytes` may create a file instead of writing to the port. Use one of these methods:

**Method A: Use FileStream** (recommended):
```powershell
# Create ESC/POS test bytes
$bytes = [byte[]](0x1B, 0x40)  # Initialize
$bytes += [System.Text.Encoding]::ASCII.GetBytes("Printer Test")
$bytes += [byte[]](0x0A, 0x0A)  # Line feeds
$bytes += [byte[]](0x1D, 0x56, 0x00)  # Cut

# Write to port using FileStream
$stream = [System.IO.File]::OpenWrite("USB001")
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
$stream.Close()
```

**Method B: Use copy command** (most reliable):
```powershell
# Create ESC/POS test file
$bytes = [byte[]](0x1B, 0x40)
$bytes += [System.Text.Encoding]::ASCII.GetBytes("Printer Test")
$bytes += [byte[]](0x0A, 0x0A, 0x1D, 0x56, 0x00)
[System.IO.File]::WriteAllBytes("test.raw", $bytes)

# Send to printer
cmd /c copy /b test.raw USB001
```

---

## Common Printer Ports

- **USB001, USB002, etc.**: USB printers
- **COM1, COM2, COM3, etc.**: Serial/COM port printers
- **LPT1, LPT2, etc.**: Parallel port printers (rare)
- **FILE**: Print to file

---

## Troubleshooting

### If copy command fails:
- Make sure printer is online
- Check port name is correct (case-sensitive)
- Try running Command Prompt as Administrator

### If PowerShell commands fail:
- Check PowerShell execution policy: `Get-ExecutionPolicy`
- If restricted, run: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Make sure printer name matches exactly (including spaces and special characters)

### To find your printer port:
1. Open Windows Settings > Printers & scanners
2. Click on your printer
3. Click "Printer properties"
4. Go to "Ports" tab
5. Look for the checked port (e.g., USB001)

---

## Example: Complete Print Flow

1. **List printers**:
   ```cmd
   wmic printer get name
   ```

2. **Get printer port**:
   ```powershell
   powershell -Command "Get-Printer -Name 'HP LaserJet Pro' | Select-Object PortName"
   ```
   Output: `USB001`

3. **Create temp file with ESC/POS data**:
   ```
   File: C:\Users\John\AppData\Local\Temp\escpos_1234567890.raw
   ```

4. **Print using copy command**:
   ```cmd
   cmd /c copy /b "C:\Users\John\AppData\Local\Temp\escpos_1234567890.raw" "USB001"
   ```

5. **Verify success** (exit code 0 = success)

---

## Notes

- All commands are executed with `runInShell: true` for proper environment
- Temporary files are automatically deleted after printing
- The code tries methods in order until one succeeds
- Logs are written to: `%USERPROFILE%\Documents\pos_system\logs\printer_log_YYYY-MM-DD.txt`

