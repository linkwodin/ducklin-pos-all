import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_cache_service.dart';

/// Product image that is downloaded once to local storage and not re-downloaded when URL is unchanged.
class CachedProductImage extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;

  const CachedProductImage({
    super.key,
    required this.imageUrl,
    this.width = 50,
    this.height = 50,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').toString().trim();
    if (url.isEmpty) return _placeholder(context);

    return FutureBuilder<String?>(
      key: ValueKey(url),
      future: ImageCacheService.getOrDownload(url, subdir: ImageCacheService.subdirProductImages),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final filePath = snapshot.data!;
          if (File(filePath).existsSync()) {
            return Image.file(
              File(filePath),
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, __, ___) => _placeholder(context),
            );
          }
        }
        return _placeholder(context);
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: Text(
          '?',
          style: TextStyle(
            fontSize: width * 0.5,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
      ),
    );
  }
}
