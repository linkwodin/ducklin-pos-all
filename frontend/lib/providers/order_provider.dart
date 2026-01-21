import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';

class OrderProvider with ChangeNotifier {
  List<Map<String, dynamic>> _cartItems = [];
  int? _storeId;
  int? _sectorId;
  bool _isLoading = false;
  String? _lastAddedMessage;

  OrderProvider() {
    _initializeStoreId();
  }

  Future<void> _initializeStoreId() async {
    try {
      final deviceInfo = await DatabaseService.instance.getDeviceInfo();
      final storeId = deviceInfo?['store_id'] as int? ?? 1;
      _storeId = storeId;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing store ID: $e');
      // Default to store ID 1 if device info is not available
      _storeId = 1;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> get cartItems => _cartItems;
  int? get storeId => _storeId;
  int? get sectorId => _sectorId;
  bool get isLoading => _isLoading;

  double get subtotal {
    return _cartItems.fold(0.0, (sum, item) {
      final quantity = (item['quantity'] as num).toDouble();
      final unitPrice = (item['unit_price'] as num).toDouble();
      return sum + (quantity * unitPrice);
    });
  }

  double get discountAmount {
    return _cartItems.fold(0.0, (sum, item) {
      return sum + ((item['discount_amount'] as num?)?.toDouble() ?? 0.0);
    });
  }

  double get total {
    return subtotal - discountAmount;
  }

  void setStore(int storeId) {
    _storeId = storeId;
    notifyListeners();
  }

  void setSector(int? sectorId) {
    _sectorId = sectorId;
    notifyListeners();
  }

  String? get lastAddedMessage => _lastAddedMessage;

  void addToCart(Map<String, dynamic> product, {double? quantity, double? weight, String? message}) {
    final existingIndex = _cartItems.indexWhere(
      (item) => item['product_id'] == product['id'],
    );

    final qty = quantity ?? weight ?? 1.0;
    final unitPrice = _getProductPrice(product);
    final discountPercent = _getDiscountPercent(product);
    final discountAmount = unitPrice * (discountPercent / 100.0) * qty;
    final lineTotal = (unitPrice * qty) - discountAmount;

    if (existingIndex >= 0) {
      // Update existing item
      final existing = _cartItems[existingIndex];
      final existingQty = (existing['quantity'] as num).toDouble();
      final newQty = existingQty + qty;
      final newDiscountAmount = unitPrice * (discountPercent / 100.0) * newQty;
      final newLineTotal = (unitPrice * newQty) - newDiscountAmount;
      final unitType = product['unit_type'] ?? 'quantity';

      _cartItems[existingIndex] = {
        ...existing,
        'quantity': newQty,
        'unit_type': unitType, // Ensure unit_type is set
        'discount_amount': newDiscountAmount,
        'line_total': newLineTotal,
      };
    } else {
      // Add new item
      final unitType = product['unit_type'] ?? 'quantity';
      _cartItems.add({
        'product_id': product['id'],
        'product': product,
        'quantity': qty,
        'unit_type': unitType, // Store unit type (quantity or weight)
        'unit_price': unitPrice,
        'discount_percent': discountPercent,
        'discount_amount': discountAmount,
        'line_total': lineTotal,
      });
    }
    
    // Set notification message
    _lastAddedMessage = message;
    notifyListeners();
    
    // Clear message after 2 seconds
    if (message != null) {
      Future.delayed(const Duration(seconds: 2), () {
        _lastAddedMessage = null;
        notifyListeners();
      });
    }
  }

  void removeFromCart(int productId) {
    _cartItems.removeWhere((item) => item['product_id'] == productId);
    notifyListeners();
  }

  void updateCartItemQuantity(int productId, double quantity) {
    final index = _cartItems.indexWhere((item) => item['product_id'] == productId);
    if (index >= 0) {
      final item = _cartItems[index];
      final product = item['product'] as Map<String, dynamic>;
      final unitPrice = (item['unit_price'] as num).toDouble();
      final discountPercent = (item['discount_percent'] as num).toDouble();
      final discountAmount = unitPrice * (discountPercent / 100.0) * quantity;
      final lineTotal = (unitPrice * quantity) - discountAmount;

      _cartItems[index] = {
        ...item,
        'quantity': quantity,
        'discount_amount': discountAmount,
        'line_total': lineTotal,
      };
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }

  Future<Map<String, dynamic>?> checkout(int userId, String deviceCode) async {
    if (_storeId == null) {
      throw Exception('Store not selected');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final orderNumber = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
      
      final orderData = {
        'store_id': _storeId,
        'device_code': deviceCode,
        'sector_id': _sectorId,
        'items': _cartItems.map((item) => {
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_type': item['unit_type'] ?? 'quantity', // Specify unit or gram
        }).toList(),
      };

      // Try to create order via API
      try {
        debugPrint('OrderProvider: Attempting to create order via API');
        debugPrint('OrderProvider: Order data: $orderData');
        final order = await ApiService.instance.createOrder(orderData);
        debugPrint('OrderProvider: Order created successfully: $order');
        
        // Save to local database
        await DatabaseService.instance.saveOrder({
          'order_number': order['order_number'],
          'store_id': _storeId,
          'user_id': userId,
          'sector_id': _sectorId,
          'subtotal': subtotal,
          'discount_amount': discountAmount,
          'total_amount': total,
          'status': 'pending',
          'qr_code_data': order['qr_code_data'],
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'synced': 1,
        });

        final orderId = order['id'];
        final orderItems = _cartItems.map((item) => {
          'order_id': orderId,
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
          'discount_percent': item['discount_percent'],
          'discount_amount': item['discount_amount'],
          'line_total': item['line_total'],
        }).toList();

        await DatabaseService.instance.saveOrderItems(orderId, orderItems);

        clearCart();
        return order;
      } catch (e, stackTrace) {
        // Network error - save offline
        debugPrint('OrderProvider: Network error, saving offline');
        debugPrint('OrderProvider: Error: $e');
        debugPrint('OrderProvider: Stack trace: $stackTrace');
        
        final localOrderId = await DatabaseService.instance.saveOrder({
          'order_number': orderNumber,
          'store_id': _storeId,
          'user_id': userId,
          'sector_id': _sectorId,
          'subtotal': subtotal,
          'discount_amount': discountAmount,
          'total_amount': total,
          'status': 'pending',
          'qr_code_data': '',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'synced': 0,
        });

        final orderItems = _cartItems.map((item) => {
          'order_id': localOrderId,
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
          'discount_percent': item['discount_percent'],
          'discount_amount': item['discount_amount'],
          'line_total': item['line_total'],
        }).toList();

        await DatabaseService.instance.saveOrderItems(localOrderId, orderItems);

        clearCart();
        return {
          'id': localOrderId,
          'order_number': orderNumber,
          'status': 'pending',
          'offline': true,
        };
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  double _getProductPrice(Map<String, dynamic> product) {
    // Use pos_price if available (already calculated by backend with sector discount)
    final posPrice = (product['pos_price'] as num?)?.toDouble();
    if (posPrice != null && posPrice > 0) {
      return posPrice;
    }
    
    // Fallback to current_cost if pos_price not available
    final cost = product['current_cost'];
    if (cost != null && cost is Map) {
      // Try direct_retail_online_store_price_gbp first
      final directRetailPrice = (cost['direct_retail_online_store_price_gbp'] as num?)?.toDouble();
      if (directRetailPrice != null && directRetailPrice > 0) {
        return directRetailPrice;
      }
      // Fallback to wholesale_cost_gbp
      return (cost['wholesale_cost_gbp'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  double _getDiscountPercent(Map<String, dynamic> product) {
    // Since pos_price already includes sector discount, we don't need additional discount
    // Product-specific discounts are handled by the backend when creating orders
    return 0.0;
  }
}

