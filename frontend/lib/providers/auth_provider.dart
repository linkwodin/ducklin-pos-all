import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/jwt_utils.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _currentUser;
  bool _isAuthenticated = false;
  Timer? _sessionTimer;
  static const Duration _idleTimeout = Duration(hours: 4);

  String? get token => _token;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;

  Future<bool> login(String username, String password) async {
    try {
      print('AuthProvider: Attempting login for user: $username');
      final response = await ApiService.instance.login(username, password);
      print('AuthProvider: Login response received: $response');
      _token = response['token'];
      _currentUser = response['user'];
      _isAuthenticated = true;

      // Save token, user role, and user ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', _token!);
      await prefs.setInt('last_activity_time', DateTime.now().millisecondsSinceEpoch);
      if (_currentUser?['role'] != null) {
        await prefs.setString('user_role', _currentUser!['role']);
      }
      if (_currentUser?['id'] != null) {
        await prefs.setInt('user_id', _currentUser!['id'] as int);
      }
      print('AuthProvider: Token saved, login successful');

      // Start session monitoring
      _startSessionMonitoring();

      notifyListeners();
      return true;
    } catch (e) {
      print('AuthProvider: Login failed with error: $e');
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> pinLogin(String username, String pin) async {
    try {
      print('AuthProvider: PIN login for user: $username');
      final response = await ApiService.instance.pinLogin(username, pin);
      print('AuthProvider: PIN login response: $response');
      _token = response['token'];
      _currentUser = response['user'];
      print('AuthProvider: Current user from response: $_currentUser');
      print('AuthProvider: User ID from response: ${_currentUser?['id']}');
      _isAuthenticated = true;

      // Save token, user role, and user ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', _token!);
      await prefs.setInt('last_activity_time', DateTime.now().millisecondsSinceEpoch);
      if (_currentUser?['role'] != null) {
        await prefs.setString('user_role', _currentUser!['role']);
      }
      if (_currentUser?['id'] != null) {
        final userId = _currentUser!['id'];
        print('AuthProvider: Saving user ID to SharedPreferences: $userId');
        // Handle both int and string IDs
        if (userId is int) {
          await prefs.setInt('user_id', userId);
        } else if (userId is String) {
          await prefs.setInt('user_id', int.parse(userId));
        } else {
          await prefs.setInt('user_id', userId as int);
        }
        print('AuthProvider: User ID saved: ${prefs.getInt('user_id')}');
      } else {
        print('AuthProvider: WARNING - User ID is null in response!');
      }

      // Start session monitoring
      _startSessionMonitoring();

      notifyListeners();
      return true;
    } catch (e) {
      print('AuthProvider: PIN login error: $e');
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _isAuthenticated = false;

    // Stop session monitoring
    _stopSessionMonitoring();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('last_activity_time');

    notifyListeners();
  }
  
  /// Update last activity time (call this on user interactions)
  Future<void> updateLastActivity() async {
    if (!_isAuthenticated) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_activity_time', DateTime.now().millisecondsSinceEpoch);
  }
  
  /// Start monitoring session for JWT expiration and idle timeout
  void _startSessionMonitoring() {
    _stopSessionMonitoring(); // Stop any existing timer
    
    // Check every minute
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkSession();
    });
  }
  
  /// Stop session monitoring
  void _stopSessionMonitoring() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }
  
  /// Check if session should be terminated
  Future<void> _checkSession() async {
    if (!_isAuthenticated || _token == null) {
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    
    // Check JWT expiration
    if (JWTUtils.isExpired(_token!)) {
      print('AuthProvider: JWT token expired, logging out');
      await logout();
      return;
    }
    
    // Check idle timeout (4 hours)
    final lastActivityTime = prefs.getInt('last_activity_time');
    if (lastActivityTime != null) {
      final lastActivity = DateTime.fromMillisecondsSinceEpoch(lastActivityTime);
      final now = DateTime.now();
      final idleDuration = now.difference(lastActivity);
      
      if (idleDuration >= _idleTimeout) {
        print('AuthProvider: Idle timeout exceeded (${idleDuration.inHours} hours), logging out');
        await logout();
        return;
      }
    }
  }

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null) {
      // Check if token is expired
      if (JWTUtils.isExpired(token)) {
        print('AuthProvider: Token expired on checkAuth, logging out');
        await logout();
        return;
      }
      
      // Check idle timeout
      final lastActivityTime = prefs.getInt('last_activity_time');
      if (lastActivityTime != null) {
        final lastActivity = DateTime.fromMillisecondsSinceEpoch(lastActivityTime);
        final now = DateTime.now();
        final idleDuration = now.difference(lastActivity);
        
        if (idleDuration >= _idleTimeout) {
          print('AuthProvider: Idle timeout exceeded on checkAuth, logging out');
          await logout();
          return;
        }
      }
      
      _token = token;
      _isAuthenticated = true;
      
      // Restore user ID from SharedPreferences
      final userId = prefs.getInt('user_id');
      final userRole = prefs.getString('user_role');
      if (userId != null) {
        _currentUser = {
          'id': userId,
          if (userRole != null) 'role': userRole,
        };
      }
      
      // Start session monitoring
      _startSessionMonitoring();
      
      notifyListeners();
    }
  }
  
  int? get userId {
    if (_currentUser?['id'] != null) {
      return _currentUser!['id'] as int;
    }
    // Fallback to SharedPreferences
    return null;
  }
}

