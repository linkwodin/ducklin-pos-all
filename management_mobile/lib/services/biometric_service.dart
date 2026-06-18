import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  /// True when the device can show a biometric or device-credential prompt.
  Future<bool> isBiometricAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final types = await _auth.getAvailableBiometrics();
      if (types.isNotEmpty) return true;
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  Future<String> biometricLabel() async {
    final types = await availableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    }
    if (types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong)) {
      return 'Fingerprint';
    }
    if (types.contains(BiometricType.weak)) {
      return 'Biometrics';
    }
    return 'Device passcode';
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      if (!await isBiometricAvailable()) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
