import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_cache_service.dart';

class Logo extends StatelessWidget {
  final Color textColor;
  final double fontSize;
  /// If set, this image is downloaded to local storage (logo directory) and shown.
  /// Not re-downloaded if the URL has not changed.
  final String? imageUrl;

  const Logo({
    super.key,
    this.textColor = Colors.black,
    this.fontSize = 24,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      return FutureBuilder<String?>(
        future: ImageCacheService.getOrDownload(imageUrl!.trim()),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final path = snapshot.data!;
            if (File(path).existsSync()) {
              return Image.file(
                File(path),
                height: fontSize,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
              );
            }
          }
          return _buildFallback();
        },
      );
    }
    return _buildAssetLogo(context);
  }

  Widget _buildFallback() {
    return Text(
      '德靈公司 POS',
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildAssetLogo(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: fontSize,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/images/logo.avif',
          height: fontSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      },
    );
  }
}

