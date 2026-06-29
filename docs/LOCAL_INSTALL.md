# Local installation (one-click)

Run the full POS stack on your machine: **MySQL**, **Go backend API**, and **React management website**. No Google Cloud required.

## Prerequisites

Install these once on the machine:

| Tool | Version | Download |
|------|---------|----------|
| **Docker Desktop** | latest | Installed automatically by `INSTALL-LOCAL.bat` if missing (via winget) |
| **Go** | 1.21+ | [go.dev/dl](https://go.dev/dl/) |
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org/) |

Optional (POS till app):

| Tool | Notes |
|------|--------|
| **Flutter** | Only if you want the desktop POS app locally — pass `--with-flutter` to the installer |

## Install (one click)

From the **repo root**:

### macOS / Linux

```bash
chmod +x INSTALL-LOCAL.sh START-LOCAL.sh
./INSTALL-LOCAL.sh
```

Or:

```bash
./scripts/install-local.sh
```

### Windows

Double-click **`INSTALL-LOCAL.bat`** in Explorer, or in Command Prompt:

```bat
INSTALL-LOCAL.bat
```

### Options

| Flag | Description |
|------|-------------|
| `--start` | Start backend + management UI immediately after install |
| `--with-flutter` | Also run `flutter pub get` in `frontend/` |
| `--skip-docker` | Skip Docker MySQL (use your own MySQL; set `DATABASE_URL` in `backend/.env`) |

Example:

```bash
./INSTALL-LOCAL.sh --start --with-flutter
```

## What the installer does

1. Starts **MySQL 8** in Docker (`docker-compose.local.yml`)
2. Creates **`backend/.env`** from `backend/.env.local.example` (random JWT secret)
3. Downloads PDF fonts if missing
4. Runs **`go mod download`** and builds **`bin/pos-backend`**
5. Runs **`npm install`** in `management-frontend/`
6. Runs **`go run ./cmd/seed-local`** — GORM migrations + default admin user

## Default credentials

| Item | Value |
|------|--------|
| Management login | `admin` / `admin123` |
| Admin PIN (POS) | `1234` |
| MySQL | `pos_user` / `pos_local_pass` on `127.0.0.1:3306`, database `pos_system` |

Change these before going live. Override seed values with env vars when running seed:

```bash
SEED_ADMIN_USERNAME=you SEED_ADMIN_PASSWORD=secret SEED_ADMIN_PIN=5678 \
  go run ./cmd/seed-local
```

## Start / stop

### Start everything

```bash
./START-LOCAL.sh          # macOS/Linux — single terminal, Ctrl+C stops all
START-LOCAL.bat           # Windows — opens two command windows
```

| Service | URL |
|---------|-----|
| Management website | http://localhost:3000 |
| Backend API | http://localhost:8868/api/v1 |

### Stop MySQL

```bash
docker compose -f docker-compose.local.yml down
```

Data is kept in the Docker volume `pos_mysql_data`. To wipe the database:

```bash
docker compose -f docker-compose.local.yml down -v
./INSTALL-LOCAL.sh
```

## POS desktop app (optional)

After install with `--with-flutter`:

```bash
cd frontend
flutter run -d windows   # or macos / linux
```

The Flutter app uses `http://127.0.0.1:8868/api/v1` in development mode (`frontend/lib/config/api_config.dart`).

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Docker not running | The installer starts Docker Desktop and waits up to 10 minutes; if it times out, open Docker Desktop manually and re-run |
| Docker install failed | Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) manually, or use `--skip-docker` with your own MySQL |
| Port 3306 in use | Stop local MySQL or change the port mapping in `docker-compose.local.yml` and `backend/.env` |
| Port 8868 / 3000 in use | Stop other services or change `PORT` in `backend/.env` / Vite port in `management-frontend/vite.config.ts` |
| Re-seed admin | Drop DB volume (`docker compose … down -v`) and re-run install, or create users in the management UI |
| Backend starts but DB fails | `docker compose -f docker-compose.local.yml logs mysql` |

## Related files

| File | Purpose |
|------|---------|
| `docker-compose.local.yml` | Local MySQL container |
| `backend/.env.local.example` | Template copied to `backend/.env` |
| `backend/cmd/seed-local/` | Migrations + default admin/store/sectors |
| `scripts/install-local.sh` / `.bat` | Installer logic |
| `scripts/start-local.sh` / `.bat` | Dev server launcher |

For cloud / client deployment see [docs/CLIENT_INSTALL.md](./CLIENT_INSTALL.md).
