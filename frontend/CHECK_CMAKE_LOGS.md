# Finding CMake Error Logs

Based on your error, the CMake build is failing. Here's how to find the actual error:

## Step 1: Check CMake Error Log

The error mentions logs. Check this specific location:

```cmd
type "C:\frontend\build\windows\x64\CMakeFiles\CMakeError.log"
```

If that file doesn't exist, try:

```cmd
dir "C:\frontend\build\windows\x64\CMakeFiles" /s
```

This will show all files in the CMakeFiles directory.

## Step 2: Check CMake Output Log

Also check the output log:

```cmd
type "C:\frontend\build\windows\x64\CMakeFiles\CMakeOutput.log"
```

## Step 3: Search for All Log Files

Find all log files in the build directory:

```cmd
dir "C:\frontend\build" /s /b | findstr /i "\.log$"
```

## Step 4: Check the Actual CMake Configuration

Try running CMake manually to see the error:

```cmd
cd "C:\frontend\build\windows\x64"
cmake ..\..\..\windows\flutter -G "Visual Studio 17 2022" -A x64
```

This will show the exact CMake configuration error.

## Step 5: Look Earlier in Your Output

The CMake error is usually **before** the MSB8066 error. In your terminal output, scroll **up** from the MSB8066 error to find lines like:

- `CMake Error: ...`
- `CMake Warning: ...`
- `Error: ...`
- `FAILURE: ...`

These will tell you what CMake actually failed on.

## Step 6: Capture Full Build Output

Run the build again and capture everything:

```cmd
cd C:\frontend
flutter clean
flutter build windows --debug --verbose --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1" > build-full.txt 2>&1
type build-full.txt
```

Then search for "Error" or "CMake":
```cmd
type build-full.txt | findstr /i "error cmake"
```

## Step 7: Check for HandshakeException

I see `HandshakeException` in your output. This might indicate:
- Network issues during package download
- Firewall blocking connections
- Proxy issues

Try:
```cmd
flutter pub get
flutter clean
flutter build windows --debug --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Step 8: Check Visual Studio Version

Your error shows Visual Studio 18 (which is VS 2022). Make sure you have the right generator:

```cmd
cmake --version
```

Then try specifying the generator explicitly:
```cmd
cd "C:\frontend\build\windows\x64"
cmake ..\..\..\windows\flutter -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
```

## Step 9: Check Flutter Windows Support

Verify Windows is properly configured:

```cmd
flutter doctor -v
```

Should show:
- ✅ Visual Studio - develop for Windows
- ✅ CMake - required for building native assets

## Step 10: Common CMake Errors and Fixes

### Error: "Could not find CMAKE_C_COMPILER"
**Fix:** Use Developer Command Prompt or install Visual Studio C++ tools

### Error: "Could not find CMAKE_CXX_COMPILER"  
**Fix:** Same as above

### Error: "CMake Error: CMAKE_C_COMPILER not set"
**Fix:** Use Developer Command Prompt for VS 2022

### Error: "No CMAKE_C_COMPILER could be found"
**Fix:** Install "Desktop development with C++" workload

### Error: "CMake Error: The source directory does not exist"
**Fix:** Recreate Windows platform:
```cmd
flutter create --platforms=windows .
```

## Quick Diagnostic Script

Create `check-cmake.bat`:

```batch
@echo off
echo === Checking CMake Logs ===
if exist "build\windows\x64\CMakeFiles\CMakeError.log" (
    echo Found CMakeError.log:
    type "build\windows\x64\CMakeFiles\CMakeError.log"
) else (
    echo CMakeError.log NOT found
)

echo.
echo === Checking CMakeOutput.log ===
if exist "build\windows\x64\CMakeFiles\CMakeOutput.log" (
    echo Found CMakeOutput.log:
    type "build\windows\x64\CMakeFiles\CMakeOutput.log"
) else (
    echo CMakeOutput.log NOT found
)

echo.
echo === Listing CMakeFiles directory ===
if exist "build\windows\x64\CMakeFiles" (
    dir "build\windows\x64\CMakeFiles" /s /b
) else (
    echo CMakeFiles directory does NOT exist
)

pause
```

Run it:
```cmd
cd C:\frontend
check-cmake.bat
```

## Most Important: Get the Actual Error

The MSB8066 error is just saying "CMake failed". The **real error** is in:
1. The CMakeError.log file (if it exists)
2. Earlier in your terminal output (scroll up)
3. The CMakeOutput.log file

Run the diagnostic script above or check the log files directly to see what CMake actually complained about!

