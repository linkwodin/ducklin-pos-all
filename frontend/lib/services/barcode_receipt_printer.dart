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

/// Barcode receipt printer - with entry price and total, with barcode
class BarcodeReceiptPrinter {
  /// Format amount as £x,xxx.xx for receipt
  static String _formatCurrency(double value) {
    final str = value.toStringAsFixed(2);
    final parts = str.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '00';
    final integerWithCommas = integerPart.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match.group(1)},',
    );
    return '£$integerWithCommas.$decimalPart';
  }

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

    // receiptName used later for header above product list (printed once only)
    final receiptName = order['receipt_name']?.toString() ?? '';

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

    // Print order date and time
    final dateStr = ReceiptPrinterHelpers.formatOrderDateTime(order['created_at']);
    final dateText = l10n.date(dateStr);
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      dateText,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
    );
    bytes += generator.feed(1);

    // Print check code (for invoice) - use from database if available, otherwise generate
    String checkCode;
    if (order['invoice_check_code'] != null && order['invoice_check_code'].toString().isNotEmpty) {
      // Use check code from database
      checkCode = order['invoice_check_code'].toString();
    } else {
      // Fallback: generate check code (for backward compatibility)
      final totalAmountValue = order['total_amount'];
      final totalAmountNum = (totalAmountValue != null ? (totalAmountValue as num).toDouble() : 0.0);
      checkCode = ReceiptPrinterHelpers.generateCheckCode(orderNumber, totalAmountNum, receiptType: 'invoice');
    }
    final checkCodeText = 'Check Code: $checkCode';
    bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
      generator,
      checkCodeText,
      baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true),
    );
    bytes += generator.feed(1);

    bytes += generator.hr();
    bytes += generator.feed(1);

    // Header with Product and Qty (QTY right-aligned)
    // Print receipt name in header as two lines (use receipt name if available, otherwise use default)
    final headerName = receiptName.isNotEmpty ? receiptName : '下單紙 (龍鳳存根)\nOrder Clip (Loon Fung copy)';
    final headerLines = headerName.split('\n').where((l) => l.trim().isNotEmpty).toList();
    for (var i = 0; i < headerLines.length; i++) {
      final line = headerLines[i];
      bytes += await ReceiptPrinterHelpers.getTextBytesWithImage(
        generator,
        line,
        baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2),
      );
      // Only one line feed after the whole header block to avoid excess gap between lines
      if (i == headerLines.length - 1) bytes += generator.feed(1);
    }
    bytes += generator.hr();
    bytes += generator.feed(1);
    
    // Header: Product, Qty, Price (natural width, maxWidth 800)
    const int lineChars = 58;
    const int qtyWidth = 6;
    const int priceWidth = 10;
    final productHeader = 'Product 產品'.padRight(lineChars - qtyWidth - priceWidth, ' ');
    final headerLine = productHeader + 'Qty'.padLeft(qtyWidth, ' ') + 'Price'.padLeft(priceWidth, ' ');

    final headerWidth = _getHeaderLineWidth(headerLine);

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
      final unitPriceNum = (item['unit_price'] != null ? (item['unit_price'] as num).toDouble() : 0.0);
      final unitPriceText = _formatCurrency(unitPriceNum);

      final productLine = ReceiptPrinterHelpers.formatProductName(
        productNameChinese: productNameChinese,
        productNameEnglish: productNameEnglish,
      );

      // Format quantity text
      final quantityText = unitType == 'weight'
          ? '${quantity.toStringAsFixed(2)}g'
          : '${quantity.toStringAsFixed(0)} ';

      // With qty and price, with barcode: product line width = header width for alignment
      if (barcode.isNotEmpty) {
        final result = await _renderProductLineWithBarcode(
          productLine,
          barcode,
          quantityText,
          unitPriceText: unitPriceText,
          fontSize: 24,
          lineWidth: headerWidth,
        );
        if (result.textImage != null) {
          final textImg = await ReceiptPrinterHelpers.convertImageToEscPos(result.textImage!);
          if (textImg != null) {
            bytes += generator.image(textImg, align: esc_pos_utils.PosAlign.left);
          }
        }
        if (result.barcodeImage != null) {
          final barcodeImg = await ReceiptPrinterHelpers.convertImageToEscPos(result.barcodeImage!);
          if (barcodeImg != null) {
            bytes += generator.image(barcodeImg, align: esc_pos_utils.PosAlign.left);
          }
        }
      } else {
        // No barcode: product name with quantity, price
        final productLineImageBytes = await _renderProductLineSimple(
          productLine,
          quantityText,
          unitPriceText: unitPriceText,
          fontSize: 24,
          lineWidth: headerWidth,
        );
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

    // Generate and print QR code with order number and check code
    Uint8List? qrImage;
    if (orderNumber.isNotEmpty) {
      try {
        // Use check code from database for invoice, otherwise generate
        String checkCode;
        if (order['invoice_check_code'] != null && order['invoice_check_code'].toString().isNotEmpty) {
          // Use check code from database
          checkCode = order['invoice_check_code'].toString();
        } else {
          // Fallback: generate check code (for backward compatibility)
          final totalAmountValue = order['total_amount'];
          final totalAmountNum = (totalAmountValue != null ? (totalAmountValue as num).toDouble() : 0.0);
          checkCode = ReceiptPrinterHelpers.generateCheckCode(orderNumber, totalAmountNum, receiptType: 'invoice');
        }
        
        // QR code data format: "ORDER_NUMBER|CHECK_CODE|RECEIPT_TYPE"
        final qrData = '$orderNumber|$checkCode|invoice';
        
        final qrPainter = QrPainter(
          data: qrData,
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

  /// Column layout: 58 chars total (42 product, 6 qty, 10 price). Zones scale with line width.
  static const int _columnLineChars = 58;
  static const int _columnProductChars = 42;
  static const int _columnQtyChars = 6;
  static const int _columnPriceChars = 10;

  /// Measure header line width (same style as rendered header) to use as product line width.
  static double _getHeaderLineWidth(String headerLine, {double fontSize = 24}) {
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );
    final painter = TextPainter(
      text: TextSpan(text: headerLine, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: 800);
    return painter.width;
  }

  static double _productZoneWidth(double totalWidth) =>
      totalWidth * _columnProductChars / _columnLineChars;
  static double _qtyZoneWidth(double totalWidth) =>
      totalWidth * _columnQtyChars / _columnLineChars;
  static double _priceZoneWidth(double totalWidth) =>
      totalWidth * _columnPriceChars / _columnLineChars;

  /// Width of [count] space characters in [textStyle].
  static double _widthOfSpaces(int count, TextStyle textStyle) {
    final painter = TextPainter(
      text: TextSpan(text: ' ' * count, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter.width;
  }

  /// Render product line with barcode: text at [lineWidth] (header width) and barcode (464px).
  static Future<({Uint8List? textImage, Uint8List? barcodeImage})> _renderProductLineWithBarcode(
    String productName,
    String barcode,
    String quantityText, {
    String unitPriceText = '£0.00',
    double fontSize = 24,
    double lineWidth = 384.0,
  }) async {
    const int qtyWidth = 6;
    const int priceWidth = 10;
    Uint8List? textImage;
    Uint8List? barcodeImage;
    try {

      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.normal,
        color: Colors.black,
      );

      final gapBetweenQtyAndPrice = _widthOfSpaces(3, TextStyle(fontSize: fontSize, fontWeight: FontWeight.normal, color: Colors.black));
      final textLayoutWidth = lineWidth + gapBetweenQtyAndPrice;
      const double barcodeMaxWidth = 464.0;
      final charsPerLine = 42;
      final lineHeight = fontSize * 1.2;

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

      // 1) Text image: 384px (matches header) – name + qty + price
      final textHeight = (lines.length * lineHeight).toInt();
      final textRecorder = ui.PictureRecorder();
      final textCanvas = Canvas(textRecorder);
      textCanvas.drawRect(Rect.fromLTWH(0, 0, textLayoutWidth, textHeight.toDouble()), Paint()..color = Colors.white);

      for (int i = 0; i < lines.length - 1; i++) {
        final linePainter = TextPainter(
          text: TextSpan(text: lines[i], style: textStyle),
          textDirection: TextDirection.ltr,
        );
        linePainter.layout();
        linePainter.paint(textCanvas, Offset(0, i * lineHeight));
      }
      if (lines.isNotEmpty) {
        final lastLineY = (lines.length - 1) * lineHeight;
        final productZoneWidth = _productZoneWidth(lineWidth);
        final qtyZoneWidth = _qtyZoneWidth(lineWidth);
        final priceZoneWidth = _priceZoneWidth(lineWidth);

        final linePainter = TextPainter(
          text: TextSpan(text: lines.last, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        );
        linePainter.layout(maxWidth: productZoneWidth);
        linePainter.paint(textCanvas, Offset(0, lastLineY));

        final qtyPainter = TextPainter(
          text: TextSpan(text: quantityText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        qtyPainter.layout();
        final pricePainter = TextPainter(
          text: TextSpan(text: unitPriceText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        pricePainter.layout();
        qtyPainter.paint(textCanvas, Offset(productZoneWidth + qtyZoneWidth - qtyPainter.width, lastLineY));
        pricePainter.paint(textCanvas, Offset(productZoneWidth + qtyZoneWidth + gapBetweenQtyAndPrice, lastLineY));
      }

      final textPicture = textRecorder.endRecording();
      final textImg = await textPicture.toImage(textLayoutWidth.round(), textHeight);
      final textByteData = await textImg.toByteData(format: ui.ImageByteFormat.png);
      textImage = textByteData?.buffer.asUint8List();

      // 2) Barcode image: 464px
      final bcImage = await _generateBarcodeImage(barcode, barcodeMaxWidth);
      if (bcImage != null) {
        final bcRecorder = ui.PictureRecorder();
        final bcCanvas = Canvas(bcRecorder);
        final bcH = bcImage.height.toDouble();
        final bcW = bcImage.width.toDouble();
        bcCanvas.drawRect(Rect.fromLTWH(0, 0, barcodeMaxWidth, bcH), Paint()..color = Colors.white);
        bcCanvas.drawImage(bcImage, Offset((barcodeMaxWidth - bcW) / 2, 0), Paint());
        final bcPicture = bcRecorder.endRecording();
        final bcImg = await bcPicture.toImage(barcodeMaxWidth.toInt(), bcH.toInt());
        final bcByteData = await bcImg.toByteData(format: ui.ImageByteFormat.png);
        barcodeImage = bcByteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Error rendering product line with barcode: $e');
    }

    return (textImage: textImage, barcodeImage: barcodeImage);
  }

  /// Render simple product line with quantity and price (no barcode)
  static Future<Uint8List?> _renderProductLineSimple(
    String productName,
    String quantityText, {
    String unitPriceText = '£0.00',
    double fontSize = 24,
    double lineWidth = 384.0,
  }) async {
    const int qtyWidth = 6;
    const int priceWidth = 10;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.normal,
        color: Colors.black,
      );

      final gapBetweenQtyAndPrice = _widthOfSpaces(3, textStyle);
      final paperWidth = lineWidth + gapBetweenQtyAndPrice;
      final charsPerLine = 42;
      final lineHeight = fontSize * 1.2;

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

      // Last line: name in product zone, qty and price right-aligned in columns (same as header)
      if (lines.isNotEmpty) {
        final productZoneWidth = _productZoneWidth(lineWidth);
        final qtyZoneWidth = _qtyZoneWidth(lineWidth);
        final priceZoneWidth = _priceZoneWidth(lineWidth);
        final lastLineY = (lines.length - 1) * lineHeight;

        final lastLinePainter = TextPainter(
          text: TextSpan(text: lines.last, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        );
        lastLinePainter.layout(maxWidth: productZoneWidth);
        lastLinePainter.paint(canvas, Offset(0, lastLineY));

        final qtyPainter = TextPainter(
          text: TextSpan(text: quantityText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        qtyPainter.layout();
        final pricePainter = TextPainter(
          text: TextSpan(text: unitPriceText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        pricePainter.layout();
        qtyPainter.paint(canvas, Offset(productZoneWidth + qtyZoneWidth - qtyPainter.width, lastLineY));
        pricePainter.paint(canvas, Offset(productZoneWidth + qtyZoneWidth + gapBetweenQtyAndPrice, lastLineY));
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(paperWidth.round(), totalHeight.toInt());
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

