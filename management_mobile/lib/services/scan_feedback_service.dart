import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ScanFeedbackService {
  ScanFeedbackService._();

  static final ScanFeedbackService instance = ScanFeedbackService._();

  final AudioPlayer _player = AudioPlayer();
  var _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    _ready = true;
  }

  Future<void> playSuccess() async {
    await ensureReady();
    await HapticFeedback.lightImpact();
    await _player.stop();
    await _player.play(AssetSource('sounds/scan_success.wav'));
  }

  Future<void> playError() async {
    await ensureReady();
    await HapticFeedback.heavyImpact();
    await _player.stop();
    await _player.play(AssetSource('sounds/scan_error.wav'));
  }

  Future<void> dispose() async {
    await _player.dispose();
    _ready = false;
  }
}
