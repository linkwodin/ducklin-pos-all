import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'barcode_scan_window.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, this.title = 'Scan barcode'});

  final String title;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController();
  var _handled = false;
  Rect? _scanWindow;
  Size? _layoutSize;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

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
    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_off),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layoutSize = constraints.biggest;
          final scanWindow = barcodeScanWindowForSize(
            layoutSize,
            topMargin: 0.12,
            bottomMargin: 0.18,
          );
          _scanWindow = scanWindow;
          _layoutSize = layoutSize;

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                fit: kBarcodeScannerPreviewFit,
                scanWindow: scanWindow,
                overlayBuilder: (context, _) => BarcodeScanWindowOverlay(scanWindow: scanWindow),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Align the barcode inside the white frame.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<String?> openBarcodeScanner(BuildContext context, {String title = 'Scan barcode'}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => BarcodeScannerScreen(title: title)),
  );
}
