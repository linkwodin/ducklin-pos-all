import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image/image.dart' as img;
// Removed printing package to resolve dependency conflict with esc_pos_utils
// PDF generation removed - using direct ESC/POS printing instead
// esc_pos_printer not used directly - using raw socket for network printing
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as bt;
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _isProcessing = false;
  Map<String, dynamic>? _order;
  String? _notificationMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderProvider = Provider.of<OrderProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.checkout),
      ),
      body: Stack(
        children: [
          _buildCheckoutForm(orderProvider, authProvider),
          if (_notificationMessage != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 6,
                color: Colors.red,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _notificationMessage!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () {
                          setState(() {
                            _notificationMessage = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckoutForm(
    OrderProvider orderProvider,
    AuthProvider authProvider,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Order items list
          if (orderProvider.cartItems.isNotEmpty) ...[
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.product,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(),
                  ...orderProvider.cartItems.map((item) {
                    final product = item['product'] as Map<String, dynamic>;
                    final quantity = (item['quantity'] as num).toDouble();
                    final unitType = product['unit_type'] ?? 'quantity';
                    return ListTile(
                      leading: product['image_url'] != null
                          ? Image.network(product['image_url'], width: 50, height: 50)
                          : const Icon(Icons.image),
                      title: Text(_getProductName(product, context)),
                      subtitle: Text(
                        unitType == 'weight'
                            ? l10n.weightDisplay(quantity.toStringAsFixed(2))
                            : l10n.qty(quantity.toStringAsFixed(0)),
                      ),
                      trailing: Text(
                        '£${(item['line_total'] as num).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Order summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSummaryRow(l10n.subtotal, orderProvider.subtotal),
                  if (orderProvider.discountAmount > 0)
                    _buildSummaryRow(l10n.discount, -orderProvider.discountAmount, isDiscount: true),
                  const Divider(),
                  _buildSummaryRow(l10n.total, orderProvider.total, isTotal: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Checkout button
          ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () => _processCheckout(orderProvider, authProvider),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isProcessing
                ? const CircularProgressIndicator()
                : Text(l10n.processPayment),
          ),
        ],
      ),
    );
  }

  String _getProductName(Map<String, dynamic> product, BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final currentLocale = languageProvider.locale;
    
    // If locale is Chinese (zh_CN or zh_TW), use name_chinese if available
    if (currentLocale.languageCode == 'zh') {
      final nameChinese = product['name_chinese']?.toString();
      if (nameChinese != null && nameChinese.isNotEmpty) {
        return nameChinese;
      }
    }
    
    // Otherwise, use the English name
    return product['name']?.toString() ?? '';
  }

  Widget _buildSummaryRow(String label, double amount, {bool isDiscount = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 20 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '£${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 20 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDiscount ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processCheckout(
    OrderProvider orderProvider,
    AuthProvider authProvider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    
    if (orderProvider.storeId == null) {
      setState(() {
        _notificationMessage = l10n.storeNotSelected;
      });
      // Auto-hide after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _notificationMessage = null;
          });
        }
      });
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Try to get user ID from currentUser, or from SharedPreferences
      debugPrint('CheckoutScreen: Getting user ID...');
      debugPrint('CheckoutScreen: currentUser: ${authProvider.currentUser}');
      int? userId = authProvider.currentUser?['id'] as int?;
      debugPrint('CheckoutScreen: User ID from currentUser: $userId');
      
      if (userId == null) {
        final prefs = await SharedPreferences.getInstance();
        userId = prefs.getInt('user_id');
        debugPrint('CheckoutScreen: User ID from SharedPreferences: $userId');
      }
      
      // If still null, try to get from database - get the first active user as fallback
      // This is a workaround if user ID wasn't saved properly
      if (userId == null) {
        debugPrint('CheckoutScreen: User ID still null, trying database lookup...');
        try {
          final users = await DatabaseService.instance.getUsers();
          if (users.isNotEmpty) {
            // Use the first user as fallback (not ideal but better than failing)
            userId = users.first['id'] as int?;
            debugPrint('CheckoutScreen: Found user ID from database: $userId');
            // Save it for next time
            if (userId != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('user_id', userId);
            }
          }
        } catch (e) {
          debugPrint('CheckoutScreen: Error getting user from database: $e');
        }
      }
      
      if (userId == null) {
        debugPrint('CheckoutScreen: ERROR - User ID is null!');
        throw Exception(l10n.userNotAuthenticated);
      }
      
      debugPrint('CheckoutScreen: Final user ID: $userId');

      final deviceCode = ApiService.instance.deviceCode ?? '';
      debugPrint('CheckoutScreen: Calling checkout with userId: $userId, deviceCode: $deviceCode');
      final order = await orderProvider.checkout(userId, deviceCode);
      debugPrint('CheckoutScreen: Checkout successful, order: $order');

      setState(() {
        _isProcessing = false;
      });

      // Navigate to print receipt screen
      if (mounted && order != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(order: order!),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('CheckoutScreen: Error during checkout: $e');
      debugPrint('CheckoutScreen: Stack trace: $stackTrace');
      setState(() => _isProcessing = false);
      if (mounted) {
        setState(() {
          _notificationMessage = '${l10n.loginFailed}: $e';
        });
        // Auto-hide after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _notificationMessage = null;
            });
          }
        });
      }
    }
  }

}

class ReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const ReceiptScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderNumber = order['order_number'] ?? '';
    final qrData = order['qr_code_data'] ?? '';
    final items = order['items'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderReceipt),
      ),
      body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                    Text(
                      l10n.orderReceipt,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                    Text(l10n.orderNumber(orderNumber)),
                    const SizedBox(height: 24),
                    // Order items
                    if (items.isNotEmpty) ...[
                      const Divider(),
                      ...items.map((item) {
                        final product = item['product'] as Map<String, dynamic>?;
                        final quantity = (item['quantity'] as num).toDouble();
                        final unitType = product?['unit_type'] ?? 'quantity';
                        final productName = _getProductName(product ?? {}, context);
                        return ListTile(
                          title: Text(productName),
                          subtitle: Text(
                            unitType == 'weight'
                                ? l10n.weightDisplay(quantity.toStringAsFixed(2))
                                : l10n.qty(quantity.toStringAsFixed(0)),
                          ),
                          trailing: Text(
                            '£${(item['line_total'] as num).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.total,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '£${(order['total_amount'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  const SizedBox(height: 24),
                  if (qrData.isNotEmpty)
                    QrImageView(
                      data: qrData,
                      size: 200,
                    ),
                  const SizedBox(height: 24),
                      ElevatedButton.icon(
                      onPressed: () => _printReceipt(context, order),
                        icon: const Icon(Icons.print),
                      label: Text(l10n.print),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _getProductName(Map<String, dynamic> product, BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final currentLocale = languageProvider.locale;
    
    // If locale is Chinese (zh_CN or zh_TW), use name_chinese if available
    if (currentLocale.languageCode == 'zh') {
      final nameChinese = product['name_chinese']?.toString();
      if (nameChinese != null && nameChinese.isNotEmpty) {
        return nameChinese;
      }
    }
    
    // Otherwise, use the English name
    return product['name']?.toString() ?? '';
  }

  Future<void> _printReceipt(BuildContext buildContext, Map<String, dynamic> order) async {
    final l10n = AppLocalizations.of(buildContext)!;
    final languageProvider = Provider.of<LanguageProvider>(buildContext, listen: false);
    final currentLocale = languageProvider.locale;
    final items = order['items'] as List<dynamic>? ?? [];
    final orderNumber = order['order_number']?.toString() ?? '';
    
    // Helper function to get product name (without BuildContext)
    String getProductNameForPdf(Map<String, dynamic> product) {
      // If locale is Chinese (zh_CN or zh_TW), use name_chinese if available
      if (currentLocale.languageCode == 'zh') {
        final nameChinese = product['name_chinese']?.toString();
        if (nameChinese != null && nameChinese.isNotEmpty) {
          return nameChinese;
        }
      }
      // Otherwise, use the English name
      return product['name']?.toString() ?? '';
    }
    
    // Generate QR code image for the order number (for ESC/POS printing)
    final qrImage = await _generateQRCodeImage(orderNumber);

    // Try direct printing first (skip dialog)
    try {
      await _printDirectly(buildContext, order, orderNumber, items, getProductNameForPdf, qrImage, l10n);
    } catch (e) {
      debugPrint('Direct print failed: $e');
      // Show error to user - they can configure printer in settings
      if (buildContext.mounted) {
        ScaffoldMessenger.of(buildContext).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e. Please check printer settings.'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      // Note: PDF generation is still available, but printing dialog removed
      // to resolve dependency conflicts. Users should configure direct printing.
    }
  }
  
  Future<void> _printDirectly(
    BuildContext buildContext,
    Map<String, dynamic> order,
    String orderNumber,
    List<dynamic> items,
    String Function(Map<String, dynamic>) getProductNameForPdf,
    Uint8List? qrImage,
    AppLocalizations l10n,
  ) async {
    // Get printer settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final printerType = prefs.getString('printer_type') ?? 'network'; // 'network', 'bluetooth', or 'usb'
    final printerIP = prefs.getString('printer_ip');
    final printerPort = prefs.getInt('printer_port') ?? 9100;
    final printerBluetoothAddress = prefs.getString('printer_bluetooth_address');
    final printerUsbSerialPort = prefs.getString('printer_usb_serial_port');
    
    final profile = await esc_pos_utils.CapabilityProfile.load();
    final generator = esc_pos_utils.Generator(esc_pos_utils.PaperSize.mm80, profile);
    
    // Check if USB printer is CUPS printer (doesn't start with /dev/)
    bool isCupsPrinter = false;
    
    // Connect based on printer type
    if (printerType == 'bluetooth') {
      // Note: esc_pos_printer doesn't support Bluetooth directly
      // For now, throw an error and ask user to use network printing
      // TODO: Add esc_pos_bluetooth package for Bluetooth support
      throw Exception('Bluetooth printing not yet supported. Please use network or USB printing.');
    } else if (printerType == 'usb') {
      // USB printer via serial port or CUPS
      if (printerUsbSerialPort == null || printerUsbSerialPort.isEmpty) {
        throw Exception('USB printer not configured. Please set USB serial port in settings.');
      }
      
      // Check if this is a CUPS printer name (doesn't start with /dev/)
      isCupsPrinter = !printerUsbSerialPort.startsWith('/dev/');
    } else {
      // Network printer
      if (printerIP == null || printerIP.isEmpty) {
        throw Exception('Network printer not configured. Please set printer IP in settings.');
      }
    }
    
    // Helper function to get English fallback for Chinese text
    String getEnglishFallback(String text) {
      // Common Chinese phrases to English
      if (text.contains('訂單收據') || text.contains('订单收据')) return 'Order Receipt';
      if (text.contains('訂單編號') || text.contains('订单编号') || text.contains('訂單號') || text.contains('订单号')) {
        // Extract order number if present
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
      // If no match, return empty (will be handled by caller)
      return '';
    }
    
    // Helper function to get ASCII-safe text for PosColumn (which doesn't support code pages well)
    String getAsciiSafeText(String text) {
      if (text.runes.any((rune) => rune >= 0x4E00)) {
        // Contains Chinese - get English fallback
        final fallback = getEnglishFallback(text);
        if (fallback.isNotEmpty) return fallback;
        // If no fallback, return empty
        return '';
      }
      // For GBP, we'll handle it separately in PosColumn with codeTable
      return text;
    }
    
    // Helper function to print text with appropriate code page
    // Returns a list of bytes with code page selection if needed
    List<int> getTextBytes(String text, {esc_pos_utils.PosStyles? baseStyles}) {
      esc_pos_utils.PosStyles styles;
      
      // Determine code page based on text content
      String? codeTable;
      if (text.contains('£')) {
        // Use CP1252 for GBP sign (Western Europe code page)
        codeTable = 'CP1252';
      } else if (text.runes.any((rune) => rune > 127 && rune < 0x4E00)) {
        // Non-ASCII but not Chinese - try CP1252
        codeTable = 'CP1252';
      } else if (text.runes.any((rune) => rune >= 0x4E00)) {
        // Chinese characters - try GB18030 or GB2312 if printer supports
        // If that fails, fall back to English
        codeTable = 'GB18030'; // Try GB18030 first (more comprehensive)
      }
      
      // Merge base styles with code table
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
      
      // Try to print with the selected code page
      try {
        return generator.text(text, styles: styles);
      } catch (e) {
        // If code page fails, try fallback
        if (codeTable == 'GB18030') {
          try {
            // Try GB2312 as fallback
            final fallbackStyles = esc_pos_utils.PosStyles(
              align: styles.align,
              bold: styles.bold,
              height: styles.height,
              width: styles.width,
              codeTable: 'GB2312',
            );
            return generator.text(text, styles: fallbackStyles);
          } catch (e2) {
            // Chinese code pages not supported - use English fallback
            final englishText = getEnglishFallback(text);
            if (englishText.isNotEmpty) {
              debugPrint('Chinese code page not supported, using English fallback: $text -> $englishText');
              // Use base styles without code table for English
              final englishStyles = baseStyles ?? esc_pos_utils.PosStyles();
              return generator.text(englishText, styles: englishStyles);
            }
            debugPrint('Chinese code page not supported and no fallback, skipping: $text');
            return [];
          }
        } else {
          // For other code pages, just try without code table
          debugPrint('Code page $codeTable failed, trying default: $e');
          return generator.text(text, styles: baseStyles ?? esc_pos_utils.PosStyles());
        }
      }
    }
    
    // Helper function to render text as image (for Chinese characters and long text)
    // Default maxWidth: ~384 pixels for headers (full width)
    // For product names: 25 characters * ~8 pixels = ~200 pixels
    Future<Uint8List?> renderTextAsImage(String text, {double fontSize = 24, bool bold = false, int maxWidth = 384}) async {
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        
        // Create text style
        final textStyle = TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: Colors.black,
        );
        
        // Create text painter with word wrapping
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: null,
        );
        
        // Layout text with max width for wrapping
        textPainter.layout(maxWidth: maxWidth.toDouble());
        
        // Draw text on canvas
        final size = Size(textPainter.width, textPainter.height);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);
        textPainter.paint(canvas, Offset.zero);
        
        // Convert to image
        final picture = recorder.endRecording();
        final image = await picture.toImage(size.width.toInt(), size.height.toInt());
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        
        return byteData?.buffer.asUint8List();
      } catch (e) {
        debugPrint('Error rendering text as image: $e');
        return null;
      }
    }
    
    // Helper function to render product name with qty and subtotal on same line
    // Product name can wrap at 34 characters per line, but qty and subtotal stay together on the right
    // Last line of product name is padded to 40 characters for consistent alignment
    Future<Uint8List?> renderProductLineWithQtyPrice(String productName, String qtyText, String priceText, {double fontSize = 24}) async {
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        
        final textStyle = TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.normal,
          color: Colors.black,
        );
        
        // Calculate space needed for qty and price on the right
        final qtyPriceText = '${qtyText.padLeft(10, "+")} ---   $priceText'; 
        print("qtyPriceText" + qtyPriceText);
        final qtyPricePainter = TextPainter(
          text: TextSpan(text: qtyPriceText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        qtyPricePainter.layout();
        final qtyPriceWidth = qtyPricePainter.width;
        
        // Product name can have 40 characters per line
        // At 24px font, approximately 8 pixels per character = 272 pixels for 34 characters
        final productMaxWidth = 40 * 24; // 40 characters per line
        final charsPerLine = 40;
        final lineHeight = fontSize * 1.2; // Approximate line height
        
        // First split by newlines (to separate Chinese and English), then split each by 40 characters
        List<String> lines = [];
        final nameParts = productName.split('\n'); // Split Chinese and English
        
        for (final part in nameParts) {
          if (part.isEmpty) continue;
          
          // Split each part into lines of 40 characters
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
        
        // Calculate total height (all lines)
        final totalHeight = lines.length * lineHeight;
        final paperWidth = 384.0; // 80mm thermal paper width
        
        // Draw white background
        canvas.drawRect(Rect.fromLTWH(0, 0, paperWidth, totalHeight), Paint()..color = Colors.white);
        
        // Render all lines except the last one (if there are multiple lines)
        for (int i = 0; i < lines.length - 1; i++) {
          final linePainter = TextPainter(
            text: TextSpan(text: lines[i], style: textStyle),
            textDirection: TextDirection.ltr,
          );
          linePainter.layout();
          linePainter.paint(canvas, Offset(0, i * lineHeight));
        }
        
        // For the last line: pad product name to 40 chars, then add qty and price on same line
        double actualWidth = paperWidth;
        if (lines.isNotEmpty) {
          final lastLineProduct = lines.last.padRight(charsPerLine, ' '); // Pad to 40 chars
          final lastLineText = '$lastLineProduct${qtyText.padLeft(5, " ")}${priceText.padLeft(16, ' ')}'; // Add qty and price
          
          final lastLinePainter = TextPainter(
            text: TextSpan(text: lastLineText, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          lastLinePainter.layout();
          
          // Ensure canvas is wide enough for the last line
          final requiredWidth = lastLinePainter.width;
          actualWidth = requiredWidth > paperWidth ? requiredWidth : paperWidth;
          
          // Redraw background if width changed
          if (actualWidth > paperWidth) {
            canvas.drawRect(Rect.fromLTWH(0, 0, actualWidth, totalHeight), Paint()..color = Colors.white);
            // Redraw all previous lines
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
        
        // Convert to image
        final picture = recorder.endRecording();
        final image = await picture.toImage(actualWidth.toInt(), totalHeight.toInt());
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        
        return byteData?.buffer.asUint8List();
      } catch (e) {
        debugPrint('Error rendering product line with qty/price: $e');
        return null;
      }
    }
    
    // Helper function to convert image bytes to image.Image for esc_pos_utils
    Future<img.Image?> convertImageToEscPos(Uint8List imageBytes) async {
      try {
        // Decode image using image package
        final decodedImage = img.decodeImage(imageBytes);
        return decodedImage;
      } catch (e) {
        debugPrint('Error converting image to ESC/POS format: $e');
        return null;
      }
    }
    
    // Helper function to get currency text - render £ as image if needed
    Future<List<int>> getCurrencyBytes(String amount) async {
      // Check if amount contains £ symbol
      if (amount.contains('£')) {
        // Render £ symbol as image to ensure it prints correctly
        final currencyImageBytes = await renderTextAsImage(
          amount,
          fontSize: 20,
          bold: false,
          maxWidth: 200,
        );
        if (currencyImageBytes != null) {
          final currencyImg = await convertImageToEscPos(currencyImageBytes);
          if (currencyImg != null) {
            return generator.image(currencyImg, align: esc_pos_utils.PosAlign.right);
          }
        }
        // Fallback: try CP1252 code page
        return generator.text(amount, styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.right, codeTable: 'CP1252'));
      }
      // No £ symbol, use regular text
      return generator.text(amount, styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.right));
    }
    
    // Helper function to print text (as image if Chinese, otherwise as text)
    Future<List<int>> getTextBytesWithImage(String text, {esc_pos_utils.PosStyles? baseStyles}) async {
      // Check if text contains Chinese characters
      if (text.runes.any((rune) => rune >= 0x4E00)) {
        // Render as image for Chinese
        final imageBytes = await renderTextAsImage(
          text,
          fontSize: baseStyles?.height == esc_pos_utils.PosTextSize.size2 ? 32 : 24,
          bold: baseStyles?.bold ?? false,
        );
        
        if (imageBytes != null) {
          final img = await convertImageToEscPos(imageBytes);
          if (img != null) {
            // Print image with alignment
            final align = baseStyles?.align ?? esc_pos_utils.PosAlign.left;
            return generator.image(img, align: align);
          }
        }
        // If image rendering fails, fall back to English
        final englishText = getEnglishFallback(text);
        if (englishText.isNotEmpty) {
          return getTextBytes(englishText, baseStyles: baseStyles);
        }
        return [];
      }
      
      // For non-Chinese text, use regular text printing
      return getTextBytes(text, baseStyles: baseStyles);
    }
    
    // Get store name from order (comes from server)
    String storeName = '';
    if (order['store'] != null) {
      final store = order['store'] as Map<String, dynamic>?;
      storeName = store?['name']?.toString() ?? '';
    }
    
    // If store name not in order, try to get from database
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
    
    List<int> bytes = [];
    
    // Initialize printer
    bytes += generator.reset();
    
    // Print company name (bilingual) - ensure it stays on one line
    final companyName = '德靈公司 Ducklin Company';
    // Use smaller font or no wrapping to keep on one line
    final companyImageBytes = await renderTextAsImage(
      companyName,
      fontSize: 28,
      bold: true,
      maxWidth: 384, // Full width to prevent wrapping
    );
    if (companyImageBytes != null) {
      final companyImg = await convertImageToEscPos(companyImageBytes);
      if (companyImg != null) {
        bytes += generator.image(companyImg, align: esc_pos_utils.PosAlign.center);
      } else {
        bytes += await getTextBytesWithImage(companyName, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2));
      }
    } else {
      bytes += await getTextBytesWithImage(companyName, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2));
    }
    bytes += generator.feed(1);
    
    // Print store name if available
    if (storeName.isNotEmpty) {
      final storeLine = 'Store - $storeName';
      bytes += await getTextBytesWithImage(storeLine, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true));
      bytes += generator.feed(1);
    }
    
    bytes += generator.hr();
    bytes += generator.feed(1);
    
    // Print receipt title (bilingual)
    final receiptTitle = '訂單收據  Order Receipt';
    bytes += await getTextBytesWithImage(receiptTitle, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2));
    bytes += generator.feed(1);
    
    // Order number and date
    final orderNumText = l10n.orderNumber(orderNumber);
    bytes += await getTextBytesWithImage(orderNumText, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true));
    final dateStr = DateTime.now().toString().split('.')[0];
    final dateText = l10n.date(dateStr);
    bytes += await getTextBytesWithImage(dateText, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center));
    bytes += generator.feed(1);
    bytes += generator.hr();
    
    // Items header - show Product, Qty, and Subtotal
    // Product column: 34 characters (to match product line width)
    // Format: "Product 產品" (padded to 34 chars) + "Qty" + "Subtotal"
    final productHeader = 'Product 產品'.padRight(40, ' ');
    final qtyHeader = 'Qty';
    final subtotalHeader = 'Subtotal';
    // Slightly smaller gap so everything fits on one line
    final headerSpacing = ' ' * 10;
    final headerLine = '$productHeader$qtyHeader$headerSpacing$subtotalHeader';
    
    // Render header as image within paper width so it doesn't wrap
    final headerImageBytes = await renderTextAsImage(
      headerLine,
      fontSize: 24,
      bold: true,
      maxWidth: 800, // 80mm paper width
    );
    if (headerImageBytes != null) {
      final headerImg = await convertImageToEscPos(headerImageBytes);
      if (headerImg != null) {
        bytes += generator.image(headerImg, align: esc_pos_utils.PosAlign.left);
      } else {
        bytes += await getTextBytesWithImage(headerLine, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left, bold: true));
      }
    } else {
      bytes += await getTextBytesWithImage(headerLine, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left, bold: true));
    }
    // bytes += generator.feed(1);
    bytes += generator.hr();
    
    // Order items
    for (var item in items) {
      final product = item['product'] as Map<String, dynamic>?;
      final quantityValue = item['quantity'];
      final quantity = (quantityValue != null ? (quantityValue as num).toDouble() : 0.0);
      final unitType = product?['unit_type'] ?? 'quantity';
      
      // Get both Chinese and English names
      final productNameChinese = product?['name_chinese']?.toString() ?? '';
      final productNameEnglish = product?['name']?.toString() ?? '';
      
      final quantityText = unitType == 'weight'
          ? '${quantity.toStringAsFixed(2)}g'
          : '${quantity.toStringAsFixed(0)} ';
      
      // Format price with £ symbol and commas for thousands
      final lineTotalValue = item['line_total'];
      final lineTotalNum = (lineTotalValue != null ? (lineTotalValue as num).toDouble() : 0.0);
      final lineTotalFormatted = lineTotalNum.toStringAsFixed(2);
      // Add commas for thousands
      final parts = lineTotalFormatted.split('.');
      final integerPart = parts[0];
      final decimalPart = parts.length > 1 ? parts[1] : '00';
      final integerWithCommas = integerPart.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match.group(1)},',
      );
      final lineTotal = '£ $integerWithCommas.$decimalPart';
      
      // Combine product names: Chinese on one line, English on next line
      // Use newline to separate Chinese and English
      String productLine = '';
      if (productNameChinese.isNotEmpty) {
        productLine += productNameChinese;
      }
      if (productNameEnglish.isNotEmpty && productNameEnglish != productNameChinese) {
        if (productLine.isNotEmpty) {
          productLine += '\n'; // New line between Chinese and English
        }

        final englishParts = productNameEnglish.split(' ');
        print("englishParts " + englishParts.toString());
        for (final part in englishParts) {
          if (productLine.length + part.length > 40) {
            productLine += '\n';
          }
          productLine += part;
          if (part != englishParts.last) {
            productLine += ' ';
          } 
        }
        print("productLine " + productLine);
        // productLine += productNameEnglish;
      }
      
      // Render product name with qty and price on the same line
      // Product name can wrap if too long, but qty and price stay together on the right
      final productLineImageBytes = await renderProductLineWithQtyPrice(
        productLine,
        quantityText,
        lineTotal,
        fontSize: 24,
      );
      
      if (productLineImageBytes != null) {
        final productLineImg = await convertImageToEscPos(productLineImageBytes);
        if (productLineImg != null) {
          bytes += generator.image(productLineImg, align: esc_pos_utils.PosAlign.left);
        } else {
          // Fallback: print separately
          if (productLine.isNotEmpty) {
            bytes += getTextBytes(productLine, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left));
          }
          bytes += generator.text(
            ' ${quantityText.padLeft(10, "+")}      ===      ${lineTotal.replaceAll('£', 'GBP ')}',
            styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left, codeTable: 'CP1252'),
          );
          print("quantityText " + ' ${quantityText.padRight(10, "+")}      ===      ${lineTotal.replaceAll('£', 'GBP ')}');
        }
      } else {
        // Fallback: print separately
        if (productLine.isNotEmpty) {
          bytes += getTextBytes(productLine, baseStyles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left));
        }
        bytes += generator.text(
            ' ${quantityText.padLeft(10, "*")}      ===      ${lineTotal.replaceAll('£', 'GBP ')}',
          styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.left, codeTable: 'CP1252'),
        );
        print("quantityText2 " + ' ${quantityText.padRight(10, "*")}      ===      ${lineTotal.replaceAll('£', 'GBP ')}');
      }
      // Minimal spacing between items - use half feed
      // bytes += generator.feed(1);
    }
    
    bytes += generator.hr();
    bytes += generator.feed(1);
    
    // Total - render as image to ensure £ symbol prints correctly
    final totalLabel = "Total";
    final totalAmountValue = order['total_amount'];
    final totalAmountNum = (totalAmountValue != null ? (totalAmountValue as num).toDouble() : 0.0);
    final totalAmountFormatted = totalAmountNum.toStringAsFixed(2);
    // Add commas for thousands
    final totalParts = totalAmountFormatted.split('.');
    final totalIntegerPart = totalParts[0];
    final totalDecimalPart = totalParts.length > 1 ? totalParts[1] : '00';
    final totalIntegerWithCommas = totalIntegerPart.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match.group(1)},',
    );
    final totalAmount = '£ $totalIntegerWithCommas.$totalDecimalPart';
    
    // Build total line with proper spacing
    final labelLen = totalLabel.length;
    final amountLen = totalAmount.length;
    final totalLine = '$totalLabel${totalAmount.padLeft(55, ' ')}';
    
    // Render total line as image to ensure £ symbol prints correctly
    final totalImageBytes = await renderTextAsImage(
      totalLine,
      fontSize: 28,
      bold: true,
      maxWidth: 800,
    );
    
    if (totalImageBytes != null) {
      final totalImg = await convertImageToEscPos(totalImageBytes);
      if (totalImg != null) {
        bytes += generator.image(totalImg, align: esc_pos_utils.PosAlign.left);
      } else {
        // Fallback
        bytes += generator.row([
          esc_pos_utils.PosColumn(text: totalLabel, width: 8, styles: esc_pos_utils.PosStyles(bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
          esc_pos_utils.PosColumn(text: totalAmount.replaceAll('£', 'GBP '), width: 4, styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.right, bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
        ]);
      }
    } else {
      // Fallback
      bytes += generator.row([
        esc_pos_utils.PosColumn(text: totalLabel, width: 8, styles: esc_pos_utils.PosStyles(bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
        esc_pos_utils.PosColumn(text: totalAmount.replaceAll('£', 'GBP '), width: 4, styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.right, bold: true, height: esc_pos_utils.PosTextSize.size2, codeTable: 'CP1252')),
      ]);
    }
    bytes += generator.feed(2);
    
    // QR Code
    bytes += generator.text(
      'Scan to confirm collection',
      styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, height: esc_pos_utils.PosTextSize.size1),
    );
    bytes += generator.feed(1);
    // Print QR code
    if (qrImage != null) {
      try {
        // Convert QR code image to ESC/POS format
        final qrImg = await convertImageToEscPos(qrImage);
        if (qrImg != null) {
          // Center the QR code
          bytes += generator.feed(1);
          bytes += generator.image(qrImg, align: esc_pos_utils.PosAlign.center);
          bytes += generator.feed(1);
        } else {
          // Fallback to text if image conversion fails
          bytes += generator.text(
            'QR: $orderNumber',
            styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
          );
      }
    } catch (e) {
        debugPrint('Error printing QR code: $e');
        // Fallback to text
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
    
    // Send to printer based on connection type
    if (printerType == 'usb') {
      if (isCupsPrinter) {
        // Use CUPS lp command to print raw data
        // Try to pipe data directly to lp via stdin first
        final env = Map<String, String>.from(Platform.environment);
        env['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin';
        
        ProcessResult? result;
        String? errorMsg;
        
        try {
          // Try with temp file first (more reliable with sandbox)
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/escpos_${DateTime.now().millisecondsSinceEpoch}.raw');
          try {
            await tempFile.writeAsBytes(bytes);
            
            // Verify file was written
            if (!await tempFile.exists()) {
              throw Exception('Failed to create temporary file');
            }
            
            // Try using shell to execute lp (may help with sandbox)
            final printerName = printerUsbSerialPort!.trim();
            final filePath = tempFile.path;
            
            // Ensure file path is properly encoded and doesn't contain special characters
            // Escape any special characters in the file path
            final escapedFilePath = filePath.replaceAll("'", "'\\''");
            final escapedPrinterName = printerName.replaceAll("'", "'\\''");
            
            // Use shell to execute lp command with proper escaping
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
          
          // Fallback: try direct Process.start with stdin
          try {
            final process = await Process.start('/usr/bin/lp', [
              '-d', printerUsbSerialPort!.trim(),
              '-o', 'raw',
            ], environment: env, mode: ProcessStartMode.normal);
            
            // Read stderr in parallel
            final stderrFuture = process.stderr.toList();
            
            // Write bytes to stdin
            process.stdin.add(bytes);
            await process.stdin.close();
            
            // Wait for process to complete
            final exitCode = await process.exitCode;
            final stderr = await stderrFuture;
            final stderrStr = String.fromCharCodes(stderr.expand((list) => list));
            
            result = ProcessResult(
              process.pid,
              exitCode,
              '',
              stderrStr,
            );
            
            if (exitCode != 0) {
              errorMsg = stderrStr;
            }
          } catch (e2) {
            debugPrint('lp with stdin also failed: $e2');
            throw Exception('Failed to execute lp command: $errorMsg. Please ensure CUPS is installed and the app has necessary permissions. You may need to rebuild the app after adding print entitlements.');
          }
        }
        
        if (result == null) {
          throw Exception('lp command returned null result');
        }
        
        if (result.exitCode != 0) {
          final stderrMsg = errorMsg ?? result.stderr.toString();
          final stdoutMsg = result.stdout.toString();
          final finalErrorMsg = stderrMsg.isNotEmpty ? stderrMsg : stdoutMsg;
          
          debugPrint('lp command failed with exit code ${result.exitCode}');
          debugPrint('stderr: $stderrMsg');
          debugPrint('stdout: $stdoutMsg');
          
          throw Exception('Print failed: $finalErrorMsg');
        }
      } else {
        // USB printer via serial port (direct device access)
        final file = File(printerUsbSerialPort!);
        if (!await file.exists()) {
          throw Exception('USB serial port not found: $printerUsbSerialPort');
        }
        
        final raf = await file.open(mode: FileMode.write);
        try {
          await raf.writeFrom(bytes);
          await raf.flush();
        } finally {
          await raf.close();
        }
      }
    } else {
      // Network printer via raw socket
      final socket = await Socket.connect(printerIP!, printerPort);
      try {
        socket.add(bytes);
        await socket.flush();
      } finally {
        await socket.close();
      }
    }
  }
  
  Future<Uint8List?> _generateQRCodeImage(String data) async {
    try {
      // Validate QR code data
      final qrValidationData = QrValidator.validate(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );
      
      if (!qrValidationData.isValid) {
        debugPrint('Invalid QR code data: $data');
        return null;
      }
      
      final qrCode = qrValidationData.qrCode!;
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
        color: Colors.black,
        emptyColor: Colors.white,
      );
      
      // Render QR code to image
      const size = 200.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(size, size));
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error generating QR code: $e');
      return null;
    }
  }
}

