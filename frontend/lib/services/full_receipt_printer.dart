import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'receipt_printer_helpers.dart';

/// Full receipt printer - with or without price, with QR code (audit note = no price)
class FullReceiptPrinter {
  static const int _qtyColumnWidth = 8;

  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required AppLocalizations l10n,
    required esc_pos_utils.Generator generator,
    required Map<String, dynamic> printerConfig,
    bool includePrice = true,
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

    // Print receipt name if available
    final receiptName = order['receipt_name']?.toString() ?? '';
    if (receiptName.isNotEmpty) {
      bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
        generator,
        receiptName,
        baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size1),
      );
      bytes += generator.feed(1);
    }

    bytes += generator.hr();
    bytes += generator.feed(1);

    // Order number and date
    final orderNumText = l10n.orderNumber(orderNumber);
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      orderNumText,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true),
    );
    final dateStr = ReceiptPrinterHelpers.formatOrderDateTime(order['created_at']);
    final dateText = l10n.date(dateStr);
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      dateText,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
    );
    bytes += generator.feed(1);
    bytes += generator.hr();

    // Items header (QTY right-aligned in column)
    final headerName = receiptName.isNotEmpty ? receiptName : 'Order Receipt';
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      headerName,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2),
    );
    bytes += generator.feed(1);
    bytes += generator.hr();
    bytes += generator.feed(1);
    
    // Qty at the very right; when no price use full width (48+10 chars)
    const int lineChars = 58;
    final productHeader = 'Product 產品'.padRight(includePrice ? 40 : lineChars - 3, ' ');
    final qtyHeaderRight = 'Qty'.padLeft(_qtyColumnWidth, ' ');
    final headerLine = includePrice
        ? '$productHeader$qtyHeaderRight${' ' * 10}Subtotal'
        : '${productHeader}Qty';

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

      // Full receipt: product name, quantity (right-aligned), and optionally price
      final quantityText = unitType == 'weight'
          ? '${quantity.toStringAsFixed(2)}g'
          : '${quantity.toStringAsFixed(0)} ';

      String? lineTotal;
      if (includePrice) {
        final lineTotalValue = item['line_total'];
        final lineTotalNum = (lineTotalValue != null ? (lineTotalValue as num).toDouble() : 0.0);
        final lineTotalFormatted = lineTotalNum.toStringAsFixed(2);
        final parts = lineTotalFormatted.split('.');
        final integerPart = parts[0];
        final decimalPart = parts.length > 1 ? parts[1] : '00';
        final integerWithCommas = integerPart.replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match.group(1)},',
        );
        lineTotal = '£ $integerWithCommas.$decimalPart';
      }

      final productLineImageBytes = await _renderProductLineWithQtyPrice(
        productLine,
        quantityText,
        lineTotal,
        fontSize: 24,
        qtyColumnWidth: _qtyColumnWidth,
      );

      if (productLineImageBytes != null) {
        final productLineImg = await ReceiptPrinterHelpers.convertImageToEscPos(productLineImageBytes);
        if (productLineImg != null) {
          bytes += generator.image(productLineImg, align: esc_pos_utils.PosAlign.left);
        }
      }
    }

    bytes += generator.hr();
    bytes += generator.feed(1);

    // Total (only when includePrice)
    if (includePrice) {
      final totalLabel = "Total";
      final totalAmountValue = order['total_amount'];
      final totalAmountNum = (totalAmountValue != null ? (totalAmountValue as num).toDouble() : 0.0);
      final totalAmountFormatted = totalAmountNum.toStringAsFixed(2);
      final totalParts = totalAmountFormatted.split('.');
      final totalIntegerPart = totalParts[0];
      final totalDecimalPart = totalParts.length > 1 ? totalParts[1] : '00';
      final totalIntegerWithCommas = totalIntegerPart.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match.group(1)},',
      );
      final totalAmount = '£ $totalIntegerWithCommas.$totalDecimalPart';

      final totalLine = '$totalLabel${totalAmount.padLeft(55, ' ')}';

      final totalImageBytes = await ReceiptPrinterHelpers.renderTextAsImage(
        totalLine,
        fontSize: 28,
        bold: true,
        maxWidth: 800,
      );

      if (totalImageBytes != null) {
        final totalImg = await ReceiptPrinterHelpers.convertImageToEscPos(totalImageBytes);
        if (totalImg != null) {
          bytes += generator.image(totalImg, align: esc_pos_utils.PosAlign.left);
        } else {
          bytes += generator.row([
            esc_pos_utils.PosColumn(text: totalLabel, width: 8, styles: esc_pos_utils.PosStyles(bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
            esc_pos_utils.PosColumn(text: totalAmount.replaceAll('£', 'GBP '), width: 4, styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.right, bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
          ]);
        }
      } else {
        bytes += generator.row([
          esc_pos_utils.PosColumn(text: totalLabel, width: 8, styles: esc_pos_utils.PosStyles(bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
          esc_pos_utils.PosColumn(text: totalAmount.replaceAll('£', 'GBP '), width: 4, styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.right, bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
        ]);
      }
      bytes += generator.feed(2);
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    // Send to printer
    await ReceiptPrinterHelpers.sendToPrinter(bytes, printerConfig);
  }

  /// Render product line with quantity (right-aligned) and optional price
  static Future<Uint8List?> _renderProductLineWithQtyPrice(
    String productName,
    String qtyText,
    String? priceText, {
    double fontSize = 24,
    int qtyColumnWidth = 8,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.normal,
        color: Colors.black,
      );

      // Match header line width (58 chars) so Qty aligns at the very right when no price
      final charsPerLine = 41;
      final lineHeight = fontSize * 1.2;
      final paperWidth = 464.0; // 384 * 58/48

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

      for (int i = 0; i < lines.length - 1; i++) {
        final linePainter = TextPainter(
          text: TextSpan(text: lines[i], style: textStyle),
          textDirection: TextDirection.ltr,
        );
        linePainter.layout();
        linePainter.paint(canvas, Offset(0, i * lineHeight));
      }

      double actualWidth = paperWidth;
      if (lines.isNotEmpty) {
        final lastLineY = (lines.length - 1) * lineHeight;
        if (priceText == null) {
          // No price: draw product name left, qty at the very right
          final productPainter = TextPainter(
            text: TextSpan(text: lines.last, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          productPainter.layout();
          final qtyPainter = TextPainter(
            text: TextSpan(text: qtyText, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          qtyPainter.layout();
          productPainter.paint(canvas, Offset(0, lastLineY));
          final qtyX = paperWidth - qtyPainter.width;
          qtyPainter.paint(canvas, Offset(qtyX, lastLineY));
        } else {
          // With price: product + qty column + subtotal
          final lastLineProduct = lines.last.padRight(charsPerLine, ' ');
          final qtyRight = qtyText.padLeft(qtyColumnWidth, ' ');
          final lastLineText = '$lastLineProduct$qtyRight${priceText.padLeft(16, ' ')}';

          final lastLinePainter = TextPainter(
            text: TextSpan(text: lastLineText, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          lastLinePainter.layout();

          final requiredWidth = lastLinePainter.width;
          actualWidth = requiredWidth > paperWidth ? requiredWidth : paperWidth;

          if (actualWidth > paperWidth) {
            canvas.drawRect(Rect.fromLTWH(0, 0, actualWidth, totalHeight), Paint()..color = Colors.white);
            for (int i = 0; i < lines.length - 1; i++) {
              final linePainter = TextPainter(
                text: TextSpan(text: lines[i], style: textStyle),
                textDirection: TextDirection.ltr,
              );
              linePainter.layout();
              linePainter.paint(canvas, Offset(0, i * lineHeight));
            }
          }

          lastLinePainter.paint(canvas, Offset(0, lastLineY));
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(actualWidth.toInt(), totalHeight.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error rendering product line with qty/price: $e');
      return null;
    }
  }
}

