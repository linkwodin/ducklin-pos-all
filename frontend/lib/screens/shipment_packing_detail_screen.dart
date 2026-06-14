import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/shipment_status.dart';
import 'shipment_packing_scan_panel.dart';

/// Detail / packing screen for one shipment.
class ShipmentPackingDetailScreen extends StatefulWidget {
  const ShipmentPackingDetailScreen({
    super.key,
    required this.shipment,
    required this.courierOptions,
    required this.onUpdated,
  });

  final Map<String, dynamic> shipment;
  final List<String> courierOptions;
  final void Function(Map<String, dynamic> updated) onUpdated;

  @override
  State<ShipmentPackingDetailScreen> createState() => _ShipmentPackingDetailScreenState();
}

class _ShipmentPackingDetailScreenState extends State<ShipmentPackingDetailScreen> {
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _fullShipment;
  List<Map<String, dynamic>> _products = [];
  List<dynamic> _storeStock = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final shipmentId = (widget.shipment['id'] as num).toInt();
      final storeId = (widget.shipment['store_id'] as num).toInt();
      final results = await Future.wait([
        ApiService.instance.getShipment(shipmentId),
        ApiService.instance.listProducts(),
        ApiService.instance.getStoreStock(storeId),
      ]);
      if (!mounted) return;
      setState(() {
        _fullShipment = results[0] as Map<String, dynamic>;
        _products = (results[1] as List<dynamic>).whereType<Map<String, dynamic>>().toList();
        _storeStock = results[2] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    }
  }

  Future<void> _completeAssignmentIfNeeded(int orderId) async {
    final order = await ApiService.instance.getWholesaleOrder(orderId);
    if (order['status']?.toString() == 'assign_shipment') {
      await ApiService.instance.completeWholesaleOrderAssignment(orderId);
    }
  }

  Future<void> _handleFinish(ShipmentPackingFinishPayload payload) async {
    final target = _fullShipment ?? widget.shipment;
    setState(() => _submitting = true);
    try {
      final orderId = (target['wholesale_order_id'] as num).toInt();
      await _completeAssignmentIfNeeded(orderId);
      final updated = await ApiService.instance.startShipment(
        (target['id'] as num).toInt(),
        caseQty: payload.caseQty,
        deliveryDate: payload.deliveryDate,
        courier: payload.courier,
        trackingNumber: payload.trackingNumber,
      );
      widget.onUpdated(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shipment packed')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.shipment['wholesale_order'] as Map<String, dynamic>?;
    final orderNumber = order?['order_number']?.toString() ?? '#${widget.shipment['wholesale_order_id']}';
    final status = widget.shipment['status']?.toString() ?? '';
    final canPack = shipmentNeedsPacking(status);

    return Scaffold(
      appBar: AppBar(title: Text(canPack ? 'Pack: $orderNumber' : orderNumber)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : canPack && _fullShipment != null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: ShipmentPackingScanPanel(
                    shipment: _fullShipment!,
                    products: _products,
                    storeStock: _storeStock,
                    courierOptions: widget.courierOptions,
                    submitting: _submitting,
                    onFinish: _handleFinish,
                  ),
                )
              : _buildSummary(),
    );
  }

  Widget _buildSummary() {
    final shipment = _fullShipment ?? widget.shipment;
    final order = shipment['wholesale_order'] as Map<String, dynamic>?;
    final items = shipment['items'] as List<dynamic>? ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Status: ${shipment['status']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        if (order?['ref_no'] != null) Text('Ref: ${order!['ref_no']}'),
        if (order?['po_number'] != null) Text('PO: ${order!['po_number']}'),
        if (shipment['courier'] != null) Text('Courier: ${shipment['courier']}'),
        if (shipment['tracking_number'] != null) Text('Tracking: ${shipment['tracking_number']}'),
        const SizedBox(height: 16),
        const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
        ...items.whereType<Map<String, dynamic>>().map((si) {
          final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
          final product = woItem?['product'] as Map<String, dynamic>?;
          final name = product?['name']?.toString() ?? 'Item';
          final qty = si['quantity'] ?? woItem?['quantity'];
          return ListTile(title: Text(name), trailing: Text('$qty'));
        }),
      ],
    );
  }
}
