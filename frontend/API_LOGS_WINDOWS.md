# Finding API Call Logs

The POS System now automatically logs all API calls to a file.

## Log File Location

### Windows
```
C:\Users\<YourUsername>\Documents\pos_system\logs\
```

Example:
```
C:\Users\JohnDoe\Documents\pos_system\logs\api_log_2026-02-03.txt
```

### macOS
```
~/Documents/pos_system/logs/
```

Example:
```
/Users/tommy/Documents/pos_system/logs/api_log_2026-02-03.txt
```

## Log File Format

Each day gets its own log file named: `api_log_YYYY-MM-DD.txt`

The log file contains:
- **Requests**: Method, URI, headers (with masked authorization tokens), and request data
- **Responses**: Status code, URI, and response data (truncated if > 1000 chars)
- **Errors**: Error type, message, status code, and response data

## How to View Logs

### Windows

#### Method 1: File Explorer
1. Press `Win + R`
2. Type: `%USERPROFILE%\Documents\pos_system\logs`
3. Press Enter
4. Open the latest `api_log_YYYY-MM-DD.txt` file with Notepad or any text editor

#### Method 2: Command Prompt
```cmd
cd %USERPROFILE%\Documents\pos_system\logs
dir
type api_log_2026-02-03.txt
```

#### Method 3: PowerShell
```powershell
cd $env:USERPROFILE\Documents\pos_system\logs
Get-Content api_log_2026-02-03.txt
```

### macOS

#### Method 1: Finder
1. Press `Cmd + Shift + G` in Finder
2. Type: `~/Documents/pos_system/logs`
3. Press Enter
4. Open the latest `api_log_YYYY-MM-DD.txt` file

#### Method 2: Terminal
```bash
cd ~/Documents/pos_system/logs
ls -la
cat api_log_2026-02-03.txt
```

#### Method 3: View Latest Log
```bash
cd ~/Documents/pos_system/logs
ls -t api_log_*.txt | head -1 | xargs cat
```

#### Method 4: Open in TextEdit
```bash
open ~/Documents/pos_system/logs/api_log_2026-02-03.txt
```

## Log File Contents Example

```
[2026-02-03T10:30:45.123Z] >>> REQUEST
Method: GET
URI: https://pos-backend-28040503481.europe-west1.run.app/api/v1/device/DFEA26CE-2FCD-4CD6-B62A-09476BDE938B/users
Headers:
  Content-Type: application/json
  Authorization: Bearer ***

[2026-02-03T10:30:45.456Z] <<< RESPONSE
Status: 200
URI: https://pos-backend-28040503481.europe-west1.run.app/api/v1/device/DFEA26CE-2FCD-4CD6-B62A-09476BDE938B/users
Data: [{"id":1,"username":"admin",...}]
```

## Console Output

The logs are also printed to the console (if running from command line):
- When running with `flutter run -d windows` or `flutter run -d macos`, logs appear in the terminal
- When running the built executable, logs may not be visible unless you redirect output

## Redirecting Console Output to File

If you want to capture console output to a file when running the app:

### Windows - Command Prompt:
```cmd
flutter run -d windows --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B > console_output.txt 2>&1
```

### Windows - PowerShell:
```powershell
flutter run -d windows --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B *> console_output.txt
```

### macOS - Terminal:
```bash
flutter run -d macos --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B > console_output.txt 2>&1
```

## Notes

- Log files are created automatically when the app starts
- Each day gets a new log file
- Authorization tokens are masked in logs for security
- Large responses (>1000 chars) are truncated in logs
- Logs are appended to the file, so you can monitor in real-time by keeping the file open

