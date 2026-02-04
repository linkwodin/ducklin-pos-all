# Adding CMake to System PATH

If `cmake --version` works in Visual Studio's Developer Command Prompt but not in regular CMD, CMake needs to be added to your system PATH.

## Method 1: GUI (Easiest)

1. **Find CMake Installation Path**
   - In VS Developer Command Prompt, run:
     ```cmd
     where cmake
     ```
   - This will show the path, typically:
     - `C:\Program Files\CMake\bin\cmake.exe`
     - Or: `C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`

2. **Add to System PATH**
   - Press `Win + R`, type `sysdm.cpl`, press Enter
   - Go to **"Advanced"** tab
   - Click **"Environment Variables"**
   - Under **"System variables"** (or "User variables"), find **"Path"**
   - Click **"Edit"**
   - Click **"New"**
   - Add the CMake **bin folder** path (without `cmake.exe`):
     - Example: `C:\Program Files\CMake\bin`
     - Or: `C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`
   - Click **"OK"** on all dialogs

3. **Restart Command Prompt**
   - Close all open CMD/PowerShell windows
   - Open a new Command Prompt
   - Test: `cmake --version`

## Method 2: Command Line (PowerShell as Administrator)

1. **Open PowerShell as Administrator**
   - Right-click Start menu → "Windows PowerShell (Admin)" or "Terminal (Admin)"

2. **Find CMake Path**
   ```powershell
   Get-Command cmake | Select-Object -ExpandProperty Source
   ```
   This shows where cmake.exe is located.

3. **Get the Directory (without cmake.exe)**
   ```powershell
   $cmakePath = (Get-Command cmake).Source
   $cmakeDir = Split-Path -Parent $cmakePath
   Write-Host "CMake directory: $cmakeDir"
   ```

4. **Add to User PATH**
   ```powershell
   $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
   $cmakeDir = (Split-Path -Parent (Get-Command cmake).Source)
   [Environment]::SetEnvironmentVariable("Path", "$currentPath;$cmakeDir", "User")
   ```

5. **Or Add to System PATH** (requires admin)
   ```powershell
   $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
   $cmakeDir = (Split-Path -Parent (Get-Command cmake).Source)
   [Environment]::SetEnvironmentVariable("Path", "$currentPath;$cmakeDir", "Machine")
   ```

6. **Restart Terminal**
   - Close and reopen your command prompt
   - Test: `cmake --version`

## Method 3: Quick Fix - Use Developer Command Prompt

If you just want to build Flutter apps quickly without modifying PATH:

1. **Always use Developer Command Prompt**
   - Search for: "Developer Command Prompt for VS 2022"
   - Run your Flutter commands from here
   - This automatically has all build tools in PATH

2. **Or set up a shortcut**
   - Create a batch file that opens Developer Command Prompt and navigates to your project:
   ```batch
   @echo off
   call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
   cd /d C:\path\to\pos-system\frontend
   cmd /k
   ```

## Verify It Works

After adding to PATH:

1. **Close all command prompts**
2. **Open a new Command Prompt**
3. **Test:**
   ```cmd
   cmake --version
   ```
   Should show version info

4. **Test Flutter:**
   ```cmd
   flutter doctor -v
   ```
   Should show CMake as available

## Common CMake Locations

CMake might be installed in one of these locations:
- `C:\Program Files\CMake\bin`
- `C:\Program Files (x86)\CMake\bin`
- `C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`
- `C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`
- `C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`

## Troubleshooting

**If PATH was added but still not working:**
1. Make sure you added the **bin folder**, not the cmake.exe file
2. Restart your computer (sometimes needed for system PATH changes)
3. Check for typos in the path
4. Verify the path exists: `dir "C:\Program Files\CMake\bin"`

**If you can't find CMake:**
- It might be installed with Visual Studio
- Check: `C:\Program Files\Microsoft Visual Studio\2022\[Edition]\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`

