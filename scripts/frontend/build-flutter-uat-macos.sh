#!/bin/bash
#
# Build Flutter POS for macOS (UAT) with UAT-branded icon and app name.
#
# Usage:
#   ./scripts/frontend/build-flutter-uat-macos.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

UAT_BACKEND_URL="${UAT_BACKEND_URL:-https://pos-backend-28040503481.europe-west1.run.app/api/v1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/../../frontend" && pwd)"
APP_INFO="$FRONTEND_DIR/macos/Runner/Configs/AppInfo.xcconfig"
APP_INFO_BAK=""

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

restore_app_info() {
  if [ -n "$APP_INFO_BAK" ] && [ -f "$APP_INFO_BAK" ]; then
    mv "$APP_INFO_BAK" "$APP_INFO"
  fi
}

restore_prod_icon() {
  if [ -f "$SCRIPT_DIR/setup-macos-icon.sh" ]; then
    (cd "$FRONTEND_DIR" && "$SCRIPT_DIR/setup-macos-icon.sh" assets/images/app_icon.png) >/dev/null 2>&1 || true
  fi
}

trap 'restore_app_info; restore_prod_icon' EXIT

if ! command -v flutter &>/dev/null; then
  error "Flutter is not installed."
  exit 1
fi

cd "$FRONTEND_DIR"

info "Generating UAT app icon..."
dart run tool/generate_uat_icon.dart

info "Applying UAT icon to macOS AppIcon set..."
"$SCRIPT_DIR/setup-macos-icon.sh" assets/images/app_icon_uat.png

info "Setting macOS app name to UAT..."
APP_INFO_BAK="${APP_INFO}.buildbak.$$"
cp "$APP_INFO" "$APP_INFO_BAK"
if grep -q '^PRODUCT_NAME =' "$APP_INFO"; then
  sed -i '' 's/^PRODUCT_NAME = .*/PRODUCT_NAME = 德靈海味 POS UAT/' "$APP_INFO"
else
  echo 'PRODUCT_NAME = 德靈海味 POS UAT' >> "$APP_INFO"
fi

info "Getting dependencies..."
flutter pub get

info "Building macOS release (UAT)..."
flutter build macos --release \
  --dart-define=ENV=uat \
  --dart-define=API_BASE_URL="$UAT_BACKEND_URL"

APP_BUNDLE=$(find build/macos/Build/Products/Release -name "*.app" -type d | head -1)
if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
  error "Build failed — app bundle not found"
  exit 1
fi

info "Build complete: $APP_BUNDLE"
info "Backend: $UAT_BACKEND_URL"
