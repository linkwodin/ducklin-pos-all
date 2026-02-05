import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class OrderPickupScreen extends StatefulWidget {
  final Function(String)? onProductBarcodeScanned;
  
  const OrderPickupScreen({super.key, this.onProductBarcodeScanned});

  @override
  State<OrderPickupScreen> createState() => _OrderPickupScreenState();
}

class _OrderPickupScreenState extends State<OrderPickupScreen> {
  final MobileScannerController controller = MobileScannerController();

  // Scan input (raw QR string)
  final TextEditingController _scanInputController = TextEditingController();
  final FocusNode _scanInputFocus = FocusNode();
  String _lastProcessedValue = ''; // Track last processed value to avoid duplicate processing

  // Invoice text boxes (left-hand side)
  final TextEditingController _invoiceOrderController = TextEditingController();
  final TextEditingController _invoiceCheckController = TextEditingController();

  // Receipt text boxes (right-hand side)
  final TextEditingController _receiptOrderController = TextEditingController();
  final TextEditingController _receiptCheckController = TextEditingController();

  // Current order number (for header / editing)
  String? _currentOrderNumber;

  // Simple UI flow: step 1 = intro screen, step 2 = invoice/receipt screen
  int _uiStep = 1;

  bool _isProcessing = false;
  String? _message;
  bool _isSuccess = false;
  bool _isWarning = false; // For warnings (already picked up) vs errors
  bool _useCamera = false; // Camera disabled initially, enable when button is clicked
  bool _isDialogOpen = false; // Track if a dialog is currently open
  
  // Two-scan verification
  String? _firstScanOrderNumber; // From first QR code (invoice or receipt)
  String? _firstScanCheckCode; // First scan check code
  String? _firstScanReceiptType; // "invoice" or "receipt"
  String? _secondScanOrderNumber; // From second QR code (opposite type)
  String? _secondScanCheckCode; // Second scan check code
  String? _secondScanReceiptType; // "invoice" or "receipt"
  int _scanStep = 1; // 1 = first scan (any type), 2 = second scan (opposite type)

  @override
  void initState() {
    super.initState();
    // Auto-focus the text field when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanInputFocus.requestFocus();
    });
    
    // Listen to focus changes to keep the hidden text field focused
    _scanInputFocus.addListener(() {
      if (!_scanInputFocus.hasFocus && _uiStep == 1) {
        // Re-focus if we're in step 1 and lost focus
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_uiStep == 1 && !_useCamera) {
            _scanInputFocus.requestFocus();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    _scanInputController.dispose();
    _scanInputFocus.dispose();
    _invoiceOrderController.dispose();
    _invoiceCheckController.dispose();
    _receiptOrderController.dispose();
    _receiptCheckController.dispose();
    super.dispose();
  }

  void _handleQRCodeScan(String orderNumber, String checkCode, {String? receiptType, BuildContext? context}) {
    if (_isProcessing) return;

    // Only proceed if receipt type is explicitly provided
    if (receiptType == null) return;

    // Use the provided receipt type (don't default)
    final currentReceiptType = receiptType;

    if (_scanStep == 1) {
      // First scan - Accept either invoice or receipt QR code
      setState(() {
        _currentOrderNumber = orderNumber;
        _firstScanOrderNumber = orderNumber;
        _firstScanCheckCode = checkCode;
        _firstScanReceiptType = currentReceiptType;
        // Populate appropriate side based on type
        if (currentReceiptType == 'invoice') {
          _invoiceOrderController.text = orderNumber;
          _invoiceCheckController.text = checkCode;
          // Clear receipt side
          _receiptOrderController.clear();
          _receiptCheckController.clear();
        } else if (currentReceiptType == 'receipt') {
          _receiptOrderController.text = orderNumber;
          _receiptCheckController.text = checkCode;
          // Clear invoice side
          _invoiceOrderController.clear();
          _invoiceCheckController.clear();
        }
        _scanStep = 2;
        
        // Determine what to scan next (opposite type)
        final nextType = currentReceiptType == 'invoice' ? 'Receipt' : 'Invoice';
        _message = '${currentReceiptType == 'invoice' ? 'Invoice' : 'Receipt'} QR code scanned. Please scan the $nextType QR code from the same order.';
        _isSuccess = false;
        _isWarning = true; // Show as informational message (orange/yellow) instead of error
      });
      // Focus on order number field for second scan
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanInputFocus.requestFocus();
      });
    } else if (_scanStep == 2) {
      // Second scan - Must be the opposite type
      // Verify order number matches the first scan
      if (orderNumber != _firstScanOrderNumber) {
        setState(() {
          _message = 'Error: Order numbers do not match. First scan: $_firstScanOrderNumber, Second scan: $orderNumber. Please start over.';
          _isSuccess = false;
          _isWarning = false;
          // Reset to first scan
          _firstScanOrderNumber = null;
          _firstScanCheckCode = null;
          _firstScanReceiptType = null;
          _secondScanOrderNumber = null;
          _secondScanCheckCode = null;
          _secondScanReceiptType = null;
          _invoiceOrderController.clear();
          _invoiceCheckController.clear();
          _receiptOrderController.clear();
          _receiptCheckController.clear();
          _scanStep = 1;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scanInputFocus.requestFocus();
        });
        return;
      }

      // Verify it's the opposite receipt type
      if (currentReceiptType == _firstScanReceiptType) {
        // Same receipt type scanned twice - show warning but don't clear input
        final oppositeType = _firstScanReceiptType == 'invoice' ? 'Receipt' : 'Invoice';
        final warningMessage = 'Warning: You scanned the same ${_firstScanReceiptType == 'invoice' ? 'Invoice' : 'Receipt'} QR code again. Please scan the $oppositeType QR code from the same order.';
        
        // Show toast message
        if (context != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(warningMessage),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Close',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
        
        // Don't clear any input - keep the check codes that were already entered
        // Don't reset scan step - stay in step 2
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scanInputFocus.requestFocus();
        });
        return;
      }

      // Order numbers match and types are opposite - store second scan and proceed with pickup
      setState(() {
        _secondScanOrderNumber = orderNumber;
        _secondScanCheckCode = checkCode;
        _secondScanReceiptType = currentReceiptType;
      });

      // Complete pickup using both check codes (determine which is invoice and which is receipt)
      final invoiceCheckCode = _firstScanReceiptType == 'invoice' ? _firstScanCheckCode : checkCode;
      final receiptCheckCode = _firstScanReceiptType == 'receipt' ? _firstScanCheckCode : checkCode;

      _confirmPickupWithCheckCode(
        orderNumber, 
        null, // No single check code
        receiptType: null, // No single receipt type
        invoiceCheckCode: invoiceCheckCode,
        receiptCheckCode: receiptCheckCode,
        context: context,
      );
    }
  }

  Future<void> _confirmPickup(String orderNumber, checkCodeParam, {BuildContext? context}) async {
    if (_isProcessing) return;

    final checkCode = checkCodeParam?.toString().trim() ?? '';
    // If we're in two-scan mode, handle the scan
    if (_scanStep == 1) {
      // First scan - Accept either invoice or receipt QR code
      if (checkCode.isEmpty) {
        setState(() {
          _message = 'Please scan a complete QR code (with check code).';
          _isSuccess = false;
          _isWarning = false;
        });
        return;
      }
      // Receipt type will be determined from QR code or default to invoice
      _handleQRCodeScan(orderNumber, checkCode, context: context);
      return;
    } else if (_scanStep == 2) {
      // Second scan - Must be opposite type of first scan
      if (checkCode.isEmpty) {
        final expectedType = _firstScanReceiptType == 'invoice' ? 'Receipt' : 'Invoice';
        setState(() {
          _message = 'Please scan a complete $expectedType QR code (with check code).';
          _isSuccess = false;
          _isWarning = false;
        });
        return;
      }
      // Verify order number matches first scan
      if (orderNumber != _firstScanOrderNumber) {
        setState(() {
          _message = 'Error: Order numbers do not match. First scan: $_firstScanOrderNumber, Second scan: $orderNumber. Please start over.';
          _isSuccess = false;
          _isWarning = false;
          // Reset to first scan
          _firstScanOrderNumber = null;
          _firstScanCheckCode = null;
          _firstScanReceiptType = null;
          _secondScanOrderNumber = null;
          _secondScanCheckCode = null;
          _secondScanReceiptType = null;
          _scanStep = 1;
          _invoiceOrderController.clear();
          _invoiceCheckController.clear();
          _receiptOrderController.clear();
          _receiptCheckController.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scanInputFocus.requestFocus();
        });
        return;
      }
      // Order numbers match - proceed with pickup (receipt type will be determined from QR code)
      _handleQRCodeScan(orderNumber, checkCode, context: context);
      return;
    }

    // Legacy single-scan mode (shouldn't happen, but keep for safety)
    if (checkCode.isEmpty) {
      // If no check code provided, try both receipt types
      await _confirmPickupWithCheckCode(orderNumber, null, context: context);
      return;
    }

    // Try receipt first, then invoice
    await _confirmPickupWithCheckCode(orderNumber, checkCode, context: context);
  }

  Future<void> _confirmPickupWithCheckCode(
    String orderNumber, 
    String? checkCode, {
    String? receiptType,
    String? invoiceCheckCode,
    String? receiptCheckCode,
    BuildContext? context,
  }) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _message = null;
      _isSuccess = false;
      _isWarning = false;
    });

    try {
      // If both check codes are provided, use the new format
      if (invoiceCheckCode != null && invoiceCheckCode.isNotEmpty && 
          receiptCheckCode != null && receiptCheckCode.isNotEmpty) {
        final response = await ApiService.instance.confirmOrderPickup(
          orderNumber,
          invoiceCheckCode: invoiceCheckCode,
          receiptCheckCode: receiptCheckCode,
        );
        await _handlePickupSuccess(response, orderNumber);
        return;
      }
      
      // Legacy format: If receipt type not specified and check code provided, try both
      if (receiptType == null && checkCode != null && checkCode.isNotEmpty) {
        // Try receipt first
        try {
          final response = await ApiService.instance.confirmOrderPickup(
            orderNumber,
            checkCode: checkCode,
            receiptType: 'receipt',
          );
          await _handlePickupSuccess(response, orderNumber);
          return;
        } catch (e) {
          // If receipt fails, try invoice
          try {
            final response = await ApiService.instance.confirmOrderPickup(
              orderNumber,
              checkCode: checkCode,
              receiptType: 'invoice',
            );
            await _handlePickupSuccess(response, orderNumber);
            return;
          } catch (e2) {
            // Both failed, show error
            throw e2;
          }
        }
      }

      // Use specified receipt type or default
      final response = await ApiService.instance.confirmOrderPickup(
        orderNumber,
        checkCode: checkCode,
        receiptType: receiptType ?? 'receipt',
      );
      
      await _handlePickupSuccess(response, orderNumber);

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
        
        // If order is already picked up, go back to step 1
        if (isWarning && errorMessage.contains('already picked up')) {
          _uiStep = 1;
          _useCamera = false;
          _scanInputController.clear();
          _invoiceOrderController.clear();
          _invoiceCheckController.clear();
          _receiptOrderController.clear();
          _receiptCheckController.clear();
          _currentOrderNumber = null;
          _firstScanOrderNumber = null;
          _firstScanCheckCode = null;
          _firstScanReceiptType = null;
          _secondScanOrderNumber = null;
          _secondScanCheckCode = null;
          _secondScanReceiptType = null;
          _scanStep = 1;
          _lastProcessedValue = '';
          
          // Show toast message in step 1
          if (context != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Close',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ),
            );
          }
          
          // Re-focus the text field in step 1
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _uiStep == 1) {
              _scanInputFocus.requestFocus();
            }
          });
        } else if (context != null && mounted && _uiStep == 2) {
          // Show toast message in step 2 for all errors/warnings
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: isWarning ? Colors.orange : Colors.red,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Close',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      });
    }
  }

  void _tryAutoConfirmIfReady({BuildContext? context}) {
    final invoiceOrder = _invoiceOrderController.text.trim();
    final receiptOrder = _receiptOrderController.text.trim();
    final invoiceCode = _invoiceCheckController.text.trim();
    final receiptCode = _receiptCheckController.text.trim();

    if (invoiceOrder.isNotEmpty &&
        receiptOrder.isNotEmpty &&
        invoiceCode.isNotEmpty &&
        receiptCode.isNotEmpty &&
        invoiceOrder == receiptOrder &&
        !_isProcessing) {
      _confirmPickup(invoiceOrder, {
        'invoice': invoiceCode,
        'receipt': receiptCode,
      }, context: context);
    }
  }

  Future<void> _handlePickupSuccess(Map<String, dynamic> response, String orderNumber) async {
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

    // Clear input fields and reset scan step
    _scanInputController.clear();
    _invoiceOrderController.clear();
    _invoiceCheckController.clear();
    _receiptOrderController.clear();
    _receiptCheckController.clear();
    _currentOrderNumber = null;
    _firstScanOrderNumber = null;
    _firstScanCheckCode = null;
    _firstScanReceiptType = null;
    _secondScanOrderNumber = null;
    _secondScanCheckCode = null;
    _secondScanReceiptType = null;
    _scanStep = 1;
    _uiStep = 1; // Go back to first step after successful pickup
    _scanInputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    print('_scanStep $_scanStep');
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderPickup ?? 'Order Pickup'),
        leading: _uiStep == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _uiStep = 1;
                    _useCamera = false;
                    _scanInputController.clear();
                    _invoiceOrderController.clear();
                    _invoiceCheckController.clear();
                    _receiptOrderController.clear();
                    _receiptCheckController.clear();
                    _currentOrderNumber = null;
                    _firstScanOrderNumber = null;
                    _firstScanCheckCode = null;
                    _firstScanReceiptType = null;
                    _secondScanOrderNumber = null;
                    _secondScanCheckCode = null;
                    _secondScanReceiptType = null;
                    _scanStep = 1;
                    _message = null;
                    _isSuccess = false;
                    _isWarning = false;
                    _lastProcessedValue = '';
                  });
                  // Use a delayed callback to ensure widget tree is rebuilt
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && _uiStep == 1) {
                      _scanInputFocus.requestFocus();
                    }
                  });
                  // Also request focus immediately after setState
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _uiStep == 1) {
                      _scanInputFocus.requestFocus();
                    }
                  });
                },
              )
            : null,
        actions: _uiStep == 1
            ? null
            : [
                IconButton(
                  icon: Icon(_useCamera ? Icons.keyboard : Icons.camera_alt),
                  onPressed: () {
                    setState(() {
                      _useCamera = !_useCamera;
                      if (_useCamera) {
                        _scanInputFocus.unfocus();
                      } else {
                        _scanInputFocus.requestFocus();
                      }
                    });
                  },
                  tooltip: _useCamera ? 'Use Keyboard Input' : 'Use Camera Scanner',
                ),
                if (_useCamera)
                  IconButton(
                    icon: const Icon(Icons.flash_off, color: Colors.grey),
                    onPressed: () => controller.toggleTorch(),
                  ),
              ],
      ),
      body: _uiStep == 1
          ? _buildStepOne(context, l10n)
          : _buildStepTwo(context, l10n),
    );
  }

  Widget _buildStepOne(BuildContext context, AppLocalizations l10n) {
    // Ensure focus when step 1 is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_uiStep == 1 && !_useCamera && !_scanInputFocus.hasFocus) {
        _scanInputFocus.requestFocus();
      }
    });
    
    return Stack(
      children: [
        // Hidden text field for barcode scanner input (barcode scanners act as keyboard)
        Positioned(
          left: -1000,
          top: -1000,
          child: SizedBox(
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: Focus(
              onFocusChange: (hasFocus) {
                // Re-focus if we lost focus and we're in step 1
                if (!hasFocus && _uiStep == 1 && !_useCamera) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_uiStep == 1 && !_useCamera) {
                      _scanInputFocus.requestFocus();
                    }
                  });
                }
              },
              child: TextField(
                controller: _scanInputController,
                focusNode: _scanInputFocus,
                autofocus: true,
                enabled: !_useCamera, // Disable when camera is on
                onChanged: (value) {
                  // Don't process on every character change - wait for complete input
                  // Barcode scanners typically send all data at once, but we'll process in onSubmitted
                },
                onSubmitted: (value) {
                  // Process QR code when Enter is pressed (barcode scanners send Enter after data)
                  if (_isProcessing || _uiStep != 1 || value.isEmpty) return;
                  if (value == _lastProcessedValue) return;
                  
                  // Parse QR code format: "ORDER_NUMBER|CHECK_CODE|RECEIPT_TYPE"
                  // Handle both '|' and '｜' (full-width pipe) as separators
                  final normalizedValue = value.replaceAll('｜', '|');
                  
                  // If it doesn't contain pipes, it's likely a product barcode - navigate to create order page
                  if (!normalizedValue.contains('|') && value.trim().length >= 3) {
                    // Product barcode scanned - trigger navigation to create order page
                    if (widget.onProductBarcodeScanned != null) {
                      widget.onProductBarcodeScanned!(value.trim());
                    }
                    _scanInputController.clear();
                    _lastProcessedValue = '';
                    return;
                  }
                  
                  if (normalizedValue.contains('|')) {
                    final parts = normalizedValue.split('|');
                    if (parts.length >= 2) {
                      final orderNumber = parts[0].trim();
                      final checkCode = parts[1].trim();
                      final receiptTypeFromQR = parts.length >= 3 ? parts[2].trim().toLowerCase() : null;
                      
                      // Debug: print parsed values
                      debugPrint('Parsed QR code - Order: $orderNumber, Check: $checkCode, Type: $receiptTypeFromQR');
                      
                      if (orderNumber.isNotEmpty && checkCode.isNotEmpty) {
                        _lastProcessedValue = value;
                        // Transition to step 2 and populate fields
                        setState(() {
                          _uiStep = 2;
                          _currentOrderNumber = orderNumber;
                          if (receiptTypeFromQR == 'invoice') {
                            _invoiceOrderController.text = orderNumber;
                            _invoiceCheckController.text = checkCode;
                            // Clear receipt side
                            _receiptOrderController.clear();
                            _receiptCheckController.clear();
                          } else if (receiptTypeFromQR == 'receipt') {
                            _receiptOrderController.text = orderNumber;
                            _receiptCheckController.text = checkCode;
                            // Clear invoice side
                            _invoiceOrderController.clear();
                            _invoiceCheckController.clear();
                          }
                        });
                        // Handle the QR code scan only if receipt type is specified
                        if (receiptTypeFromQR != null) {
                          _handleQRCodeScan(orderNumber, checkCode, receiptType: receiptTypeFromQR, context: context);
                        }
                        _scanInputController.clear();
                        _lastProcessedValue = '';
                        // Re-focus after transition
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_uiStep == 2 && !_useCamera) {
                            _scanInputFocus.requestFocus();
                          }
                        });
                      }
                    }
                  }
                },
              ),
            ),
          ),
          ),
        ),
        // Visible UI
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Scan QR code button
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ElevatedButton(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            setState(() {
                              _uiStep = 2;
                              _useCamera = true;
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                    ),
                    child: Text(
                      l10n.scanQRCodeToConfirmPickup ?? 'Scan a QR code to confirm the pickup',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // OR separator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 120, height: 2, color: Colors.grey[400]),
                  const SizedBox(width: 16),
                  Text(
                    'OR',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(width: 120, height: 2, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 24),
              // Enter it manually button
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: OutlinedButton(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            setState(() {
                              _uiStep = 2;
                              _useCamera = false;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _scanInputFocus.requestFocus();
                            });
                          },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      l10n.enterItManually ?? 'Enter it manually',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepTwo(BuildContext context, AppLocalizations l10n) {
    // Ensure the hidden text field is focused when step 2 is shown and camera is off
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_uiStep == 2 && !_useCamera && !_scanInputFocus.hasFocus && !_isDialogOpen) {
        _scanInputFocus.requestFocus();
      }
    });
    
    return Stack(
      children: [
        // Hidden text field for barcode scanner input (always available, focused when camera is off)
        Positioned(
          left: -1000,
          top: -1000,
          child: SizedBox(
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: Focus(
                onFocusChange: (hasFocus) {
                  // Re-focus if we lost focus and camera is off, but not if a dialog is open
                  if (!hasFocus && _uiStep == 2 && !_useCamera && !_isDialogOpen) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_uiStep == 2 && !_useCamera && !_isDialogOpen) {
                        _scanInputFocus.requestFocus();
                      }
                    });
                  }
                },
                child: TextField(
                  enabled: !_useCamera, // Disable when camera is on
                  controller: _scanInputController,
                  focusNode: _scanInputFocus,
                  autofocus: true,
                  onChanged: (value) {
                    // Don't process on every character change - wait for complete input
                    // Barcode scanners typically send all data at once, but we'll process in onSubmitted
                  },
                  onSubmitted: (value) {
                    // Process QR code when Enter is pressed (barcode scanners send Enter after data)
                    if (_isProcessing || _uiStep != 2 || value.isEmpty) return;
                    if (value == _lastProcessedValue) return;
                    
                    // Parse QR code format: "ORDER_NUMBER|CHECK_CODE|RECEIPT_TYPE"
                    // Handle both '|' and '｜' (full-width pipe) as separators
                    final normalizedValue = value.replaceAll('｜', '|');
                    
                    // If it doesn't contain pipes, it's likely a product barcode - navigate to create order page
                    if (!normalizedValue.contains('|') && value.trim().length >= 3) {
                      // Product barcode scanned - trigger navigation to create order page
                      if (widget.onProductBarcodeScanned != null) {
                        widget.onProductBarcodeScanned!(value.trim());
                      }
                      _scanInputController.clear();
                      _lastProcessedValue = '';
                      return;
                    }
                    
                    if (normalizedValue.contains('|')) {
                      final parts = normalizedValue.split('|');
                      if (parts.length >= 2) {
                        final orderNumber = parts[0].trim();
                        final checkCode = parts[1].trim();
                        final receiptTypeFromQR = parts.length >= 3 ? parts[2].trim().toLowerCase() : null;
                        
                        // Debug: print parsed values
                        debugPrint('Parsed QR code (step 2) - Order: $orderNumber, Check: $checkCode, Type: $receiptTypeFromQR');
                        
                        if (orderNumber.isNotEmpty && checkCode.isNotEmpty) {
                          _lastProcessedValue = value;
                          // Populate appropriate side based on type - ONLY if receipt type is specified
                          setState(() {
                            _currentOrderNumber = orderNumber;
                            if (receiptTypeFromQR == 'invoice') {
                              _invoiceOrderController.text = orderNumber;
                              _invoiceCheckController.text = checkCode;
                              // Clear receipt side if invoice is scanned
                              _receiptOrderController.clear();
                              _receiptCheckController.clear();
                            } else if (receiptTypeFromQR == 'receipt') {
                              _receiptOrderController.text = orderNumber;
                              _receiptCheckController.text = checkCode;
                              // Clear invoice side if receipt is scanned
                              _invoiceOrderController.clear();
                              _invoiceCheckController.clear();
                            }
                            // If receiptTypeFromQR is null, don't populate anything
                          });
                          // Handle the QR code scan only if receipt type is specified
                          if (receiptTypeFromQR != null) {
                            _handleQRCodeScan(orderNumber, checkCode, receiptType: receiptTypeFromQR, context: context);
                          }
                          _scanInputController.clear();
                          _lastProcessedValue = '';
                          // Re-focus after clearing
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_uiStep == 2 && !_useCamera) {
                              _scanInputFocus.requestFocus();
                            }
                          });
                        }
                      }
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        // Visible UI - use Positioned.fill so Stack gives bounded constraints (Expanded is invalid in Stack)
        Positioned.fill(
          child: Column(
            children: [
            // Scan input and side-by-side invoice / receipt text boxes
            Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order number header (clickable to edit)
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Order number',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _isProcessing
                            ? null
                            : () async {
                                setState(() {
                                  _isDialogOpen = true;
                                });
                                _scanInputFocus.unfocus(); // Unfocus the hidden text field
                                
                                final controller = TextEditingController(text: _currentOrderNumber ?? '');
                                final newValue = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) {
                                    return AlertDialog(
                                      title: const Text('Edit order number'),
                                      content: TextField(
                                        controller: controller,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Order number',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                
                                setState(() {
                                  _isDialogOpen = false;
                                });
                                
                                if (newValue != null && newValue.isNotEmpty) {
                                  setState(() {
                                    _currentOrderNumber = newValue;
                                    _invoiceOrderController.text = newValue;
                                    _receiptOrderController.text = newValue;
                                  });
                                  _tryAutoConfirmIfReady(context: context);
                                }
                                
                                // Re-focus the hidden text field after dialog closes
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (_uiStep == 2 && !_useCamera && !_isDialogOpen) {
                                    _scanInputFocus.requestFocus();
                                  }
                                });
                              },
                        child: Text(
                          _currentOrderNumber ?? 'Tap to enter order number',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Invoice (left)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Invoice',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _isProcessing
                                ? null
                                : () async {
                                    setState(() {
                                      _isDialogOpen = true;
                                    });
                                    _scanInputFocus.unfocus(); // Unfocus the hidden text field
                                    
                                    final controller = TextEditingController(text: _invoiceCheckController.text);
                                    final newCode = await showDialog<String>(
                                      context: context,
                                      builder: (ctx) {
                                        return AlertDialog(
                                          title: const Text('Edit invoice check code'),
                                          content: TextField(
                                            controller: controller,
                                            autofocus: true,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Invoice check code',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    
                                    setState(() {
                                      _isDialogOpen = false;
                                    });
                                    
                                    if (newCode != null && newCode.isNotEmpty) {
                                      setState(() {
                                        _invoiceCheckController.text = newCode;
                                        // Ensure order number is set
                                        if (_currentOrderNumber != null) {
                                          _invoiceOrderController.text = _currentOrderNumber!;
                                        }
                                      });
                                      _tryAutoConfirmIfReady(context: context);
                                    }
                                    
                                    // Re-focus the hidden text field after dialog closes
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (_uiStep == 2 && !_useCamera && !_isDialogOpen) {
                                        _scanInputFocus.requestFocus();
                                      }
                                    });
                                  },
                            child: Container(
                              height: 160,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.black, width: 3),
                              ),
                              child: Center(
                                child: _invoiceCheckController.text.isNotEmpty
                                    ? const Icon(Icons.check, color: Colors.green, size: 64)
                                    : const Text(
                                        'Tap to set invoice check code',
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Receipt (right)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Receipt',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _isProcessing
                                ? null
                                : () async {
                                    setState(() {
                                      _isDialogOpen = true;
                                    });
                                    _scanInputFocus.unfocus(); // Unfocus the hidden text field
                                    
                                    final controller = TextEditingController(text: _receiptCheckController.text);
                                    final newCode = await showDialog<String>(
                                      context: context,
                                      builder: (ctx) {
                                        return AlertDialog(
                                          title: const Text('Edit receipt check code'),
                                          content: TextField(
                                            controller: controller,
                                            autofocus: true,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Receipt check code',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    
                                    setState(() {
                                      _isDialogOpen = false;
                                    });
                                    
                                    if (newCode != null && newCode.isNotEmpty) {
                                      setState(() {
                                        _receiptCheckController.text = newCode;
                                        // Ensure order number is set
                                        if (_currentOrderNumber != null) {
                                          _receiptOrderController.text = _currentOrderNumber!;
                                        }
                                      });
                                      _tryAutoConfirmIfReady(context: context);
                                    }
                                    
                                    // Re-focus the hidden text field after dialog closes
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (_uiStep == 2 && !_useCamera && !_isDialogOpen) {
                                        _scanInputFocus.requestFocus();
                                      }
                                    });
                                  },
                            child: Container(
                              height: 160,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.black, width: 3),
                              ),
                              child: Center(
                                child: _receiptCheckController.text.isNotEmpty
                                    ? const Icon(Icons.check, color: Colors.green, size: 64)
                                    : const Text(
                                        'Tap to set receipt check code',
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Camera scanner (optional) or full height for keyboard mode
          if (_useCamera)
            Expanded(
              child: Stack(
                children: [
                  MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      if (_isProcessing) return;
                      if (capture.barcodes.isEmpty) return;
                      
                      final barcode = capture.barcodes.first;
                      if (barcode.rawValue != null) {
                        final qrData = barcode.rawValue!;
                        // Check if QR code contains '|' (invoice or receipt format)
                        // Format: "ORDER_NUMBER|CHECK_CODE|RECEIPT_TYPE" or "ORDER_NUMBER|CHECK_CODE"
                        if (qrData.contains('|')) {
                          final parts = qrData.split('|');
                          if (parts.length >= 2) {
                            // QR code contains order number and check code
                            final orderNumber = parts[0].trim();
                            final checkCode = parts[1].trim();
                            // Receipt type is optional (parts[2] if present)
                            final receiptTypeFromQR = parts.length >= 3 ? parts[2].trim().toLowerCase() : null;
                            
                            if (orderNumber.isNotEmpty && checkCode.isNotEmpty) {
                              // Populate appropriate side based on type
                              setState(() {
                                if (receiptTypeFromQR == 'invoice') {
                                  _invoiceOrderController.text = orderNumber;
                                  _invoiceCheckController.text = checkCode;
                                } else if (receiptTypeFromQR == 'receipt') {
                                  _receiptOrderController.text = orderNumber;
                                  _receiptCheckController.text = checkCode;
                                }
                              });
                              
                              // Also drive the two-scan state machine
                              _handleQRCodeScan(orderNumber, checkCode, receiptType: receiptTypeFromQR, context: context);
                            } else {
                              setState(() {
                                _message = 'Invalid QR code format. Please scan again.';
                                _isSuccess = false;
                                _isWarning = false;
                              });
                            }
                          } else {
                            setState(() {
                              _message = 'QR code format invalid. Expected: ORDER_NUMBER|CHECK_CODE|RECEIPT_TYPE';
                              _isSuccess = false;
                              _isWarning = false;
                            });
                          }
                        } else {
                          // QR code doesn't contain '|' - treat as order number only
                          setState(() {
                            _message = _scanStep == 1 
                                ? 'Invoice QR code should contain |. Please enter check code manually or scan again.'
                                : 'Receipt QR code should contain |. Please enter check code manually or scan again.';
                            _isSuccess = false;
                            _isWarning = false;
                          });
                          // Focus on check code field
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scanInputFocus.requestFocus();
                          });
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
            ),
          ],
          ),
        ),
      ],
    );
  }
}

