import 'package:shared_preferences/shared_preferences.dart';

/// Tracks day start / day end stocktake prompt state. Persists via SharedPreferences.
/// - First login of the day: we prompt for day start stocktake.
/// - If user skips (with reason), we do not mark day start done → prompt again on next login.
/// - On logout: we prompt for day end stocktake; skip with reason is allowed, then logout.
class StocktakePromptService {
  static const _keyLastLoginDate = 'stocktake_last_login_date';
  static const _keyDayStartDoneDate = 'stocktake_day_start_done_date';
  static const _keyDayEndDoneDate = 'stocktake_day_end_done_date';

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Call when user has successfully logged in and landed on POS (or equivalent).
  /// Updates last login date to today.
  static Future<void> recordLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastLoginDate, _today());
  }

  /// True if we should show the day start stocktake prompt (first login of the day and not yet done today).
  static Future<bool> shouldPromptDayStart() async {
    final prefs = await SharedPreferences.getInstance();
    final lastLogin = prefs.getString(_keyLastLoginDate);
    final dayStartDone = prefs.getString(_keyDayStartDoneDate);
    final today = _today();
    if (lastLogin != today) return true;
    return dayStartDone != today;
  }

  static Future<void> recordDayStartDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDayStartDoneDate, _today());
  }

  /// True if we should show the day end stocktake prompt (day end not done today).
  static Future<bool> shouldPromptDayEnd() async {
    final prefs = await SharedPreferences.getInstance();
    final dayEndDone = prefs.getString(_keyDayEndDoneDate);
    return dayEndDone != _today();
  }

  static Future<void> recordDayEndDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDayEndDoneDate, _today());
  }

  /// True if day start or day end stocktake is not done today.
  static Future<bool> hasPendingStocktakeToday() async {
    final dayStart = await shouldPromptDayStart();
    final dayEnd = await shouldPromptDayEnd();
    return dayStart || dayEnd;
  }

  /// True if day start stocktake is pending today (for notification bar icon; icon opens day-start flow).
  static Future<bool> hasPendingDayStartToday() async {
    return shouldPromptDayStart();
  }

  /// Clear day-start and day-end "done" flags so the reminder will show again.
  /// Keeps last_login_date so "first login today" logic still works after they complete/skip once.
  static Future<void> clearReminderState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDayStartDoneDate);
    await prefs.remove(_keyDayEndDoneDate);
  }
}
