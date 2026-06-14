import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/shipment_delivery_note_scan.dart';
import '../utils/shipment_expected_boxes.dart';
import '../utils/shipment_order_time.dart';
import '../widgets/wizard_step_header.dart';

class ShipmentCourierPickupScreen extends StatefulWidget {
  const ShipmentCourierPickupScreen({
    super.key,
    required this.queue,
    required this.courierOptions,
    required this.onShipmentShipped,
  });

  final List<Map<String, dynamic>> queue;
  final List<String> courierOptions;
  final void Function(Map<String, dynamic> updated) onShipmentShipped;

  @override
  State<ShipmentCourierPickupScreen> createState() => _ShipmentCourierPickupScreenState();
}

class _ShipmentCourierPickupScreenState extends State<ShipmentCourierPickupScreen> {
  static const _steps = ['courier', 'orders', 'confirm'];
  static const _stepLabels = ['Courier', 'Orders', 'Confirm'];

  String _step = 'courier';
  String? _selectedCourier;
  final Set<int> _selectedOrderIds = {};
  final Set<int> _shippedIds = {};
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocus = FocusNode();
  bool _submitting = false;

  List<Map<String, dynamic>> get _sortedQueue {
    final list = widget.queue.map((s) => Map<String, dynamic>.from(s)).toList();
    list.sort(sortShipmentsByOrderTimeAsc);
    return list;
  }

  List<Map<String, dynamic>> get _activeQueue =>
      _sortedQueue.where((s) => !_shippedIds.contains((s['id'] as num).toInt())).toList();

  List<Map<String, dynamic>> get _eligibleOrders {
    if (_selectedCourier == null) return [];
    return _activeQueue.where((s) => shipmentMatchesCouriers(s, [_selectedCourier!])).toList();
  }

  List<Map<String, dynamic>> get _selectedShipments =>
      _eligibleOrders.where((s) => _selectedOrderIds.contains((s['id'] as num).toInt())).toList();

  int get _selectedTotalBoxes =>
      _selectedShipments.fold<int>(0, (sum, s) => sum + shipmentTotalBoxes(s).round());

  int get _stepIndex => _steps.indexOf(_step);

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  void _toggleOrder(int shipmentId) {
    setState(() {
      if (_selectedOrderIds.contains(shipmentId)) {
        _selectedOrderIds.remove(shipmentId);
      } else {
        _selectedOrderIds.add(shipmentId);
      }
    });
  }

  void _handleScanSubmit() {
    final code = _scanController.text.trim();
    if (code.isEmpty) return;
    Map<String, dynamic>? match;
    for (final s in _eligibleOrders) {
      if (shipmentMatchesDeliveryNoteScan(s, code)) {
        match = s;
        break;
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not found: $code')));
      _scanController.clear();
      _scanFocus.requestFocus();
      return;
    }
    _toggleOrder((match['id'] as num).toInt());
    _scanController.clear();
    _scanFocus.requestFocus();
  }

  Future<void> _confirmBatch() async {
    if (_submitting || _selectedShipments.isEmpty || _selectedCourier == null) return;
    final toShip = List<Map<String, dynamic>>.from(_selectedShipments);
    setState(() => _submitting = true);
    var successCount = 0;
    try {
      for (final shipment in toShip) {
        final id = (shipment['id'] as num).toInt();
        if ((shipment['courier']?.toString() ?? '').trim().isEmpty) {
          await ApiService.instance.updateShipment(id, courier: _selectedCourier);
        }
        final updated = await ApiService.instance.updateShipmentStatus(id, 'shipped');
        widget.onShipmentShipped(updated);
        _shippedIds.add(id);
        successCount++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirmed $successCount shipment(s) with $_selectedCourier')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), ''))),
        );
        setState(() => _submitting = false);
      }
    }
  }

  void _goNext() {
    if (_step == 'courier') {
      if (_selectedCourier == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a courier')));
        return;
      }
      setState(() => _step = 'orders');
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanFocus.requestFocus());
      return;
    }
    if (_step == 'orders') {
      if (_selectedOrderIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one order')));
        return;
      }
      setState(() => _step = 'confirm');
    }
  }

  void _goBack() {
    if (_step == 'confirm') {
      setState(() => _step = 'orders');
    } else if (_step == 'orders') {
      setState(() {
        _selectedOrderIds.clear();
        _step = 'courier';
      });
    }
  }

  String _orderNumber(Map<String, dynamic> shipment) {
    final order = shipment['wholesale_order'] as Map<String, dynamic>?;
    return order?['order_number']?.toString() ?? '#${shipment['wholesale_order_id']}';
  }

  String? _orderRef(Map<String, dynamic> shipment) {
    return (shipment['wholesale_order'] as Map<String, dynamic>?)?['ref_no']?.toString().trim();
  }

  String _orderSecondary(Map<String, dynamic> shipment) {
    final order = shipment['wholesale_order'] as Map<String, dynamic>?;
    final parts = <String>[
      if (order?['wholesale_client']?['name'] != null) order!['wholesale_client']['name'].toString(),
      if (shipment['store']?['name'] != null) shipment['store']['name'].toString(),
      if (shipment['delivery_date'] != null) shipment['delivery_date'].toString().substring(0, 10),
      if (order?['po_number'] != null) 'PO ${order!['po_number']}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courier pickup'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WizardStepHeader(currentStep: _stepIndex, labels: _stepLabels),
                        const SizedBox(height: 16),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _step == 'courier'
                                ? _buildCourierStep()
                                : _step == 'orders'
                                    ? _buildOrdersStep()
                                    : _buildConfirmStep(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (_step != 'courier')
                    TextButton(onPressed: _submitting ? null : _goBack, child: const Text('Back')),
                  const Spacer(),
                  TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Close')),
                  const SizedBox(width: 8),
                  if (_step == 'confirm')
                    FilledButton(
                      onPressed: _submitting || _selectedShipments.isEmpty ? null : _confirmBatch,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirm pickup'),
                    )
                  else
                    FilledButton(onPressed: _goNext, child: const Text('Next')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierStep() {
    if (widget.courierOptions.isEmpty) {
      return const Text('No couriers configured in company settings.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Select courier', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Choose one courier for this pickup batch.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.courierOptions.map((courier) {
            final count = _activeQueue.where((s) => shipmentMatchesCouriers(s, [courier])).length;
            final selected = _selectedCourier == courier;
            final colorScheme = Theme.of(context).colorScheme;
            return selected
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      elevation: 2,
                    ),
                    onPressed: () => setState(() => _selectedCourier = courier),
                    child: _CourierButtonContent(courier: courier, count: count, selected: true),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      side: BorderSide(color: colorScheme.outline),
                      foregroundColor: colorScheme.onSurface,
                    ),
                    onPressed: () => setState(() => _selectedCourier = courier),
                    child: _CourierButtonContent(courier: courier, count: count, selected: false),
                  );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOrdersStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Select orders', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Chip(label: Text(_selectedCourier ?? '')),
            Chip(
              label: Text('Selected ${_selectedOrderIds.length}'),
              backgroundColor: _selectedOrderIds.isNotEmpty ? Colors.green.shade100 : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _scanController,
          focusNode: _scanFocus,
          decoration: const InputDecoration(
            labelText: 'Scan delivery note',
            prefixIcon: Icon(Icons.qr_code_scanner),
            border: OutlineInputBorder(),
            helperText: 'Scan to toggle order selection',
          ),
          onSubmitted: (_) => _handleScanSubmit(),
        ),
        const SizedBox(height: 12),
        if (_eligibleOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No orders for this courier', style: TextStyle(color: Colors.grey))),
          )
        else
          ..._eligibleOrders.map((shipment) {
            final id = (shipment['id'] as num).toInt();
            final checked = _selectedOrderIds.contains(id);
            final boxes = shipmentTotalBoxes(shipment).round();
            final ref = _orderRef(shipment);
            return CheckboxListTile(
              value: checked,
              onChanged: (_) => _toggleOrder(id),
              title: Row(
                children: [
                  Text(_orderNumber(shipment), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (ref != null && ref.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('Ref: $ref', style: const TextStyle(color: Colors.grey)),
                  ],
                ],
              ),
              subtitle: Text(_orderSecondary(shipment)),
              secondary: Chip(label: Text('$boxes boxes')),
              contentPadding: EdgeInsets.zero,
            );
          }),
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Confirm pickup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Mark ${_selectedShipments.length} shipment(s) as shipped with $_selectedCourier.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('${_selectedShipments.length} orders')),
            Chip(label: Text('$_selectedTotalBoxes boxes total')),
          ],
        ),
        const SizedBox(height: 12),
        ..._selectedShipments.map((shipment) {
          final boxes = shipmentTotalBoxes(shipment).round();
          final ref = _orderRef(shipment);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Text(_orderNumber(shipment), style: const TextStyle(fontWeight: FontWeight.bold)),
                if (ref != null && ref.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('Ref: $ref', style: const TextStyle(color: Colors.grey)),
                ],
              ],
            ),
            subtitle: Text(_orderSecondary(shipment)),
            trailing: Chip(label: Text('$boxes boxes')),
          );
        }),
      ],
    );
  }
}

class _CourierButtonContent extends StatelessWidget {
  const _CourierButtonContent({
    required this.courier,
    required this.count,
    required this.selected,
  });

  final String courier;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(courier, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? colorScheme.onPrimary.withValues(alpha: 0.2) : colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: selected ? null : Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: selected ? colorScheme.onPrimary : colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
