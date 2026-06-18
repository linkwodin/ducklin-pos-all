import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../utils/user_avatar.dart';
import 'api_service.dart';

/// Persists user avatar bytes on disk and keeps a small in-memory cache so
/// avatars survive app resume / widget rebuilds without re-downloading.
class UserAvatarCache extends ChangeNotifier {
  UserAvatarCache._();
  static final UserAvatarCache instance = UserAvatarCache._();

  static const sessionIconMarker = '__local_avatar__';
  static const _iconUrlKeyPrefix = 'management_user_icon_url_';

  final Map<int, Uint8List> _memory = {};

  String _iconUrlPrefsKey(int userId) => '$_iconUrlKeyPrefix$userId';

  /// Synchronous read from the in-memory cache (for first paint).
  Uint8List? bytesFor(int userId) => _memory[userId];

  Future<Directory> _avatarDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/user_avatars');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _bytesPath(int userId) => 'user_$userId.bin';
  String _metaPath(int userId) => 'user_$userId.meta.json';

  Future<Map<String, dynamic>?> _readMeta(int userId) async {
    try {
      final file = File('${(await _avatarDir()).path}/${_metaPath(userId)}');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> _writeMeta(int userId, String iconUrl) async {
    final file = File('${(await _avatarDir()).path}/${_metaPath(userId)}');
    await file.writeAsString(
      jsonEncode({
        'icon_url': iconUrl.trim(),
        'cached_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Last known icon URL for [userId], from prefs or on-disk metadata.
  Future<String?> storedIconUrl(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString(_iconUrlPrefsKey(userId))?.trim();
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;

    final meta = await _readMeta(userId);
    final fromMeta = meta?['icon_url']?.toString().trim();
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
    return null;
  }

  Future<void> _rememberIconUrl(int userId, String iconUrl) async {
    final trimmed = iconUrl.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_iconUrlPrefsKey(userId), trimmed);
  }

  /// Load avatar bytes from disk into memory (call on app start).
  Future<void> warmMemory(int userId) async {
    if (_memory.containsKey(userId)) return;
    await read(userId);
  }

  /// Returns cached bytes for [userId]. URL match is best-effort only.
  Future<Uint8List?> read(int userId, {String? iconUrl}) async {
    final inMemory = _memory[userId];
    if (inMemory != null) return inMemory;

    try {
      final file = File('${(await _avatarDir()).path}/${_bytesPath(userId)}');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      if (iconUrl != null && iconUrl.trim().isNotEmpty) {
        final meta = await _readMeta(userId);
        final cachedUrl = meta?['icon_url']?.toString().trim() ?? '';
        if (cachedUrl.isNotEmpty && cachedUrl != iconUrl.trim()) {
          return null;
        }
      }

      _memory[userId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(int userId, String iconUrl, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final trimmed = iconUrl.trim();
    if (trimmed.isEmpty) return;

    _memory[userId] = bytes;
    await _rememberIconUrl(userId, trimmed);
    await _writeMeta(userId, trimmed);

    final file = File('${(await _avatarDir()).path}/${_bytesPath(userId)}');
    await file.writeAsBytes(bytes, flush: true);
    notifyListeners();
  }

  /// Decode data-URL icons and persist bytes immediately (call on login/refresh).
  Future<void> ingest(AppUser user) async {
    final iconUrl = user.iconUrl?.trim();
    if (iconUrl == null || iconUrl.isEmpty) return;

    if (iconUrl.startsWith('data:')) {
      final bytes = decodeDataUrlImage(iconUrl);
      if (bytes != null && bytes.isNotEmpty) {
        await write(user.id, iconUrl, bytes);
      }
      return;
    }

    await _rememberIconUrl(user.id, iconUrl);
    final existing = await read(user.id, iconUrl: iconUrl);
    if (existing != null) return;
    await prefetch(user);
  }

  Future<void> clear(int userId) async {
    _memory.remove(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_iconUrlPrefsKey(userId));
    try {
      final dir = await _avatarDir();
      final bytesFile = File('${dir.path}/${_bytesPath(userId)}');
      final metaFile = File('${dir.path}/${_metaPath(userId)}');
      if (await bytesFile.exists()) await bytesFile.delete();
      if (await metaFile.exists()) await metaFile.delete();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearAll() async {
    _memory.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_iconUrlKeyPrefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    try {
      final dir = await _avatarDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Download (if needed) and persist avatar bytes for [user].
  Future<void> prefetch(AppUser user) async {
    var iconUrl = user.iconUrl?.trim();
    if (iconUrl == null || iconUrl.isEmpty) {
      iconUrl = await storedIconUrl(user.id);
    }
    if (iconUrl == null || iconUrl.isEmpty) return;

    final existing = await read(user.id, iconUrl: iconUrl);
    if (existing != null) return;

    final resolved = resolveUserIconUrl(iconUrl);
    Uint8List? bytes;
    if (resolved.startsWith('data:')) {
      bytes = decodeDataUrlImage(resolved);
    } else {
      try {
        final response = await ApiService.instance.downloadUrl(resolved);
        if (response.isNotEmpty) {
          bytes = Uint8List.fromList(response);
        }
      } catch (_) {
        return;
      }
    }
    if (bytes != null && bytes.isNotEmpty) {
      await write(user.id, iconUrl, bytes);
    }
  }
}

/// Session JSON helpers — data-URL icons are too large for secure storage.
String encodeUserForSession(AppUser user) {
  final json = user.toJson();
  final iconUrl = user.iconUrl?.trim();
  if (iconUrl != null && iconUrl.startsWith('data:')) {
    json['icon_url'] = UserAvatarCache.sessionIconMarker;
  }
  return jsonEncode(json);
}

Future<AppUser> hydrateSessionUser(AppUser user) async {
  var iconUrl = user.iconUrl?.trim();
  if (iconUrl == null ||
      iconUrl.isEmpty ||
      iconUrl == UserAvatarCache.sessionIconMarker) {
    iconUrl = await UserAvatarCache.instance.storedIconUrl(user.id);
  }
  if (iconUrl == null || iconUrl.isEmpty || iconUrl == user.iconUrl) {
    await UserAvatarCache.instance.warmMemory(user.id);
    return user;
  }
  final hydrated = AppUser(
    id: user.id,
    username: user.username,
    role: user.role,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    iconUrl: iconUrl,
    iconBgColor: user.iconBgColor,
    iconTextColor: user.iconTextColor,
    isActive: user.isActive,
    stores: user.stores,
  );
  await UserAvatarCache.instance.warmMemory(user.id);
  return hydrated;
}
