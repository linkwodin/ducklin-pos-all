import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

/// Server-driven day-start stocktake reminder.
/// Flag is set from login response (last_stocktake_at): if null or date before today → show icon/dialog.
/// Flag becomes false when user completes stocktake or after sync when last_stocktake_at is today.
class StocktakeStatusProvider with ChangeNotifier {
  bool _hasPendingDayStartToday = false;

  bool get hasPendingStocktakeToday => _hasPendingDayStartToday;
  bool get hasPendingDayStartToday => _hasPendingDayStartToday;

  /// Set flag from login response. Call right after login before navigating to POS.
  /// If [lastStocktakeAt] is null or its date is before today, flag = true (show reminder).
  void setPendingFromLastStocktakeAt(dynamic lastStocktakeAt) {
    final pending = _isPendingFromLastStocktakeAt(lastStocktakeAt);
    _hasPendingDayStartToday = pending;
    notifyListeners();
  }

  static bool _isPendingFromLastStocktakeAt(dynamic lastStocktakeAt) {
    if (lastStocktakeAt == null) return true;
    if (lastStocktakeAt is! String) return true;
    final parsed = DateTime.tryParse(lastStocktakeAt);
    if (parsed == null) return true;
    final local = parsed.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    return !isToday;
  }

  /// Call when user completes the day-start stocktake (flag = false).
  void setPendingDone() {
    if (_hasPendingDayStartToday) {
      _hasPendingDayStartToday = false;
      notifyListeners();
    }
  }

  /// Fetch last_stocktake_at from server (device info) and update flag. Call after sync.
  /// When fetch fails or returns no data, sets flag to true (show icon) so reminder is not hidden by mistake.
  Future<void> refreshFromServer() async {
    final deviceCode = ApiService.instance.deviceCode;
    if (deviceCode == null) return;
    final info = await ApiService.instance.getDeviceInfo(deviceCode);
    if (info == null) {
      _hasPendingDayStartToday = true;
      notifyListeners();
      return;
    }
    final lastAt = info['last_stocktake_at'];
    final pending = _isPendingFromLastStocktakeAt(lastAt);
    _hasPendingDayStartToday = pending;
    notifyListeners();
  }

  /// Kept for callers that expect refresh(); now delegates to refreshFromServer().
  Future<void> refresh() async => refreshFromServer();
}
