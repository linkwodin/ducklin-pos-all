#!/usr/bin/env bash
# Run management_mobile against local backend (:8868).
#
# Usage:
#   ./scripts/run-management-mobile-local.sh              # iOS Simulator
#   ./scripts/run-management-mobile-local.sh android      # Android emulator (10.0.2.2)
#   ./scripts/run-management-mobile-local.sh device       # Physical phone on same Wi‑Fi (Mac LAN IP)
#   ./scripts/run-management-mobile-local.sh <device-id>  # flutter devices id (remote/wireless OK)
#
# Prerequisites:
#   cd backend && go run .

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-ios-sim}"

local_ip() {
  ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
}

LAN_IP="$(local_ip)"
if [[ -z "$LAN_IP" ]]; then
  echo "Warning: could not detect LAN IP (en0/en1). Use ios-sim/android or pass API_BASE_URL manually."
fi

case "$TARGET" in
  ios|ios-sim|simulator)
    API_URL="http://127.0.0.1:8868/api/v1"
    FLUTTER_DEVICE="ios"
    ;;
  android|emu|emulator)
    API_URL="http://10.0.2.2:8868/api/v1"
    FLUTTER_DEVICE="android"
    ;;
  device|phone|physical)
    if [[ -z "$LAN_IP" ]]; then
      echo "Set LAN IP manually: export LOCAL_HOST=192.168.x.x"
      exit 1
    fi
    API_URL="http://${LAN_IP}:8868/api/v1"
    FLUTTER_DEVICE=""
    ;;
  *)
    API_URL="http://${LAN_IP:-127.0.0.1}:8868/api/v1"
    FLUTTER_DEVICE="$TARGET"
    ;;
esac

if [[ -n "${LOCAL_HOST:-}" ]]; then
  API_URL="http://${LOCAL_HOST}:8868/api/v1"
fi

echo "=== POS Management mobile (local) ==="
echo "API: $API_URL"
echo ""
echo "Ensure backend (:8868) is running."
echo ""

cd "$ROOT/management_mobile"

ARGS=(
  --device-timeout=120
  --dart-define=ENV=development
  --dart-define=API_BASE_URL="$API_URL"
)

if [[ -n "$FLUTTER_DEVICE" ]]; then
  flutter run -d "$FLUTTER_DEVICE" "${ARGS[@]}"
else
  flutter run "${ARGS[@]}"
fi
