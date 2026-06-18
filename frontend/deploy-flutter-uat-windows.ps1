# Deprecated: use scripts\frontend\build-flutter-uat-windows.ps1 -Deploy
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $repoRoot 'scripts\frontend\build-flutter-uat-windows.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Deploy -Env uat
exit $LASTEXITCODE
