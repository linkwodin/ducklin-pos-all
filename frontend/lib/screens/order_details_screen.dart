import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/notification_bar_provider.dart';
import '../services/receipt_printer.dart';
import '../services/receipt_printer_helpers.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class OrderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailsScreen({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  Map<String, dynamic>? _order;
  bool _isLoading = false;
  bool _isPrinting = false;
  bool _orderUpdated = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    // If order doesn't have items, try to fetch from backend
    if (_order!['items'] == null || (_order!['items'] as List).isEmpty) {
      _loadOrderDetails();
    }
  }

  Future<void> _loadOrderDetails() async {
    final orderNumber = _order!['order_number']?.toString() ?? '';
    if (orderNumber.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final orderData = await ApiService.instance.getOrder(orderNumber);
      setState(() {
        _order = orderData;
        _isLoading = false;
      });

      // Update local database with the latest order data
      await _updateLocalDatabase(orderData);
    } catch (e) {
      // Offline or API error: try to load from local database
      try {
        final localOrder = await DatabaseService.instance.getOrderWithItemsByOrderNumber(orderNumber);
        if (localOrder != null) {
          setState(() {
            _order = localOrder;
            _isLoading = false;
          });
          return;
        }
      } catch (_) {}
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showNotification('Error loading order details: $e', isError: true);
      }
    }
  }

  Future<void> _confirmPickup() async {
    if (_order == null || _isLoading) return;

    final orderNumber = _order!['order_number']?.toString() ?? '';
    if (orderNumber.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Confirm pickup without check codes (optional validation)
      // Check codes are only required when scanning QR codes in the pickup screen
      await ApiService.instance.confirmOrderPickup(orderNumber);
      
      if (mounted) {
        // Reload full order details to ensure we have all data including items
        await _loadOrderDetails();
        _orderUpdated = true;
        
        context.showNotification('Order pickup confirmed successfully', isSuccess: true);
      }
    } catch (e) {
      // Network lost: update local DB so data is consistent when offline
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final updated = await DatabaseService.instance.updateOrderStatusByOrderNumber(
          orderNumber,
          status: 'completed',
          pickedUpAtMillis: now,
        );
        if (updated && mounted) {
          await _loadOrderDetails();
          _orderUpdated = true;
          setState(() => _isLoading = false);
          context.showNotification('Pickup recorded locally. Will sync when back online.');
          return;
        }
      } catch (_) {}
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showNotification('Error confirming pickup: $e', isError: true);
      }
    }
  }

  Future<void> _cancelOrder() async {
    if (_order == null || _isLoading) return;

    final orderId = _order!['id'];
    if (orderId == null) return;

    final l10n = AppLocalizations.of(context)!;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cancelOrder ?? 'Cancel Order'),
        content: Text(l10n.cancelOrderConfirmation ?? 'Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirm ?? 'Confirm'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.instance.cancelOrder(orderId);
      
      if (mounted) {
        // Reload full order details to ensure we have all data including items
        await _loadOrderDetails();
        _orderUpdated = true;
        
        context.showNotification('Order cancelled successfully', isSuccess: true);
      }
    } catch (e) {
      // Network lost: update local DB so data is consistent when offline
      final orderNumber = _order!['order_number']?.toString() ?? '';
      if (orderNumber.isNotEmpty) {
        try {
          final updated = await DatabaseService.instance.updateOrderStatusByOrderNumber(
            orderNumber,
            status: 'cancelled',
          );
          if (updated && mounted) {
            await _loadOrderDetails();
            _orderUpdated = true;
            setState(() => _isLoading = false);
            context.showNotification('Cancellation recorded locally. Will sync when back online.');
            return;
          }
        } catch (_) {}
      }
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showNotification('Error cancelling order: $e', isError: true);
      }
    }
  }

  Future<void> _updateLocalDatabase(Map<String, dynamic> orderData) async {
    try {
      final db = await DatabaseService.instance.database;
      final createdAt = orderData['created_at'] != null
          ? DateTime.parse(orderData['created_at']).millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch;
      final pickedUpAt = orderData['picked_up_at'] != null
          ? DateTime.parse(orderData['picked_up_at']).millisecondsSinceEpoch
          : null;

      await db.insert(
        'orders',
        {
          'order_number': orderData['order_number'],
          'store_id': orderData['store_id'] ?? 1,
          'user_id': orderData['user_id'] ?? 0,
          'sector_id': orderData['sector_id'],
          'subtotal': orderData['subtotal'] ?? 0.0,
          'discount_amount': orderData['discount_amount'] ?? 0.0,
          'total_amount': orderData['total_amount'] ?? 0.0,
          'status': orderData['status'] ?? 'pending',
          'qr_code_data': orderData['qr_code_data'],
          'created_at': createdAt,
          'picked_up_at': pickedUpAt,
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error updating order in local database: $e');
    }
  }

  /// Force upload this order to the backend (for offline orders with synced == 0).
  Future<void> _forceUploadOrder() async {
    if (_order == null || _isLoading) return;

    final orderNumber = _order!['order_number']?.toString() ?? '';
    if (orderNumber.isEmpty) return;

    final localOrder = await DatabaseService.instance.getOrderByOrderNumber(orderNumber);
    if (localOrder == null) return;
    if ((localOrder['synced'] ?? 1) != 0) {
      if (mounted) {
        context.showNotification('Order is already synced');
      }
      return;
    }

    final deviceCode = ApiService.instance.deviceCode;
    if (deviceCode == null || deviceCode.isEmpty) {
      if (mounted) {
        context.showNotification('Device not registered', isError: true);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final orderId = localOrder['id'] as int;
      final items = await DatabaseService.instance.getOrderItems(orderId);
      final createdAt = localOrder['created_at'];
      final created_at_iso = createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAt as int).toUtc().toIso8601String()
          : null;
      final orderData = {
        'store_id': localOrder['store_id'],
        'device_code': deviceCode,
        'sector_id': localOrder['sector_id'],
        'order_number': localOrder['order_number'],
        if (created_at_iso != null) 'created_at': created_at_iso,
        'items': items.map((item) => {
              'product_id': item['product_id'],
              'quantity': item['quantity'],
              'unit_type': item['unit_type'] ?? 'quantity',
            }).toList(),
      };
      await ApiService.instance.createOrder(orderData);
      await DatabaseService.instance.markOrderSynced(orderId);

      if (mounted) {
        await _loadOrderDetails();
        _orderUpdated = true;
        setState(() => _isLoading = false);
        context.showNotification('Order uploaded successfully', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String message = 'Upload failed';
        if (e is DioException && e.response?.data is Map<String, dynamic>) {
          final error = (e.response!.data as Map<String, dynamic>)['error']?.toString();
          if (error != null && error.isNotEmpty) {
            message = 'Upload failed: $error';
          }
        } else {
          message = 'Upload failed: $e';
        }
        context.showNotification(message, isError: true);
      }
    }
  }

  Future<void> _printReceipt(ReceiptType receiptType) async {
    if (_order == null || _isPrinting) return;

    final notificationProvider = context.read<NotificationBarProvider>();

    setState(() {
      _isPrinting = true;
    });

    try {
      final l10n = AppLocalizations.of(context)!;
      await ReceiptPrinter.printReceipt(
        order: _order!,
        l10n: l10n,
        receiptType: receiptType,
      );

      if (mounted) {
        notificationProvider.show('Receipt printed successfully', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        notificationProvider.show('Error printing receipt: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    
    DateTime dt;
    if (dateTime is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(dateTime);
    } else if (dateTime is String) {
      dt = DateTime.parse(dateTime);
    } else {
      return 'N/A';
    }
    
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  String _getProductName(Map<String, dynamic>? product, AppLocalizations l10n) {
    if (product == null) return 'Unknown Product';
    
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'zh') {
      return product['name_chinese']?.toString() ?? product['name']?.toString() ?? 'Unknown Product';
    }
    return product['name']?.toString() ?? product['name_chinese']?.toString() ?? 'Unknown Product';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'picked_up':
        return Colors.purple;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.orderDetails ?? 'Order Details'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_order == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.orderDetails ?? 'Order Details'),
        ),
        body: Center(child: Text(l10n.noOrdersFound)),
      );
    }

    final order = _order!;
    final orderNumber = order['order_number']?.toString() ?? 'N/A';
    final status = order['status']?.toString() ?? 'pending';
    final total = (order['total_amount'] ?? 0.0) as num;
    final subtotal = (order['subtotal'] ?? 0.0) as num;
    final discount = (order['discount_amount'] ?? 0.0) as num;
    final items = order['items'] as List<dynamic>? ?? [];
    final createdAt = order['created_at'];
    final paidAt = order['paid_at'];
    final completedAt = order['completed_at'];
    final pickedUpAt = order['picked_up_at'];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderDetails ?? 'Order Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Return true if order was updated to trigger refresh
            Navigator.of(context).pop(_orderUpdated);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Number and Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.orderNumber(orderNumber),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: _getStatusColor(status),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Force upload for offline (unsynced) orders
            if ((_order!['synced'] ?? 1) == 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : _forceUploadOrder,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Force upload'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action buttons for pending orders
            if (status.toLowerCase() == 'pending')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () async {
                            await _confirmPickup();
                          },
                          icon: const Icon(Icons.check_circle),
                          label: Text(l10n.confirmPickup ?? 'Confirm Pickup'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () async {
                            await _cancelOrder();
                          },
                          icon: const Icon(Icons.cancel),
                          label: Text(l10n.cancelOrder ?? 'Cancel Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Order Dates
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.orderInformation ?? 'Order Information',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(l10n.createdAt ?? 'Created At', _formatDateTime(createdAt)),
                    if (paidAt != null)
                      _buildInfoRow(l10n.paidAt ?? 'Paid At', _formatDateTime(paidAt)),
                    if (completedAt != null)
                      _buildInfoRow(l10n.completedAt ?? 'Completed At', _formatDateTime(completedAt)),
                    if (pickedUpAt != null)
                      _buildInfoRow(l10n.pickedUpAt ?? 'Picked Up At', _formatDateTime(pickedUpAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Order Items
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.orderItems ?? 'Order Items',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.noItemsFound ?? 'No items found'),
                      )
                    else
                      ...items.map((item) {
                        final product = item['product'] as Map<String, dynamic>?;
                        final quantity = (item['quantity'] ?? 0.0) as num;
                        final unitPrice = (item['unit_price'] ?? 0.0) as num;
                        final lineTotal = (item['line_total'] ?? 0.0) as num;
                        final unitType = product?['unit_type'] ?? 'quantity';
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getProductName(product, l10n),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${l10n.quantity}: ${unitType == 'weight' ? '${quantity.toStringAsFixed(2)}g' : quantity.toStringAsFixed(0)} @ £${unitPrice.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '£${lineTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Order Totals
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTotalRow(l10n.subtotal, subtotal),
                    if (discount > 0) _buildTotalRow(l10n.discount, -discount),
                    const Divider(),
                    _buildTotalRow(
                      l10n.total,
                      total,
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Print Buttons
            Text(
              l10n.printReceipts ?? 'Print Receipts',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _isPrinting ? null : () => _printReceipt(ReceiptType.noPriceWithBarcode),
                  icon: const Icon(Icons.receipt),
                  label: Text(l10n.printInvoice),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isPrinting ? null : () => _printReceipt(ReceiptType.customerCounterfoil),
                  icon: const Icon(Icons.receipt),
                  label: Text(l10n.printCustomerCounterfoil),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isPrinting ? null : () => _printReceipt(ReceiptType.noPriceNoBarcode),
                  icon: const Icon(Icons.receipt_long),
                  label: Text(l10n.printCustomerReceipt),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, num amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '£${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

