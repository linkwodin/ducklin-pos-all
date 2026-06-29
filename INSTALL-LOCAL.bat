@echo off
setlocal EnableDelayedExpansion

REM One-click local install for Windows.
REM Double-click INSTALL-LOCAL.bat or run from repo root in cmd.exe.

cd /d "%~dp0"
if exist "scripts\install-local.bat" (
  call "scripts\install-local.bat" %*
) else (
  echo Could not find scripts\install-local.bat
  exit /b 1
)
