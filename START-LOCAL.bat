@echo off
setlocal EnableDelayedExpansion

REM Start local POS stack on Windows.
cd /d "%~dp0"
if exist "scripts\start-local.bat" (
  call "scripts\start-local.bat" %*
) else (
  echo Could not find scripts\start-local.bat
  exit /b 1
)
