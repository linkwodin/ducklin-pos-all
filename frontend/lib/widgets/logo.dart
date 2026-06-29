import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class Logo extends StatefulWidget {
  final Color textColor;
  /// Text size for the fallback label.
  final double fontSize;
  /// Image display height (defaults to [fontSize] when omitted).
  final double? height;
  /// If set, downloaded and shown from the API server.
  final String? imageUrl;
  /// Shown when no image is available (defaults to generic POS label).
  final String? fallbackText;

  const Logo({
    super.key,
    this.textColor = Colors.black,
    this.fontSize = 24,
    this.height,
    this.imageUrl,
    this.fallbackText,
  });

  @override
  State<Logo> createState() => _LogoState();
}

class _LogoState extends State<Logo> {
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolvedUrl = _resolve(widget.imageUrl);
  }

  @override
  void didUpdateWidget(Logo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolvedUrl = _resolve(widget.imageUrl);
    }
  }

  String? _resolve(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return ApiService.instance.resolveAssetUrl(trimmed);
  }

  double get _imageHeight => widget.height ?? widget.fontSize;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedUrl;
    if (resolved != null && resolved.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: resolved,
        height: _imageHeight,
        fit: BoxFit.contain,
        placeholder: (_, __) => SizedBox(
          height: _imageHeight,
          width: _imageHeight,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _buildAssetLogo(),
      );
    }
    return _buildAssetLogo();
  }

  Widget _buildFallback() {
    final label = (widget.fallbackText?.trim().isNotEmpty == true)
        ? widget.fallbackText!.trim()
        : 'POS';
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: widget.textColor,
        fontSize: widget.fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildAssetLogo() {
    return Image.asset(
      'assets/images/logo.png',
      height: _imageHeight,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/images/logo.avif',
          height: _imageHeight,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      },
    );
  }
}
