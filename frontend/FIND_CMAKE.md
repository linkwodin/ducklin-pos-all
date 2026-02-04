# Finding CMake Installation Location

If `where cmake` returns nothing but `cmake --version` works, CMake might be loaded via a batch file. Here's how to find it:

## Method 1: Check What cmake Actually Is

In VS Developer Command Prompt, run:

```cmd
where /r C:\ cmake.exe
```

This searches the entire C: drive (may take a while). To search faster, try specific locations:

```cmd
where /r "C:\Program Files" cmake.exe
where /r "C:\Program Files (x86)" cmake.exe
```

## Method 2: Check Environment Variables

In VS Developer Command Prompt, check if CMake path is set:

```cmd
echo %CMAKE%
echo %CMAKE_PATH%
```

Also check PATH:
```cmd
echo %PATH% | findstr /i cmake
```

## Method 3: Check Visual Studio CMake Location

CMake might be bundled with Visual Studio. Check these locations:

```cmd
dir "C:\Program Files\Microsoft Visual Studio\2022\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" /s
```

Or check for Community edition specifically:
```cmd
dir "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
```

## Method 4: Use PowerShell to Find It

Open PowerShell and run:

```powershell
Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "cmake.exe" -ErrorAction SilentlyContinue | Select-Object FullName
```

Or search in Program Files (x86):
```powershell
Get-ChildItem -Path "C:\Program Files (x86)" -Recurse -Filter "cmake.exe" -ErrorAction SilentlyContinue | Select-Object FullName
```

## Method 5: Check if It's a Batch File Wrapper

In VS Developer Command Prompt:

```cmd
type cmake
```

Or:
```cmd
which cmake
```

This might show if it's actually a batch file.

## Method 6: Check Visual Studio Installer

1. Open Visual Studio Installer
2. Find your VS installation
3. Click "Modify"
4. Go to "Individual components" tab
5. Search for "CMake"
6. It will show the installation path

## Method 7: Check Registry (Advanced)

CMake might be registered in Windows Registry:

```cmd
reg query "HKLM\SOFTWARE\Kitware\CMake" /s
```

Or:
```cmd
reg query "HKLM\SOFTWARE\WOW6432Node\Kitware\CMake" /s
```

## Quick Fix: Install CMake Separately

If you can't find it, the easiest solution is to install CMake separately:

1. Download CMake: https://cmake.org/download/
2. Download the Windows x64 Installer
3. During installation, check ✅ **"Add CMake to system PATH"**
4. Install
5. Restart command prompt
6. Test: `cmake --version`

## Alternative: Use Flutter's Built-in Detection

Flutter might be able to find CMake even if it's not in PATH. Try:

```cmd
flutter doctor -v
```

This will show if Flutter can detect CMake and where it found it.

## If CMake is Only Available in VS Developer Prompt

If CMake only works in VS Developer Command Prompt, you have two options:

### Option 1: Always Use Developer Command Prompt
- Search for "Developer Command Prompt for VS 2022"
- Use this for all Flutter builds
- It automatically sets up the environment

### Option 2: Create a Batch File to Set Up Environment
Create a file `build-windows.bat` in your frontend folder:

```batch
@echo off
REM Set up Visual Studio environment
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
REM Now run your Flutter build
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

Adjust the path to match your Visual Studio installation (Community/Professional/Enterprise).

