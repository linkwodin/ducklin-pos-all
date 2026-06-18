@echo off
REM Build only (no GCS upload). Optional: build-and-deploy-flutter-uat-windows.bat production
chcp 65001 >nul
setlocal
set ENV_ARG=uat
if /I "%~1"=="production" set ENV_ARG=production

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-flutter-uat-windows.ps1" -Env %ENV_ARG%
exit /b %ERRORLEVEL%
