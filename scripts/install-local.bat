@echo off
setlocal EnableDelayedExpansion

REM One-click local install for Windows (MySQL via Docker + backend + management UI).
REM Usage: INSTALL-LOCAL.bat [--start] [--with-flutter] [--skip-docker]

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "COMPOSE_FILE=%REPO_ROOT%\docker-compose.local.yml"
set "ENV_FILE=%REPO_ROOT%\backend\.env"
set "ENV_EXAMPLE=%REPO_ROOT%\backend\.env.local.example"
set "BIN_DIR=%REPO_ROOT%\bin"
set "START_AFTER=0"
set "WITH_FLUTTER=0"
set "SKIP_DOCKER=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--start" set "START_AFTER=1"
if /i "%~1"=="--with-flutter" set "WITH_FLUTTER=1"
if /i "%~1"=="--skip-docker" set "SKIP_DOCKER=1"
shift
goto parse_args
:args_done

echo.
echo ========================================
echo   POS System - Local One-Click Install
echo ========================================
echo.

call :need_cmd docker || exit /b 1
call :need_cmd go || exit /b 1
call :need_cmd node || exit /b 1
call :need_cmd npm || exit /b 1

if "%SKIP_DOCKER%"=="0" (
  echo ==^> Starting MySQL ^(Docker^)
  docker info >nul 2>&1
  if errorlevel 1 (
    echo [ERROR] Docker is not running. Start Docker Desktop and try again.
    exit /b 1
  )
  call :compose_up
  if errorlevel 1 exit /b 1
  call :wait_for_mysql
  if errorlevel 1 exit /b 1
) else (
  echo [WARN] Skipping Docker MySQL ^(--skip-docker^)
)

echo ==^> Configuring backend environment
if not exist "%REPO_ROOT%\backend\uploads\assets\fonts" mkdir "%REPO_ROOT%\backend\uploads\assets\fonts"
if not exist "%REPO_ROOT%\backend\uploads\assets\images" mkdir "%REPO_ROOT%\backend\uploads\assets\images"
if not exist "%ENV_FILE%" (
  if not exist "%ENV_EXAMPLE%" (
    echo [ERROR] Missing backend\.env.local.example
    exit /b 1
  )
  copy /Y "%ENV_EXAMPLE%" "%ENV_FILE%" >nul
  powershell -NoProfile -Command "$s = -join ((48..57 + 65..90 + 97..122 | Get-Random -Count 48 | ForEach-Object {[char]$_})); (Get-Content '%ENV_FILE%') -replace '^JWT_SECRET=.*', ('JWT_SECRET=' + $s) | Set-Content '%ENV_FILE%'"
  echo [INFO] Created backend\.env
) else (
  echo [INFO] Using existing backend\.env
)

if not exist "%REPO_ROOT%\backend\pdf-assets\fonts\Arial.ttf" (
  if exist "%REPO_ROOT%\scripts\download-arial-font.sh" (
    echo [INFO] Downloading PDF fonts via Git Bash...
    where bash >nul 2>&1
    if not errorlevel 1 (
      bash "%REPO_ROOT%\scripts\download-arial-font.sh"
    ) else (
      echo [WARN] bash not found - skip PDF font download
    )
  )
)

echo ==^> Installing backend dependencies
pushd "%REPO_ROOT%\backend"
go mod download
if errorlevel 1 (
  popd
  exit /b 1
)
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
go build -o "%BIN_DIR%\pos-backend.exe" .
if errorlevel 1 (
  popd
  exit /b 1
)
popd

echo ==^> Installing management frontend dependencies
pushd "%REPO_ROOT%\management-frontend"
call npm install
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if "%WITH_FLUTTER%"=="1" (
  echo ==^> Installing POS ^(Flutter^) dependencies
  where flutter >nul 2>&1
  if errorlevel 1 (
    echo [WARN] Flutter not found - skipped
  ) else (
    pushd "%REPO_ROOT%\frontend"
    call flutter pub get
    popd
  )
)

echo ==^> Creating database schema and default admin user
pushd "%REPO_ROOT%\backend"
go run ./cmd/seed-local
if errorlevel 1 (
  popd
  exit /b 1
)
popd

echo.
echo ========================================
echo [INFO] Installation complete!
echo ========================================
echo.
echo   MySQL:            127.0.0.1:3306 ^(user pos_user / pos_local_pass^)
echo   Backend API:      http://localhost:8868/api/v1
echo   Management UI:    http://localhost:3000
echo   Default login:    admin / admin123
echo.
echo   Start everything:  START-LOCAL.bat
echo   Stop MySQL:        docker compose -f docker-compose.local.yml down
echo.

if "%START_AFTER%"=="1" (
  call "%REPO_ROOT%\scripts\start-local.bat"
)
exit /b 0

:need_cmd
where %~1 >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Missing required command: %~1
  exit /b 1
)
exit /b 0

:compose_up
docker compose version >nul 2>&1
if not errorlevel 1 (
  docker compose -f "%COMPOSE_FILE%" up -d
  exit /b 0
)
docker-compose version >nul 2>&1
if not errorlevel 1 (
  docker-compose -f "%COMPOSE_FILE%" up -d
  exit /b 0
)
echo [ERROR] Docker Compose not found
exit /b 1

:wait_for_mysql
echo [INFO] Waiting for MySQL...
set /a COUNT=0
:mysql_wait_loop
set /a COUNT+=1
if %COUNT% GTR 60 (
  echo [ERROR] MySQL did not become ready in time
  exit /b 1
)
docker compose -f "%COMPOSE_FILE%" exec -T mysql mysqladmin ping -h 127.0.0.1 -uroot -ppos_local_root --silent >nul 2>&1
if not errorlevel 1 goto mysql_ready
docker-compose -f "%COMPOSE_FILE%" exec -T mysql mysqladmin ping -h 127.0.0.1 -uroot -ppos_local_root --silent >nul 2>&1
if not errorlevel 1 goto mysql_ready
timeout /t 2 /nobreak >nul
goto mysql_wait_loop
:mysql_ready
echo [INFO] MySQL is ready.
exit /b 0
