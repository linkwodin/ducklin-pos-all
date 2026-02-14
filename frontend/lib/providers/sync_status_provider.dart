import 'package:flutter/foundation.dart';
import '../services/database_service.dart';

/// Exposes pending (unsynced) orders, stocktakes and user activity events count for UI (e.g. red badge on sync button, sync screen).
class SyncStatusProvider with ChangeNotifier {
  int _pendingOrdersCount = 0;
  int _pendingStocktakesCount = 0;
  int _pendingUserActivityEventsCount = 0;

  int get pendingOrdersCount => _pendingOrdersCount;
  int get pendingStocktakesCount => _pendingStocktakesCount;
  int get pendingUserActivityEventsCount => _pendingUserActivityEventsCount;

  Future<void> refreshPendingCount() async {
    try {
      final orders = await DatabaseService.instance.getPendingOrdersCount();
      final stocktakes = await DatabaseService.instance.getPendingStocktakeCount();
      final events = await DatabaseService.instance.getPendingUserActivityEventCount();
      if (orders != _pendingOrdersCount ||
          stocktakes != _pendingStocktakesCount ||
          events != _pendingUserActivityEventsCount) {
        _pendingOrdersCount = orders;
        _pendingStocktakesCount = stocktakes;
        _pendingUserActivityEventsCount = events;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SyncStatusProvider: failed to get pending count: $e');
    }
  }
}
