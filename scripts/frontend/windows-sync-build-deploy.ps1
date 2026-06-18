# Sync repo from git, pick UAT/production, then build and deploy Windows POS.
#
# Double-click: BUILD-AND-DEPLOY-WINDOWS.bat (repo root)
# Or: powershell -ExecutionPolicy Bypass -File scripts\frontend\windows-sync-build-deploy.ps1

param(
    [ValidateSet('', 'uat', 'production')]
    [string]$Env = '',

    [switch]$SkipGit,

    [switch]$BuildOnly,

    [string]$GitUrl = 'https://github.com/linkwodin/ducklin-pos-all.git',

    [string]$GitBranch = 'main',

    [string]$CloneDir = ''
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultCloneDir = Join-Path $env:USERPROFILE 'ducklin-pos-all'

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Find-RepoRoot([string]$StartDir) {
    $dir = (Resolve-Path $StartDir).Path
    while ($true) {
        if (Test-Path (Join-Path $dir 'frontend\pubspec.yaml')) {
            return $dir
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) {
            return $null
        }
        $dir = $parent
    }
}

function Sync-GitRepo {
    param(
        [string]$RepoRoot,
        [string]$RemoteUrl,
        [string]$Branch
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not installed. Install from https://git-scm.com/download/win'
    }

    Set-Location $RepoRoot

    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        throw "Not a git repository: $RepoRoot"
    }

    Write-Info "Fetching latest code ($Branch)..."
    git fetch origin $Branch 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }

    $branchExists = git rev-parse --verify $Branch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Checking out origin/$Branch..."
        git checkout -B $Branch "origin/$Branch" 2>&1 | ForEach-Object { Write-Host $_ }
    } else {
        git checkout $Branch 2>&1 | ForEach-Object { Write-Host $_ }
    }
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Branch failed" }

    git pull --ff-only origin $Branch 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw 'git pull failed (resolve conflicts manually or delete folder and re-clone)' }

    $commit = (git rev-parse --short HEAD).Trim()
    Write-Info "Repo up to date at $commit"
}

function Clone-GitRepo {
    param(
        [string]$TargetDir,
        [string]$RemoteUrl,
        [string]$Branch
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not installed. Install from https://git-scm.com/download/win'
    }

    if (Test-Path $TargetDir) {
        throw "Clone path already exists but is not a repo: $TargetDir`nRemove it or pick another folder."
    }

    $parent = Split-Path $TargetDir -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Info "Cloning $RemoteUrl ..."
    Write-Info "Into: $TargetDir"
    git clone --branch $Branch --single-branch $RemoteUrl $TargetDir 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed. If the repo is private, run: git config --global credential.helper manager`nthen clone once manually to sign in."
    }
}

function Read-EnvironmentChoice {
    while ($true) {
        Write-Host ''
        Write-Host 'Select environment:' -ForegroundColor Cyan
        Write-Host '  1 = UAT        (ducklin-uk-uat)'
        Write-Host '  2 = Production (ducklin-uk-prod)'
        Write-Host ''
        $choice = Read-Host 'Enter 1 or 2'
        switch ($choice.Trim()) {
            '1' { return @{ Env = 'uat'; ProjectId = 'ducklin-uk-uat'; Label = 'UAT' } }
            '2' { return @{ Env = 'production'; ProjectId = 'ducklin-uk-prod'; Label = 'Production' } }
            default { Write-Warn 'Invalid choice. Please enter 1 or 2.' }
        }
    }
}

Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' POS Windows — sync, build, deploy' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''

$launcherDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$repoRoot = Find-RepoRoot -StartDir (Join-Path $launcherDir '..\..')
if (-not $repoRoot) {
    $repoRoot = Find-RepoRoot -StartDir $launcherDir
}

if (-not $repoRoot) {
    $targetDir = if ($CloneDir) { $CloneDir } else { $DefaultCloneDir }
    if (Test-Path (Join-Path $targetDir 'frontend\pubspec.yaml')) {
        $repoRoot = (Resolve-Path $targetDir).Path
    } elseif (Test-Path (Join-Path $targetDir '.git')) {
        $repoRoot = (Resolve-Path $targetDir).Path
    } else {
        Clone-GitRepo -TargetDir $targetDir -RemoteUrl $GitUrl -Branch $GitBranch
        $repoRoot = (Resolve-Path $targetDir).Path
    }
}

$repoRoot = (Resolve-Path $repoRoot).Path
Write-Info "Using repo: $repoRoot"

if (-not $SkipGit) {
    Sync-GitRepo -RepoRoot $repoRoot -RemoteUrl $GitUrl -Branch $GitBranch
}

$selection = if ($Env) {
    if ($Env -eq 'production') {
        @{ Env = 'production'; ProjectId = 'ducklin-uk-prod'; Label = 'Production' }
    } else {
        @{ Env = 'uat'; ProjectId = 'ducklin-uk-uat'; Label = 'UAT' }
    }
} else {
    Read-EnvironmentChoice
}

Write-Host ''
Write-Info "Selected: $($selection.Label)"
Write-Info "GCP project: $($selection.ProjectId)"

if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    $currentProject = (gcloud config get-value project 2>$null).Trim()
    if ($currentProject -ne $selection.ProjectId) {
        Write-Info "Setting gcloud project to $($selection.ProjectId)..."
        gcloud config set project $selection.ProjectId 2>&1 | ForEach-Object { Write-Host $_ }
    }
} elseif (-not $BuildOnly) {
    throw 'gcloud CLI is required for deploy. Install Google Cloud SDK or use -BuildOnly.'
}

$buildScript = Join-Path $repoRoot 'scripts\frontend\build-flutter-uat-windows.ps1'
if (-not (Test-Path $buildScript)) {
    throw "Build script not found: $buildScript"
}

$buildArgs = @{
    Env       = $selection.Env
    ProjectId = $selection.ProjectId
}
if (-not $BuildOnly) {
    $buildArgs['Deploy'] = $true
}

Write-Host ''
Write-Info 'Starting build...'
& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript @buildArgs
exit $LASTEXITCODE
