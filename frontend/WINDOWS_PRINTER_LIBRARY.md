# Windows Printer Library Integration

## Overview

The POS system now uses the **`windows_printer`** package for Windows printing, which provides native Windows printing API support. This is much more reliable than the previous command-line approach (PowerShell, `copy` commands, etc.).

## Benefits

1. **Native Windows API**: Uses proper Windows printing APIs instead of command-line workarounds
2. **Raw Data Support**: Built-in `useRawDatatype: true` flag for ESC/POS printers
3. **Automatic Printer Discovery**: Simple API to get all available printers
4. **More Reliable**: Eliminates issues with PowerShell aliases, file paths, and port handling
5. **Better Error Handling**: Proper exception handling from native APIs

## Changes Made

### 1. Added Dependency

**File**: `frontend/pubspec.yaml`

```yaml
dependencies:
  windows_printer: ^0.2.1
```

### 2. Printer Discovery

**File**: `frontend/lib/screens/printer_settings_screen.dart`

- **Primary Method**: Uses `WindowsPrinter.getAvailablePrinters()` first
- **Fallback**: Falls back to PowerShell `Get-Printer` if library fails
- **Final Fallback**: Uses WMIC if PowerShell also fails

```dart
// Try windows_printer library first (most reliable)
try {
  final availablePrinters = await windows_printer.WindowsPrinter.getAvailablePrinters();
  // Process printers...
} catch (e) {
  // Fall back to PowerShell...
}
```

### 3. Printing Implementation

**File**: `frontend/lib/services/receipt_printer_helpers.dart`

- **Primary Method**: Uses `WindowsPrinter.printRawData()` with `useRawDatatype: true`
- **Fallback**: Falls back to manual methods (PowerShell, copy command, etc.) if library fails

```dart
// Try windows_printer library first (most reliable method)
if (Platform.isWindows) {
  try {
    await windows_printer.WindowsPrinter.printRawData(
      printerName: printerName,
      data: Uint8List.fromList(bytes),
      useRawDatatype: true, // Critical for ESC/POS printers
    );
    return; // Success!
  } catch (e) {
    // Fall back to manual methods...
  }
}
```

## How It Works

1. **Printer Discovery**:
   - App tries `windows_printer` library first
   - If that fails, falls back to PowerShell `Get-Printer`
   - If that fails, falls back to WMIC (if available)

2. **Printing**:
   - App tries `windows_printer.printRawData()` with `useRawDatatype: true`
   - This sends raw ESC/POS data directly to the printer without Windows processing
   - If that fails, falls back to manual methods (COM port, PowerShell, copy command, etc.)

## Key Feature: `useRawDatatype: true`

This flag is **critical** for ESC/POS printers. It tells Windows to:
- Send raw binary data directly to the printer
- Skip Windows print processing (which would corrupt ESC/POS commands)
- Use the printer's native raw data port

Without this flag, Windows would try to process the ESC/POS commands as text or images, which is why plain text files didn't print.

## Testing

1. **Install the package**:
   ```bash
   cd frontend
   flutter pub get
   ```

2. **Test printer discovery**:
   - Go to Settings → Printer Settings
   - Click "Scan for Printers" or "List All Printers"
   - Printers should appear from the `windows_printer` library

3. **Test printing**:
   - Select a printer
   - Click "Test Print"
   - The library should send raw ESC/POS data directly to the printer

## Troubleshooting

### Library Not Found
If you get import errors:
- Make sure you ran `flutter pub get`
- The library only works on Windows (it has a stub for web/other platforms)

### Printers Not Appearing
- The library will fall back to PowerShell automatically
- Check the debug logs to see which method succeeded

### Printing Still Not Working
- Check the log file: `%USERPROFILE%\Documents\pos_system\logs\printer_log_YYYY-MM-DD.txt`
- The library logs when it tries the native method and when it falls back
- If the library fails, it will automatically try the manual methods

## Migration Notes

- **Backward Compatible**: All existing manual methods are still available as fallbacks
- **No Breaking Changes**: The app will work the same way, just more reliably
- **Automatic Fallback**: If the library fails, it automatically tries the old methods

## Documentation

- Package: https://pub.dev/packages/windows_printer
- API Docs: https://pub.dev/documentation/windows_printer/latest

