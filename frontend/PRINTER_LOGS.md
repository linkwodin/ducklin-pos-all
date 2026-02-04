# Printer Debug Logs

The POS System now automatically logs all printer operations to a file for debugging.

## Log File Location

### Windows
```
C:\Users\<YourUsername>\Documents\pos_system\logs\
```

Example:
```
C:\Users\JohnDoe\Documents\pos_system\logs\printer_log_2026-02-03.txt
```

### macOS
```
~/Documents/pos_system/logs/
```

Example:
```
/Users/tommy/Documents/pos_system/logs/printer_log_2026-02-03.txt
```

## Log File Format

Each day gets its own log file named: `printer_log_YYYY-MM-DD.txt`

The log file contains:
- **Print attempts**: Printer type, data size, printer name/address
- **Success messages**: When printing succeeds
- **Error messages**: Detailed error information when printing fails
- **Debug information**: Port detection, method attempts, etc.

## How to View Logs

### Windows

#### Method 1: File Explorer
1. Press `Win + R`
2. Type: `%USERPROFILE%\Documents\pos_system\logs`
3. Press Enter
4. Open the latest `printer_log_YYYY-MM-DD.txt` file with Notepad or any text editor

#### Method 2: Command Prompt
```cmd
cd %USERPROFILE%\Documents\pos_system\logs
dir
type printer_log_2026-02-03.txt
```

#### Method 3: PowerShell
```powershell
cd $env:USERPROFILE\Documents\pos_system\logs
Get-Content printer_log_2026-02-03.txt
```

#### Method 4: View Latest Log
```powershell
cd $env:USERPROFILE\Documents\pos_system\logs
Get-Content (Get-ChildItem printer_log_*.txt | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
```

### macOS

#### Method 1: Finder
1. Press `Cmd + Shift + G` in Finder
2. Type: `~/Documents/pos_system/logs`
3. Press Enter
4. Open the latest `printer_log_YYYY-MM-DD.txt` file

#### Method 2: Terminal
```bash
cd ~/Documents/pos_system/logs
ls -la
cat printer_log_2026-02-03.txt
```

#### Method 3: View Latest Log
```bash
cd ~/Documents/pos_system/logs
ls -t printer_log_*.txt | head -1 | xargs cat
```

#### Method 4: Open in TextEdit
```bash
open ~/Documents/pos_system/logs/printer_log_2026-02-03.txt
```

## Log File Contents Example

```
[2026-02-03T10:30:45.123Z] === Printer Logger Initialized ===
[2026-02-03T10:30:45.124Z] Log file: C:\Users\JohnDoe\Documents\pos_system\logs\printer_log_2026-02-03.txt
[2026-02-03T10:30:45.125Z] Timestamp: 2026-02-03T10:30:45.125Z
[2026-02-03T10:30:45.125Z] 
[2026-02-03T10:30:50.456Z] === Starting Print Job ===
[2026-02-03T10:30:50.457Z] Printer type: usb
[2026-02-03T10:30:50.457Z] Data size: 256 bytes
[2026-02-03T10:30:50.458Z] USB printer: HP LaserJet Pro
[2026-02-03T10:30:50.458Z] Is CUPS printer: false
[2026-02-03T10:30:50.459Z] Platform: Windows
[2026-02-03T10:30:50.460Z] === Windows USB Printer ===
[2026-02-03T10:30:50.461Z] Printer name: HP LaserJet Pro
[2026-02-03T10:30:50.462Z] Data size: 256 bytes
[2026-02-03T10:30:50.500Z] DEBUG: Found printer port via PowerShell: USB001
[2026-02-03T10:30:50.550Z] SUCCESS: Successfully printed via copy command to port: USB001
```

## What to Look For

When debugging printer issues, check the log file for:

1. **Print job start**: Look for "=== Starting Print Job ==="
2. **Printer detection**: Check if printer name/port is detected correctly
3. **Method attempts**: See which printing methods are being tried
4. **Error messages**: Look for "ERROR:" entries with detailed error information
5. **Success messages**: Look for "SUCCESS:" entries to see which method worked

## Notes

- Log files are created automatically when the app starts
- Each day gets a new log file
- Logs are appended to the file, so you can monitor in real-time by keeping the file open
- All printer operations are logged, including test prints
- Error messages include stack traces for debugging

## Troubleshooting

If you see errors in the log:

1. **"Printer not found"**: Check printer name matches exactly in Windows Settings
2. **"Port not found"**: Printer may not be properly installed or connected
3. **"Access denied"**: App may need administrator privileges for some printers
4. **"COM port failed"**: Serial port may be in use by another application
5. **"Copy command failed"**: Printer port may not support raw data transfer

