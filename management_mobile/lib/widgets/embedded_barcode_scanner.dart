import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'barcode_scan_window.dart';

class EmbeddedBarcodeScanner extends StatefulWidget {
  const EmbeddedBarcodeScanner({
    super.key,
    required this.onDetect,
    this.enabled = true,
  });

  final ValueChanged<String> onDetect;
  final bool enabled;

  @override
  State<EmbeddedBarcodeScanner> createState() => _EmbeddedBarcodeScannerState();
}

class _EmbeddedBarcodeScannerState extends State<EmbeddedBarcodeScanner> {
  final _controller = MobileScannerController();
  var _started = true;
  Rect? _scanWindow;
  Size? _layoutSize;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _controller.stop();
      _started = false;
    }
  }

  @override
  void didUpdateWidget(covariant EmbeddedBarcodeScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) return;
    if (widget.enabled) {
      _controller.start();
      _started = true;
    } else {
      _controller.stop();
      _started = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!widget.enabled || !_started) return;

    final scanWindow = _scanWindow;
    final layoutSize = _layoutSize;
    Barcode? barcode;
    if (scanWindow != null && layoutSize != null) {
      barcode = firstBarcodeInScanWindow(
        capture,
        scanWindow,
        fit: kBarcodeScannerPreviewFit,
        widgetSize: layoutSize,
      );
    } else {
      barcode = capture.barcodes.firstOrNull;
    }

    final value = barcode?.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    widget.onDetect(value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutSize = constraints.biggest;
        final scanWindow = barcodeScanWindowForSize(
          layoutSize,
          horizontalMargin: 0.05,
          topMargin: 0.12,
          bottomMargin: 0.22,
        );
        _scanWindow = scanWindow;
        _layoutSize = layoutSize;

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                fit: kBarcodeScannerPreviewFit,
                scanWindow: scanWindow,
                overlayBuilder: (context, _) => BarcodeScanWindowOverlay(scanWindow: scanWindow),
              ),
            if (widget.enabled)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Align the barcode inside the white frame',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.flash_off, color: Colors.white, size: 20),
                      onPressed: () => _controller.toggleTorch(),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 20),
                      onPressed: () => _controller.switchCamera(),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }
}
