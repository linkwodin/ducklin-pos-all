@echo off
setlocal EnableDelayedExpansion

REM Start local POS stack: MySQL + backend + management frontend dev server.

set "REPO_ROOT=%~dp0.."
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "COMPOSE_FILE=%REPO_ROOT%\docker-compose.local.yml"
set "BIN_DIR=%REPO_ROOT%\bin"
set "BACKEND_BIN=%BIN_DIR%\pos-backend.exe"

cd /d "%REPO_ROOT%"

if not exist "%REPO_ROOT%\backend\.env" (
  echo backend\.env not found. Run INSTALL-LOCAL.bat first.
  exit /b 1
)

echo ==^> Checking Docker
call "%REPO_ROOT%\scripts\ensure-docker.bat"
if errorlevel 1 exit /b 1

echo ==^> Starting MySQL
docker compose version >nul 2>&1
if not errorlevel 1 (
  docker compose -f "%COMPOSE_FILE%" up -d
) else (
  docker-compose -f "%COMPOSE_FILE%" up -d
)

echo ==^> Starting backend API on :8868
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
if not exist "%BACKEND_BIN%" (
  pushd "%REPO_ROOT%\backend"
  go build -o "%BACKEND_BIN%" .
  popd
)

start "POS Backend" cmd /k "cd /d %REPO_ROOT%\backend && %BACKEND_BIN%"

timeout /t 2 /nobreak >nul

echo ==^> Starting management frontend on :3000
echo.
echo   Management UI:  http://localhost:3000
echo   Backend API:    http://localhost:8868/api/v1
echo   Login:          admin / admin123
echo.

start "POS Management UI" cmd /k "cd /d %REPO_ROOT%\management-frontend && npm run dev"

echo [INFO] Backend and frontend started in separate windows.
echo Close those windows to stop the services.
exit /b 0
