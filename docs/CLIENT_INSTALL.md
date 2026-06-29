# New client installation — preparation checklist & setup guide

Use this when a **new company** buys the POS + management system.  
**Client** = the buyer’s organisation. **Installer** = you or their IT person who runs the technical setup.

---

## Part 1 — What the client should prepare (their side)

Give the client this checklist **before** installation day. They do **not** need to write code.

### A. Google Cloud (hosting)

| Item | Required? | Notes |
|------|-----------|--------|
| **Google account** (Gmail or Google Workspace admin) | Yes | Person who can create projects and accept billing |
| **Google Cloud billing account** | Yes | Credit card or invoiced billing; [cloud.google.com/billing](https://cloud.google.com/billing) |
| **Chosen GCP project ID** | Yes | Short, unique, lowercase, e.g. `acme-foods-pos` (cannot be changed later) |
| **Budget alert** (optional) | Recommended | e.g. email when monthly spend exceeds £50 / £100 |

**Rough monthly cost (small shop, EU):** often **£30–£150+** depending on database size, traffic, and storage. Client pays Google directly unless you host for them.

### B. Email (wholesale invoices, delivery notes, payment reminders)

| Item | Required? | Notes |
|------|-----------|--------|
| **Company email address** | Yes | e.g. `hello@theircompany.co.uk` — shown on PDFs and emails |
| **Google Workspace** or other SMTP | Recommended | For reliable outbound email |
| **App password** (if using Gmail/Workspace SMTP) | If using Google SMTP | [Google App Passwords](https://myaccount.google.com/apppasswords) — not their normal login password |
| **Default CC list** (optional) | Optional | Who should be copied on wholesale order emails |

Without SMTP, the system still runs; **automatic wholesale emails** may not send until SMTP is configured on the server.

### C. Company & legal details (entered in the app after install)

Prepare these in a Word doc or spreadsheet — someone will type them into **Settings → Company settings**:

| Field | Example |
|-------|---------|
| Company name | Acme Foods Ltd |
| Address lines, city, postcode | For invoices & delivery notes |
| Telephone | |
| Bank account name, sort code, account number | For payment instructions on invoices |
| IBAN (if needed) | |
| Payment / transfer instructions | Text shown on documents |
| Shipment couriers list | DHL, Royal Mail, etc. |

### D. Business data (first week)

| Item | Required? | Notes |
|------|-----------|--------|
| **Store list** | Yes | Shop names & addresses (warehouse vs retail) |
| **Staff list** | Yes | Names, roles (management / POS user / supervisor / HQ staff) |
| **Product catalogue** | Yes | Or agreement to import from spreadsheet / old system |
| **Wholesale clients** | If wholesale | Client names, addresses, VAT numbers, payment terms |
| **POS devices** | Yes | One Windows PC/tablet per till; device name per store |

### E. Domain & branding (optional but common)

| Item | Required? | Notes |
|------|-----------|--------|
| **Custom domain** | Optional | e.g. `manage.acmefoods.co.uk` for the management website |
| **DNS access** | If custom domain | Whoever controls their domain registrar |
| **Company logo (PNG)** | Recommended | For PDF invoices & on-screen POS branding (see Part 3) |
| **App icon (PNG)** | Optional | Square 1024×1024 for desktop shortcut / dock icon |

Default URLs without a custom domain look like:  
`https://YOUR-PROJECT-ID.web.app` (Firebase Hosting).

### F. POS desktop app (Windows / macOS)

| Item | Required? | Notes |
|------|-----------|--------|
| **Windows PC per till** | Yes (typical) | Windows 10/11, stable Wi‑Fi or LAN |
| **Receipt printer** | If used | **ESC/POS** thermal printer; **network (Ethernet/Wi‑Fi) recommended** on Windows |
| **Printer IP address** | If network printer | e.g. `192.168.1.100`, port **9100** (write it down) |
| **USB printer** | Alternative | Must be installed in Windows **Settings → Printers & scanners** first |
| **Barcode scanner** | If used | USB keyboard-style scanners work out of the box |
| **Installer builds app** | Installer | POS app is built with client API URL + branding (see Part 2 & 3) |

App store distribution (Apple/Google) is **not** required for the desktop POS used in shops today.

### G. Access & decisions (one meeting)

- [ ] Who is the **main admin** (management login)?
- [ ] Who can **approve wholesale orders**?
- [ ] Which **stores** each staff member can use (set in **Store & client settings**)
- [ ] Which **wholesale clients** each POS user may see (optional restriction)
- [ ] **VAT / currency** — confirm UK £ and tax treatment with their accountant

---

## Part 2 — Installer setup guide (technical)

**Prerequisites on the installer's machine:**

- macOS or Linux (or Windows with WSL) for scripts
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install)
- [Node.js 18+](https://nodejs.org/) (management website build)
- [Firebase CLI](https://firebase.google.com/docs/cli): `npm install -g firebase-tools`
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (only if building POS app)
- Access to this git repository

### Step 0 — Collect from client

Fill in before starting:

```
Client name:     _______________________
GCP project ID:  _______________________   (e.g. acme-foods-pos)
Region:          europe-west1             (default; change only if needed)
Admin email:     _______________________
SMTP from:       _______________________
```

### Step 1 — Create & select GCP project

```bash
gcloud auth login
gcloud projects create CLIENT_PROJECT_ID --name="Client Company POS"
gcloud billing projects link CLIENT_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
gcloud config set project CLIENT_PROJECT_ID
```

Find billing account ID: `gcloud billing accounts list`

### Step 2 — One-time infrastructure

From the **repo root**:

```bash
export PROJECT_ID=$(gcloud config get-value project)
./scripts/setup-gcp.sh
```

This enables APIs, creates Cloud SQL (`pos-database`), storage buckets, and secrets.  
Save all passwords shown or stored in **Secret Manager**.

**Alternative** (clone from your existing UAT template):

```bash
export PROD_PROJECT_ID=CLIENT_PROJECT_ID
export UAT_PROJECT_ID=your-uat-project-id
./scripts/setup-prod-from-uat.sh
```

### Step 3 — Database schema

```bash
# Option A: Cloud SQL Auth proxy / gcloud sql connect
gcloud sql connect pos-database --user=pos_user --project=CLIENT_PROJECT_ID
# Then run database/schema.sql

# Option B: Use connection from setup script output
```

Create the first **management** user via API or SQL as you do today for new environments.

### Step 4 — Point Firebase at the new project

Edit **`management-frontend/.firebaserc`**:

```json
{
  "projects": {
    "default": "CLIENT_PROJECT_ID",
    "uat": "CLIENT_PROJECT_ID",
    "production": "CLIENT_PROJECT_ID"
  }
}
```

Enable Firebase on the GCP project (once):  
[Firebase Console](https://console.firebase.google.com/) → Add project → link to same GCP project → enable **Hosting**.

```bash
cd management-frontend
firebase login
firebase use CLIENT_PROJECT_ID
```

### Step 5 — Deploy backend (API)

```bash
./scripts/deploy.sh backend
# Or: cd backend && gcloud builds submit --config=cloudbuild.yaml --project=CLIENT_PROJECT_ID
```

Note the **Cloud Run URL**, e.g. `https://pos-backend-xxxxx-ew.a.run.app`

Set SMTP on Cloud Run (if client provided email):

- Console → Cloud Run → `pos-backend` → Edit → Variables / Secrets  
- Or add to deploy env: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`  
- See `backend/.env.example` and `backend/cloud-run-env.example`

Backend storage bucket (set automatically on deploy) is usually:

```text
GCP_BUCKET_NAME=CLIENT_PROJECT_ID-pos-uploads
```

### Step 6 — Deploy management website

Edit **`management-frontend/.env.production`**:

```env
VITE_API_URL=https://pos-backend-xxxxx-ew.a.run.app/api/v1
VITE_AI_PLAYBOOK_URL=/api/ai-playbook
```

Deploy:

```bash
./scripts/deploy-firebase.sh production
```

Give the client the Hosting URL (`firebase hosting:sites:list`) or attach their custom domain in Firebase Console → Hosting → Add custom domain.

### Step 7 — Build POS desktop app (per client)

Edit **`frontend/lib/config/api_config.dart`** — set `_prodUrl` to the client’s API:

```dart
static const String _prodUrl = 'https://pos-backend-xxxxx-ew.a.run.app/api/v1';
```

Build (example Windows) — **do branding in Part 3 first** (logo, app name):

```bash
# On Windows PC at each site, or build once and distribute:
BUILD-AND-DEPLOY-WINDOWS.bat
# Or see scripts/frontend/ for macOS / upload scripts
```

Then complete **Part 3** on each till (device registration, printer, test sale).

### Step 8 — Smoke test

| Check | How |
|-------|-----|
| Management login | Open Hosting URL → login as admin |
| Company settings | Settings → Company settings → save test |
| Create store | Settings → Stores |
| Create user | Settings → Users + Store & client settings |
| Register POS device | Devices → configure → test login on till |
| Wholesale order | Create test order → PDF generates |
| Email (if SMTP) | Send test invoice email |

### Step 9 — Handover to client

Provide a one-page **Go-live sheet**:

| What | Value |
|------|--------|
| Management website | `https://....web.app` or custom domain |
| Admin username | (they choose password on first login / you set temp PIN) |
| Support contact | Your email/phone |
| GCP project ID | For their records (billing) |
| Where passwords live | Secret Manager / your secure vault |

Train 30–60 minutes: products, stock, wholesale flow, POS checkout, printer test, user settings.

---

## Part 3 — Setting up the POS (each till)

Do this **on every shop PC** after the cloud system is live. Staff can do printer setup themselves once the app is installed; the installer usually handles branding and device registration.

### 3.1 What the client should have ready (POS)

| Item | Notes |
|------|--------|
| **Logo file** | PNG, transparent background if possible; wide format OK for receipts/PDFs |
| **Printer** | ESC/POS compatible (most shop receipt printers) |
| **Printer connection** | Network IP **or** USB cable + Windows driver installed |
| **Store name** | Already created in management website |
| **Staff PINs** | Each cashier needs a user account + 4-digit PIN |

### 3.2 Company logo & branding (installer — before building the app)

Branding is applied **before** you build the POS installer for that client.

| Where it appears | File to replace | Notes |
|----------------|-----------------|--------|
| **Wholesale PDFs** (invoice, order confirmation, delivery note) | `backend/pdf-assets/images/pdf_logo.png` | Redeploy backend after replacing |
| **POS on-screen logo** | `frontend/assets/images/logo.png` | Shown in the app UI |
| **Desktop app icon** (shortcut / dock) | `frontend/assets/images/app_icon.png` | 1024×1024 PNG; then run `flutter pub run flutter_launcher_icons` |
| **Receipt print header** (company name text) | `frontend/lib/services/simple_receipt_printer.dart` (and `full_receipt_printer.dart`, `barcode_receipt_printer.dart`) | Set `companyName` to client legal/trading name |
| **Company details on PDFs** | Management UI → **Settings → Company settings** | Name, address, bank — no code change |

**PDF logo tips**

- Use PNG, roughly **300–800 px wide**, white or transparent background.
- After replacing `pdf_logo.png`, redeploy the backend (`./scripts/deploy.sh backend`).
- Optional server override: env var `PDF_LOGO_PATH` (see `backend/.env.example`).

**POS UI logo tips**

- Replace `frontend/assets/images/logo.png`, then rebuild the Flutter app.
- If no logo file is bundled, the app shows a text fallback.

See also: `frontend/SETUP_APP_ICON.md`, `frontend/UPDATE_ICON_AND_REBUILD.md`.

### 3.3 Install the POS app on the till PC

1. Copy the built installer or `.exe` / `.app` to the shop PC (from your build step in Part 2).
2. Install / unzip to a permanent folder (e.g. `C:\POS` or `/Applications`).
3. First launch: the app generates a **device code** (unique ID for this till).
4. Ensure the PC has internet access to the management API URL.

### 3.4 Register the till in the management website

**Management user (admin):**

1. Open the management website → **Settings → Devices**.
2. Click **Register device** (or add device).
3. Enter the **device code** shown on the POS screen.
4. Choose **store** (which shop this till belongs to).
5. Enter a friendly **device name** (e.g. `Marylebone Till 1`).
6. Save.

**Assign staff to that store** (if not done already):

- **Settings → Users** — each cashier must have the correct **store(s)** ticked.
- **Store & client settings** — set default store / wholesale clients if needed.

**On the POS app:**

1. On the login screen, tap **Sync users** (or equivalent) so local user list updates.
2. Staff select their name → enter **PIN** → start selling.

**Optional (management login on the till):**  
**Settings → Configure device** (management role only) — copy device ID, change linked store.

### 3.5 Printer setup (on the till)

Open the POS app → **Settings** (gear) → **Printer settings**.

#### Recommended: network printer (Windows & macOS)

1. Connect the printer to the shop LAN (Ethernet or Wi‑Fi).
2. Print a **network config page** from the printer (or check router DHCP list) to find its **IP address**.
3. In POS printer settings:
   - Type: **Network**
   - **IP address**: e.g. `192.168.1.100`
   - **Port**: `9100` (default for ESC/POS)
4. Tap **Test printer** — a test slip should print.
5. Tap **Save**.

#### USB printer (Windows)

1. Install the printer in **Windows Settings → Printers & scanners**.
2. Note the **exact printer name** (case-sensitive).
3. In POS → **Settings → Printer settings**:
   - Type: **USB**
   - **Scan for printers** → select your printer
4. **Test printer** → **Save**.

#### USB / serial COM port (advanced)

1. Open Windows **Device Manager** → **Ports (COM & LPT)** → note COM number (e.g. `COM3`).
2. In POS printer settings, scan and select the COM port.
3. **Test printer** → **Save**.

#### Bluetooth (macOS / mobile — not Windows desktop)

- Pair the printer in system Bluetooth settings first.
- In POS → Printer settings → **Bluetooth** → select paired device → test → save.

**Troubleshooting**

| Problem | Try |
|---------|-----|
| Test print fails | Ping printer IP; check port 9100; try network instead of USB |
| USB printer not listed | Install driver in Windows; replug USB; restart POS app |
| Receipts don’t print after sale | Confirm settings saved; run test print again |
| Garbled characters | Printer must support ESC/POS; check paper width (usually 80 mm) |

Full detail: [frontend/WINDOWS_PRINTING.md](../frontend/WINDOWS_PRINTING.md)

### 3.6 First-day checklist (each till)

| Step | Done? |
|------|-------|
| POS app installed & opens | ☐ |
| Device registered to correct store | ☐ |
| Users synced; test PIN login works | ☐ |
| Printer test slip prints | ☐ |
| Test sale → receipt prints | ☐ |
| Barcode scan adds product (if used) | ☐ |
| **Sync** run (Settings → Sync) — uploads offline orders | ☐ |
| Logo correct on PDF (wholesale test order) | ☐ |

### 3.7 Day-to-day (what staff need to know)

- **Change PIN / avatar**: Settings → Profile  
- **Printer stopped working**: Settings → Printer settings → Test printer  
- **New staff member**: admin adds user in management website → Sync users on till  
- **End of day**: logout may prompt for **stocktake** — follow on-screen steps  
- **Offline sales**: app queues orders; run **Sync** when internet returns  

---

## Part 4 — Quick reference: where settings live

| What | Where |
|------|--------|
| **GCP project ID (global)** | `gcloud config set project …` |
| **Firebase project** | `management-frontend/.firebaserc` |
| **Management API URL** | `management-frontend/.env.production` → `VITE_API_URL` |
| **POS app API URL** | `frontend/lib/config/api_config.dart` → `_prodUrl` |
| **Backend bucket / storage** | Cloud Run env `GCP_BUCKET_NAME` or `backend/.env` locally |
| **Company name, bank, email templates** | Management UI → **Company settings** |
| **Users, stores, client access** | Management UI → **Users** & **Store & client settings** |
| **POS tills** | Management UI → **Devices** |
| **POS printer** | POS app → **Settings → Printer settings** (saved on each PC) |
| **PDF document logo** | `backend/pdf-assets/images/pdf_logo.png` → redeploy backend |
| **POS screen logo** | `frontend/assets/images/logo.png` → rebuild POS app |
| **Receipt company name** | `frontend/lib/services/*_receipt_printer.dart` → rebuild POS app |

---

## Part 5 — Optional enhancements (later)

- **Custom domain** on Firebase Hosting (client DNS + SSL automatic)
- **Separate UAT project** for training (`acme-foods-pos-uat`) before production cutover
- **Backups**: Cloud SQL automated backups (enabled in `setup-gcp.sh`); document restore procedure
- **Monitoring**: GCP billing alerts + uptime check on Cloud Run URL

---

## Related docs in this repo

- [QUICK_START.md](../QUICK_START.md) — fast deploy overview  
- [DEPLOYMENT.md](../DEPLOYMENT.md) — full GCP architecture  
- [README_DEPLOYMENT.md](../README_DEPLOYMENT.md) — troubleshooting `gcloud`  
- [scripts/README.md](../scripts/README.md) — all deploy scripts  
- [FIREBASE_SETUP.md](../FIREBASE_SETUP.md) — Firebase Hosting details  
- [frontend/WINDOWS_PRINTING.md](../frontend/WINDOWS_PRINTING.md) — POS printer setup (Windows)  
- [frontend/SETUP_APP_ICON.md](../frontend/SETUP_APP_ICON.md) — POS desktop app icon  

---

## Printable client checklist (copy/paste)

```
NEW CLIENT — PLEASE PREPARE

□ Google Cloud billing account (card or invoice)
□ Decide GCP project ID: ____________________
□ Company legal name & address for invoices
□ Bank details for payment instructions on invoices
□ Outbound email address (+ app password if Google)
□ List of shops / warehouses
□ List of staff & roles
□ Product list (or sample export from old system)
□ Wholesale customer list (if applicable)
□ One Windows PC per till
□ Receipt printer (+ IP address if network, or USB)
□ Company logo PNG (+ optional app icon 1024×1024)
□ Barcode scanner (if used)
□ Who is the main system administrator
□ Optional: custom domain for management website

POS SETUP (on each till — installer or shop manager)

□ Install POS app
□ Register device code in management website → Devices
□ Sync users → test staff PIN login
□ Settings → Printer settings → Test print → Save
□ Test sale with receipt
□ Confirm logo on wholesale PDF (if used)
```
