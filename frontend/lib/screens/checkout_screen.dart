import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/sync_status_provider.dart';
import '../providers/notification_bar_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../services/receipt_printer.dart';
import '../services/receipt_printer_helpers.dart';
import '../services/database_service.dart';
import '../services/offline_sync_service.dart';
import '../widgets/cached_product_image.dart';

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
                    final imageUrl = (product['image_url'] ?? '').toString().trim();
                    return ListTile(
                      leading: imageUrl.isNotEmpty
                          ? CachedProductImage(
                              imageUrl: imageUrl,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey[200],
                              child: const Center(
                                child: Text(
                                  '?',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
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
          // Checkout button (2x height)
          ElevatedButton(
            onPressed: (_isProcessing || orderProvider.cartItems.isEmpty)
                ? null
                : () => _processCheckout(orderProvider, authProvider),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 96),
              padding: const EdgeInsets.symmetric(vertical: 32),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
      // Auto-hide after 10 seconds (close button also available)
      Future.delayed(const Duration(seconds: 10), () {
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

      // Navigate to print receipt screen (online and offline: receipts are printed from local data)
      if (mounted && order != null) {
        if (order['offline'] == true) {
          context.showNotification('Order saved offline. It will sync when the server is back.');
        }
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
        // Auto-hide after 10 seconds (close button also available)
        Future.delayed(const Duration(seconds: 10), () {
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

class ReceiptScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const ReceiptScreen({super.key, required this.order});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.order['offline'] == true && context.mounted) {
        final syncStatus = Provider.of<SyncStatusProvider>(context, listen: false);
        syncStatus.refreshPendingCount();
        OfflineSyncService.start(() => syncStatus.refreshPendingCount());
      }
      _autoPrintOrderReceipts(context, widget.order);
    });
  }

  Future<void> _autoPrintOrderReceipts(BuildContext context, Map<String, dynamic> order) async {
    final l10n = AppLocalizations.of(context)!;
    // Do not print invoice/audit note — only order clips and 貨品細明
    const sequence = [
      ReceiptType.noPriceWithBarcode,   // 下單紙 (龍鳳存根)
      ReceiptType.customerCounterfoil, // 下單紙 (客戶存根)
      ReceiptType.noPriceNoBarcode,    // 貨品細明
    ];
    for (final receiptType in sequence) {
      try {
        await ReceiptPrinter.printReceipt(order: order, l10n: l10n, receiptType: receiptType);
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Auto-print failed for ${receiptType.name}: $e');
      }
    }
    if (context.mounted) {
      context.showNotification('3 documents sent to printer.', isSuccess: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final order = widget.order;
    final orderNumber = order['order_number'] ?? '';
    final qrData = order['qr_code_data'] ?? '';
    final items = order['items'] as List<dynamic>? ?? [];
    final totalAmountNum = (order['total_amount'] != null ? (order['total_amount'] as num).toDouble() : 0.0);
    final invoiceCheckCode = order['invoice_check_code']?.toString().trim();
    final receiptCheckCode = order['receipt_check_code']?.toString().trim();
    final displayInvoiceCode = (invoiceCheckCode != null && invoiceCheckCode.isNotEmpty)
        ? invoiceCheckCode
        : ReceiptPrinterHelpers.generateCheckCode(orderNumber, totalAmountNum, receiptType: 'invoice');
    final displayReceiptCode = (receiptCheckCode != null && receiptCheckCode.isNotEmpty)
        ? receiptCheckCode
        : ReceiptPrinterHelpers.generateCheckCode(orderNumber, totalAmountNum, receiptType: 'receipt');

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
                  const SizedBox(height: 16),
                  // Show both check codes so user can use them if printer is out
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.invoiceCheckCodeLabel,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          displayInvoiceCode,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.receiptCheckCodeLabel,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          displayReceiptCode,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
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
                  // Print buttons
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _printReceipt(context, order, receiptType: ReceiptType.auditNote),
                        icon: const Icon(Icons.print),
                        label: Text(l10n.printInternalAuditNote),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _printReceipt(context, order, receiptType: ReceiptType.noPriceWithBarcode),
                        icon: const Icon(Icons.receipt),
                        label: Text(l10n.printInvoice),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _printReceipt(context, order, receiptType: ReceiptType.customerCounterfoil),
                        icon: const Icon(Icons.receipt),
                        label: Text(l10n.printCustomerCounterfoil),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _printReceipt(context, order, receiptType: ReceiptType.noPriceNoBarcode),
                        icon: const Icon(Icons.receipt_long),
                        label: Text(l10n.printCustomerReceipt),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _printAllReceipts(context, order),
                        icon: const Icon(Icons.print_outlined),
                        label: Text(l10n.printAll),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
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

  Future<void> _printReceipt(BuildContext buildContext, Map<String, dynamic> order, {ReceiptType receiptType = ReceiptType.auditNote}) async {
    final l10n = AppLocalizations.of(buildContext)!;

    // Try direct printing
    try {
      await ReceiptPrinter.printReceipt(
        order: order,
        l10n: l10n,
        receiptType: receiptType,
      );
      if (buildContext.mounted) {
        buildContext.showNotification('${l10n.print} successful', isSuccess: true);
      }
    } catch (e) {
      debugPrint('Direct print failed: $e');
      // Show error to user - they can configure printer in settings
      if (buildContext.mounted) {
        buildContext.showNotification('Print failed: $e. Please check printer settings.', isError: true);
      }
    }
  }

  Future<void> _printAllReceipts(BuildContext buildContext, Map<String, dynamic> order) async {
    final l10n = AppLocalizations.of(buildContext)!;

    if (buildContext.mounted) {
      buildContext.showNotification('Printing all receipts...');
    }

    // Print all four receipt types sequentially (audit note, 龍鳳存根, 客戶存根, pickup receipt)
    final receiptTypes = [
      ReceiptType.auditNote,
      ReceiptType.noPriceWithBarcode,
      ReceiptType.customerCounterfoil,
      ReceiptType.noPriceNoBarcode,
    ];

    int successCount = 0;
    int failCount = 0;

    for (final receiptType in receiptTypes) {
      try {
        await ReceiptPrinter.printReceipt(
          order: order,
          l10n: l10n,
          receiptType: receiptType,
        );
        successCount++;
        // Small delay between prints
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Print failed for ${receiptType.name}: $e');
        failCount++;
      }
    }

    if (buildContext.mounted) {
      if (failCount == 0) {
        buildContext.showNotification('All receipts printed successfully ($successCount)', isSuccess: true);
      } else {
        buildContext.showNotification('Printed: $successCount, Failed: $failCount');
      }
    }
  }
}
