import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({required this.token, required this.userJson});
  final String token;
  final String userJson;
}

class SecureSessionService {
  SecureSessionService._();
  static final SecureSessionService instance = SecureSessionService._();

  static const _tokenKey = 'management_jwt_token';
  static const _userKey = 'management_user_json';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> saveSession({required String token, required String userJson}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: userJson);
  }

  Future<StoredSession?> readSession() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (token == null || userJson == null || token.isEmpty || userJson.isEmpty) {
      return null;
    }
    return StoredSession(token: token, userJson: userJson);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
