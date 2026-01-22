import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class OrderPickupScreen extends StatefulWidget {
  const OrderPickupScreen({super.key});

  @override
  State<OrderPickupScreen> createState() => _OrderPickupScreenState();
}

class _OrderPickupScreenState extends State<OrderPickupScreen> {
  final MobileScannerController controller = MobileScannerController();
  final TextEditingController _orderNumberController = TextEditingController();
  final FocusNode _orderNumberFocus = FocusNode();
  bool _isProcessing = false;
  String? _message;
  bool _isSuccess = false;
  bool _isWarning = false; // For warnings (already picked up) vs errors
  bool _useCamera = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the text field when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _orderNumberFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    _orderNumberController.dispose();
    _orderNumberFocus.dispose();
    super.dispose();
  }

  Future<void> _confirmPickup(String orderNumber) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _message = null;
      _isSuccess = false;
      _isWarning = false;
    });

    try {
      final response = await ApiService.instance.confirmOrderPickup(orderNumber);
      
      // Update local database with new order status
      try {
        final db = await DatabaseService.instance.database;
        final pickedUpAt = response['picked_up_at'] != null 
            ? DateTime.parse(response['picked_up_at']).millisecondsSinceEpoch 
            : DateTime.now().millisecondsSinceEpoch;
        
        final newStatus = response['status'] ?? 'completed';
        
        // Check if order exists in local database
        final existingOrder = await db.query(
          'orders',
          where: 'order_number = ?',
          whereArgs: [orderNumber],
          limit: 1,
        );
        
        if (existingOrder.isNotEmpty) {
          // Update existing order
          final rowsAffected = await db.update(
            'orders',
            {
              'status': newStatus,
              'picked_up_at': pickedUpAt,
            },
            where: 'order_number = ?',
            whereArgs: [orderNumber],
          );
          debugPrint('Updated local order status for $orderNumber: $rowsAffected row(s) affected');
          
          if (rowsAffected == 0) {
            debugPrint('Warning: No rows updated for order $orderNumber');
          }
        } else {
          // Order doesn't exist locally, save the pickup response data
          debugPrint('Order $orderNumber not found in local database, saving from pickup response...');
          try {
            // Save the order to local database using response data
            await DatabaseService.instance.saveOrder({
              'order_number': response['order_number'] ?? orderNumber,
              'store_id': response['store_id'] ?? 1,
              'user_id': response['user_id'] ?? 0,
              'sector_id': response['sector_id'],
              'subtotal': response['subtotal'] ?? 0.0,
              'discount_amount': response['discount_amount'] ?? 0.0,
              'total_amount': response['total_amount'] ?? 0.0,
              'status': newStatus,
              'qr_code_data': response['qr_code_data'],
              'created_at': response['created_at'] != null
                  ? DateTime.parse(response['created_at']).millisecondsSinceEpoch
                  : DateTime.now().millisecondsSinceEpoch,
              'picked_up_at': pickedUpAt,
              'synced': 1,
            });
            debugPrint('Saved order $orderNumber to local database');
          } catch (saveError) {
            debugPrint('Error saving order to local database: $saveError');
          }
        }
      } catch (e) {
        debugPrint('Error updating local database: $e');
        debugPrint('Stack trace: ${StackTrace.current}');
        // Continue even if local update fails
      }
      
      setState(() {
        _isSuccess = true;
        _message = 'Order $orderNumber picked up successfully!';
        _isProcessing = false;
      });

      // Clear input field
      _orderNumberController.clear();
      _orderNumberFocus.requestFocus();

      // Reset message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _message = null;
            _isSuccess = false;
            _isWarning = false;
          });
        }
      });
    } catch (e) {
      String errorMessage = 'Error: ${e.toString()}';
      bool isWarning = false;
      
      // Check if it's a DioException with "Order already picked up" error
      if (e is DioException && e.response?.statusCode == 400) {
        final errorData = e.response?.data;
        if (errorData is Map && errorData['error'] == 'Order already picked up') {
          // Extract pickup time from response
          final pickedUpAt = errorData['picked_up_at'];
          if (pickedUpAt != null) {
            try {
              final pickupTime = DateTime.parse(pickedUpAt);
              final formattedTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(pickupTime);
              errorMessage = 'Order $orderNumber was already picked up at $formattedTime';
              isWarning = true; // Show as warning (yellow/orange) instead of error (red)
            } catch (parseError) {
              errorMessage = 'Order $orderNumber was already picked up';
              isWarning = true;
            }
          } else {
            errorMessage = 'Order $orderNumber was already picked up';
            isWarning = true;
          }
        }
      }
      
      setState(() {
        _isSuccess = false;
        _isWarning = isWarning;
        _message = errorMessage;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderPickup ?? 'Order Pickup'),
        actions: [
          IconButton(
            icon: Icon(_useCamera ? Icons.keyboard : Icons.camera_alt),
            onPressed: () {
              setState(() {
                _useCamera = !_useCamera;
                if (_useCamera) {
                  _orderNumberFocus.unfocus();
                } else {
                  _orderNumberFocus.requestFocus();
                }
              });
            },
            tooltip: _useCamera ? 'Use Keyboard Input' : 'Use Camera Scanner',
          ),
          if (_useCamera)
            IconButton(
              icon: ValueListenableBuilder(
                valueListenable: controller.torchState,
                builder: (context, state, child) {
                  if (state == TorchState.on) {
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  } else {
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  }
                },
              ),
              onPressed: () => controller.toggleTorch(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Text input field for manual entry and barcode scanner
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.enterOrderNumber ?? 'Enter Order Number',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _orderNumberController,
                  focusNode: _orderNumberFocus,
                  decoration: InputDecoration(
                    hintText: l10n.scanOrEnterOrderNumber ?? 'Scan QR code or enter order number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.qr_code),
                    suffixIcon: _orderNumberController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _orderNumberController.clear();
                              _orderNumberFocus.requestFocus();
                            },
                          )
                        : null,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty && !_isProcessing) {
                      _confirmPickup(value.trim());
                      _orderNumberController.clear();
                    }
                  },
                  enabled: !_isProcessing,
                ),
              ],
            ),
          ),
          
          // Status message
          if (_message != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _isSuccess 
                  ? Colors.green 
                  : (_isWarning ? Colors.orange : Colors.red),
              child: Text(
                _message!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Camera scanner (optional)
          if (_useCamera)
            Expanded(
              child: Stack(
                children: [
                  MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      if (_isProcessing) return;
                      
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          final orderNumber = barcode.rawValue!;
                          _confirmPickup(orderNumber);
                          break;
                        }
                      }
                    },
                  ),
                  
                  // Instructions overlay for camera
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.qr_code_scanner,
                            size: 48,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.scanOrderQRCode ?? 'Scan Order QR Code',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.scanQRCodeToConfirmPickup ?? 'Scan the QR code on the invoice to confirm order pickup',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.scanOrEnterOrderNumber ?? 'Scan QR code or enter order number',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.useBarcodeScannerOrTypeManually ?? 'Use a barcode scanner or type the order number manually',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

