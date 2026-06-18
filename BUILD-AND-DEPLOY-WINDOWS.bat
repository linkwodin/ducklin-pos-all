@echo off
REM One-click Windows POS: sync from git, pick UAT (1) or Production (2), build + deploy.
REM Double-click from repo root, or from anywhere (clones to %%USERPROFILE%%\ducklin-pos-all on first run).
chcp 65001 >nul
setlocal EnableExtensions

set "GIT_URL=https://github.com/linkwodin/ducklin-pos-all.git"
set "CLONE_DIR=%USERPROFILE%\ducklin-pos-all"
set "SYNC_SCRIPT="

if exist "%~dp0scripts\frontend\windows-sync-build-deploy.ps1" (
    set "SYNC_SCRIPT=%~dp0scripts\frontend\windows-sync-build-deploy.ps1"
)

if not defined SYNC_SCRIPT if exist "%CLONE_DIR%\scripts\frontend\windows-sync-build-deploy.ps1" (
    set "SYNC_SCRIPT=%CLONE_DIR%\scripts\frontend\windows-sync-build-deploy.ps1"
)

if not defined SYNC_SCRIPT (
    echo.
    echo [INFO] Repository not found locally. Cloning to:
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
    git clone --branch main --single-branch %GIT_URL% "%CLONE_DIR%"
    if errorlevel 1 (
        echo [ERROR] git clone failed. For private repos, sign in with Git Credential Manager first.
        pause
        exit /b 1
    )
    set "SYNC_SCRIPT=%CLONE_DIR%\scripts\frontend\windows-sync-build-deploy.ps1"
)

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%"
set EXIT_CODE=%ERRORLEVEL%

echo.
if %EXIT_CODE% EQU 0 (
    echo All done.
) else (
    echo Failed. See errors above.
)
echo.
pause
exit /b %EXIT_CODE%
