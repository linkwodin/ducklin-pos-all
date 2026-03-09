import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/cached_product_image.dart';
import 'weight_input_dialog.dart';

/// Packing flow for one shipment: scan each item (barcode) and qty; complete when all lines satisfied.
class ShipmentPackingDetailScreen extends StatefulWidget {
  const ShipmentPackingDetailScreen({
    super.key,
    required this.shipment,
    required this.onCompleted,
  });

  final Map<String, dynamic> shipment;
  final VoidCallback? onCompleted;

  @override
  State<ShipmentPackingDetailScreen> createState() => _ShipmentPackingDetailScreenState();
}

class _ShipmentPackingDetailScreenState extends State<ShipmentPackingDetailScreen> {
  /// product_id -> scanned quantity
  final Map<int, double> _scannedQty = {};
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  bool _submitting = false;

  List<_PackingLine> get _expectedLines {
    final items = widget.shipment['items'] as List<dynamic>? ?? [];
    final byProduct = <int, _PackingLine>{};
    for (final si in items) {
      final woItem = si is Map ? si['wholesale_order_item'] as Map<String, dynamic>? : null;
      if (woItem == null) continue;
      final productId = woItem['product_id'] is int ? woItem['product_id'] as int : (woItem['product_id'] as num).toInt();
      final expectedQty = woItem['quantity'] is num ? (woItem['quantity'] as num).toDouble() : 0.0;
      final product = woItem['product'] as Map<String, dynamic>?;
      if (byProduct.containsKey(productId)) {
        byProduct[productId] = _PackingLine(
          productId: productId,
          expectedQty: byProduct[productId]!.expectedQty + expectedQty,
          product: product ?? byProduct[productId]!.product,
        );
      } else {
        byProduct[productId] = _PackingLine(productId: productId, expectedQty: expectedQty, product: product ?? {});
      }
    }
    return byProduct.values.toList();
  }

  bool get _allSatisfied {
    for (final line in _expectedLines) {
      final scanned = _scannedQty[line.productId] ?? 0.0;
      if (scanned < line.expectedQty - 0.0001) return false;
    }
    return _expectedLines.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barcodeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  String _productName(Map<String, dynamic>? product, bool useChinese) {
    if (product == null) return '—';
    final name = product['name']?.toString() ?? '';
    final zh = product['name_chinese']?.toString();
    if (useChinese && zh != null && zh.isNotEmpty) return zh;
    return name.isNotEmpty ? name : (zh ?? '—');
  }

  Future<void> _onBarcodeSubmitted(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return;

    final product = await DatabaseService.instance.getProductByBarcode(code);
    if (product == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product not found for barcode: $code')),
        );
      }
      _barcodeController.clear();
      return;
    }

    final productId = product['id'] as int;
    _PackingLine? line;
    for (final l in _expectedLines) {
      if (l.productId == productId) {
        line = l;
        break;
      }
    }
    if (line == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not in this shipment')),
        );
      }
      _barcodeController.clear();
      return;
    }

    final unitType = (product['unit_type'] ?? 'quantity').toString().toLowerCase();
    final isWeight = unitType == 'weight';
    final alreadyScanned = _scannedQty[productId] ?? 0.0;
    final remaining = line.expectedQty - alreadyScanned;

    if (remaining <= 0.0001) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Already packed full quantity for ${_productName(line.product, Provider.of<LanguageProvider>(context, listen: false).locale.languageCode == 'zh')}')),
        );
      }
      _barcodeController.clear();
      return;
    }

    if (isWeight) {
      final weight = await showDialog<double>(
        context: context,
        builder: (ctx) => const WeightInputDialog(),
      );
      if (weight == null || weight <= 0 || !mounted) {
        _barcodeController.clear();
        return;
      }
      // Do not allow scanning more than required for this line.
      final applied = weight > remaining ? remaining : weight;
      setState(() {
        _scannedQty[productId] = alreadyScanned + applied;
      });
      if (weight > remaining && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Only $remaining remaining for this product. Count set to full.')),
        );
      }
    } else {
      if (remaining <= 0.9999) {
        // Would exceed required quantity – block the scan.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Already packed full quantity for ${_productName(line.product, Provider.of<LanguageProvider>(context, listen: false).locale.languageCode == 'zh')}')),
          );
        }
      } else {
        setState(() {
          _scannedQty[productId] = alreadyScanned + 1;
        });
      }
    }
    _barcodeController.clear();
    if (mounted) _barcodeFocus.requestFocus();
  }

  Future<void> _completePacking() async {
    final shipmentId = widget.shipment['id'] is int ? widget.shipment['id'] as int : (widget.shipment['id'] as num).toInt();
    setState(() => _submitting = true);
    try {
      await ApiService.instance.completeShipmentPacking(shipmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Packing completed. Delivery note generated.')));
      widget.onCompleted?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final useChinese = languageProvider.locale.languageCode == 'zh';
    final order = widget.shipment['wholesale_order'] as Map<String, dynamic>?;
    final orderNumber = order?['order_number']?.toString() ?? '—';
    final lines = _expectedLines;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pack: $orderNumber'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocus,
              decoration: const InputDecoration(
                hintText: 'Scan barcode...',
                prefixIcon: Icon(Icons.qr_code_scanner),
                border: OutlineInputBorder(),
              ),
              onSubmitted: _onBarcodeSubmitted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Scan each item. By-weight products: enter weight after scan.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                final scanned = _scannedQty[line.productId] ?? 0.0;
                final satisfied = scanned >= line.expectedQty - 0.0001;
                final product = line.product;
                final imageUrl = product['image_url']?.toString();
                final name = _productName(product, useChinese);
                return ListTile(
                  leading: SizedBox(
                    width: 44,
                    height: 44,
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? CachedProductImage(imageUrl: imageUrl, width: 44, height: 44, fit: BoxFit.cover)
                        : Container(color: Colors.grey[300], child: const Center(child: Icon(Icons.inventory_2))),
                  ),
                  title: Text(name),
                  subtitle: Text('Expected: ${line.expectedQty == line.expectedQty.roundToDouble() ? line.expectedQty.toInt() : line.expectedQty}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Scanned: ${scanned == scanned.roundToDouble() ? scanned.toInt() : scanned.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: satisfied ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (satisfied)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                        ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Reset scanned count',
                        onPressed: () {
                          setState(() {
                            _scannedQty.remove(line.productId);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline),
                label: Text(_submitting ? 'Completing...' : 'Complete packing'),
                onPressed: (_submitting || !_allSatisfied) ? null : _completePacking,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackingLine {
  _PackingLine({required this.productId, required this.expectedQty, required this.product});
  final int productId;
  final double expectedQty;
  final Map<String, dynamic> product;
}
