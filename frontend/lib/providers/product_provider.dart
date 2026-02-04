import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';

class ProductProvider with ChangeNotifier {
  List<Map<String, dynamic>> _products = [];
  List<String> _categories = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get products => _products;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<bool> syncProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final deviceCode = ApiService.instance.deviceCode;
      if (deviceCode == null) {
        throw Exception('Device code not initialized');
      }

      // Fetch from API
      final products = await ApiService.instance.getProductsForDevice(deviceCode);

      // Save to local database
      try {
        await DatabaseService.instance.saveProducts(
          products.cast<Map<String, dynamic>>(),
        );
      } catch (saveError) {
        debugPrint('Error saving products to database: $saveError');
        rethrow; // Re-throw to be caught by outer catch
      }

      // Load from local database
      await loadProducts();
      
      return true; // Success
    } catch (e) {
      debugPrint('Error syncing products: $e');
      return false; // Failure
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadProducts() async {
    try {
      _products = await DatabaseService.instance.getProducts();
      _categories = _products
          .map((p) => p['category'] as String?)
          .where((c) => c != null && c.isNotEmpty)
          .toSet()
          .toList()
          .cast<String>();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading products: $e');
    }
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    return await DatabaseService.instance.getProductByBarcode(barcode);
  }

  List<Map<String, dynamic>> getProductsByCategory(String? category) {
    if (category == null) return _products;
    return _products.where((p) => p['category'] == category).toList();
  }

  List<Map<String, dynamic>> searchProducts(String query) {
    if (query.isEmpty) return _products;
    final lowerQuery = query.toLowerCase();
    return _products.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final nameChinese = (p['name_chinese'] ?? '').toString().toLowerCase();
      final barcode = (p['barcode'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      return name.contains(lowerQuery) ||
          nameChinese.contains(lowerQuery) ||
          barcode.contains(lowerQuery) ||
          sku.contains(lowerQuery);
    }).toList();
  }
}

