#!/usr/bin/env bash
# Download Liberation Sans (free, Arial-compatible) and install as Arial.ttf for PDFs.
# Run from repo root: ./scripts/download-arial-font.sh
# Note: Liberation Sans does not include Chinese; for Chinese use Noto (see backend/fonts/README.md).

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FONTS_DIR="$REPO_ROOT/backend/pdf-assets/fonts"
REGULAR_URL="https://raw.githubusercontent.com/shantigilbert/liberation-fonts-ttf/master/LiberationSans-Regular.ttf"
BOLD_URL="https://raw.githubusercontent.com/shantigilbert/liberation-fonts-ttf/master/LiberationSans-Bold.ttf"

mkdir -p "$FONTS_DIR"

echo "Downloading Liberation Sans Regular..."
if ! curl -sL "$REGULAR_URL" -o "$FONTS_DIR/Arial.ttf"; then
  echo "Download failed. Check your connection and try again."
  exit 1
fi
echo "Installed: $FONTS_DIR/Arial.ttf"

echo "Downloading Liberation Sans Bold..."
if curl -sL "$BOLD_URL" -o "$FONTS_DIR/Arial-Bold.ttf"; then
  echo "Installed: $FONTS_DIR/Arial-Bold.ttf"
else
  echo "Bold download failed (optional); PDFs will use Regular for bold too."
  rm -f "$FONTS_DIR/Arial-Bold.ttf"
fi

echo "Done. Run the backend from the backend/ directory so PDFs use Arial."
echo "For Chinese text, keep Noto fonts in backend/pdf-assets/fonts/ (see backend/fonts/README.md)."
