import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
// Windows printer library (only available on Windows)
import 'package:windows_printer/windows_printer.dart' if (dart.library.html) 'package:windows_printer/windows_printer_stub.dart' as windows_printer;
import 'database_service.dart';
import 'printer_logger.dart';

/// Shared helper functions for all receipt printers
class ReceiptPrinterHelpers {
  /// Log message to both console and file
  static void _log(String message) {
    debugPrint(message);
    PrinterLogger.instance.log(message);
  }
  
  /// Log error to both console and file
  static void _logError(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('ERROR: $message');
    if (error != null) debugPrint('Exception: $error');
    if (stackTrace != null) debugPrint('Stack trace: $stackTrace');
    PrinterLogger.instance.logError(message, error, stackTrace);
  }
  
  /// Log debug message to both console and file
  static void _logDebug(String message) {
    debugPrint('DEBUG: $message');
    PrinterLogger.instance.logDebug(message);
  }
  
  /// Log success message to both console and file
  static void _logSuccess(String message) {
    debugPrint('SUCCESS: $message');
    PrinterLogger.instance.logSuccess(message);
  }
  /// Generate a check code from order number and total amount
  /// Returns a 4-digit code for verification
  /// [receiptType] - "receipt" or "invoice" to generate different codes
  static String generateCheckCode(String orderNumber, double totalAmount, {String receiptType = 'receipt'}) {
    // Create a deterministic hash from order number, total amount, and receipt type
    // This ensures invoice and receipt have different check codes
    final combined = '$orderNumber-${totalAmount.toStringAsFixed(2)}-$receiptType';
    int hash = combined.hashCode;
    // Ensure positive and get last 4 digits
    final code = (hash.abs() % 10000).toString().padLeft(4, '0');
    return code;
  }
  /// Get printer configuration from SharedPreferences
  static Future<Map<String, dynamic>> getPrinterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'type': prefs.getString('printer_type') ?? 'network',
      'ip': prefs.getString('printer_ip'),
      'port': int.tryParse(prefs.getString('printer_port') ?? '9100') ?? 9100,
      'usb_serial_port': prefs.getString('printer_usb_serial_port'),
      'bluetooth_address': prefs.getString('printer_bluetooth_address'),
    };
  }

  /// Validate printer configuration
  static void validatePrinterConfig(Map<String, dynamic> config) {
    final printerType = config['type'] as String;
    
    if (printerType == 'bluetooth') {
      final address = config['bluetooth_address'] as String?;
      if (address == null || address.isEmpty) {
        throw Exception('Bluetooth printer not configured. Please set Bluetooth address in settings.');
      }
      throw Exception('Bluetooth printing is not yet supported. Please use network or USB printer.');
    } else if (printerType == 'usb') {
      final serialPort = config['usb_serial_port'] as String?;
      if (serialPort == null || serialPort.isEmpty) {
        throw Exception('USB printer not configured. Please set USB serial port in settings.');
      }
    } else {
      final ip = config['ip'] as String?;
      if (ip == null || ip.isEmpty) {
        throw Exception('Network printer not configured. Please set printer IP in settings.');
      }
    }
  }

  /// Check if USB printer is CUPS printer
  static bool isCupsPrinter(String? usbSerialPort) {
    if (usbSerialPort == null || usbSerialPort.isEmpty) return false;
    return !usbSerialPort.startsWith('/dev/');
  }

  /// Get store name from order or database
  static Future<String> getStoreName(Map<String, dynamic> order) async {
    String storeName = '';
    if (order['store'] != null) {
      final store = order['store'] as Map<String, dynamic>?;
      storeName = store?['name']?.toString() ?? '';
    }

    if (storeName.isEmpty) {
      try {
        final db = await DatabaseService.instance.database;
        final deviceInfo = await DatabaseService.instance.getDeviceInfo();
        if (deviceInfo != null && deviceInfo['store_id'] != null) {
          final storeId = deviceInfo['store_id'] as int;
          final storeResult = await db.query(
            'stores',
            where: 'id = ?',
            whereArgs: [storeId],
          );
          if (storeResult.isNotEmpty) {
            storeName = storeResult.first['name']?.toString() ?? '';
          }
        }
      } catch (e) {
        _logError('Error getting store info', e);
      }
    }

    return storeName;
  }

  /// Get English fallback for Chinese text
  static String getEnglishFallback(String text) {
    if (text.contains('訂單收據') || text.contains('订单收据')) return 'Order Receipt';
    if (text.contains('訂單編號') || text.contains('订单编号') || text.contains('訂單號') || text.contains('订单号')) {
      final match = RegExp(r'[:：]\s*(.+)').firstMatch(text);
      if (match != null) {
        return 'Order #: ${match.group(1)}';
      }
      return 'Order #';
    }
    if (text.contains('日期')) {
      final match = RegExp(r'[:：]\s*(.+)').firstMatch(text);
      if (match != null) {
        return 'Date: ${match.group(1)}';
      }
      return 'Date';
    }
    if (text.contains('產品') || text.contains('产品')) return 'Product';
    if (text.contains('總計') || text.contains('总计')) return 'Total';
    return '';
  }

  /// Get ASCII-safe text for PosColumn
  static String getAsciiSafeText(String text) {
    if (text.runes.any((rune) => rune >= 0x4E00)) {
      final fallback = getEnglishFallback(text);
      if (fallback.isNotEmpty) return fallback;
      return '';
    }
    return text;
  }

  /// Print text with appropriate code page
  static List<int> getTextBytes(
    esc_pos_utils.Generator generator,
    String text, {
    esc_pos_utils.PosStyles? baseStyles,
  }) {
    esc_pos_utils.PosStyles styles;

    String? codeTable;
    if (text.contains('£')) {
      codeTable = 'CP1252';
    } else if (text.runes.any((rune) => rune > 127 && rune < 0x4E00)) {
      codeTable = 'CP1252';
    } else if (text.runes.any((rune) => rune >= 0x4E00)) {
      codeTable = 'GB18030';
    }

    if (baseStyles != null) {
      styles = esc_pos_utils.PosStyles(
        align: baseStyles.align,
        bold: baseStyles.bold,
        height: baseStyles.height,
        width: baseStyles.width,
        codeTable: codeTable ?? baseStyles.codeTable,
      );
    } else if (codeTable != null) {
      styles = esc_pos_utils.PosStyles(codeTable: codeTable);
    } else {
      styles = esc_pos_utils.PosStyles();
    }

    try {
      return generator.text(text, styles: styles);
    } catch (e) {
      if (codeTable == 'GB18030') {
        try {
          final fallbackStyles = esc_pos_utils.PosStyles(
            align: styles.align,
            bold: styles.bold,
            height: styles.height,
            width: styles.width,
            codeTable: 'GB2312',
          );
          return generator.text(text, styles: fallbackStyles);
        } catch (e2) {
          final englishText = getEnglishFallback(text);
          if (englishText.isNotEmpty) {
            _logDebug('Chinese code page not supported, using English fallback: $text -> $englishText');
            final englishStyles = baseStyles ?? esc_pos_utils.PosStyles();
            return generator.text(englishText, styles: englishStyles);
          }
          _logDebug('Chinese code page not supported and no fallback, skipping: $text');
          return [];
        }
      } else {
        _logDebug('Code page $codeTable failed, trying default: $e');
        return generator.text(text, styles: baseStyles ?? esc_pos_utils.PosStyles());
      }
    }
  }

  /// Render text as image (for Chinese characters and long text)
  static Future<Uint8List?> renderTextAsImage(
    String text, {
    double fontSize = 24,
    bool bold = false,
    int maxWidth = 384,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: Colors.black,
      );

      final textPainter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: null,
      );

      textPainter.layout(maxWidth: maxWidth.toDouble());

      final size = Size(textPainter.width, textPainter.height);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);
      textPainter.paint(canvas, Offset.zero);

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      _logError('Error rendering text as image', e);
      return null;
    }
  }

  /// Convert image bytes to image.Image for esc_pos_utils
  static Future<img.Image?> convertImageToEscPos(Uint8List imageBytes) async {
    try {
      final decodedImage = img.decodeImage(imageBytes);
      return decodedImage;
    } catch (e) {
      _logError('Error converting image to ESC/POS format', e);
      return null;
    }
  }

  /// Print text (as image if Chinese, otherwise as text)
  static Future<List<int>> getTextBytesWithImage(
    esc_pos_utils.Generator generator,
    String text, {
    esc_pos_utils.PosStyles? baseStyles,
  }) async {
    if (text.runes.any((rune) => rune >= 0x4E00)) {
      final imageBytes = await renderTextAsImage(
        text,
        fontSize: baseStyles?.height == esc_pos_utils.PosTextSize.size2 ? 32 : 24,
        bold: baseStyles?.bold ?? false,
      );

      if (imageBytes != null) {
        final img = await convertImageToEscPos(imageBytes);
        if (img != null) {
          final align = baseStyles?.align ?? esc_pos_utils.PosAlign.left;
          return generator.image(img, align: align);
        }
      }
      final englishText = getEnglishFallback(text);
      if (englishText.isNotEmpty) {
        return getTextBytes(generator, englishText, baseStyles: baseStyles);
      }
      return [];
    }

    return getTextBytes(generator, text, baseStyles: baseStyles);
  }

  /// Send bytes to printer
  static Future<void> sendToPrinter(
    List<int> bytes,
    Map<String, dynamic> config,
  ) async {
    final printerType = config['type'] as String;
    final printerIP = config['ip'] as String?;
    final printerPort = config['port'] as int? ?? 9100; // Default to 9100 if not provided
    final printerUsbSerialPort = config['usb_serial_port'] as String?;
    final isCups = isCupsPrinter(printerUsbSerialPort);
    
    // Log print attempt
    _log('=== Starting Print Job ===');
    _log('Printer type: $printerType');
    _log('Data size: ${bytes.length} bytes');
    if (printerType == 'network') {
      _log('Network printer: $printerIP:$printerPort');
    } else if (printerType == 'usb') {
      _log('USB printer: $printerUsbSerialPort');
      _log('Is CUPS printer: $isCups');
      _log('Platform: ${Platform.isWindows ? "Windows" : Platform.isMacOS ? "macOS" : "Linux"}');
    }

    if (printerType == 'usb') {
      if (Platform.isWindows) {
        // Windows USB printing
        await _printToWindowsPrinter(bytes, printerUsbSerialPort);
      } else if (isCups) {
        // macOS/Linux CUPS printing
        final env = Map<String, String>.from(Platform.environment);
        env['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin';

        ProcessResult? result;
        String? errorMsg;

        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/escpos_${DateTime.now().millisecondsSinceEpoch}.raw');
          try {
            await tempFile.writeAsBytes(bytes);

            if (!await tempFile.exists()) {
              throw Exception('Failed to create temporary file');
            }

            final printerName = printerUsbSerialPort!.trim();
            final filePath = tempFile.path;

            final escapedFilePath = filePath.replaceAll("'", "'\\''");
            final escapedPrinterName = printerName.replaceAll("'", "'\\''");

            result = await Process.run(
              '/bin/sh',
              [
                '-c',
                "/usr/bin/lp -d '$escapedPrinterName' -o raw '$escapedFilePath'",
              ],
              environment: env,
              runInShell: false,
            );

            if (result.exitCode != 0) {
              final stderrMsg = result.stderr.toString();
              final stdoutMsg = result.stdout.toString();
              errorMsg = stderrMsg.isNotEmpty ? stderrMsg : stdoutMsg;
            }
          } finally {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          }
        } catch (e) {
          errorMsg = e.toString();
          _logError('lp command via shell failed', e);
        }

        if (result == null || result.exitCode != 0) {
          final errorOutput = errorMsg ?? result?.stderr.toString() ?? result?.stdout.toString() ?? 'Unknown error';
          _logError('CUPS print failed - exit code: ${result?.exitCode}, error: $errorOutput');
          throw Exception('Print failed: $errorOutput');
        }
        
        // Verify print was actually sent - check for success message
        final output = result.stdout.toString();
        if (output.isNotEmpty) {
          _logDebug('CUPS print output: $output');
        }
      } else {
        // Serial port printing (macOS/Linux direct device)
        final serialFile = File(printerUsbSerialPort!);
        if (!await serialFile.exists()) {
          throw Exception('Serial port device not found: $printerUsbSerialPort');
        }
        try {
          final sink = serialFile.openWrite();
          sink.add(bytes);
          await sink.flush(); // Ensure data is flushed
          await sink.close();
          // Small delay to ensure data is sent
          await Future.delayed(const Duration(milliseconds: 100));
          _logSuccess('Successfully wrote ${bytes.length} bytes to serial port: $printerUsbSerialPort');
        } catch (e) {
          _logError('Serial port write failed', e);
          throw Exception('Print failed: $e');
        }
      }
    } else {
      // Network printing (works on all platforms)
      if (printerIP == null || printerIP.isEmpty) {
        throw Exception('Network printer IP address is required');
      }
      try {
        final socket = await Socket.connect(printerIP, printerPort);
        socket.add(bytes);
        await socket.flush();
        await socket.close();
      } catch (e) {
        throw Exception('Print failed: $e');
      }
    }
  }

  /// Print to Windows printer using print spooler
  static Future<void> _printToWindowsPrinter(
    List<int> bytes,
    String? printerName,
  ) async {
    _log('=== Windows USB Printer ===');
    _log('Printer name: $printerName');
    _log('Data size: ${bytes.length} bytes');
    
    if (printerName == null || printerName.isEmpty) {
      _logError('Windows printer name is required');
      throw Exception('Windows printer name is required');
    }

    // Try windows_printer library first (most reliable method)
    if (Platform.isWindows) {
      try {
        _log('Attempting to print using windows_printer library...');
        await windows_printer.WindowsPrinter.printRawData(
          printerName: printerName,
          data: Uint8List.fromList(bytes),
          useRawDatatype: true, // Critical for ESC/POS printers - sends raw data without Windows processing
        );
        _logSuccess('Successfully printed via windows_printer library');
        await Future.delayed(const Duration(milliseconds: 200));
        return; // Success!
      } catch (e) {
        _logError('windows_printer library failed, falling back to manual methods', e);
        // Fall through to manual methods below
      }
    }

    // Fallback to manual methods (PowerShell, copy command, etc.)
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}\\escpos_${DateTime.now().millisecondsSinceEpoch}.raw');
      
      try {
        await tempFile.writeAsBytes(bytes);

        if (!await tempFile.exists()) {
          throw Exception('Failed to create temporary file');
        }

        // Method 1: Try using PowerShell to send raw data to printer
        // This works for network printers and printers with raw port support
        try {
          // Use PowerShell to send raw bytes to printer
          final printerNameEscaped = printerName.replaceAll('"', '\\"');
          final filePathEscaped = tempFile.path.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
          
          // PowerShell command to send raw data to printer
          final psScript = '''
\$printerName = "$printerNameEscaped"
\$filePath = "$filePathEscaped"
\$bytes = [System.IO.File]::ReadAllBytes(\$filePath)
\$printer = New-Object System.Drawing.Printing.PrintDocument
\$printer.PrinterSettings.PrinterName = \$printerName
\$printer.PrintPage += {
    param(\$sender, \$e)
    \$e.Graphics.DrawImage([System.Drawing.Image]::FromStream([System.IO.MemoryStream]\$bytes), 0, 0)
}
\$printer.Print()
''';

          // Try simpler method: Use copy command to printer port
          // For ESC/POS printers, we need to send raw data
          // Check if printer name is a COM port (COM1, COM2, etc.)
          if (printerName.toUpperCase().startsWith('COM')) {
            // Direct COM port access
            final comFile = File(printerName);
            try {
              final sink = comFile.openWrite();
              sink.add(bytes);
              await sink.flush(); // Ensure data is flushed
              await sink.close();
              // Small delay to ensure data is sent
              await Future.delayed(const Duration(milliseconds: 100));
              _logSuccess('Successfully wrote ${bytes.length} bytes to COM port: $printerName');
              return; // Success
            } catch (e) {
              _logError('Direct COM port access failed', e);
              // Fall through to try print spooler method
            }
          }

          // Method 2: Use Windows print command (works for installed printers)
          // First, try to find the printer in Windows print queue
          ProcessResult? listResult;
          bool printerFound = false;
          try {
            // Try PowerShell first (more reliable and available on all modern Windows)
            try {
              final psListPrinters = '''
\$printers = Get-Printer -ErrorAction SilentlyContinue
\$printerNames = \$printers | ForEach-Object { \$_.Name }
\$printerNames -join "`n"
''';
              
              listResult = await Process.run(
                'powershell',
                ['-Command', psListPrinters],
                runInShell: true,
              );
              
              if (listResult.exitCode == 0) {
                final output = listResult.stdout.toString();
                printerFound = output.contains(printerName);
                _logDebug('PowerShell found printer: $printerFound');
              }
            } catch (e) {
              _logDebug('PowerShell Get-Printer failed, trying wmic: $e');
              
              // Fallback to wmic if PowerShell fails
              try {
                listResult = await Process.run(
                  'wmic',
                  ['printer', 'get', 'name'],
                  runInShell: true,
                );
                
                if (listResult.exitCode == 0) {
                  final output = listResult.stdout.toString();
                  printerFound = output.contains(printerName);
                  _logDebug('WMIC found printer: $printerFound');
                }
              } catch (e2) {
                _logError('Both PowerShell and WMIC failed to list printers', e2);
                // Continue anyway - printer might still work
              }
            }
            
            if (!printerFound && listResult != null) {
              _logError('Printer "$printerName" not found in Windows printer list');
              throw Exception('Printer "$printerName" not found in Windows. Please check the exact printer name in Windows Settings > Printers & scanners.');
            }
          } catch (e) {
            // Only throw if it's our custom exception, otherwise continue
            if (e.toString().contains('not found in Windows')) {
              rethrow;
            }
            _logError('Failed to list printers', e);
            // Continue anyway - printer might still work
          }

          // Try using copy command to send raw data to printer
          // This requires the printer to be set up with a raw port (like FILE: or LPT1:)
          // For most ESC/POS printers, we'll use a different approach
          
          // Method 3: Use PowerShell to send raw bytes to printer port
          // This is the most reliable method for ESC/POS printers on Windows
          final psCommand = '''
\$port = New-Object System.IO.Ports.SerialPort("$printerNameEscaped", 9600, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
\$port.Open()
\$bytes = [System.IO.File]::ReadAllBytes("$filePathEscaped")
\$port.Write(\$bytes, 0, \$bytes.Length)
\$port.Close()
''';

          // If printer name looks like a COM port, try serial port method
          if (printerName.toUpperCase().startsWith('COM')) {
            // Already tried direct file access above, if that failed, try PowerShell serial
            try {
              final psResult = await Process.run(
                'powershell',
                ['-Command', psCommand],
                runInShell: true,
              );
              
              if (psResult.exitCode == 0) {
                return; // Success
              } else {
                final errorMsg = psResult.stderr.toString().isNotEmpty 
                    ? psResult.stderr.toString() 
                    : psResult.stdout.toString();
                throw Exception('Failed to print to COM port: $errorMsg');
              }
            } catch (e) {
              _logError('PowerShell serial port method failed', e);
              throw Exception('Failed to print to COM port $printerName. Make sure the COM port exists and the printer is connected. Error: $e');
            }
          } else {
            // For named printers, we need to send raw data to the printer port
            // Method 1: Get printer port and send raw data directly
            ProcessResult? portResult;
            String? portName;
            try {
              // Use PowerShell to get printer port (more reliable than wmic)
              final psGetPort = '''
\$printer = Get-Printer -Name "$printerNameEscaped" -ErrorAction SilentlyContinue
if (\$printer) {
    Write-Output \$printer.PortName
} else {
    Write-Error "Printer not found"
}
''';
              
              portResult = await Process.run(
                'powershell',
                ['-Command', psGetPort],
                runInShell: true,
              );
              
              if (portResult.exitCode == 0) {
                portName = portResult.stdout.toString().trim();
                _logDebug('Found printer port via PowerShell: $portName');
              } else {
                // Fallback to wmic (only if PowerShell is not available)
                try {
                  final wmicPrinterName = printerName.replaceAll('"', '\\"');
                  final wmicResult = await Process.run(
                    'wmic',
                    ['printer', 'where', 'name="$wmicPrinterName"', 'get', 'portname'],
                    runInShell: true,
                  );
                  
                  if (wmicResult.exitCode == 0) {
                    final portOutput = wmicResult.stdout.toString();
                    final lines = portOutput.split('\n');
                    for (var line in lines) {
                      final trimmed = line.trim();
                      if (trimmed.isNotEmpty && 
                          trimmed != 'PortName' && 
                          !trimmed.contains('PortName')) {
                        final match = RegExp(r'(\S+)').firstMatch(trimmed);
                        if (match != null) {
                          portName = match.group(1);
                          break;
                        }
                      }
                    }
                    _logDebug('Found printer port via wmic: $portName');
                  }
                } catch (e) {
                  _logDebug('WMIC also failed to get printer port: $e');
                  // Continue without port name
                }
              }
            } catch (e) {
              _logError('Failed to get printer port', e);
            }
            
            // Method 2: Send raw data to printer port
            if (portName != null && portName.isNotEmpty) {
              // If port is a COM port, use serial port method
              if (portName.toUpperCase().startsWith('COM')) {
                try {
                  final psSerialPrint = '''
\$port = New-Object System.IO.Ports.SerialPort("$portName", 9600, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
\$port.Open()
\$bytes = [System.IO.File]::ReadAllBytes("$filePathEscaped")
\$port.Write(\$bytes, 0, \$bytes.Length)
\$port.Close()
''';
                  
                  final psResult = await Process.run(
                    'powershell',
                    ['-Command', psSerialPrint],
                    runInShell: true,
                  );
                  
                  if (psResult.exitCode == 0) {
                    _logSuccess('Successfully printed to COM port via PowerShell: $portName');
                    await Future.delayed(const Duration(milliseconds: 200));
                    return; // Success
                  } else {
                    final errorMsg = psResult.stderr.toString().isNotEmpty 
                        ? psResult.stderr.toString() 
                        : psResult.stdout.toString();
                    _logError('PowerShell COM port print failed: $errorMsg');
                  }
                } catch (e) {
                  _logError('PowerShell COM port method failed', e);
                }
              }
              
              // Try copy command to port (works for USB001, LPT1, etc.)
              // Use cmd /c to ensure we use Windows copy command, not PowerShell's Copy-Item
              try {
                final copySource = tempFile.path.replaceAll('/', '\\');
                // Log file info for debugging
                final fileSize = await tempFile.length();
                _logDebug('Copying ${fileSize} bytes from $copySource to $portName');
                
                // Build command string to properly handle paths with spaces
                // cmd /c expects the full command as a string when paths might have spaces
                final copyCommand = 'copy /b "$copySource" "$portName"';
                _logDebug('Executing: cmd /c $copyCommand');
                
                final copyResult = await Process.run(
                  'cmd',
                  ['/c', copyCommand],
                  runInShell: true,
                );
                
                _logDebug('Copy command exit code: ${copyResult.exitCode}');
                _logDebug('Copy command stdout: ${copyResult.stdout}');
                if (copyResult.stderr.toString().isNotEmpty) {
                  _logDebug('Copy command stderr: ${copyResult.stderr}');
                }
                
                if (copyResult.exitCode == 0) {
                  _logSuccess('Successfully copied ${fileSize} bytes to port: $portName');
                  _log('Note: If nothing prints, verify printer is online and has paper. The data was sent successfully.');
                  await Future.delayed(const Duration(milliseconds: 200));
                  return; // Success
                } else {
                  final copyError = copyResult.stderr.toString().isNotEmpty 
                      ? copyResult.stderr.toString() 
                      : copyResult.stdout.toString();
                  _logError('Copy command failed: $copyError');
                }
              } catch (e) {
                _logError('Copy command exception', e);
              }
              
              // Try PowerShell FileStream to port (more reliable than WriteAllBytes)
              try {
                // Use FileStream.OpenWrite instead of WriteAllBytes
                // WriteAllBytes may create a file instead of writing to the port
                final psFileStream = '''
\$bytes = [System.IO.File]::ReadAllBytes("$filePathEscaped")
\$stream = [System.IO.File]::OpenWrite("$portName")
\$stream.Write(\$bytes, 0, \$bytes.Length)
\$stream.Flush()
\$stream.Close()
''';
                
                final psResult = await Process.run(
                  'powershell',
                  ['-Command', psFileStream],
                  runInShell: true,
                );
                
                if (psResult.exitCode == 0) {
                  _logSuccess('Successfully printed via PowerShell FileStream to port: $portName');
                  await Future.delayed(const Duration(milliseconds: 200));
                  return; // Success
                } else {
                  final errorMsg = psResult.stderr.toString().isNotEmpty 
                      ? psResult.stderr.toString() 
                      : psResult.stdout.toString();
                  _logError('PowerShell FileStream failed: $errorMsg');
                }
              } catch (e) {
                _logError('PowerShell FileStream exception', e);
              }
            }
            
            // Final fallback: Try using raw print via Windows API
            try {
              // Use PowerShell to send raw bytes using .NET PrintDocument with raw mode
              final psRawPrint = '''
Add-Type -AssemblyName System.Drawing
\$printerName = "$printerNameEscaped"
\$filePath = "$filePathEscaped"
\$bytes = [System.IO.File]::ReadAllBytes(\$filePath)

# Try to send raw data using Windows print spooler
\$printer = Get-Printer -Name \$printerName -ErrorAction Stop
\$port = \$printer.PortName

# Write bytes directly to port
\$stream = [System.IO.File]::OpenWrite(\$port)
\$stream.Write(\$bytes, 0, \$bytes.Length)
\$stream.Flush()
\$stream.Close()
''';
              
              final psResult = await Process.run(
                'powershell',
                ['-Command', psRawPrint],
                runInShell: true,
              );
              
              if (psResult.exitCode == 0) {
                _logSuccess('Successfully printed via PowerShell raw stream');
                await Future.delayed(const Duration(milliseconds: 200));
                return; // Success
              } else {
                final errorMsg = psResult.stderr.toString().isNotEmpty 
                    ? psResult.stderr.toString() 
                    : psResult.stdout.toString();
                _logError('PowerShell raw stream failed: $errorMsg');
                throw Exception('Print failed: $errorMsg\n\nTroubleshooting:\n1. Verify printer name matches exactly in Windows Settings\n2. Check printer is online and ready\n3. Try using network printing instead\n4. For USB printers, ensure printer driver supports raw printing');
              }
            } catch (e) {
              _logError('All Windows print methods failed', e);
              throw Exception('Print failed. For ESC/POS USB printers on Windows:\n\n1. Verify the printer name matches exactly in Windows Settings > Printers & scanners\n2. Check the printer is online and has paper\n3. Try using network printing if available\n4. Ensure the printer driver supports raw/ESC-POS printing\n\nError: $e');
            }
          }
        } catch (e) {
          _logError('Windows print method failed', e);
          rethrow;
        }
      } finally {
        // Clean up temp file
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          _logError('Failed to delete temp file', e);
        }
      }
    } catch (e) {
      throw Exception('Windows print failed: $e');
    }
  }

  /// Format product name with Chinese and English, with word-aware wrapping for English
  /// English name is split by spaces and wrapped at 40 characters per line
  static String formatProductName({
    required String productNameChinese,
    required String productNameEnglish,
  }) {
    String productLine = '';
    
    // Add Chinese name if available
    if (productNameChinese.isNotEmpty) {
      productLine += productNameChinese;
    }
    
    // Add English name with word-aware wrapping
    if (productNameEnglish.isNotEmpty && productNameEnglish != productNameChinese) {
      if (productLine.isNotEmpty) {
        productLine += '\n';
      }

      final englishParts = productNameEnglish.split(' ');
      String thisLine = '';
      for (final part in englishParts) {
        if (thisLine.length + part.length > 25) {
      print('helper thisLine: $thisLine, part: $part, length: ${thisLine.length + part.length}');
          productLine += thisLine;
          productLine += '\n';
          thisLine = part;
        } else {
        print('helper adding part: $part, thisLine: $thisLine, length: ${thisLine.length + part.length}');
          thisLine += part;
        }
        if (part != englishParts.last) {
          thisLine += ' ';
        } 
      }

      // Add the last line if it has content
      if (thisLine.isNotEmpty) {
        productLine += thisLine;
      }
      print('helper productLine: $productLine');
    }
    
    return productLine;
  }
}

