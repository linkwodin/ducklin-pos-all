@echo off
chcp 65001 >nul
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0repair-windows-build.ps1"
echo.
pause
exit /b %ERRORLEVEL%
