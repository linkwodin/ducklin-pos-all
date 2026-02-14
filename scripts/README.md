# Scripts Directory

This directory contains all deployment and utility scripts for the POS system.

## Structure

```
scripts/
├── deploy.sh                    # Main deployment script
├── setup-gcp.sh                 # Initial GCP setup
├── clone-uat-to-dev.sh          # Clone UAT DB (and optional uploads) to local dev
├── deploy-firebase.sh           # Firebase deployment
├── init-firebase.sh             # Firebase initialization
└── frontend/
    ├── deploy-flutter-uat-macos.sh  # Flutter macOS UAT deployment
    ├── setup-icon.sh             # General icon setup
    ├── setup-macos-icon.sh       # macOS icon setup
    ├── setup-windows-icon.sh     # Windows icon setup
    └── clear-macos-icon-cache.sh # Clear macOS icon cache
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
./scripts/frontend/deploy-flutter-uat-macos.sh
./scripts/frontend/setup-icon.sh

# Clone UAT data to local dev (DB + optional uploads)
./scripts/clone-uat-to-dev.sh
./scripts/clone-uat-to-dev.sh --db-only   # database only
```

## Notes

- Scripts use relative paths from the project root
- Some scripts (like `deploy-flutter-uat-macos.sh`) will automatically change to the appropriate directory
- All scripts include error handling and prerequisite checks

