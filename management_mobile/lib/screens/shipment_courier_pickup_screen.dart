import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/shipment.dart';
import '../services/api_service.dart';
import '../utils/shipment_packing.dart';
import '../utils/shipment_scan.dart';
import '../widgets/barcode_scanner_screen.dart';

enum _PickupStep { courier, orders, confirm }

class ShipmentCourierPickupScreen extends StatefulWidget {
  const ShipmentCourierPickupScreen({
    super.key,
    required this.queue,
    required this.courierOptions,
    this.onShipmentShipped,
  });

  final List<Shipment> queue;
  final List<String> courierOptions;
  final ValueChanged<Shipment>? onShipmentShipped;

  @override
  State<ShipmentCourierPickupScreen> createState() => _ShipmentCourierPickupScreenState();
}

class _ShipmentCourierPickupScreenState extends State<ShipmentCourierPickupScreen> {
  var _step = _PickupStep.courier;
  String? _selectedCourier;
  final _selectedIds = <int>{};
  final _scan = TextEditingController();
  var _submitting = false;

  late final List<Shipment> _queue;

  @override
  void initState() {
    super.initState();
    _queue = widget.queue.where((s) => s.status == 'packed').toList()
      ..sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  List<Shipment> get _eligible {
    if (_selectedCourier == null) return [];
    return _queue.where((s) => shipmentMatchesCouriers(s, [_selectedCourier!])).toList();
  }

  List<Shipment> get _selectedShipments =>
      _eligible.where((s) => _selectedIds.contains(s.id)).toList();

  void _toggle(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _applyScan(String raw) {
    final l10n = AppLocalizations.of(context)!;
    final code = raw.trim();
    if (code.isEmpty) return;
    final match = _eligible.where((s) => shipmentMatchesDeliveryNoteScan(s, code)).cast<Shipment?>().firstOrNull;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noMatchingShipment(code))),
      );
      return;
    }
    setState(() => _selectedIds.add(match.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.selectedOrder(match.orderNumber ?? '${match.id}'))),
    );
  }

  Future<void> _scanWithCamera() async {
    final l10n = AppLocalizations.of(context)!;
    final code = await openBarcodeScanner(context, title: l10n.scanDeliveryNote);
    if (code != null && mounted) _applyScan(code);
  }

  Future<void> _confirmBatch() async {
    if (_submitting || _selectedShipments.isEmpty || _selectedCourier == null) return;
    setState(() => _submitting = true);
    var count = 0;
    try {
      for (final shipment in _selectedShipments) {
        if ((shipment.courier ?? '').trim().isEmpty) {
          await ApiService.instance.updateShipment(shipment.id, courier: _selectedCourier);
        }
        final updated = await ApiService.instance.updateShipmentStatus(shipment.id, 'shipped');
        widget.onShipmentShipped?.call(updated);
        count++;
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.markedShippedVia(count, _selectedCourier!))),
        );
        Navigator.pop(context);
      }
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.courierPickup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Stepper(
            currentStep: _step.index,
            onStepContinue: () {
              if (_step == _PickupStep.courier) {
                if (_selectedCourier == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.selectCourier)),
                  );
                  return;
                }
                setState(() => _step = _PickupStep.orders);
              } else if (_step == _PickupStep.orders) {
                if (_selectedIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.selectAtLeastOneShipment)),
                  );
                  return;
                }
                setState(() => _step = _PickupStep.confirm);
              } else {
                _confirmBatch();
              }
            },
            onStepCancel: () {
              if (_step == _PickupStep.orders) {
                setState(() => _step = _PickupStep.courier);
              } else if (_step == _PickupStep.confirm) {
                setState(() => _step = _PickupStep.orders);
              }
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    if (_step != _PickupStep.courier)
                      TextButton(onPressed: details.onStepCancel, child: Text(l10n.back)),
                    const Spacer(),
                    FilledButton(
                      onPressed: _submitting ? null : details.onStepContinue,
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_step == _PickupStep.confirm ? l10n.confirmPickup : l10n.next),
                    ),
                  ],
                ),
              );
            },
            steps: [
              Step(
                title: Text(l10n.courier),
                isActive: _step == _PickupStep.courier,
                content: widget.courierOptions.isEmpty
                    ? Text(l10n.noCouriersConfigured)
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.courierOptions.map((courier) {
                          final count = _queue.where((s) => shipmentMatchesCouriers(s, [courier])).length;
                          return FilterChip(
                            label: Text('$courier ($count)'),
                            selected: _selectedCourier == courier,
                            onSelected: (_) => setState(() => _selectedCourier = courier),
                          );
                        }).toList(),
                      ),
              ),
              Step(
                title: Text(l10n.selectOrders),
                isActive: _step == _PickupStep.orders,
                content: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _scan,
                            decoration: InputDecoration(
                              labelText: l10n.scanDeliveryNote,
                              hintText: l10n.scanHint,
                            ),
                            onSubmitted: _applyScan,
                          ),
                        ),
                        IconButton(
                          onPressed: _scanWithCamera,
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._eligible.map(
                      (shipment) => CheckboxListTile(
                        value: _selectedIds.contains(shipment.id),
                        onChanged: (_) => _toggle(shipment.id),
                        title: Text(shipment.orderNumber ?? l10n.shipmentNumber(shipment.id)),
                        subtitle: Text(
                          [
                            shipment.wholesaleOrder?.clientName,
                            l10n.boxesCount(shipmentTotalBoxes(shipment)),
                          ].whereType<String>().where((p) => p.isNotEmpty).join(' · '),
                        ),
                        secondary: Text('${shipmentTotalBoxes(shipment)}'),
                      ),
                    ),
                  ],
                ),
              ),
              Step(
                title: Text(l10n.confirmStep),
                isActive: _step == _PickupStep.confirm,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.courierLabel(_selectedCourier ?? '')),
                    Text(l10n.shipmentsCountLabel(_selectedShipments.length)),
                    Text(
                      l10n.totalBoxes(
                        _selectedShipments.fold(0, (sum, s) => sum + shipmentTotalBoxes(s)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._selectedShipments.map(
                      (s) => ListTile(
                        dense: true,
                        title: Text(s.orderNumber ?? '#${s.id}'),
                        trailing: Text(l10n.boxesCount(shipmentTotalBoxes(s))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
