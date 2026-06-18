import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/shipment.dart';
import '../utils/shipment_packing.dart';
import 'shipment_packing_scan_screen.dart';

class ShipmentPackingQueueScreen extends StatefulWidget {
  const ShipmentPackingQueueScreen({
    super.key,
    required this.queue,
    required this.courierOptions,
    this.onShipmentPacked,
  });

  final List<Shipment> queue;
  final List<String> courierOptions;
  final ValueChanged<Shipment>? onShipmentPacked;

  @override
  State<ShipmentPackingQueueScreen> createState() => _ShipmentPackingQueueScreenState();
}

class _ShipmentPackingQueueScreenState extends State<ShipmentPackingQueueScreen> {
  late List<Shipment> _queue;
  final _skipped = <int>{};

  @override
  void initState() {
    super.initState();
    _queue = widget.queue.where((s) => shipmentNeedsPacking(s.status)).toList()
      ..sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
  }

  List<Shipment> get _active =>
      _queue.where((s) => !_skipped.contains(s.id)).toList();

  Shipment? get _current => _active.isEmpty ? null : _active.first;

  Future<void> _openCurrent() async {
    final current = _current;
    if (current == null) return;
    final updated = await Navigator.of(context).push<Shipment>(
      MaterialPageRoute(
        builder: (_) => ShipmentPackingScanScreen(
          shipmentId: current.id,
          courierOptions: widget.courierOptions,
        ),
      ),
    );
    if (updated != null) {
      widget.onShipmentPacked?.call(updated);
      setState(() => _queue.removeWhere((s) => s.id == current.id));
      if (_active.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.packingQueueComplete)),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = _current;
    final total = widget.queue.length;
    final done = total - _active.length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.batchPacking)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (total > 0)
              LinearProgressIndicator(value: total == 0 ? 0 : done / total),
            const SizedBox(height: 16),
            if (current == null)
              Expanded(
                child: Center(child: Text(l10n.noShipmentsInQueue)),
              )
            else ...[
              Text(
                l10n.shipmentProgress(done + 1, total),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(current.orderNumber ?? l10n.shipmentNumber(current.id)),
                  subtitle: Text(current.wholesaleOrder?.clientName ?? current.store?.name ?? ''),
                ),
              ),
              const Spacer(),
              if (_active.length > 1)
                OutlinedButton(
                  onPressed: () => setState(() => _skipped.add(current.id)),
                  child: Text(l10n.skipThisShipment),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _openCurrent,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l10n.startPacking),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
