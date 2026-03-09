# PDF fonts (order confirmation, invoice, delivery note)

PDFs need a UTF-8 font so that **Chinese characters** and the **£ (GBP)** symbol display correctly.

## Arial (optional)

If you want **Arial**, the app looks for it in (in order):

1. `PDF_FONT_PATH` in `.env` (only if the path contains "Arial")
2. **`backend/pdf-assets/fonts/Arial Unicode MS.ttf`** or **`Arial.ttf`**
3. **`uploads/assets/fonts/Arial Unicode MS.ttf`** or **`Arial.ttf`**

Arial is a Microsoft font and is **not included** in this repo. You can:

- **Download a free Arial-like font (Liberation Sans):** from the repo root run  
  `./scripts/download-arial-font.sh`  
  This installs `backend/pdf-assets/fonts/Arial.ttf`. Liberation Sans does not include Chinese (use Noto for that).
- **Use real Arial:** copy `arial.ttf` or `Arial Unicode MS.ttf` from your system (e.g. Windows: `C:\Windows\Fonts\`) into `backend/pdf-assets/fonts/` or `uploads/assets/fonts/`.

If no Arial file is found, the app uses Noto (see below).

## Noto (fallback)

1. Download **Noto Sans TC** (Traditional) or **Noto Sans SC** (Simplified) from [Google Fonts](https://fonts.google.com/noto).

2. Place the `.ttf` files in `uploads/assets/fonts/` or `backend/pdf-assets/fonts/`:
   - **Regular:** `NotoSansTC-Regular.ttf` (or `NotoSansSC-Regular.ttf`)
   - **Bold (for headers):** `NotoSansTC-Bold.ttf` (or `NotoSansSC-Bold.ttf`) — same folder as Regular. If Bold is missing, headers use the same weight as body text.

3. Optional: set in `.env`:
   ```bash
   PDF_FONT_PATH=uploads/assets/fonts/NotoSansTC-Regular.ttf
   ```
   If unset, the backend tries the paths above automatically when running from the backend directory.
