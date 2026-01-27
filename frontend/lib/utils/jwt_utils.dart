import 'dart:convert';

class JWTUtils {
  /// Decode JWT token and return the payload as a Map
  static Map<String, dynamic>? decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }
      
      // Decode the payload (second part)
      final payload = parts[1];
      
      // Add padding if needed
      String normalizedPayload = payload;
      switch (payload.length % 4) {
        case 1:
          normalizedPayload += '===';
          break;
        case 2:
          normalizedPayload += '==';
          break;
        case 3:
          normalizedPayload += '=';
          break;
      }
      
      final decodedBytes = base64Url.decode(normalizedPayload);
      final decodedString = utf8.decode(decodedBytes);
      return jsonDecode(decodedString) as Map<String, dynamic>;
    } catch (e) {
      print('JWTUtils: Error decoding token: $e');
      return null;
    }
  }
  
  /// Check if JWT token is expired
  static bool isExpired(String token) {
    final payload = decodePayload(token);
    if (payload == null) {
      return true;
    }
    
    final exp = payload['exp'];
    if (exp == null) {
      // If no expiration claim, consider it expired for safety
      return true;
    }
    
    // exp is in seconds since epoch
    final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final now = DateTime.now();
    
    return now.isAfter(expirationTime);
  }
  
  /// Get expiration time from JWT token
  static DateTime? getExpirationTime(String token) {
    final payload = decodePayload(token);
    if (payload == null) {
      return null;
    }
    
    final exp = payload['exp'];
    if (exp == null) {
      return null;
    }
    
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  }
}

