import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/secure_session_service.dart';
import '../services/user_avatar_cache.dart';
import '../utils/jwt_utils.dart';

enum AuthStatus {
  loading,
  unauthenticated,
  biometricRequired,
  authenticated,
}

class AuthProvider with ChangeNotifier {
  AuthStatus _status = AuthStatus.loading;
  String? _token;
  AppUser? _user;
  String? _error;
  bool _biometricEnabled = false;

  AuthStatus get status => _status;
  String? get token => _token;
  AppUser? get user => _user;
  String? get error => _error;
  bool get biometricEnabled => _biometricEnabled;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  AppUser _mergeUserProfile(AppUser fresh, AppUser fallback, {String? cachedIconUrl}) {
    var iconUrl = fresh.iconUrl?.trim();
    if (iconUrl == null ||
        iconUrl.isEmpty ||
        iconUrl == UserAvatarCache.sessionIconMarker) {
      iconUrl = fallback.iconUrl?.trim();
    }
    if (iconUrl == null ||
        iconUrl.isEmpty ||
        iconUrl == UserAvatarCache.sessionIconMarker) {
      iconUrl = cachedIconUrl?.trim();
    }
    if (iconUrl != null &&
        iconUrl.isNotEmpty &&
        iconUrl != UserAvatarCache.sessionIconMarker &&
        iconUrl == fresh.iconUrl?.trim()) {
      return fresh;
    }
    if (iconUrl == null || iconUrl.isEmpty || iconUrl == UserAvatarCache.sessionIconMarker) {
      return fresh;
    }
    return AppUser(
      id: fresh.id,
      username: fresh.username,
      role: fresh.role,
      firstName: fresh.firstName,
      lastName: fresh.lastName,
      email: fresh.email,
      iconUrl: iconUrl,
      iconBgColor: fresh.iconBgColor ?? fallback.iconBgColor,
      iconTextColor: fresh.iconTextColor ?? fallback.iconTextColor,
      isActive: fresh.isActive,
      stores: fresh.stores,
    );
  }

  Future<AppUser> _mergeWithCachedIcon(AppUser fresh, AppUser fallback) async {
    final cachedIconUrl = await UserAvatarCache.instance.storedIconUrl(fresh.id);
    return _mergeUserProfile(fresh, fallback, cachedIconUrl: cachedIconUrl);
  }

  Future<void> _persistUser(AppUser user, String token) async {
    await UserAvatarCache.instance.ingest(user);
    await SecureSessionService.instance.saveSession(
      token: token,
      userJson: encodeUserForSession(user),
    );
  }

  Future<AppUser?> _refreshStoredUser(String token, AppUser fallback) async {
    try {
      final fresh = await ApiService.instance.refreshSessionUser(token);
      if (fresh != null) {
        final merged = await _mergeWithCachedIcon(fresh, fallback);
        await _persistUser(merged, token);
        return merged;
      }
    } catch (_) {}
    try {
      final fresh = await ApiService.instance.fetchUserProfile(fallback.id);
      final merged = await _mergeWithCachedIcon(fresh, fallback);
      await _persistUser(merged, token);
      return merged;
    } catch (_) {}
    final cachedOnly = await _mergeWithCachedIcon(fallback, fallback);
    if (cachedOnly.iconUrl?.trim().isNotEmpty ?? false) {
      await UserAvatarCache.instance.ingest(cachedOnly);
      return cachedOnly;
    }
    return fallback;
  }

  Future<void> onAppResumed() async {
    if (_status != AuthStatus.authenticated && _status != AuthStatus.biometricRequired) {
      return;
    }
    final token = _token;
    if (token == null) return;

    final refreshedToken = await ApiService.instance.refreshTokenIfNeeded(token);
    if (refreshedToken != null) {
      _token = refreshedToken;
      ApiService.instance.setToken(refreshedToken);
    }

    final currentUser = _user;
    if (currentUser == null) return;

    final fresh = await _refreshStoredUser(_token!, currentUser);
    if (fresh != null) {
      _user = fresh;
      notifyListeners();
    }
  }

  Future<void> bootstrap() async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    _biometricEnabled = await ApiService.instance.isBiometricEnabled();
    final session = await SecureSessionService.instance.readSession();

    if (session == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    var token = session.token;
    AppUser sessionUser = await hydrateSessionUser(
      ApiService.instance.decodeUser(session.userJson),
    );

    if (JwtUtils.isExpired(token) ||
        JwtUtils.expiresWithin(token, const Duration(minutes: 30))) {
      final refreshed = await ApiService.instance.refreshTokenIfNeeded(token);
      if (refreshed == null) {
        await _clearAll();
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
      token = refreshed;
      final fromRefresh = await ApiService.instance.refreshSessionUser(token);
      if (fromRefresh != null) {
        sessionUser = await hydrateSessionUser(fromRefresh);
      }
    }

    _token = token;
    ApiService.instance.setToken(token);
    _user = await _refreshStoredUser(token, sessionUser);

    if (_biometricEnabled) {
      _status = AuthStatus.biometricRequired;
    } else {
      _status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  Future<bool> login(
    String username,
    String password, {
    bool enableBiometric = false,
    String? biometricEnableReason,
  }) async {
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.instance.login(username.trim(), password);
      final token = data['token']?.toString();
      if (token == null || token.isEmpty) {
        _error = 'Login failed: missing token';
        notifyListeners();
        return false;
      }

      var user = ApiService.instance.parseUser(data);
      if (!user.canUseManagementPortal) {
        _error = 'This account cannot access the management portal.';
        notifyListeners();
        return false;
      }

      _token = token;
      ApiService.instance.setToken(token);
      await UserAvatarCache.instance.ingest(user);
      user = await _refreshStoredUser(token, user) ?? user;

      await _persistUser(user, token);
      await ApiService.instance.saveUsername(username.trim());

      if (enableBiometric) {
        final canUse = await BiometricService.instance.isBiometricAvailable();
        if (canUse) {
          final verified = await BiometricService.instance.authenticate(
            reason: biometricEnableReason ?? 'Enable biometric unlock for POS Management',
          );
          if (verified) {
            await ApiService.instance.setBiometricEnabled(true);
            _biometricEnabled = true;
          }
        }
      }

      _user = user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _messageFromError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockWithBiometric({String? reason}) async {
    final ok = await BiometricService.instance.authenticate(
      reason: reason ?? 'Unlock POS Management',
    );
    if (!ok) return false;
    if (_token != null && _user != null) {
      _user = await _refreshStoredUser(_token!, _user!) ?? _user;
      await UserAvatarCache.instance.warmMemory(_user!.id);
    }
    _status = AuthStatus.authenticated;
    notifyListeners();
    return true;
  }

  Future<void> skipBiometricUnlock() async {
    if (_user != null) {
      await UserAvatarCache.instance.warmMemory(_user!.id);
    }
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> logout({bool disableBiometric = false}) async {
    final userId = _user?.id;
    await _clearAll(disableBiometric: disableBiometric);
    if (userId != null) {
      await UserAvatarCache.instance.clear(userId);
    }
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> _clearAll({bool disableBiometric = false}) async {
    _token = null;
    _user = null;
    ApiService.instance.setToken(null);
    await SecureSessionService.instance.clearSession();
    if (disableBiometric) {
      await ApiService.instance.setBiometricEnabled(false);
      _biometricEnabled = false;
    }
  }

  String _messageFromError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      return e.message ?? 'Network error';
    }
    return e.toString();
  }
}
