# Fonts Directory

This directory is for custom font files used for icon generation.

## Custom Icon Font

To use a custom font for user icon generation:

1. Place a TrueType font file (`.ttf`) named `icon.ttf` in this directory
2. The font should be a monospace font for best results
3. Recommended fonts:
   - Roboto Mono
   - Source Code Pro
   - Courier New
   - Monaco
   - DejaVu Sans Mono

## Font Selection Priority

The backend will try to load fonts in this order:
1. `fonts/icon.ttf` (custom font in this directory) - **Highest Priority**
2. System monospace fonts (Monaco on macOS, DejaVu Sans Mono on Linux, Consolas on Windows)
3. `basicfont.Face7x13` (fallback if no fonts found)

## Notes

- The font file must be a valid TrueType (TTF) font
- The font will be loaded at size 13 DPI 72 for icon generation
- If the custom font file is not found, the system will automatically fall back to system fonts or basicfont

