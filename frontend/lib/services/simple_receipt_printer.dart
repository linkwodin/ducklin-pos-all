import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'receipt_printer_helpers.dart';

/// Simple receipt printer - without price, without barcode
class SimpleReceiptPrinter {
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

      final productLine = ReceiptPrinterHelpers.formatProductName(
        productNameChinese: productNameChinese,
        productNameEnglish: productNameEnglish,
      );

      // Format quantity text
      final quantityText = unitType == 'weight'
          ? '${quantity.toStringAsFixed(2)}g'
          : '${quantity.toStringAsFixed(0)} ';

      // No price, no barcode - just product name with quantity
      final productLineImageBytes = await _renderProductLineSimple(productLine, quantityText, fontSize: 24);
      if (productLineImageBytes != null) {
        final productLineImg = await ReceiptPrinterHelpers.convertImageToEscPos(productLineImageBytes);
        if (productLineImg != null) {
          bytes += generator.image(productLineImg, align: esc_pos_utils.PosAlign.left);
        }
      }
    }

    bytes += generator.hr();
    bytes += generator.feed(1);
    bytes += generator.feed(2);
    bytes += generator.cut();

    // Send to printer
    await ReceiptPrinterHelpers.sendToPrinter(bytes, printerConfig);
  }

  /// Render simple product line with quantity
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
}

