# POS Management Mobile (iOS & Android)

Native Flutter management app with **Face ID / Touch ID** unlock. Calls the Go backend API directly — no WebView, no npm/Vite dev server required.

## Features

- Username/password login (management & supervisor roles)
- Optional **Face ID / Touch ID / fingerprint** unlock on next app open
- Native screens: dashboard, wholesale orders, shipments, account settings
- Automatic JWT refresh before expiry

## Prerequisites

- Flutter SDK 3.10+
- Xcode (iOS) and/or Android Studio (Android)
- Backend API URL reachable from the device

## Local development

Only the **backend** needs to run locally:

```bash
cd backend && go run .
```

Then run the app:

```bash
# iOS Simulator (127.0.0.1)
./scripts/run-management-mobile-local.sh ios-sim

# Android emulator (10.0.2.2)
./scripts/run-management-mobile-local.sh android

# Physical phone on Wi‑Fi (Mac LAN IP)
./scripts/run-management-mobile-local.sh device
```

Override IP if auto-detect is wrong:

```bash
export LOCAL_HOST=192.168.1.42
./scripts/run-management-mobile-local.sh device
```

### URL cheat sheet

| Where the app runs | API URL |
|--------------------|---------|
| iOS Simulator | `http://127.0.0.1:8868/api/v1` |
| Android emulator | `http://10.0.2.2:8868/api/v1` |
| Physical phone (Wi‑Fi) | `http://<mac-ip>:8868/api/v1` |

Find Mac IP: `ipconfig getifaddr en0`

HTTP is allowed for local dev (iOS ATS + Android cleartext in debug builds).

## VS Code / Cursor

Launch configs in `.vscode/launch.json`:

- **iOS Simulator (local)** — `127.0.0.1`
- **Android emulator (local)** — `10.0.2.2`
- **Physical device (LAN IP)** — edit `192.168.68.118` to your Mac's IP

## Configuration (UAT / production)

| Variable | Purpose | Example |
|----------|---------|---------|
| `ENV` | Preset bundle (`development`, `uat`, `production`) | `uat` |
| `API_BASE_URL` | Override backend API | `https://…/api/v1` |

```bash
cd management_mobile
flutter run --dart-define=ENV=uat
```

Production build:

```bash
flutter build apk \
  --dart-define=ENV=production \
  --dart-define=API_BASE_URL=https://YOUR-BACKEND.run.app/api/v1
```

## Biometric login flow

1. **First sign-in:** username + password → optional “Use Face ID next time” toggle.
2. **Later opens:** Face ID / Touch ID prompt → unlock stored session → native home screen.
3. **Fallback:** “Use password instead” returns to the sign-in screen.

## Project layout

```
lib/
  config/app_config.dart
  providers/auth_provider.dart
  services/                   # API, biometrics, secure session
  screens/                    # Login, biometric unlock, dashboard, orders, shipments
```

## Related projects

| Project | Purpose |
|---------|---------|
| `management-frontend/` | Full web management portal (browser) |
| `frontend/` | Flutter POS app (store checkout, packing) |
| `backend/` | Shared API |
