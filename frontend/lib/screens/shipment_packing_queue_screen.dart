import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/shipment_order_time.dart';
import 'shipment_packing_scan_panel.dart';

class ShipmentPackingQueueScreen extends StatefulWidget {
  const ShipmentPackingQueueScreen({
    super.key,
    required this.queue,
    required this.courierOptions,
    required this.onShipmentPacked,
  });

  final List<Map<String, dynamic>> queue;
  final List<String> courierOptions;
  final void Function(Map<String, dynamic> updated) onShipmentPacked;

  @override
  State<ShipmentPackingQueueScreen> createState() => _ShipmentPackingQueueScreenState();
}

class _ShipmentPackingQueueScreenState extends State<ShipmentPackingQueueScreen> {
  late int _initialTotal;
  final Set<int> _skippedIds = {};
  bool _submitting = false;
  bool _dataLoading = false;
  Map<String, dynamic>? _currentShipment;
  List<Map<String, dynamic>> _products = [];
  List<dynamic> _storeStock = [];

  List<Map<String, dynamic>> get _sortedQueue {
    final list = widget.queue.map((s) => Map<String, dynamic>.from(s)).toList();
    list.sort(sortShipmentsByOrderTimeAsc);
    return list;
  }

  List<Map<String, dynamic>> get _activeQueue =>
      _sortedQueue.where((s) => !_skippedIds.contains((s['id'] as num).toInt())).toList();

  Map<String, dynamic>? get _current => _activeQueue.isEmpty ? null : _activeQueue.first;

  int get _doneCount => (_initialTotal - _activeQueue.length).clamp(0, _initialTotal);

  @override
  void initState() {
    super.initState();
    _initialTotal = widget.queue.length;
    _loadCurrentIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ShipmentPackingQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue.length != widget.queue.length) {
      _initialTotal = widget.queue.length;
    }
  }

  Future<void> _loadCurrentIfNeeded() async {
    final current = _current;
    if (current == null) return;
    setState(() {
      _dataLoading = true;
      _currentShipment = null;
    });
    try {
      final shipmentId = (current['id'] as num).toInt();
      final storeId = (current['store_id'] as num).toInt();
      final results = await Future.wait([
        ApiService.instance.getShipment(shipmentId),
        ApiService.instance.listProducts(),
        ApiService.instance.getStoreStock(storeId),
      ]);
      if (!mounted) return;
      setState(() {
        _currentShipment = results[0] as Map<String, dynamic>;
        _products = (results[1] as List<dynamic>).whereType<Map<String, dynamic>>().toList();
        _storeStock = results[2] as List<dynamic>;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load packing data: $e')));
      }
    } finally {
      if (mounted) setState(() => _dataLoading = false);
    }
  }

  Future<void> _completeAssignmentIfNeeded(int orderId) async {
    final order = await ApiService.instance.getWholesaleOrder(orderId);
    if (order['status']?.toString() == 'assign_shipment') {
      await ApiService.instance.completeWholesaleOrderAssignment(orderId);
    }
  }

  Future<void> _handleFinish(ShipmentPackingFinishPayload payload) async {
    final target = _currentShipment ?? _current;
    if (target == null) return;
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
      widget.onShipmentPacked(updated);
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

  void _skipCurrent() {
    final current = _current;
    if (current == null) return;
    setState(() {
      _skippedIds.add((current['id'] as num).toInt());
      _currentShipment = null;
    });
    if (_activeQueue.isEmpty) {
      Navigator.pop(context);
    } else {
      _loadCurrentIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final order = current?['wholesale_order'] as Map<String, dynamic>?;
    final orderLabel = order?['order_number']?.toString() ?? (current != null ? '#${current['wholesale_order_id']}' : '');
    final progress = _initialTotal > 0 ? (_doneCount / _initialTotal).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Packing queue'),
            if (current != null)
              Text(
                '${_doneCount + 1} / $_initialTotal · $orderLabel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (current != null && _activeQueue.length > 1)
            TextButton.icon(onPressed: _submitting ? null : _skipCurrent, icon: const Icon(Icons.skip_next), label: const Text('Skip')),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ],
      ),
      body: Column(
        children: [
          if (_initialTotal > 0) LinearProgressIndicator(value: progress),
          Expanded(
            child: current == null
                ? const Center(child: Text('Queue empty'))
                : _dataLoading || _currentShipment == null
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: ShipmentPackingScanPanel(
                          key: ValueKey(_currentShipment!['id']),
                          shipment: _currentShipment!,
                          products: _products,
                          storeStock: _storeStock,
                          courierOptions: widget.courierOptions,
                          submitting: _submitting,
                          onFinish: _handleFinish,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
