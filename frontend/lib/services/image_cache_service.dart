import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'api_service.dart';

/// Downloads images to local storage and returns cached path.
/// Does not re-download if the URL has not changed (same URL → same cached file).
class ImageCacheService {
  static const String subdirLogo = 'logo';
  static const String subdirProductImages = 'product_images';

  static final Map<String, String> _cacheDirPaths = {};

  static Future<String> _getCacheDir(String subdir) async {
    if (_cacheDirPaths[subdir] != null) return _cacheDirPaths[subdir]!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(base.path, 'pos_system', subdir));
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDirPaths[subdir] = dir.path;
    return _cacheDirPaths[subdir]!;
  }

  /// Produces a unique cache key from the full URL (SHA-256 hash) so no two URLs collide.
  /// Truncation was causing different product image URLs to share the same key and show wrong images.
  static String _cacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Returns the path to the cached image for [url]. Downloads and saves to [subdir]
  /// if not already cached. Does not re-download if the URL has not changed.
  static Future<String?> getOrDownload(String url, {String subdir = subdirLogo}) async {
    if (url.isEmpty) return null;
    try {
      final dir = await _getCacheDir(subdir);
      final key = _cacheKey(url);
      final ext = _extensionFromUrl(url);
      final filePath = path.join(dir, '$key$ext');
      final file = File(filePath);
      if (await file.exists()) return filePath;

      final response = await ApiService.instance.downloadUrl(url);
      if (response == null) return null;
      await file.writeAsBytes(response);
      return filePath;
    } catch (e) {
      debugPrint('ImageCacheService: getOrDownload failed for $url: $e');
      return null;
    }
  }

  static String _extensionFromUrl(String url) {
    final lower = url.split('?').first.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '.jpg';
    if (lower.endsWith('.gif')) return '.gif';
    if (lower.endsWith('.webp')) return '.webp';
    return '.img';
  }

  /// Clears the product images cache so next load re-downloads. Use for full resync.
  static Future<void> clearProductImageCache() async {
    try {
      final dir = await _getCacheDir(subdirProductImages);
      final directory = Directory(dir);
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          try {
            if (entity is File) await entity.delete();
            if (entity is Directory) await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
      debugPrint('ImageCacheService: product image cache cleared');
    } catch (e) {
      debugPrint('ImageCacheService: clearProductImageCache failed: $e');
    }
  }
}
