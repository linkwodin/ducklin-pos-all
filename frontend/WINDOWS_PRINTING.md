# Windows Printing Support

The POS system now supports printing on Windows! Here's how to set it up:

## Supported Printer Types

1. **Network Printers** (Recommended)
   - Works with any ESC/POS printer connected via Ethernet/WiFi
   - Most reliable method on Windows

2. **USB Printers via Windows Print Queue**
   - Printers installed in Windows Settings
   - Works with most ESC/POS printers

3. **COM Port Printers**
   - Direct serial/USB connection via COM ports (COM1, COM2, etc.)
   - For advanced users

## Setup Instructions

### Network Printer (Recommended)

1. Make sure your printer is connected to the network and has an IP address
2. Open the POS app
3. Go to **Settings** → **Printer Settings**
4. Select **Network** as printer type
5. Enter:
   - **Printer IP Address**: Your printer's IP (e.g., `192.168.1.100`)
   - **Port**: Usually `9100` (default for ESC/POS)
6. Click **Test Printer** to verify
7. Click **Save**

### USB Printer (Windows Print Queue)

1. Make sure your printer is installed in Windows:
   - Go to **Windows Settings** → **Printers & scanners**
   - Your printer should appear in the list
   - Note the exact printer name (case-sensitive)

2. In the POS app:
   - Go to **Settings** → **Printer Settings**
   - Select **USB** as printer type
   - Click **Scan for Printers**
   - Select your printer from the list
   - Click **Test Printer** to verify
   - Click **Save**

### COM Port Printer (Advanced)

1. Find your printer's COM port:
   - Open **Device Manager**
   - Expand **Ports (COM & LPT)**
   - Find your printer (e.g., "USB Serial Port (COM3)")
   - Note the COM port number

2. In the POS app:
   - Go to **Settings** → **Printer Settings**
   - Select **USB** as printer type
   - Click **Scan for Printers**
   - Look for entries like "COM3" or "USB Serial Port (COM3)"
   - Select the COM port
   - Click **Test Printer** to verify
   - Click **Save**

## Troubleshooting

### "Printer not found" Error

- **Network printer**: Check IP address and port (usually 9100)
- **USB printer**: Make sure printer is installed in Windows Settings
- **COM port**: Check Device Manager to verify COM port number

### "Print failed" Error

1. **Check printer connection**:
   - Network: Ping the printer IP address
   - USB: Check Windows Settings → Printers & scanners
   - COM: Check Device Manager

2. **Check printer name**:
   - Must match exactly (case-sensitive)
   - No extra spaces or special characters

3. **Try network printing**:
   - Network printing is more reliable on Windows
   - If your printer supports it, use network mode

### Printer Not Appearing in List

1. **For USB printers**:
   - Make sure printer is installed in Windows
   - Restart the POS app
   - Click "Scan for Printers" again

2. **For COM ports**:
   - Check Device Manager
   - Make sure printer driver is installed
   - Try unplugging and replugging the USB cable

### Test Print Works But Receipts Don't Print

- Check printer settings are saved
- Make sure you're using the same printer type (Network/USB) for both test and actual printing
- Try restarting the app

## Best Practices

1. **Use Network Printing When Possible**
   - Most reliable on Windows
   - Works even if USB connection is unstable
   - Multiple devices can use the same printer

2. **Keep Printer Name Exact**
   - Windows printer names are case-sensitive
   - Copy the exact name from Windows Settings

3. **Test After Changes**
   - Always use "Test Printer" after changing settings
   - This verifies the connection before printing receipts

## Technical Details

### How It Works

- **Network**: Sends raw ESC/POS data via TCP socket (port 9100)
- **USB (Windows Queue)**: Uses Windows print spooler with raw mode
- **COM Port**: Direct serial communication

### Limitations

- Bluetooth printing is not yet supported on Windows
- Some printers may require specific drivers
- COM port access may require administrator privileges

## Need Help?

If printing still doesn't work:
1. Check the error message in the app
2. Verify printer is working in Windows (try printing a test page)
3. Try network printing as an alternative
4. Check Windows Event Viewer for printer errors

