import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NotificationItem {
  final String id;
  final String message;
  final bool isError;
  final bool isSuccess;

  /// When the notification was created. Used for countdown/progress UI.
  final DateTime createdAt;

  /// If true, this item is not auto-dismissed (e.g. stocktake skipped).
  final bool isPersistent;

  /// Shown in the message list drawer; if null, [message] is used.
  final String? fullMessage;

  NotificationItem({
    required this.id,
    required this.message,
    this.isError = false,
    this.isSuccess = false,
    DateTime? createdAt,
    this.isPersistent = false,
    this.fullMessage,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Provides notifications for the bar (live, auto-dismiss) and a persistent history for the message list (max 50).
class NotificationBarProvider with ChangeNotifier {
  static const int _maxBarItems = 50;
  static const int _maxHistory = 50;
  static const Duration autoDismissDuration = Duration(seconds: 10);

  /// Live items shown in the bar; auto-removed after [autoDismissDuration].
  final List<NotificationItem> _items = [];
  /// Persistent history for the message list (max [_maxHistory]); never auto-removed by time.
  final List<NotificationItem> _history = [];
  final Map<String, Timer> _timers = {};
  /// When hovered, remaining ms for that id (timer is cancelled until resume).
  final Map<String, int> _pausedRemainingMs = {};
  int _idCounter = 0;

  List<NotificationItem> get items => List.unmodifiable(_items);
  List<NotificationItem> get history => List.unmodifiable(_history);
  bool get hasItems => _items.isNotEmpty;

  /// Remaining milliseconds for an item (from pause or from elapsed). Used for countdown bar. Persistent items return full.
  int getRemainingMsFor(NotificationItem item) {
    if (item.isPersistent) return autoDismissDuration.inMilliseconds;
    if (_pausedRemainingMs.containsKey(item.id)) {
      return _pausedRemainingMs[item.id]!.clamp(0, autoDismissDuration.inMilliseconds);
    }
    final elapsed = DateTime.now().difference(item.createdAt).inMilliseconds;
    return (autoDismissDuration.inMilliseconds - elapsed).clamp(0, autoDismissDuration.inMilliseconds);
  }

  void pauseTimer(String id) {
    NotificationItem? item;
    for (final e in _items) {
      if (e.id == id) { item = e; break; }
    }
    if (item == null || item.isPersistent) return;
    _timers[id]?.cancel();
    _timers.remove(id);
    final elapsed = DateTime.now().difference(item.createdAt).inMilliseconds;
    final remaining = (autoDismissDuration.inMilliseconds - elapsed).clamp(0, autoDismissDuration.inMilliseconds);
    _pausedRemainingMs[id] = remaining;
    notifyListeners();
  }

  void resumeTimer(String id) {
    final remaining = _pausedRemainingMs.remove(id);
    if (remaining == null || remaining <= 0) {
      _items.removeWhere((e) => e.id == id);
      notifyListeners();
      return;
    }
    _timers[id] = Timer(Duration(milliseconds: remaining), () {
      _timers.remove(id);
      _items.removeWhere((e) => e.id == id);
      notifyListeners();
    });
    notifyListeners();
  }

  /// Add a notification. Shown in the bar (auto-dismiss after 10s) and added to history (max 50).
  void show(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    _addItem(NotificationItem(
      id: 'n_${_idCounter++}',
      message: message,
      isError: isError,
      isSuccess: isSuccess,
      createdAt: DateTime.now(),
    ), withTimer: true);
  }

  /// Add a persistent notification (no auto-dismiss). Bar shows [shortMessage]; drawer shows [fullMessage] if set.
  void showPersistent(
    String shortMessage, {
    String? fullMessage,
    bool isError = true,
    bool isSuccess = false,
  }) {
    final id = 'n_${_idCounter++}';
    final item = NotificationItem(
      id: id,
      message: shortMessage,
      isError: isError,
      isSuccess: isSuccess,
      createdAt: DateTime.now(),
      isPersistent: true,
      fullMessage: fullMessage,
    );
    _addItem(item, withTimer: false);
  }

  void _addItem(NotificationItem item, {required bool withTimer}) {
    _items.add(item);
    _history.add(item);
    while (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    while (_items.length > _maxBarItems) {
      final removed = _items.removeAt(0);
      _timers[removed.id]?.cancel();
      _timers.remove(removed.id);
    }
    if (withTimer) {
      _timers[item.id] = Timer(autoDismissDuration, () {
        _timers.remove(item.id);
        _items.removeWhere((e) => e.id == item.id);
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void dismiss(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    _items.removeWhere((e) => e.id == id);
    _history.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _pausedRemainingMs.clear();
    _items.clear();
    _history.clear();
    notifyListeners();
  }
}

extension NotificationBarContext on BuildContext {
  void showNotification(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    read<NotificationBarProvider>().show(message, isError: isError, isSuccess: isSuccess);
  }
}
