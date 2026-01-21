import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';

class StockProvider with ChangeNotifier {
  Map<String, Map<String, dynamic>> _stock = {}; // key: "productId_storeId"
  bool _isLoading = false;

  Map<String, Map<String, dynamic>> get stock => _stock;
  bool get isLoading => _isLoading;

  Future<void> syncStock(int storeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final stockList = await ApiService.instance.getStoreStock(storeId);
      
      for (var item in stockList) {
        final productId = item['product_id'];
        final storeId = item['store_id'];
        final key = '${productId}_$storeId';
        _stock[key] = item as Map<String, dynamic>;
        
        // Update local database
        await DatabaseService.instance.updateStock(
          productId,
          storeId,
          (item['quantity'] as num).toDouble(),
        );
      }
    } catch (e) {
      debugPrint('Error syncing stock: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<double?> getStock(int productId, int storeId) async {
    final key = '${productId}_$storeId';
    
    // Check cache first
    if (_stock.containsKey(key)) {
      return (_stock[key]!['quantity'] as num).toDouble();
    }

    // Load from local database
    final stockData = await DatabaseService.instance.getStock(productId, storeId);
    if (stockData != null) {
      _stock[key] = stockData;
      return (stockData['quantity'] as num).toDouble();
    }

    return null;
  }

  Future<void> updateLocalStock(int productId, int storeId, double quantity) async {
    final key = '${productId}_$storeId';
    _stock[key] = {
      'product_id': productId,
      'store_id': storeId,
      'quantity': quantity,
    };
    
    await DatabaseService.instance.updateStock(productId, storeId, quantity);
    notifyListeners();
  }
}

