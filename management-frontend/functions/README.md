# AI playbook Cloud Function

Serves `docs/ai-playbook-wholesale-po-to-order.md` over HTTPS. **Not a public document:** callers must send `Authorization: Bearer <JWT>` signed with the same `JWT_SECRET` as the Go POS/management API.

## Prerequisites

- Firebase CLI logged in (`firebase login`)
- Firebase project selected (`firebase use <projectId>` from `management-frontend/`)

## Configure secret

The secret must **match** the backend `JWT_SECRET` (see `backend/internal/config/config.go`).

```bash
cd management-frontend/functions
# Set value interactively (recommended):
firebase functions:secrets:set JWT_SECRET
```

For the **emulator**, create `functions/.secret.local`:

```
JWT_SECRET=your-local-jwt-secret
```

(same value as local Go API `.env`)

## Build

```bash
npm install
npm run build
```

`build` copies the playbook from `../../docs/` into `assets/` and into `lib/assets/` for runtime.

## Deploy

From `management-frontend/`:

```bash
firebase deploy --only functions:aiPlaybook
```

**Firebase Hosting (management portal):** `firebase.json` can rewrite `GET /api/ai-playbook` to this function (same site, no browser CORS). `scripts/deploy-firebase.sh` deploys **hosting only** by default so you are not blocked on `JWT_SECRET` / Functions. When ready: set the secret, then either run `DEPLOY_FIREBASE_FUNCTIONS=1` with `deploy-firebase.sh` or `firebase deploy --only functions:aiPlaybook`. Before building for production, set `VITE_AI_PLAYBOOK_URL` (e.g. `/api/ai-playbook` after the function exists, or the full `cloudfunctions.net` URL).

If you previously opened the playbook from `https://REGION-PROJECT.cloudfunctions.net/aiPlaybook`, the browser needed CORS on `OPTIONS`; the handler now sets `Access-Control-Allow-*` for `*.web.app`, `*.firebaseapp.com`, and `storage.googleapis.com` origins. Prefer the **Hosting path** `/api/ai-playbook` when the app is on Firebase Hosting.

## Management portal

**Production (Firebase / static hosting):** set `VITE_AI_PLAYBOOK_URL` before `vite build`, for example in `management-frontend/.env.local`:

```bash
VITE_AI_PLAYBOOK_URL=https://<region>-<project>.cloudfunctions.net/aiPlaybook
```

(Exact URL is printed after `firebase deploy`.)

**With `./scripts/deploy.sh all uat`:** Firebase hosting is deployed via `deploy-firebase.sh` (functions skipped unless `DEPLOY_FIREBASE_FUNCTIONS=1`). Set `VITE_AI_PLAYBOOK_URL` in `.env.uat` or the shell after you deploy the function.

- Cloud Storage UAT path (`./scripts/deploy.sh frontend-uat`) only updates `VITE_API_URL` in `.env.uat`; playbook URL is manual there too.

Override anytime: `export VITE_AI_PLAYBOOK_URL='https://…'` or `/api/ai-playbook` before `vite build` / deploy scripts.

**Local development:** `npm run dev` loads the markdown from the repo `docs/` folder automatically when `VITE_AI_PLAYBOOK_URL` is unset — no Function required. The built production bundle does **not** embed the playbook unless you use the Cloud Function URL above (keeps internal text out of public JS).

## Security note

The function URL is discoverable; protection is **HS256 JWT validation**. Keep `JWT_SECRET` strong and rotate if leaked. For stricter network control, put the function behind **Cloud IAP** or **API Gateway** (optional).
