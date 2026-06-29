@echo off
setlocal EnableDelayedExpansion

REM Ensure Docker CLI exists, install Docker Desktop if missing, wait until engine runs.
REM Usage: call scripts\ensure-docker.bat
REM Exit code 0 = Docker ready, 1 = failed

call :refresh_docker_path
where docker >nul 2>&1
if not errorlevel 1 goto engine_check

echo [INFO] Docker is not installed.
call :install_docker_desktop
if errorlevel 1 exit /b 1
call :refresh_docker_path
where docker >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Docker was installed but the docker command is not on PATH yet.
  echo        Close this window, open a new Command Prompt, and run the script again.
  exit /b 1
)

:engine_check
docker info >nul 2>&1
if not errorlevel 1 (
  echo [INFO] Docker is installed and running.
  exit /b 0
)

echo [INFO] Docker is installed but not running. Starting Docker Desktop...
call :start_docker_desktop
call :wait_for_docker_daemon
exit /b %errorlevel%

:refresh_docker_path
set "PATH=%PATH%;C:\Program Files\Docker\Docker\resources\bin;C:\Program Files\Docker\Docker\resources"
exit /b 0

:install_docker_desktop
where winget >nul 2>&1
if errorlevel 1 goto install_manual

echo [INFO] Installing Docker Desktop via winget ^(this may take several minutes^)...
echo [INFO] You may be prompted for administrator approval.
winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements --disable-interactivity
if not errorlevel 1 exit /b 0

echo [WARN] winget install failed or was cancelled. Retrying as administrator...
powershell -NoProfile -Command "Start-Process winget -ArgumentList 'install','-e','--id','Docker.DockerDesktop','--accept-package-agreements','--accept-source-agreements','--disable-interactivity' -Verb RunAs -Wait"
if not errorlevel 1 (
  echo [INFO] Docker Desktop installed.
  exit /b 0
)

where choco >nul 2>&1
if errorlevel 1 goto install_manual
echo [INFO] Trying Chocolatey...
choco install docker-desktop -y
if not errorlevel 1 exit /b 0

:install_manual
echo [ERROR] Could not install Docker Desktop automatically.
echo.
echo   Option 1: Install manually, then re-run this script
echo             https://www.docker.com/products/docker-desktop/
echo.
echo   Option 2: Use your own MySQL and run INSTALL-LOCAL.bat --skip-docker
exit /b 1

:start_docker_desktop
if exist "C:\Program Files\Docker\Docker\Docker Desktop.exe" (
  start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  exit /b 0
)
if exist "%LOCALAPPDATA%\Docker\Docker Desktop.exe" (
  start "" "%LOCALAPPDATA%\Docker\Docker Desktop.exe"
  exit /b 0
)
echo [WARN] Could not find Docker Desktop.exe — start it from the Start menu.
exit /b 0

:wait_for_docker_daemon
echo [INFO] Waiting for Docker engine ^(first start can take 2-5 minutes^)...
set /a DOCKER_WAIT=0
:daemon_loop
set /a DOCKER_WAIT+=1
if !DOCKER_WAIT! GTR 120 (
  echo [ERROR] Docker did not become ready in time.
  echo        Open Docker Desktop from the Start menu, wait until it shows "Running",
  echo        then run the script again.
  exit /b 1
)
docker info >nul 2>&1
if not errorlevel 1 (
  echo [INFO] Docker engine is ready.
  exit /b 0
)
set /a MOD=!DOCKER_WAIT! %% 12
if !MOD!==0 echo [INFO] Still waiting for Docker... ^(!DOCKER_WAIT! x 5s^)
timeout /t 5 /nobreak >nul
goto daemon_loop
