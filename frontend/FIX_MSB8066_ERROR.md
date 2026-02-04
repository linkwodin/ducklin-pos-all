# Fixing MSB8066 CMake Build Error

The error shows:
```
error MSB8066: Custom build for '...flutter_assemble.rule...CMakeLists.txt' exited with code 1.
```

This means CMake failed during the Flutter native asset compilation. Here's how to fix it:

## Step 1: Check the Actual CMake Error

The most important step is to see what CMake actually failed on. Check these log files:

```cmd
type "C:\Users\DELL\Downloads\frontend\build\windows\x64\CMakeFiles\CMakeError.log"
type "C:\Users\DELL\Downloads\frontend\build\windows\x64\CMakeFiles\CMakeOutput.log"
```

These will show the actual error that caused CMake to fail.

## Step 2: Clean Build Directory

```cmd
cd C:\Users\DELL\Downloads\frontend
flutter clean
rmdir /s /q build\windows
flutter pub get
```

## Step 3: Try Building with Verbose Output

```cmd
flutter build windows --release --verbose --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

This will show more details about what's failing.

## Step 4: Check for Path Length Issues

Your project is in `C:\Users\DELL\Downloads\frontend\` which is quite deep. Windows has a 260 character path limit that can cause issues.

Try moving the project to a shorter path:
```cmd
# Move to shorter path
xcopy "C:\Users\DELL\Downloads\frontend" "C:\dev\pos-frontend" /E /I
cd C:\dev\pos-frontend
flutter clean
flutter pub get
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Step 5: Check CMakeLists.txt

The error mentions `CMakeLists.txt`. Check if it exists and is valid:

```cmd
type "C:\Users\DELL\Downloads\frontend\windows\flutter\CMakeLists.txt"
```

If it's missing or corrupted, recreate Windows platform:
```cmd
cd C:\Users\DELL\Downloads\frontend
flutter create --platforms=windows .
```

## Step 6: Check Visual Studio Build Tools

Make sure you're using the Developer Command Prompt or that all tools are in PATH:

```cmd
where cl
where link
where cmake
```

All should return paths. If not, use Developer Command Prompt for VS 2022.

## Step 7: Try Debug Build First

Sometimes release builds have stricter requirements:

```cmd
flutter build windows --debug --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Step 8: Check for Package Issues

The output shows 21 packages have newer versions. Some might be incompatible. Try:

```cmd
flutter pub upgrade
flutter pub get
flutter clean
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Step 9: Check Windows SDK

Make sure Windows SDK is installed:

```cmd
flutter doctor -v
```

Should show Windows SDK version.

## Step 10: Manual CMake Build (Advanced)

If all else fails, try building CMake manually to see the error:

```cmd
cd "C:\Users\DELL\Downloads\frontend\build\windows\x64"
cmake ..\..\..\windows\flutter -G "Visual Studio 17 2022" -A x64
```

This will show the exact CMake configuration error.

## Most Common Fixes

1. **Path too long** - Move project to shorter path (e.g., `C:\dev\frontend`)
2. **Missing build tools** - Use Developer Command Prompt
3. **Corrupted build cache** - Clean and rebuild
4. **CMake configuration error** - Check CMakeError.log

## Quick Diagnostic Commands

Run these to gather information:

```cmd
# Check Flutter setup
flutter doctor -v

# Check CMake
cmake --version

# Check Visual Studio
where cl
where link

# Check build directory
dir "C:\Users\DELL\Downloads\frontend\build\windows\x64\CMakeFiles"
```

Share the output of `CMakeError.log` for the most specific fix!

