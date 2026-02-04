# Windows Build Troubleshooting - CMake Errors

If you're getting CMake errors when building the Windows Flutter app, follow these steps:

## Common Error
```
target dart_build failed : error : Building native assets failed ...
c:\users\...\CMakeLists.txt exited with code 1.
```

## Solution Steps

### 1. Install Required Build Tools

**Visual Studio 2022** (or 2019) with C++ development tools:
- Download from: https://visualstudio.microsoft.com/downloads/
- During installation, select:
  - ✅ **Desktop development with C++**
  - ✅ **Windows 10/11 SDK** (latest version)
  - ✅ **CMake tools for Windows**

**CMake** (if not included with Visual Studio):
- Download from: https://cmake.org/download/
- Install and add to PATH

### 2. Verify Installation

Run these commands to verify everything is installed:

```cmd
flutter doctor -v
```

You should see:
- ✅ Visual Studio - develop for Windows
- ✅ CMake - required for building native assets

If CMake is missing, you'll see a warning. Install it and restart your terminal.

### 3. Clean and Rebuild

```cmd
cd frontend
flutter clean
flutter pub get
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

### 4. Check for Native Dependencies Issues

The project uses packages that require native compilation:
- `sqflite_common_ffi` - SQLite FFI bindings
- `mobile_scanner` - May have native dependencies

If specific packages are causing issues, try:

```cmd
flutter pub get
flutter pub upgrade
```

### 5. Use Visual Studio Developer Command Prompt

Sometimes the build tools aren't in PATH. Try building from Visual Studio Developer Command Prompt:

1. Open **"Developer Command Prompt for VS 2022"** (or VS 2019)
2. Navigate to your project:
   ```cmd
   cd C:\path\to\pos-system\frontend
   ```
3. Run the build command:
   ```cmd
   flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
   ```

### 6. Check CMake Version

Ensure CMake is version 3.15 or higher:

```cmd
cmake --version
```

If it's not found or too old, update it.

### 7. Alternative: Build Without Native Assets (If Possible)

If the issue persists, you might need to check if all native dependencies are necessary for Windows. Some packages like `mobile_scanner` might not work on Windows desktop.

### 8. Get More Detailed Error Information

Run with verbose output to see the exact CMake error:

```cmd
flutter build windows --release --verbose --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

This will show the exact CMake command and error message.

## Quick Checklist

- [ ] Visual Studio 2022 (or 2019) installed with C++ tools
- [ ] Windows 10/11 SDK installed
- [ ] CMake installed and in PATH
- [ ] Flutter doctor shows Windows support enabled
- [ ] Running from Developer Command Prompt (if regular terminal doesn't work)
- [ ] Project cleaned with `flutter clean`
- [ ] Dependencies updated with `flutter pub get`

## Still Having Issues?

If the error persists, share:
1. The full error message from `flutter build windows --verbose`
2. Output of `flutter doctor -v`
3. CMake version: `cmake --version`
4. Visual Studio version installed

