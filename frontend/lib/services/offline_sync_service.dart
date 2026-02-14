import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'database_service.dart';

/// Background service that periodically checks backend health and syncs pending (offline) orders.
class OfflineSyncService {
  static Timer? _timer;
  static void Function()? _onSyncComplete;

  /// Start background health check and sync. Calls [onSyncComplete] after a successful sync (e.g. to refresh badge).
  static void start(void Function()? onSyncComplete) {
    _onSyncComplete = onSyncComplete;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    debugPrint('OfflineSyncService: started (health check every 30s)');
  }

  /// Run one health check and sync now (e.g. when user taps Sync button). Calls [onSyncComplete] after sync.
  static Future<void> runSyncNow() async {
    await _tick();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _onSyncComplete = null;
    debugPrint('OfflineSyncService: stopped');
  }

  static Future<void> _tick() async {
    try {
      final ok = await ApiService.instance.healthCheck();
      if (!ok) return;
      // Only sync when user is authenticated; otherwise backend returns 401 (no auth header).
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) {
        debugPrint('OfflineSyncService: skipping sync (no JWT token)');
        return;
      }
      await _syncPendingOrders();
      await _syncPendingStocktakes();
      await _syncPendingUserActivityEvents();
      _onSyncComplete?.call();
      final ordersRemaining = await DatabaseService.instance.getPendingOrdersCount();
      final stocktakesRemaining = await DatabaseService.instance.getPendingStocktakeCount();
      final eventsRemaining = await DatabaseService.instance.getPendingUserActivityEventCount();
      if (ordersRemaining == 0 && stocktakesRemaining == 0 && eventsRemaining == 0) {
        stop();
        debugPrint('OfflineSyncService: all orders, stocktakes and user events synced, stopping health check');
      }
    } catch (e) {
      debugPrint('OfflineSyncService: tick error: $e');
    }
  }

  static Future<void> _syncPendingOrders() async {
    final deviceCode = ApiService.instance.deviceCode;
    if (deviceCode == null || deviceCode.isEmpty) return;

    final pending = await DatabaseService.instance.getPendingOrders();
    for (final order in pending) {
      try {
        final orderId = order['id'] as int;
        final items = await DatabaseService.instance.getOrderItems(orderId);
        // Send frontend order_number and created_at so backend uses same number and date (idempotent + correct date)
        final createdAt = order['created_at'];
        final created_at_iso = createdAt != null
            ? DateTime.fromMillisecondsSinceEpoch(createdAt as int).toUtc().toIso8601String()
            : null;
        final orderData = {
          'store_id': order['store_id'],
          'device_code': deviceCode,
          'sector_id': order['sector_id'],
          'order_number': order['order_number'],
          if (created_at_iso != null) 'created_at': created_at_iso,
          'items': items.map((item) => {
                'product_id': item['product_id'],
                'quantity': item['quantity'],
                'unit_type': item['unit_type'] ?? 'quantity',
              }).toList(),
        };
        final response = await ApiService.instance.createOrder(orderData);
        final backendOrderId = response['id'] as int?;
        if (backendOrderId != null) {
          try {
            await ApiService.instance.markOrderPaid(backendOrderId);
            await ApiService.instance.markOrderComplete(backendOrderId);
            // If order was picked up locally before sync, record pickup on backend too
            if (order['picked_up_at'] != null) {
              try {
                await ApiService.instance.confirmOrderPickup(order['order_number'] as String);
              } catch (_) {}
            }
          } catch (_) {}
        }
        await DatabaseService.instance.markOrderSynced(orderId);
        await DatabaseService.instance.updateOrderStatusByOrderNumber(
          order['order_number'] as String,
          status: 'completed',
        );
        debugPrint('OfflineSyncService: synced order ${order['order_number']}');
      } catch (e) {
        debugPrint('OfflineSyncService: failed to sync order ${order['order_number']}: $e');
      }
    }
  }

  static Future<void> _syncPendingStocktakes() async {
    final pending = await DatabaseService.instance.getPendingStocktakes();
    for (final st in pending) {
      try {
        final stocktakeId = st['id'] as int;
        final storeId = st['store_id'] as int;
        final defaultReason = (st['reason'] as String?) ?? (st['type'] == 'day_start' ? 'stocktake_day_start' : 'stocktake_day_end');
        final items = await DatabaseService.instance.getPendingStocktakeItems(stocktakeId);
        for (final item in items) {
          final reason = (item['reason'] as String?)?.trim().isNotEmpty == true
              ? item['reason'] as String
              : defaultReason;
          await ApiService.instance.updateStock(
            item['product_id'] as int,
            storeId,
            quantity: (item['quantity'] as num).toDouble(),
            reason: reason,
          );
        }
        await DatabaseService.instance.markStocktakeSynced(stocktakeId);
        debugPrint('OfflineSyncService: synced stocktake $stocktakeId');
      } catch (e) {
        debugPrint('OfflineSyncService: failed to sync stocktake ${st['id']}: $e');
      }
    }
  }

  static Future<void> _syncPendingUserActivityEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getInt('user_id');
    if (currentUserId == null) return;

    final pending = await DatabaseService.instance.getPendingUserActivityEvents(currentUserId);
    for (final ev in pending) {
      try {
        final id = ev['id'] as int;
        final eventType = ev['event_type'] as String;
        final storeId = ev['store_id'] as int?;
        final skipReason = ev['skip_reason'] as String?;

        if (eventType == 'logout') {
          await ApiService.instance.recordLogout(storeId: storeId, skipLocalSaveOnFailure: true);
        } else if (eventType == 'day_end_skipped') {
          await ApiService.instance.recordStocktakeDayEndSkip(
            skipReason: skipReason ?? '',
            storeId: storeId,
            skipLocalSaveOnFailure: true,
          );
        } else {
          await ApiService.instance.recordStocktakeDayStart(
            eventType,
            storeId: storeId,
            skipReason: skipReason,
            skipLocalSaveOnFailure: true,
          );
        }
        await DatabaseService.instance.markUserActivityEventSynced(id);
        debugPrint('OfflineSyncService: synced user activity event $id ($eventType)');
      } catch (e) {
        debugPrint('OfflineSyncService: failed to sync user activity event ${ev['id']}: $e');
      }
    }
  }
}
