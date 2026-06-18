import 'dart:convert';

class JwtUtils {
  static Map<String, dynamic>? decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      switch (payload.length % 4) {
        case 1:
          payload += '===';
          break;
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static bool isExpired(String token) {
    final payload = decodePayload(token);
    final exp = payload?['exp'];
    if (exp is! num) return true;
    return DateTime.now().isAfter(
      DateTime.fromMillisecondsSinceEpoch((exp * 1000).round()),
    );
  }

  static bool expiresWithin(String token, Duration within) {
    final payload = decodePayload(token);
    final exp = payload?['exp'];
    if (exp is! num) return true;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch((exp * 1000).round());
    return expiresAt.difference(DateTime.now()) <= within;
  }
}
