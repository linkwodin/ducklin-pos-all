@echo off
REM One-click Windows POS: git pull, pick UAT (1) or Production (2), build + deploy.
REM Repo always lives at C:\dev\ducklin-pos-all (short path for MSVC builds).
chcp 65001 >nul
setlocal EnableExtensions

set "GIT_URL=https://github.com/linkwodin/ducklin-pos-all.git"
set "GIT_BRANCH=main"
set "CLONE_DIR=C:\dev\ducklin-pos-all"
set "OLD_DIR=%USERPROFILE%\ducklin-pos-all"
set "REPO_DIR="
set "SYNC_SCRIPT="

if not exist "C:\dev" (
    echo [INFO] Creating C:\dev
    mkdir "C:\dev"
)

REM Migrate previous clone from %%USERPROFILE%% to C:\dev
if not exist "%CLONE_DIR%\.git" (
    if exist "%OLD_DIR%\.git" (
        echo.
        echo [INFO] Moving repo to short path:
        echo        %OLD_DIR%
        echo     -^> %CLONE_DIR%
        echo.
        move "%OLD_DIR%" "%CLONE_DIR%"
        if errorlevel 1 (
            echo [ERROR] Could not move folder. Close programs using the old path and retry.
            pause
            exit /b 1
        )
    )
)

REM --- Step 1: use C:\dev\ducklin-pos-all ---
if exist "%CLONE_DIR%\.git" (
    set "REPO_DIR=%CLONE_DIR%"
)

REM --- Step 2: git pull (first action when repo exists) ---
if defined REPO_DIR (
    cd /d "%REPO_DIR%"
    echo.
    echo [INFO] git pull --ff-only origin %GIT_BRANCH%
    where git >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Git is not installed. Install from https://git-scm.com/download/win
        pause
        exit /b 1
    )
    git pull --ff-only origin %GIT_BRANCH%
    if errorlevel 1 (
        echo [ERROR] git pull failed. Fix conflicts or run: git status
        pause
        exit /b 1
    )
    set "SYNC_SCRIPT=%REPO_DIR%\scripts\frontend\windows-sync-build-deploy.ps1"
)

REM --- Step 3: clone on first run ---
if not defined SYNC_SCRIPT (
    echo.
    echo [INFO] Repository not found. Cloning to:
    echo        %CLONE_DIR%
    echo.
    where git >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Git is not installed. Install from https://git-scm.com/download/win
        pause
        exit /b 1
    )
    if exist "%CLONE_DIR%" (
        echo [ERROR] Folder exists but is not a valid checkout: %CLONE_DIR%
        echo        Remove it or clone manually: git clone %GIT_URL% "%CLONE_DIR%"
        pause
        exit /b 1
    )
    git clone --branch %GIT_BRANCH% --single-branch %GIT_URL% "%CLONE_DIR%"
    if errorlevel 1 (
        echo [ERROR] git clone failed. For private repos, sign in with Git Credential Manager first.
        pause
        exit /b 1
    )
    set "REPO_DIR=%CLONE_DIR%"
    set "SYNC_SCRIPT=%CLONE_DIR%\scripts\frontend\windows-sync-build-deploy.ps1"
)

if not exist "%SYNC_SCRIPT%" (
    echo [ERROR] Script not found: %SYNC_SCRIPT%
    pause
    exit /b 1
)

echo.
echo [INFO] Working folder: %REPO_DIR%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%" -SkipGit -CloneDir "%CLONE_DIR%"
set EXIT_CODE=%ERRORLEVEL%

echo.
if %EXIT_CODE% EQU 0 (
    echo All done.
) else (
    echo Failed. See errors above.
    echo Try: %REPO_DIR%\scripts\frontend\repair-windows-build.bat
)
echo.
pause
exit /b %EXIT_CODE%
