import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'package:barcode/barcode.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'receipt_printer_helpers.dart';

/// Barcode receipt printer - without price, with barcode
class BarcodeReceiptPrinter {
  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required AppLocalizations l10n,
    required esc_pos_utils.Generator generator,
    required Map<String, dynamic> printerConfig,
  }) async {
    final storeName = await ReceiptPrinterHelpers.getStoreName(order);
    final items = order['items'] as List<dynamic>? ?? [];
    final orderNumber = order['order_number']?.toString() ?? '';

    List<int> bytes = [];
    bytes += generator.reset();

    // Print company name
    final companyName = '德靈公司 Ducklin Company';
    final companyImageBytes = await ReceiptPrinterHelpers.renderTextAsImage(
      companyName,
      fontSize: 28,
      bold: true,
      maxWidth: 800,
    );
    if (companyImageBytes != null) {
      final companyImg = await ReceiptPrinterHelpers.convertImageToEscPos(companyImageBytes);
      if (companyImg != null) {
        bytes += generator.image(companyImg, align: esc_pos_utils.PosAlign.center);
      } else {
        bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
          generator,
          companyName,
          baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2),
        );
      }
    } else {
      bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
        generator,
        companyName,
        baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2),
      );
    }
    bytes += generator.feed(1);

    // Print store name if available
    if (storeName.isNotEmpty) {
      final storeLine = 'Store - $storeName';
      bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
        generator,
        storeLine,
        baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true),
      );
      bytes += generator.feed(1);
    }

    // Print order number
    if (orderNumber.isNotEmpty) {
      final orderNumText = l10n.orderNumber(orderNumber);
      bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
        generator,
        orderNumText,
        baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true),
      );
      bytes += generator.feed(1);
    }

    bytes += generator.hr();
    bytes += generator.feed(1);

    // Header with Product and Qty
    final productHeader = 'Product 產品'.padRight(40, ' ');
    final qtyHeader = 'Qty';
    final headerSpacing = ' ' * 6;
    final headerLine = '$productHeader$qtyHeader$headerSpacing';
    
    final headerImageBytes = await ReceiptPrinterHelpers.renderTextAsImage(
      headerLine,
      fontSize: 24,
      bold: true,
      maxWidth: 800,
    );
    if (headerImageBytes != null) {
      final headerImg = await ReceiptPrinterHelpers.convertImageToEscPos(headerImageBytes);
      if (headerImg != null) {
        bytes += generator.image(headerImg, align: esc_pos_utils.PosAlign.left);
      } else {
        bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
          generator,
          headerLine,
          baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left, bold: true),
        );
      }
    } else {
      bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
        generator,
        headerLine,
        baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left, bold: true),
      );
    }
    bytes += generator.hr();

    // Order items
    for (var item in items) {
      final product = item['product'] as Map<String, dynamic>?;
      final quantityValue = item['quantity'];
      final quantity = (quantityValue != null ? (quantityValue as num).toDouble() : 0.0);
      final unitType = product?['unit_type'] ?? 'quantity';
      final productNameChinese = product?['name_chinese']?.toString() ?? '';
      final productNameEnglish = product?['name']?.toString() ?? '';
      final barcode = product?['barcode']?.toString() ?? '';

      final productLine = ReceiptPrinterHelpers.formatProductName(
        productNameChinese: productNameChinese,
        productNameEnglish: productNameEnglish,
      );

      // Format quantity text
      final quantityText = unitType == 'weight'
          ? '${quantity.toStringAsFixed(2)}g'
          : '${quantity.toStringAsFixed(0)} ';

      // No price, with barcode
      if (barcode.isNotEmpty) {
        final productLineImageBytes = await _renderProductLineWithBarcode(
          productLine,
          barcode,
          quantityText,
          fontSize: 24,
        );
        if (productLineImageBytes != null) {
          final productLineImg = await ReceiptPrinterHelpers.convertImageToEscPos(productLineImageBytes);
          if (productLineImg != null) {
            bytes += generator.image(productLineImg, align: esc_pos_utils.PosAlign.left);
          }
        }
      } else {
        // No barcode available, just print product name with quantity
        final productLineImageBytes = await _renderProductLineSimple(productLine, quantityText, fontSize: 24);
        if (productLineImageBytes != null) {
          final productLineImg = await ReceiptPrinterHelpers.convertImageToEscPos(productLineImageBytes);
          if (productLineImg != null) {
            bytes += generator.image(productLineImg, align: esc_pos_utils.PosAlign.left);
          }
        }
      }
    }

    bytes += generator.hr();
    bytes += generator.feed(1);

    // Generate and print QR code with order number
    Uint8List? qrImage;
    if (orderNumber.isNotEmpty) {
      try {
        final qrPainter = QrPainter(
          data: orderNumber,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          color: Colors.black,
          emptyColor: Colors.white,
        );

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        qrPainter.paint(canvas, const Size(200, 200));
        final picture = recorder.endRecording();
        final qrImageUi = await picture.toImage(200, 200);
        final qrByteData = await qrImageUi.toByteData(format: ui.ImageByteFormat.png);
        qrImage = qrByteData?.buffer.asUint8List();
      } catch (e) {
        debugPrint('Error generating QR code: $e');
      }
    }

    bytes += generator.text(
      'Scan to confirm pickup',
      styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, height: esc_pos_utils.PosTextSize.size1),
    );
    bytes += generator.feed(1);

    if (qrImage != null) {
      try {
        final qrImg = await ReceiptPrinterHelpers.convertImageToEscPos(qrImage);
        if (qrImg != null) {
          bytes += generator.feed(1);
          bytes += generator.image(qrImg, align: esc_pos_utils.PosAlign.center);
          bytes += generator.feed(1);
        } else {
          bytes += generator.text(
            'QR: $orderNumber',
            styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
          );
        }
      } catch (e) {
        debugPrint('Error printing QR code: $e');
        bytes += generator.text(
          'QR: $orderNumber',
          styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
        );
      }
    } else {
      bytes += generator.text(
        'QR: $orderNumber',
        styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
      );
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    // Send to printer
    await ReceiptPrinterHelpers.sendToPrinter(bytes, printerConfig);
  }

  /// Render product line with barcode and quantity
  static Future<Uint8List?> _renderProductLineWithBarcode(
    String productName,
    String barcode,
    String quantityText, {
    double fontSize = 24,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.normal,
        color: Colors.black,
      );

      final charsPerLine = 40;
      final lineHeight = fontSize * 1.2;
      final paperWidth = 384.0;

      List<String> lines = [];
      final nameParts = productName.split('\n');

      for (final part in nameParts) {
        if (part.isEmpty) continue;

        int currentIndex = 0;
        while (currentIndex < part.length) {
          int charsInLine = charsPerLine;
          if (currentIndex + charsPerLine > part.length) {
            charsInLine = part.length - currentIndex;
          }

          String line = part.substring(currentIndex, currentIndex + charsInLine);
          lines.add(line);
          currentIndex += charsInLine;
        }
      }

      final totalHeight = (lines.length + 1) * lineHeight; // +1 for barcode line

      canvas.drawRect(Rect.fromLTWH(0, 0, paperWidth, totalHeight), Paint()..color = Colors.white);

      // Draw product name lines
      for (int i = 0; i < lines.length; i++) {
        final linePainter = TextPainter(
          text: TextSpan(text: lines[i], style: textStyle),
          textDirection: TextDirection.ltr,
        );
        linePainter.layout();
        linePainter.paint(canvas, Offset(0, i * lineHeight));
      }

      // Generate barcode image
      try {
        final barcodeImage = await _generateBarcodeImage(barcode, paperWidth);
        if (barcodeImage != null) {
          // Draw barcode image below product name
          final barcodeHeight = barcodeImage.height.toDouble();
          final barcodeWidth = barcodeImage.width.toDouble();
          final barcodeX = (paperWidth - barcodeWidth) / 2; // Center the barcode
          final barcodeY = lines.length * lineHeight + 4; // Small gap after product name
          
          // Calculate total height including barcode (text is already in the barcode image)
          final finalHeight = (barcodeY + barcodeHeight).toInt();
          
          // Redraw canvas with correct height
          final newRecorder = ui.PictureRecorder();
          final newCanvas = Canvas(newRecorder);
          newCanvas.drawRect(Rect.fromLTWH(0, 0, paperWidth, finalHeight.toDouble()), Paint()..color = Colors.white);
          
          // Redraw product name lines
          for (int i = 0; i < lines.length; i++) {
            final linePainter = TextPainter(
              text: TextSpan(text: lines[i], style: textStyle),
              textDirection: TextDirection.ltr,
            );
            linePainter.layout();
            linePainter.paint(newCanvas, Offset(0, i * lineHeight));
          }
          
          // Draw quantity aligned to the very right on the last line
          if (lines.isNotEmpty) {
            final qtyPainter = TextPainter(
              text: TextSpan(text: quantityText, style: textStyle),
              textDirection: TextDirection.ltr,
            );
            qtyPainter.layout();
            final qtyX = paperWidth - qtyPainter.width; // Align to the very right
            final lastLineY = (lines.length - 1) * lineHeight;
            qtyPainter.paint(newCanvas, Offset(qtyX, lastLineY));
          }
          
          // Draw barcode image (already a ui.Image, no conversion needed)
          newCanvas.drawImage(barcodeImage, Offset(barcodeX, barcodeY), Paint());
          
          // Note: barcode text is already included in the barcode image, so we don't need to draw it separately
          
          final picture = newRecorder.endRecording();
          final image = await picture.toImage(paperWidth.toInt(), finalHeight);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          
          return byteData?.buffer.asUint8List();
        }
      } catch (e) {
        debugPrint('Error generating barcode image: $e');
        // Fallback to text if barcode generation fails
        final barcodePainter = TextPainter(
          text: TextSpan(text: barcode, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        barcodePainter.layout();
        barcodePainter.paint(canvas, Offset(0, lines.length * lineHeight));
      }
      
      // Draw quantity aligned to the very right on the last line (fallback when barcode fails)
      if (lines.isNotEmpty) {
        final qtyPainter = TextPainter(
          text: TextSpan(text: quantityText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        qtyPainter.layout();
        final qtyX = paperWidth - qtyPainter.width; // Align to the very right
        final lastLineY = (lines.length - 1) * lineHeight;
        qtyPainter.paint(canvas, Offset(qtyX, lastLineY));
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(paperWidth.toInt(), totalHeight.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error rendering product line with barcode: $e');
      return null;
    }
  }

  /// Render simple product line with quantity (no barcode)
  static Future<Uint8List?> _renderProductLineSimple(
    String productName,
    String quantityText, {
    double fontSize = 24,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.normal,
        color: Colors.black,
      );

      final charsPerLine = 40;
      final lineHeight = fontSize * 1.2;
      final paperWidth = 384.0;

      List<String> lines = [];
      final nameParts = productName.split('\n');

      for (final part in nameParts) {
        if (part.isEmpty) continue;

        int currentIndex = 0;
        while (currentIndex < part.length) {
          int charsInLine = charsPerLine;
          if (currentIndex + charsPerLine > part.length) {
            charsInLine = part.length - currentIndex;
          }

          String line = part.substring(currentIndex, currentIndex + charsInLine);
          lines.add(line);
          currentIndex += charsInLine;
        }
      }

      final totalHeight = lines.length * lineHeight;

      canvas.drawRect(Rect.fromLTWH(0, 0, paperWidth, totalHeight), Paint()..color = Colors.white);

      // Draw product name lines
      for (int i = 0; i < lines.length; i++) {
        final linePainter = TextPainter(
          text: TextSpan(text: lines[i], style: textStyle),
          textDirection: TextDirection.ltr,
        );
        linePainter.layout();
        linePainter.paint(canvas, Offset(0, i * lineHeight));
      }

      // Draw quantity aligned to the right on the last line
      if (lines.isNotEmpty) {
        final qtyPainter = TextPainter(
          text: TextSpan(text: quantityText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        qtyPainter.layout();
        final qtyX = paperWidth - qtyPainter.width;
        final lastLineY = (lines.length - 1) * lineHeight;
        qtyPainter.paint(canvas, Offset(qtyX, lastLineY));
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(paperWidth.toInt(), totalHeight.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error rendering product line: $e');
      return null;
    }
  }

  /// Generate barcode image from barcode string using Flutter canvas
  static Future<ui.Image?> _generateBarcodeImage(String barcode, double maxWidth) async {
    try {
      // Try Code128 first (most common, supports alphanumeric)
      Barcode bc = Barcode.code128();
      
      // Validate barcode
      if (!bc.isValid(barcode)) {
        // Try EAN13 if Code128 fails (numeric only)
        if (RegExp(r'^\d+$').hasMatch(barcode) && barcode.length == 13) {
          bc = Barcode.ean13();
        } else if (RegExp(r'^\d+$').hasMatch(barcode) && barcode.length == 8) {
          // Try EAN8 for 8-digit numeric codes
          bc = Barcode.ean8();
        } else {
          debugPrint('Invalid barcode format: $barcode');
          return null;
        }
      }

      // Generate SVG and parse it to extract bar positions
      final svg = bc.toSvg(barcode, width: maxWidth, height: 100.0);
      debugPrint('Generated SVG length: ${svg.length}');
      
      // The barcode package generates SVG with <path> elements, not <rect>
      // Path format: M x y h width v height h -width z
      // Example: M 0.00000 0.00000 h 6.24390 v 75.00000 h -6.24390 z
      // This means: Move to (x,y), draw horizontal line (bar width), draw vertical line (bar height), go back, close
      
      // Find all path elements
      final pathPattern = RegExp(r'<path[^>]*d="([^"]*)"', multiLine: true);
      final pathMatches = pathPattern.allMatches(svg).toList();
      debugPrint('Found ${pathMatches.length} path elements in SVG');
      
      if (pathMatches.isEmpty) {
        debugPrint('No path elements found in SVG');
        return null;
      }
      
      // Parse path data to extract bars
      // Path data format: "M x y h width v height h -width z M x y h width ..."
      final bars = <Map<String, double>>[];
      final pathDataPattern = RegExp(r'M\s+([\d.]+)\s+([\d.]+)\s+h\s+([\d.]+)\s+v\s+([\d.]+)', multiLine: true);
      
      for (final pathMatch in pathMatches) {
        final pathData = pathMatch.group(1) ?? '';
        final barMatches = pathDataPattern.allMatches(pathData);
        
        for (final barMatch in barMatches) {
          final x = double.tryParse(barMatch.group(1) ?? '0') ?? 0.0;
          final y = double.tryParse(barMatch.group(2) ?? '0') ?? 0.0;
          final width = double.tryParse(barMatch.group(3) ?? '0') ?? 0.0;
          final height = double.tryParse(barMatch.group(4) ?? '0') ?? 0.0;
          
          if (width > 0 && height > 0) {
            bars.add({'x': x, 'y': y, 'width': width, 'height': height});
          }
        }
      }
      
      debugPrint('Parsed ${bars.length} bars from path data');
      
      if (bars.isEmpty) {
        debugPrint('No valid bars found after parsing');
        return null;
      }
      
      // Calculate dimensions
      final maxBarHeight = bars.map((b) => b['height'] ?? 0).reduce((a, b) => a > b ? a : b);
      final barHeight = maxBarHeight > 0 ? maxBarHeight.toInt() : (maxWidth * 0.25).toInt();
      final textHeight = 20.0; // Height for barcode text
      final totalHeight = (barHeight + textHeight).toInt();
      final width = maxWidth.toInt();

      // Create canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Draw white background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), totalHeight.toDouble()),
        Paint()..color = Colors.white,
      );

      // Draw barcode bars
      for (final bar in bars) {
        final x = bar['x'] ?? 0.0;
        final barWidth = bar['width'] ?? 0.0;
        final barY = bar['y'] ?? 0.0;
        final barH = bar['height'] ?? barHeight.toDouble();
        
        if (barWidth > 0) {
          canvas.drawRect(
            Rect.fromLTWH(x, barY, barWidth, barH),
            Paint()..color = Colors.black,
          );
        }
      }
      
      debugPrint('Drew ${bars.length} bars on canvas');

      // Draw barcode text below the bars
      final textPainter = TextPainter(
        text: TextSpan(
          text: barcode,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(maxWidth: maxWidth);
      textPainter.paint(
        canvas,
        Offset((maxWidth - textPainter.width) / 2, barHeight.toDouble() + 2),
      );

      // Convert to image
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, totalHeight);
      
      debugPrint('Generated barcode image: ${image.width}x${image.height}');
      return image;
    } catch (e, stackTrace) {
      debugPrint('Error generating barcode: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }
}

