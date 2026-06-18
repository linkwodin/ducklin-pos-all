import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Blocks the next camera scan until the phone orientation changes and a minimum delay passes.
class ScanMovementGate {
  ScanMovementGate({
    this.minLockDuration = const Duration(seconds: 3),
    this.minOrientationChangeRadians = 0.45,
    this.referenceSettleDelay = const Duration(milliseconds: 400),
    required this.onStateChanged,
  });

  final Duration minLockDuration;
  final double minOrientationChangeRadians;
  final Duration referenceSettleDelay;
  final VoidCallback onStateChanged;

  StreamSubscription<AccelerometerEvent>? _subscription;
  DateTime? _lockedAt;
  DateTime? _unlockAt;
  DateTime? _referenceReadyAt;
  var _movementDetected = false;
  (double x, double y, double z)? _referenceGravity;
  var _peakOrientationDelta = 0.0;

  bool get isLocked => _lockedAt != null;

  bool get movementDetected => _movementDetected;

  Duration? get remainingLock {
    final unlockAt = _unlockAt;
    if (unlockAt == null) return null;
    final remaining = unlockAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return Duration.zero;
    return remaining;
  }

  bool get scannerEnabled => !isLocked;

  void start() {
    _subscription ??= accelerometerEventStream().listen(_onAccelerometer);
  }

  void lockAfterScan() {
    final now = DateTime.now();
    _lockedAt = now;
    _unlockAt = now.add(minLockDuration);
    _referenceReadyAt = now.add(referenceSettleDelay);
    _movementDetected = false;
    _referenceGravity = null;
    _peakOrientationDelta = 0;
    onStateChanged();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    if (_lockedAt == null) return;

    final readyAt = _referenceReadyAt;
    if (readyAt != null && DateTime.now().isBefore(readyAt)) return;

    final magnitude = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (magnitude < 5) return;

    final nx = event.x / magnitude;
    final ny = event.y / magnitude;
    final nz = event.z / magnitude;

    final reference = _referenceGravity;
    if (reference == null) {
      _referenceGravity = (nx, ny, nz);
      return;
    }

    final dot = (nx * reference.$1 + ny * reference.$2 + nz * reference.$3).clamp(-1.0, 1.0);
    final angle = math.acos(dot);
    if (angle > _peakOrientationDelta) {
      _peakOrientationDelta = angle;
    }

    if (!_movementDetected && _peakOrientationDelta >= minOrientationChangeRadians) {
      _movementDetected = true;
      _tryUnlock();
    }
  }

  void tick() {
    if (_lockedAt == null) return;
    if (_movementDetected) {
      _tryUnlock();
    }
    onStateChanged();
  }

  void _tryUnlock() {
    if (_lockedAt == null || !_movementDetected) return;
    final unlockAt = _unlockAt;
    if (unlockAt == null || DateTime.now().isBefore(unlockAt)) return;

    _lockedAt = null;
    _unlockAt = null;
    _referenceReadyAt = null;
    _movementDetected = false;
    _referenceGravity = null;
    _peakOrientationDelta = 0;
    onStateChanged();
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
