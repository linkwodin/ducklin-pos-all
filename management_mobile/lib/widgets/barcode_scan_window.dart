import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Fills the preview area without letterboxing. Use with [scanWindow] to limit detection.
const kBarcodeScannerPreviewFit = BoxFit.cover;

/// Visible scan region inside the camera preview widget.
Rect barcodeScanWindowForSize(
  Size size, {
  double horizontalMargin = 0.07,
  double topMargin = 0.14,
  double bottomMargin = 0.22,
}) {
  return Rect.fromLTRB(
    size.width * horizontalMargin,
    size.height * topMargin,
    size.width * (1 - horizontalMargin),
    size.height * (1 - bottomMargin),
  );
}

class BarcodeScanWindowOverlay extends StatelessWidget {
  const BarcodeScanWindowOverlay({super.key, required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BarcodeScanWindowPainter(scanWindow),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BarcodeScanWindowPainter extends CustomPainter {
  _BarcodeScanWindowPainter(this.scanWindow);

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPath = Path()..addRect(Offset.zero & size);
    final frame = RRect.fromRectAndRadius(scanWindow, const Radius.circular(12));
    final cutoutPath = Path()..addRRect(frame);

    canvas.drawPath(
      Path.combine(PathOperation.difference, dimPath, cutoutPath),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _BarcodeScanWindowPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}

/// Returns the first barcode whose center lies inside [scanWindow], mapped to widget space.
Barcode? firstBarcodeInScanWindow(
  BarcodeCapture capture,
  Rect scanWindow, {
  required BoxFit fit,
  required Size widgetSize,
}) {
  final imageSize = capture.size;
  if (imageSize.isEmpty || widgetSize.isEmpty) {
    return capture.barcodes.firstOrNull;
  }

  for (final barcode in capture.barcodes) {
    if (barcode.corners.isEmpty) continue;
    final center = _barcodeCenter(barcode);
    final mapped = _mapImagePointToWidget(center, imageSize: imageSize, widgetSize: widgetSize, fit: fit);
    if (scanWindow.contains(mapped)) return barcode;
  }
  return null;
}

Offset _barcodeCenter(Barcode barcode) {
  var x = 0.0;
  var y = 0.0;
  for (final corner in barcode.corners) {
    x += corner.dx;
    y += corner.dy;
  }
  return Offset(x / barcode.corners.length, y / barcode.corners.length);
}

Offset _mapImagePointToWidget(
  Offset point, {
  required Size imageSize,
  required Size widgetSize,
  required BoxFit fit,
}) {
  final fitted = applyBoxFit(fit, imageSize, widgetSize);
  var sx = fitted.destination.width / imageSize.width;
  var sy = fitted.destination.height / imageSize.height;

  switch (fit) {
    case BoxFit.contain:
      final scale = sx < sy ? sx : sy;
      sx = scale;
      sy = scale;
    case BoxFit.cover:
      final scale = sx > sy ? sx : sy;
      sx = scale;
      sy = scale;
    case BoxFit.fitWidth:
      sy = sx;
    case BoxFit.fitHeight:
      sx = sy;
    case BoxFit.fill:
    case BoxFit.none:
    case BoxFit.scaleDown:
      break;
  }

  final textureWindow = Alignment.center.inscribe(
    Size(imageSize.width * sx, imageSize.height * sy),
    Rect.fromLTWH(0, 0, widgetSize.width, widgetSize.height),
  );

  return Offset(
    textureWindow.left + point.dx * sx,
    textureWindow.top + point.dy * sy,
  );
}
