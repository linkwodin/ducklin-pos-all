import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../utils/product_barcode_packing.dart';
import '../utils/product_display.dart';
import '../utils/shipment_expected_boxes.dart';
import '../utils/shipment_packing.dart';
import '../utils/wholesale_order_assignment.dart';
import '../widgets/cached_product_image.dart';
import '../widgets/wizard_step_header.dart';

typedef ShipmentPackingFinishPayload = ({
  List<Map<String, dynamic>> caseQty,
  String? deliveryDate,
  String? courier,
  String? trackingNumber,
});

class ShipmentPackingScanPanel extends StatefulWidget {
  const ShipmentPackingScanPanel({
    super.key,
    required this.shipment,
    required this.products,
    required this.storeStock,
    required this.courierOptions,
    required this.submitting,
    required this.onFinish,
  });

  final Map<String, dynamic> shipment;
  final List<Map<String, dynamic>> products;
  final List<dynamic> storeStock;
  final List<String> courierOptions;
  final bool submitting;
  final void Function(ShipmentPackingFinishPayload payload) onFinish;

  @override
  State<ShipmentPackingScanPanel> createState() => _ShipmentPackingScanPanelState();
}

class _ShipmentPackingScanPanelState extends State<ShipmentPackingScanPanel> {
  static const _steps = ['scan', 'boxes', 'courier'];
  static const _stepLabels = ['Scan items', 'Confirm boxes', 'Courier'];

  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  Timer? _scanDebounce;

  String _step = 'scan';
  final Map<int, double> _scannedQty = {};
  final Map<int, TextEditingController> _caseQtyControllers = {};
  late String _courierDraft;
  late String _trackingDraft;
  late String _deliveryDateDraft;

  late final TextEditingController _trackingController;
  late final TextEditingController _deliveryDateController;

  Future<void> _showExceedDialog({
    required ShipmentPackingLine line,
    required int productId,
    required double scanDelta,
    required double alreadyScanned,
    required double applied,
    required String mode,
  }) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan exceeds order'),
        content: Text(
          mode == 'full'
              ? '${productDisplayName(line.product, lang)} is already fully scanned '
                  '(${formatPackingQty(alreadyScanned)} / ${formatPackingQty(line.expectedQty)}).'
              : 'Scan would exceed order for ${productDisplayName(line.product, lang)}. '
                  'Count remaining ${formatPackingQty(applied)}?',
        ),
        actions: [
          if (mode == 'capped')
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, mode == 'capped'),
            child: Text(mode == 'capped' ? 'Count remaining' : 'OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (mode == 'capped' && confirmed == true) {
      _finishScan(productId, line, applied, alreadyScanned);
    } else {
      _focusBarcode();
    }
  }

  Future<void> _showNoStockAdvanceDialog() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No stock warning'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Some items have no stock. Continue packing?'),
            const SizedBox(height: 8),
            ..._noStockLines.map((line) => Text('• ${productDisplayName(line.product, lang)}')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) setState(() => _step = 'boxes');
  }

  List<ShipmentPackingLine> get _packingLines => buildShipmentPackingLines(widget.shipment);
  List<Map<String, dynamic>> get _packingItems => effectiveShipmentItemsForPacking(widget.shipment);
  List<Map<String, dynamic>> get _scanCatalog => packingScanCatalog(widget.products, widget.shipment);
  Map<int, Map<String, dynamic>> get _stockMap => stockByProductId(widget.storeStock);

  @override
  void initState() {
    super.initState();
    _trackingController = TextEditingController();
    _deliveryDateController = TextEditingController();
    _resetForShipment();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusBarcode());
  }

  @override
  void didUpdateWidget(covariant ShipmentPackingScanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shipment['id'] != widget.shipment['id']) {
      _resetForShipment();
      _focusBarcode();
    }
  }

  void _resetForShipment() {
    _step = 'scan';
    _scannedQty.clear();
    _barcodeController.clear();
    _syncCaseQtyControllers();
    _courierDraft = widget.shipment['courier']?.toString() ?? '';
    _trackingDraft = widget.shipment['tracking_number']?.toString() ?? '';
    final delivery = widget.shipment['delivery_date']?.toString();
    _deliveryDateDraft = delivery != null && delivery.length >= 10
        ? delivery.substring(0, 10)
        : _todayString();
    _trackingController.text = _trackingDraft;
    _deliveryDateController.text = _deliveryDateDraft;
  }

  void _syncCaseQtyControllers() {
    for (final controller in _caseQtyControllers.values) {
      controller.dispose();
    }
    _caseQtyControllers.clear();
    final initial = initialCaseQtyFromShipment(widget.shipment);
    for (final si in effectiveShipmentItemsForPacking(widget.shipment)) {
      final itemId = (si['wholesale_order_item_id'] as num).toInt();
      final text = initial['$itemId']?.toString() ?? '';
      _caseQtyControllers[itemId] = TextEditingController(text: text)
        ..addListener(_onCaseQtyChanged);
    }
  }

  void _onCaseQtyChanged() {
    if (mounted && _step == 'boxes') setState(() {});
  }

  String _todayString() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  @override
  void dispose() {
    _scanDebounce?.cancel();
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    for (final controller in _caseQtyControllers.values) {
      controller.dispose();
    }
    _caseQtyControllers.clear();
    _trackingController.dispose();
    _deliveryDateController.dispose();
    super.dispose();
  }

  void _focusBarcode() {
    if (_step != 'scan' || !mounted) return;
    _barcodeFocus.requestFocus();
    _barcodeController.selection = TextSelection(baseOffset: 0, extentOffset: _barcodeController.text.length);
  }

  bool get _allScanned {
    final lines = _packingLines;
    if (lines.isEmpty) return false;
    return lines.every((line) => (_scannedQty[line.productId] ?? 0) >= line.expectedQty - 0.0001);
  }

  List<ShipmentPackingLine> get _noStockLines {
    return _packingLines.where((line) {
      final stock = _stockMap[line.productId];
      return hasNoStock(availableStockForProduct(stock, line.product));
    }).toList();
  }

  bool _lineHasNoStock(ShipmentPackingLine line) {
    final stock = _stockMap[line.productId];
    return hasNoStock(availableStockForProduct(stock, line.product));
  }

  void _handleBarcodeSubmit([String? rawCode]) {
    final code = normalizeBarcodeScanInput(rawCode ?? _barcodeController.text);
    if (code.isEmpty) return;

    final scanned = resolveProductScanForPacking(code, _packingLines, _scanCatalog);
    if (scanned == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Barcode not found: $code')));
      _barcodeController.clear();
      _focusBarcode();
      return;
    }

    final productId = (scanned['id'] as num).toInt();
    final line = _packingLines.cast<ShipmentPackingLine?>().firstWhere(
          (l) => l!.productId == productId,
          orElse: () => null,
        );
    if (line == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product not in this shipment')));
      _barcodeController.clear();
      _focusBarcode();
      return;
    }

    final alreadyScanned = _scannedQty[productId] ?? 0;
    final remaining = line.expectedQty - alreadyScanned;
    final scanDelta = packingScanDelta(line.product, scanned);
    _barcodeController.clear();

    if (remaining <= 0.0001) {
      _showExceedDialog(
        line: line,
        productId: productId,
        scanDelta: scanDelta,
        alreadyScanned: alreadyScanned,
        applied: 0,
        mode: 'full',
      );
      return;
    }

    if (alreadyScanned + scanDelta > line.expectedQty + 0.0001) {
      _showExceedDialog(
        line: line,
        productId: productId,
        scanDelta: scanDelta,
        alreadyScanned: alreadyScanned,
        applied: scanDelta < remaining ? scanDelta : remaining,
        mode: 'capped',
      );
      return;
    }

    _finishScan(productId, line, scanDelta, alreadyScanned);
  }

  void _finishScan(int productId, ShipmentPackingLine line, double scanDelta, double alreadyScanned) {
    final remaining = line.expectedQty - alreadyScanned;
    final applied = scanDelta < remaining ? scanDelta : remaining;
    setState(() {
      _scannedQty[productId] = alreadyScanned + applied;
    });
    final lang = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scanned ${productDisplayName(line.product, lang)}: '
          '${formatPackingQty(_scannedQty[productId] ?? 0)} / ${formatPackingQty(line.expectedQty)}',
        ),
      ),
    );
    _focusBarcode();
  }

  void _onBarcodeChanged(String value) {
    _scanDebounce?.cancel();
    final trimmed = normalizeBarcodeScanInput(value);
    if (shouldAutoSubmitBarcodeLength(trimmed)) {
      _scanDebounce = Timer(const Duration(milliseconds: 300), () => _handleBarcodeSubmit(trimmed));
    }
  }

  ShipmentPackingFinishPayload _buildFinishPayload() {
    return (
      caseQty: _packingItems.map((si) {
        final itemId = (si['wholesale_order_item_id'] as num).toInt();
        final value = _caseQtyControllers[itemId]?.text ?? '0';
        return {
          'wholesale_order_item_id': itemId,
          'case_qty': (double.tryParse(value) ?? 0).round(),
        };
      }).toList(),
      deliveryDate: _deliveryDateDraft.trim().isEmpty ? null : _deliveryDateDraft.trim(),
      courier: _courierDraft.trim().isEmpty ? null : _courierDraft.trim(),
      trackingNumber: _trackingDraft.trim().isEmpty ? null : _trackingDraft.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context).locale.languageCode;
    final stepIndex = _steps.indexOf(_step);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WizardStepHeader(currentStep: stepIndex, labels: _stepLabels),
            const SizedBox(height: 16),
            if (_step == 'scan') ...[
              const Text('Scan each item to pack', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_noStockLines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_noStockLines.length} item(s) have no stock — you can still pack.',
                    style: TextStyle(color: Colors.orange[800]),
                  ),
                ),
              if (_packingLines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('No packing lines for this shipment.', style: TextStyle(color: Colors.red)),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeController,
                      focusNode: _barcodeFocus,
                      decoration: const InputDecoration(
                        hintText: 'Scan barcode...',
                        prefixIcon: Icon(Icons.qr_code_scanner),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onBarcodeChanged,
                      onSubmitted: (_) => _handleBarcodeSubmit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _packingLines.isEmpty ? null : () => _handleBarcodeSubmit(),
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._packingLines.map((line) {
                final scanned = _scannedQty[line.productId] ?? 0;
                final satisfied = scanned >= line.expectedQty - 0.0001;
                final name = productDisplayName(line.product, lang);
                final imageUrl = line.product['image_url']?.toString();
                return Card(
                  color: satisfied ? Colors.green.shade50 : null,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: SizedBox(
                      width: 44,
                      height: 44,
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? CachedProductImage(imageUrl: imageUrl, width: 44, height: 44, fit: BoxFit.cover)
                          : Container(color: Colors.grey[300], child: const Icon(Icons.inventory_2)),
                    ),
                    title: Text(name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(packingLineSubtitle(line)),
                        if (_lineHasNoStock(line))
                          Chip(
                            label: const Text('No stock'),
                            backgroundColor: Colors.orange.shade100,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatPackingQty(scanned),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: satisfied ? Colors.green : Colors.orange,
                          ),
                        ),
                        if (satisfied) const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () => setState(() => _scannedQty.remove(line.productId)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _allScanned
                      ? () {
                          if (_noStockLines.isNotEmpty) {
                            _showNoStockAdvanceDialog();
                          } else {
                            setState(() => _step = 'boxes');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next: confirm boxes'),
                ),
              ),
              if (!_allScanned)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('Scan all items first', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
            if (_step == 'boxes') _buildBoxesStep(lang),
            if (_step == 'courier') ...[
              const Text('Courier & delivery', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _courierDraft),
                optionsBuilder: (value) {
                  if (value.text.isEmpty) return widget.courierOptions;
                  return widget.courierOptions
                      .where((c) => c.toLowerCase().contains(value.text.toLowerCase()));
                },
                onSelected: (v) => setState(() => _courierDraft = v),
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  controller.text = _courierDraft;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Courier', border: OutlineInputBorder()),
                    onChanged: (v) => _courierDraft = v,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tracking number',
                  border: OutlineInputBorder(),
                  helperText: 'Optional — saved on delivery note; mark shipped via courier pickup',
                ),
                controller: _trackingController,
                onChanged: (v) => _trackingDraft = v,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: 'Delivery date', border: OutlineInputBorder()),
                controller: _deliveryDateController,
                onChanged: (v) => _deliveryDateDraft = v,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: widget.submitting ? null : () => setState(() => _step = 'boxes'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  FilledButton.icon(
                    onPressed: widget.submitting ? null : () => widget.onFinish(_buildFinishPayload()),
                    icon: widget.submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.local_shipping),
                    label: Text(widget.submitting ? 'Processing...' : 'Finish packing'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBoxesStep(String lang) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Confirm box counts', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          'Adjust box counts if needed. The change column updates as you edit.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Table(
          border: TableBorder.all(color: theme.dividerColor),
          columnWidths: const {
            0: FlexColumnWidth(4),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
              children: [
                _boxTableCell('Product', bold: true),
                _boxTableCell('Qty', bold: true, align: TextAlign.right),
                _boxTableCell('Expected', bold: true, align: TextAlign.right),
                _boxTableCell('Boxes', bold: true, align: TextAlign.right),
                _boxTableCell('Change', bold: true, align: TextAlign.right),
              ],
            ),
            ..._packingItems.map((si) {
              final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
              final product = woItem?['product'] as Map<String, dynamic>?;
              final itemId = (si['wholesale_order_item_id'] as num).toInt();
              final name = product != null ? productDisplayName(product, lang) : 'Item #$itemId';
              final lineQty = formatAssignmentQty(effectiveShipmentItemQty(si));
              final expected = shipmentExpectedBoxes(si).round();
              final controller = _caseQtyControllers[itemId]!;
              final actual = double.tryParse(controller.text) ?? 0;
              final delta = actual.round() - expected;
              final deltaText = delta > 0 ? '+$delta' : delta < 0 ? '$delta' : '—';
              final deltaColor = delta > 0
                  ? Colors.green
                  : delta < 0
                      ? Colors.red
                      : theme.colorScheme.onSurfaceVariant;
              return TableRow(
                children: [
                  _boxTableCell(name),
                  _boxTableCell(lineQty, align: TextAlign.right),
                  _boxTableCell('$expected', align: TextAlign.right),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                  ),
                  _boxTableCell(deltaText, align: TextAlign.right, color: deltaColor),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _step = 'scan'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            FilledButton.icon(
              onPressed: () => setState(() => _step = 'courier'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next: courier'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _boxTableCell(
    String text, {
    bool bold = false,
    TextAlign align = TextAlign.left,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}
