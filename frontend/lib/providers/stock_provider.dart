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
      List<dynamic> stockList;
      bool fromApi = false;
      try {
        stockList = await ApiService.instance.getStoreStock(storeId);
        fromApi = true;
      } catch (e) {
        debugPrint('StockProvider: API unavailable, loading stock from local DB: $e');
        final local = await DatabaseService.instance.getStoreStockLocal(storeId);
        stockList = local;
      }

      for (var item in stockList) {
        final productId = item['product_id'];
        final storeIdVal = item['store_id'];
        final key = '${productId}_$storeIdVal';
        _stock[key] = item is Map<String, dynamic>
            ? Map<String, dynamic>.from(item)
            : {
                'product_id': productId,
                'store_id': storeIdVal,
                'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
              };

        if (fromApi) {
          await DatabaseService.instance.updateStock(
            productId as int,
            storeIdVal as int,
            (item['quantity'] as num).toDouble(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error syncing stock: $e');
      // Last resort: try loading from local so something shows when offline
      try {
        final local = await DatabaseService.instance.getStoreStockLocal(storeId);
        for (var item in local) {
          final productId = item['product_id'] as int;
          final storeIdVal = item['store_id'] as int;
          final key = '${productId}_$storeIdVal';
          _stock[key] = item;
        }
      } catch (_) {}
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

