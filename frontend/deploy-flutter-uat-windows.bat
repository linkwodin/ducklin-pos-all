@echo off
REM Deprecated: use repo-root BUILD-AND-DEPLOY-WINDOWS-UAT.bat or scripts\frontend\build-and-deploy-flutter-uat-windows.bat
chcp 65001 >nul
setlocal

set "REPO_ROOT=%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\frontend\build-flutter-uat-windows.ps1" -Deploy -Env uat
set EXIT_CODE=%ERRORLEVEL%
if %EXIT_CODE% NEQ 0 pause
exit /b %EXIT_CODE%
