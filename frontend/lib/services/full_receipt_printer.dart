import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'receipt_printer_helpers.dart';

/// Full receipt printer - with price, with QR code
class FullReceiptPrinter {
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

    bytes += generator.hr();
    bytes += generator.feed(1);

    // Print receipt title
    final receiptTitle = '訂單收據 Order Receipt';
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      receiptTitle,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2),
    );
    bytes += generator.feed(1);

    // Order number and date
    final orderNumText = l10n.orderNumber(orderNumber);
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      orderNumText,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true),
    );
    final dateStr = DateTime.now().toString().split('.')[0];
    final dateText = l10n.date(dateStr);
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      dateText,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
    );
    bytes += generator.feed(1);
    bytes += generator.hr();

    // Items header
    final productHeader = 'Product 產品'.padRight(40, ' ');
    final qtyHeader = 'Qty';
    final subtotalHeader = 'Subtotal';
    final headerSpacing = ' ' * 10;
    final headerLine = '$productHeader$qtyHeader$headerSpacing$subtotalHeader';

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

      // Full receipt: product name, quantity, and price
      final quantityText = unitType == 'weight'
          ? '${quantity.toStringAsFixed(2)}g'
          : '${quantity.toStringAsFixed(0)} ';

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
      final lineTotal = '£ $integerWithCommas.$decimalPart';

      final productLineImageBytes = await _renderProductLineWithQtyPrice(
        productLine,
        quantityText,
        lineTotal,
        fontSize: 24,
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

    // Total
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

    // QR Code
    Uint8List? qrImage;

    if (orderNumber.isNotEmpty) {
      try {
        final qrCode = QrCode.fromData(
          data: orderNumber,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        );
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
      'Scan to confirm collection',
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
    bytes += generator.feed(1);

    bytes += generator.feed(2);
    bytes += generator.cut();

    // Send to printer
    await ReceiptPrinterHelpers.sendToPrinter(bytes, printerConfig);
  }

  /// Render product line with quantity and price
  static Future<Uint8List?> _renderProductLineWithQtyPrice(
    String productName,
    String qtyText,
    String priceText, {
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

      final charsPerLine = 34;
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
        final lastLineProduct = lines.last.padRight(charsPerLine, ' ');
        final lastLineText = '$lastLineProduct${qtyText.padLeft(5, " ")}${priceText.padLeft(16, ' ')}'; // Add qty and price

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

        final lastLineY = (lines.length - 1) * lineHeight;
        lastLinePainter.paint(canvas, Offset(0, lastLineY));
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

