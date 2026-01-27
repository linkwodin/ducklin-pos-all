import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'database_service.dart';

/// Shared helper functions for all receipt printers
class ReceiptPrinterHelpers {
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
        debugPrint('Error getting store info: $e');
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
            debugPrint('Chinese code page not supported, using English fallback: $text -> $englishText');
            final englishStyles = baseStyles ?? esc_pos_utils.PosStyles();
            return generator.text(englishText, styles: englishStyles);
          }
          debugPrint('Chinese code page not supported and no fallback, skipping: $text');
          return [];
        }
      } else {
        debugPrint('Code page $codeTable failed, trying default: $e');
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
      debugPrint('Error rendering text as image: $e');
      return null;
    }
  }

  /// Convert image bytes to image.Image for esc_pos_utils
  static Future<img.Image?> convertImageToEscPos(Uint8List imageBytes) async {
    try {
      final decodedImage = img.decodeImage(imageBytes);
      return decodedImage;
    } catch (e) {
      debugPrint('Error converting image to ESC/POS format: $e');
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
    final printerPort = config['port'] as int;
    final printerUsbSerialPort = config['usb_serial_port'] as String?;
    final isCups = isCupsPrinter(printerUsbSerialPort);

    if (printerType == 'usb') {
      if (isCups) {
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
          debugPrint('lp command via shell failed: $e');
        }

        if (result == null || result.exitCode != 0) {
          throw Exception('Print failed: ${errorMsg ?? "Unknown error"}');
        }
      } else {
        // Serial port printing
        final serialFile = File(printerUsbSerialPort!);
        try {
          final sink = serialFile.openWrite();
          sink.add(bytes);
          await sink.close();
        } catch (e) {
          throw Exception('Print failed: $e');
        }
      }
    } else {
      // Network printing
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

