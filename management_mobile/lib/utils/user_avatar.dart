import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/user_avatar_cache.dart';

Color? parseHexColor(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(value);
}

Uri _apiOriginUri() {
  return Uri.parse(AppConfig.apiOrigin);
}

String resolveUserIconUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  if (trimmed.startsWith('data:')) return trimmed;

  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) {
    if (parsed.host == '127.0.0.1' || parsed.host == 'localhost') {
      final origin = _apiOriginUri();
      return parsed.replace(scheme: origin.scheme, host: origin.host, port: origin.port).toString();
    }
    return trimmed;
  }

  final origin = _apiOriginUri();
  if (trimmed.startsWith('/')) {
    return origin.replace(path: trimmed).toString();
  }
  return origin.replace(path: '/$trimmed').toString();
}

Uint8List? decodeDataUrlImage(String url) {
  if (!url.startsWith('data:')) return null;
  try {
    final payload = url.contains(',') ? url.split(',').last : url;
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

String userAvatarInitials(String firstName, String lastName, String username) {
  final first = firstName.trim();
  final last = lastName.trim();
  if (first.isNotEmpty && last.isNotEmpty) {
    return '${first[0]}${last[0]}';
  }
  if (first.isNotEmpty) return first[0];
  final user = username.trim();
  if (user.isEmpty) return '?';
  return user[0].toUpperCase();
}

class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    this.user,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  factory UserAvatar.fromUser(AppUser user, {double radius = 20}) => UserAvatar(user: user, radius: radius);

  final AppUser? user;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> with WidgetsBindingObserver {
  Uint8List? _bytes;
  var _loadFailed = false;
  var _loading = false;
  int? _loadedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UserAvatarCache.instance.addListener(_onCacheChanged);
    _primeFromMemory();
    _loadIcon();
  }

  @override
  void dispose() {
    UserAvatarCache.instance.removeListener(_onCacheChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onCacheChanged() {
    _primeFromMemory();
    if (mounted) setState(() {});
  }

  void _primeFromMemory() {
    final user = widget.user;
    if (user == null) return;
    final bytes = UserAvatarCache.instance.bytesFor(user.id);
    if (bytes != null) {
      _bytes = bytes;
      _loadFailed = false;
      _loadedUserId = user.id;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUser = oldWidget.user;
    final newUser = widget.user;
    if (oldUser?.id != newUser?.id ||
        oldUser?.iconUrl != newUser?.iconUrl ||
        (_bytes == null && newUser != null)) {
      _primeFromMemory();
      if (_bytes == null) {
        _loadFailed = false;
        _loadedUserId = null;
        _loadIcon();
      }
    }
  }

  Future<String?> _resolveIconUrl(AppUser? user) async {
    if (user == null) return null;
    final fromUser = user.iconUrl?.trim();
    if (fromUser != null &&
        fromUser.isNotEmpty &&
        fromUser != UserAvatarCache.sessionIconMarker) {
      return fromUser;
    }
    return UserAvatarCache.instance.storedIconUrl(user.id);
  }

  void _retryIfNeeded() {
    final user = widget.user;
    if (user == null) return;
    if (_bytes != null && !_loadFailed && _loadedUserId == user.id) return;
    _primeFromMemory();
    if (_bytes == null) {
      _loadFailed = false;
      _loadedUserId = null;
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    final user = widget.user;
    if (user == null || _loading) return;

    final iconUrl = await _resolveIconUrl(user);
    if (iconUrl == null || iconUrl.isEmpty) return;

    _loading = true;

    final cached = await UserAvatarCache.instance.read(user.id, iconUrl: iconUrl);
    if (cached != null && mounted) {
      setState(() {
        _bytes = cached;
        _loadFailed = false;
        _loading = false;
        _loadedUserId = user.id;
      });
    }

    final resolved = resolveUserIconUrl(iconUrl);
    Uint8List? freshBytes;
    if (resolved.startsWith('data:')) {
      freshBytes = decodeDataUrlImage(resolved);
    } else {
      try {
        final response = await ApiService.instance.downloadUrl(resolved);
        if (response.isNotEmpty) {
          freshBytes = Uint8List.fromList(response);
        }
      } catch (_) {
        freshBytes = null;
      }
    }

    if (!mounted) return;

    if (freshBytes != null && freshBytes.isNotEmpty) {
      await UserAvatarCache.instance.write(user.id, iconUrl, freshBytes);
      setState(() {
        _bytes = freshBytes;
        _loadFailed = false;
        _loading = false;
        _loadedUserId = user.id;
      });
      return;
    }

    if (_bytes != null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loadFailed = true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.user;
    final bg = widget.backgroundColor ??
        parseHexColor(u?.iconBgColor) ??
        theme.colorScheme.primaryContainer;
    final fg = widget.foregroundColor ??
        parseHexColor(u?.iconTextColor) ??
        theme.colorScheme.onPrimaryContainer;
    final size = widget.radius * 2;

    if (_bytes != null && !_loadFailed) {
      return ClipOval(
        child: Image.memory(
          _bytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _initialsAvatar(bg, fg, u),
        ),
      );
    }

    return _initialsAvatar(bg, fg, u);
  }

  Widget _initialsAvatar(Color bg, Color fg, AppUser? u) {
    final initials = u == null ? '?' : userAvatarInitials(u.firstName, u.lastName, u.username);
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      foregroundColor: fg,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: widget.radius * 0.72,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class DrawerUserHeader extends StatelessWidget {
  const DrawerUserHeader({
    super.key,
    required this.user,
    required this.roleLabel,
    required this.onLanguageTap,
  });

  final AppUser? user;
  final String roleLabel;
  final VoidCallback onLanguageTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;

    return Material(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  key: ValueKey('drawer-avatar-${user?.id}'),
                  user: user,
                  radius: 28,
                  backgroundColor: parseHexColor(user?.iconBgColor) ?? Colors.white,
                  foregroundColor: parseHexColor(user?.iconTextColor) ?? theme.colorScheme.primary,
                ),
                const Spacer(),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.language,
                  onPressed: onLanguageTap,
                  icon: Icon(Icons.language, color: onPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              user?.displayName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              roleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: onPrimary.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}
