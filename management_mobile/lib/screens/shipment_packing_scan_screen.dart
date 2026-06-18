import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../models/shipment.dart';
import '../services/api_service.dart';
import '../services/scan_feedback_service.dart';
import '../utils/scan_movement_gate.dart';
import '../utils/product_barcode.dart';
import '../utils/shipment_packing.dart';
import '../widgets/embedded_barcode_scanner.dart';

enum _PackingStep { scan, boxes }

enum _ScanApplyResult { ok, notFound, alreadyFull, cooldown }

enum _ScanFeedbackKind { success, notFound, overLimit }

class ShipmentPackingScanScreen extends StatefulWidget {
  const ShipmentPackingScanScreen({
    super.key,
    required this.shipmentId,
    required this.courierOptions,
    this.onFinished,
  });

  final int shipmentId;
  final List<String> courierOptions;
  final ValueChanged<Shipment>? onFinished;

  @override
  State<ShipmentPackingScanScreen> createState() => _ShipmentPackingScanScreenState();
}

class _ShipmentPackingScanScreenState extends State<ShipmentPackingScanScreen> {
  var _loading = true;
  var _submitting = false;
  var _step = _PackingStep.scan;
  Shipment? _shipment;
  List<Product> _products = [];
  final _scannedQty = <int, double>{};
  late Map<int, String> _caseQtyByItem;
  final _boxControllers = <int, TextEditingController>{};
  final _manualBarcode = TextEditingController();
  late final ScanMovementGate _movementGate;
  Timer? _movementGateTimer;
  String? _lastScanMessage;
  _ScanFeedbackKind? _lastScanKind;

  @override
  void initState() {
    super.initState();
    _movementGate = ScanMovementGate(onStateChanged: _onMovementGateChanged);
    _movementGate.start();
    _movementGateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _movementGate.tick());
    ScanFeedbackService.instance.ensureReady();
    _load();
  }

  void _syncFocusMode() {
    if (!mounted || _loading || _step != _PackingStep.scan) {
      WakelockPlus.disable();
      return;
    }
    WakelockPlus.enable();
  }

  void _onMovementGateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _movementGateTimer?.cancel();
    _movementGate.dispose();
    _manualBarcode.dispose();
    for (final c in _boxControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _playFeedbackForResult(_ScanApplyResult result) {
    switch (result) {
      case _ScanApplyResult.ok:
        ScanFeedbackService.instance.playSuccess();
      case _ScanApplyResult.notFound:
      case _ScanApplyResult.alreadyFull:
        ScanFeedbackService.instance.playError();
      case _ScanApplyResult.cooldown:
        break;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final shipment = await ApiService.instance.getShipment(widget.shipmentId);
      final products = await ApiService.instance.listProducts();
      if (!mounted) return;
      setState(() {
        _shipment = shipment;
        _products = products;
        _caseQtyByItem = initialCaseQtyFromShipment(shipment);
        for (final c in _boxControllers.values) {
          c.dispose();
        }
        _boxControllers.clear();
        for (final si in effectiveShipmentItemsForPacking(shipment)) {
          final text = _caseQtyByItem[si.wholesaleOrderItemId] ?? '${shipmentExpectedBoxes(si)}';
          _boxControllers[si.wholesaleOrderItemId] = TextEditingController(text: text);
        }
        _scannedQty.clear();
        _step = _PackingStep.scan;
        _lastScanMessage = null;
        _lastScanKind = null;
        _loading = false;
      });
      _syncFocusMode();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
        Navigator.pop(context);
      }
    }
  }

  List<ShipmentPackingLine> get _packingLines {
    final shipment = _shipment;
    if (shipment == null) return [];
    return buildShipmentPackingLines(shipment);
  }

  List<Product> get _scanCatalog {
    final shipment = _shipment;
    if (shipment == null) return [];
    return packingScanCatalog(_products, shipment);
  }

  bool get _allScanned {
    final lines = _packingLines;
    if (lines.isEmpty) return false;
    return lines.every((line) => (_scannedQty[line.productId] ?? 0) >= line.expectedQty - 0.0001);
  }

  void _setScanFeedback(_ScanFeedbackKind kind, String title, {String? detail}) {
    setState(() {
      _lastScanKind = kind;
      _lastScanMessage = detail == null || detail.isEmpty ? title : '$title\n$detail';
    });
  }

  _ScanApplyResult _applyScan(String rawCode, {bool respectScanLock = false}) {
    if (respectScanLock && !_movementGate.scannerEnabled) return _ScanApplyResult.cooldown;

    final product = resolveProductScanForPacking(rawCode, _packingLines, _scanCatalog);
    if (product == null) {
      final l10n = AppLocalizations.of(context)!;
      _setScanFeedback(
        _ScanFeedbackKind.notFound,
        l10n.productNotFound,
        detail: l10n.productNotFoundDetail(rawCode),
      );
      return _ScanApplyResult.notFound;
    }
    final line = _packingLines.firstWhere((l) => l.productId == product.id);
    final already = _scannedQty[product.id] ?? 0;
    if (line.expectedQty - already <= 0.0001) {
      final l10n = AppLocalizations.of(context)!;
      final expected = formatPackingQty(line.expectedQty);
      _setScanFeedback(
        _ScanFeedbackKind.overLimit,
        l10n.quantityAlreadyComplete,
        detail: l10n.quantityAlreadyCompleteDetail(product.displayName(), expected, expected),
      );
      return _ScanApplyResult.alreadyFull;
    }
    final next = already + 1;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _scannedQty[product.id] = next;
      _lastScanKind = _ScanFeedbackKind.success;
      _lastScanMessage = l10n.scanProgress(
        product.displayName(),
        formatPackingQty(next),
        formatPackingQty(line.expectedQty),
      );
    });
    return _ScanApplyResult.ok;
  }

  void _handleCameraScan(String rawCode) {
    if (!_movementGate.scannerEnabled) return;
    final result = _applyScan(rawCode, respectScanLock: true);
    _playFeedbackForResult(result);
    if (result == _ScanApplyResult.cooldown) return;
    _movementGate.lockAfterScan();
  }

  void _handleManualScan() {
    final code = _manualBarcode.text.trim();
    if (code.isEmpty) return;
    final result = _applyScan(code);
    _playFeedbackForResult(result);
    _manualBarcode.clear();
  }

  Future<void> _finish() async {
    final shipment = _shipment;
    if (shipment == null) return;
    setState(() => _submitting = true);
    try {
      final order = await ApiService.instance.getWholesaleOrder(shipment.wholesaleOrderId);
      if (order.status == 'assign_shipment') {
        await ApiService.instance.completeWholesaleAssignment(order.id);
      }
      final updated = await ApiService.instance.startShipment(
        shipment.id,
        caseQty: caseQtyPayload(
          shipment,
          {for (final e in _boxControllers.entries) e.key: e.value.text},
        ),
      );
      widget.onFinished?.call(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildScanBody() {
    final l10n = AppLocalizations.of(context)!;
    final remaining = _movementGate.remainingLock;
    final remainingSeconds = remaining == null ? 0 : remaining.inSeconds.clamp(0, 3);
    final movementDone = _movementGate.movementDetected;
    final scanLocked = _movementGate.isLocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              EmbeddedBarcodeScanner(
                enabled: _movementGate.scannerEnabled,
                onDetect: _handleCameraScan,
              ),
              if (scanLocked)
                Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          movementDone ? Icons.check_circle_outline : Icons.open_with,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.findNextItemToScan,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ScanLockStep(
                          done: movementDone,
                          label: movementDone ? l10n.phoneTurnedNext : l10n.turnPhoneNext,
                        ),
                        const SizedBox(height: 8),
                        _ScanLockStep(
                          done: remainingSeconds == 0,
                          label: remainingSeconds == 0
                              ? l10n.pauseComplete
                              : l10n.pauseForSeconds(remainingSeconds),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_lastScanMessage != null && _lastScanKind != null) _buildScanFeedbackBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualBarcode,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.manualBarcode,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleManualScan(),
                ),
              ),
              IconButton(
                onPressed: _handleManualScan,
                icon: const Icon(Icons.keyboard_return),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: _ProductScanList(
            lines: _packingLines,
            scannedQty: _scannedQty,
            onReset: (productId) => setState(() => _scannedQty.remove(productId)),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FilledButton(
              onPressed: _allScanned
                  ? () {
                      setState(() => _step = _PackingStep.boxes);
                      _syncFocusMode();
                    }
                  : null,
              child: Text(AppLocalizations.of(context)!.nextConfirmBoxes),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLaterStepsBody() {
    final shipment = _shipment!;
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.confirmBoxes, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _BoxesStep(
          shipment: shipment,
          controllers: _boxControllers,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: _submitting
                  ? null
                  : () {
                      setState(() => _step = _PackingStep.scan);
                      _syncFocusMode();
                    },
              child: Text(l10n.back),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _submitting ? null : _finish,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.finishPacking),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (_loading || shipment == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.packShipment)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.packOrder(shipment.orderNumber ?? '#${shipment.id}')),
        actions: [
          if (_step == _PackingStep.scan)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Tooltip(
                  message: l10n.focusModeTooltip,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.screen_lock_portrait, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        l10n.focusMode,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _step == _PackingStep.scan ? l10n.scanStep : l10n.boxesStep,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: _step == _PackingStep.scan ? _buildScanBody() : _buildLaterStepsBody(),
    );
  }

  Widget _buildScanFeedbackBanner() {
    final theme = Theme.of(context);
    final kind = _lastScanKind!;
    final message = _lastScanMessage!;
    final lines = message.split('\n');
    final title = lines.first;
    final detail = lines.length > 1 ? lines.sublist(1).join('\n') : null;

    late final Color background;
    late final Color foreground;
    late final IconData icon;

    switch (kind) {
      case _ScanFeedbackKind.success:
        background = Colors.green.shade50;
        foreground = Colors.green.shade900;
        icon = Icons.check_circle;
      case _ScanFeedbackKind.notFound:
        background = theme.colorScheme.errorContainer;
        foreground = theme.colorScheme.onErrorContainer;
        icon = Icons.error_outline;
      case _ScanFeedbackKind.overLimit:
        background = Colors.orange.shade100;
        foreground = Colors.orange.shade900;
        icon = Icons.warning_amber_rounded;
    }

    return Material(
      elevation: kind == _ScanFeedbackKind.success ? 0 : 2,
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanLockStep extends StatelessWidget {
  const _ScanLockStep({required this.done, required this.label});

  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? Colors.lightGreenAccent : Colors.white70,
          size: 18,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: done ? Colors.white : Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: done ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductScanList extends StatelessWidget {
  const _ProductScanList({
    required this.lines,
    required this.scannedQty,
    required this.onReset,
  });

  final List<ShipmentPackingLine> lines;
  final Map<int, double> scannedQty;
  final ValueChanged<int> onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(l10n.products, style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final scanned = scannedQty[line.productId] ?? 0;
              final done = scanned >= line.expectedQty - 0.0001;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: done ? Colors.green.shade50 : null,
                child: ListTile(
                  dense: true,
                  title: Text(line.product.displayName(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    l10n.needQtyBoxes(
                      formatPackingQty(line.expectedQty),
                      formatPackingQty(line.expectedBoxes),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${formatPackingQty(scanned)}/${formatPackingQty(line.expectedQty)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: done ? Colors.green.shade800 : null,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () => onReset(line.productId),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BoxesStep extends StatelessWidget {
  const _BoxesStep({
    required this.shipment,
    required this.controllers,
  });

  final Shipment shipment;
  final Map<int, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = effectiveShipmentItemsForPacking(shipment);
    return Column(
      children: items.map((si) {
        final product = si.wholesaleOrderItem?.product;
        final expected = shipmentExpectedBoxes(si);
        final controller = controllers[si.wholesaleOrderItemId];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product?.displayName() ?? 'Item #${si.wholesaleOrderItemId}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(l10n.expectedBoxes(formatPackingQty(si.effectiveQty()), expected)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: l10n.boxes),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
