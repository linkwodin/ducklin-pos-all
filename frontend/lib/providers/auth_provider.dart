import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _currentUser;
  bool _isAuthenticated = false;

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
      if (_currentUser?['role'] != null) {
        await prefs.setString('user_role', _currentUser!['role']);
      }
      if (_currentUser?['id'] != null) {
        await prefs.setInt('user_id', _currentUser!['id'] as int);
      }
      print('AuthProvider: Token saved, login successful');

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');

    notifyListeners();
  }

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null) {
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

