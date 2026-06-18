# Scripts Directory

This directory contains all deployment and utility scripts for the POS system.

## Structure

```
scripts/
├── deploy.sh                    # Main deployment script
├── setup-gcp.sh                 # Initial GCP setup
├── clone-uat-to-dev.sh          # Clone UAT DB (and optional uploads) to local dev
├── clone-uat-db-to-local.sh     # DB-only clone wrapper (simpler usage)
├── clone-uat-to-prod.sh         # Clone UAT DB + uploads into prod GCP project
├── setup-prod-from-uat.sh       # Create prod project, infra, clone UAT, deploy backend
├── deploy-firebase.sh           # Firebase deployment
├── init-firebase.sh             # Firebase initialization
└── frontend/
    ├── build-flutter-uat-macos.sh     # Flutter macOS UAT build
    ├── build-and-deploy-flutter-uat-windows.bat  # One-click build + GCS upload (Windows)
    ├── build-flutter-uat-windows.bat  # Build only (Windows)
    ├── build-flutter-uat-windows.ps1
    ├── deploy-flutter-uat-macos.sh    # Flutter macOS UAT deployment
    ├── upload-flutter-uat-windows.sh  # Upload Windows zip to GCS (from Mac)
    ├── setup-icon.sh                  # General icon setup
    ├── setup-macos-icon.sh            # macOS icon setup
    ├── setup-windows-icon.sh          # Windows icon setup (Mac + ImageMagick)
    └── clear-macos-icon-cache.sh      # Clear macOS icon cache
```

## Usage

All scripts should be run from the project root directory:

```bash
# Main deployment
./scripts/deploy.sh backend
./scripts/deploy.sh frontend

# GCP setup
./scripts/setup-gcp.sh

# Firebase
./scripts/init-firebase.sh
./scripts/deploy-firebase.sh uat

# Flutter frontend
./scripts/frontend/build-flutter-uat-macos.sh
./scripts/frontend/deploy-flutter-uat-macos.sh
./scripts/frontend/setup-icon.sh

# Flutter Windows (run on a Windows PC — double-click BUILD-AND-DEPLOY-WINDOWS.bat)
# Repo is cloned/moved to C:\dev\ducklin-pos-all for shorter MSVC paths.
BUILD-AND-DEPLOY-WINDOWS.bat

# Clone UAT data to local dev (DB + optional uploads)
./scripts/clone-uat-to-dev.sh
./scripts/clone-uat-to-dev.sh --db-only   # database only
./scripts/clone-uat-db-to-local.sh        # database only (easy command)
./scripts/clone-uat-db-to-local.sh --schema ducklin_pos_local --replace

# Production (new GCP project ducklin-uk-prod) — see PRODUCTION_CLONE.md
./scripts/setup-prod-from-uat.sh
./scripts/clone-uat-to-prod.sh
PROD_PROJECT_ID=ducklin-uk-prod ./scripts/deploy-firebase.sh production
```

## Notes

- Scripts use relative paths from the project root
- Some scripts (like `deploy-flutter-uat-macos.sh`) will automatically change to the appropriate directory
- All scripts include error handling and prerequisite checks

