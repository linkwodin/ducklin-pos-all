# Setting Up Windows Desktop Project

If you get "no windows desktop project configured" error on Windows, follow these steps:

## Step 1: Verify Windows Desktop is Enabled

```cmd
flutter config --enable-windows-desktop
flutter doctor -v
```

You should see Windows desktop support enabled.

## Step 2: Regenerate Windows Project Files

If the `windows` folder exists but Flutter doesn't recognize it:

```cmd
cd frontend
flutter create --platforms=windows .
```

This will regenerate/update the Windows project files without overwriting your code.

## Step 3: Verify Windows Directory Structure

Make sure these files exist:
```
windows/
  ├── CMakeLists.txt
  ├── runner/
  │   ├── CMakeLists.txt
  │   ├── main.cpp
  │   ├── Runner.rc
  │   └── resources/
  │       └── app_icon.ico
  └── flutter/
      └── CMakeLists.txt
```

## Step 4: Clean and Get Dependencies

```cmd
cd frontend
flutter clean
flutter pub get
```

## Step 5: Try Building

```cmd
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Common Issues

### Issue 1: Windows folder missing
**Solution**: Run `flutter create --platforms=windows .`

### Issue 2: CMake not found
**Solution**: Install CMake from https://cmake.org/download/ or via Visual Studio Installer

### Issue 3: Visual Studio not configured
**Solution**: 
- Install Visual Studio 2022 with "Desktop development with C++" workload
- Or use Visual Studio Build Tools

### Issue 4: Files not copied correctly
**Solution**: 
- Make sure to copy the entire `windows` folder
- Check that all files in `windows/runner/` are present
- Regenerate if needed: `flutter create --platforms=windows .`

## Quick Fix Script (Windows)

Create `fix-windows-project.bat`:

```batch
@echo off
echo Fixing Windows desktop project configuration...
flutter config --enable-windows-desktop
flutter create --platforms=windows .
flutter clean
flutter pub get
echo.
echo Windows project should now be configured!
echo Try: flutter build windows --release
pause
```

Run it from the `frontend` directory.

