import 'dart:convert';

import 'api_service.dart';
import 'database_service.dart';
import '../utils/pos_receipt_config.dart';

/// Loads and caches per-store POS receipt settings for offline checkout.
class StoreReceiptConfigService {
  StoreReceiptConfigService._();
  static final StoreReceiptConfigService instance = StoreReceiptConfigService._();

  Future<Map<String, dynamic>?> getCachedConfig(int? storeId) async {
    if (storeId == null) return null;
    return DatabaseService.instance.getStoreReceiptConfig(storeId);
  }

  Future<Map<String, dynamic>> resolveConfig({
    int? storeId,
    bool forceRefresh = false,
    Map<String, dynamic>? order,
  }) async {
    final deviceInfo = await DatabaseService.instance.getDeviceInfo();
    final deviceStoreId = storeId ?? deviceInfo?['store_id'] as int?;
    if (deviceStoreId == null) {
      return _defaultConfig();
    }

    Map<String, dynamic>? orderStoreConfig;
    final orderStore = order?['store'];
    if (orderStore is Map) {
      orderStoreConfig = receiptConfigFromStore(
        Map<String, dynamic>.from(orderStore as Map),
      );
    }

    Map<String, dynamic> fetched;
    if (forceRefresh) {
      fetched = await refreshFromApi(deviceStoreId);
    } else {
      final online = await ApiService.instance.healthCheck();
      if (online) {
        fetched = await refreshFromApi(deviceStoreId);
      } else {
        final cached = await getCachedConfig(deviceStoreId);
        fetched = _isUsableConfig(cached) ? cached! : _defaultConfig();
      }
    }

    final merged = mergeReceiptConfigs(fetched, orderStoreConfig);
    return merged.isNotEmpty ? merged : fetched;
  }

  Map<String, dynamic> _defaultConfig() => {
        'pos_receipt_settings_configured': false,
        'pos_receipt_types': defaultPosReceiptTypeKeys,
        'pos_auto_print_receipt_types': defaultPosAutoPrintReceiptTypeKeys,
      };

  bool _isUsableConfig(Map<String, dynamic>? config) {
    if (config == null || config.isEmpty) return false;
    if (config['pos_receipt_settings_configured'] == true) return true;
    return config['pos_receipt_types'] is List || config['pos_auto_print_receipt_types'] is List;
  }

  Future<Map<String, dynamic>> refreshFromApi(int storeId) async {
    try {
      final store = await ApiService.instance.getStore(storeId);
      final config = receiptConfigFromStore(store);
      await DatabaseService.instance.saveStoreReceiptConfig(storeId, config);
      return config;
    } catch (e) {
      final cached = await getCachedConfig(storeId);
      if (_isUsableConfig(cached)) return cached!;
      return _defaultConfig();
    }
  }

  Future<void> cacheFromDeviceInfo(Map<String, dynamic> deviceInfo) async {
    final storeId = deviceInfo['store_id'] as int?;
    if (storeId == null) return;
    final config = <String, dynamic>{};
    if (deviceInfo['pos_receipt_settings_configured'] == true) {
      config['pos_receipt_settings_configured'] = true;
    }
    if (deviceInfo['pos_receipt_types'] is List) {
      config['pos_receipt_types'] = deviceInfo['pos_receipt_types'];
    }
    if (deviceInfo['pos_auto_print_receipt_types'] is List) {
      config['pos_auto_print_receipt_types'] = deviceInfo['pos_auto_print_receipt_types'];
    }
    if (config.isEmpty) return;
    await DatabaseService.instance.saveStoreReceiptConfig(storeId, config);
  }

  String encodeConfig(Map<String, dynamic> config) => jsonEncode(config);
}
