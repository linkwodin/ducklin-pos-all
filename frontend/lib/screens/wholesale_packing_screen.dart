import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/order_provider.dart';
import '../services/api_service.dart';
import '../utils/shipment_couriers.dart';
import '../utils/shipment_order_time.dart';
import '../utils/shipment_status.dart';
import '../utils/wholesale_order_assignment.dart';
import '../widgets/shipment_monitor_grid.dart';
import 'create_wholesale_order_screen.dart';
import 'shipment_courier_pickup_screen.dart';
import 'shipment_packing_detail_screen.dart';
import 'shipment_packing_queue_screen.dart';

class WholesalePackingScreen extends StatefulWidget {
  final VoidCallback? onShipmentsChanged;
  const WholesalePackingScreen({super.key, this.onShipmentsChanged});

  @override
  State<WholesalePackingScreen> createState() => _WholesalePackingScreenState();
}

class _WholesalePackingScreenState extends State<WholesalePackingScreen> {
  static const _viewStorageKey = 'wholesaleShipmentsView';
  static const _monitorRefreshMs = 30000;
  static const _monitorCompletedDays = 3;
  static const _listCompletedDays = 10;

  List<Map<String, dynamic>> _shipments = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _viewMode = 'monitor';
  List<String> _courierOptions = defaultShipmentCouriers;
  Timer? _refreshTimer;
  final TextEditingController _searchController = TextEditingController();

  bool get _includeOldCompleted => _viewMode == 'list';
  int get _completedDaysLabel => _includeOldCompleted ? _listCompletedDays : _monitorCompletedDays;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _loadCompanySettings();
    _loadShipments();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_viewStorageKey);
    if (!mounted) return;
    setState(() => _viewMode = saved == 'list' ? 'list' : 'monitor');
    _configureRefreshTimer();
  }

  Future<void> _saveViewMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewStorageKey, mode);
  }

  Future<void> _loadCompanySettings() async {
    try {
      final settings = await ApiService.instance.getCompanySettings();
      if (!mounted) return;
      setState(() {
        _courierOptions = shipmentCourierOptionsFromSettings(settings['shipment_couriers']?.toString());
      });
    } catch (_) {}
  }

  int? _storeId(BuildContext context) {
    return Provider.of<OrderProvider>(context, listen: false).storeId;
  }

  Future<void> _loadShipments() async {
    final storeId = _storeId(context);
    if (storeId == null) {
      setState(() {
        _loading = false;
        _error = 'No store selected';
        _shipments = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.instance.listShipments(
        storeId: storeId,
        includeOldCompleted: _includeOldCompleted,
      );
      if (!mounted) return;
      setState(() {
        _shipments = list.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
      widget.onShipmentsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _shipments = [];
      });
    }
  }

  void _configureRefreshTimer() {
    _refreshTimer?.cancel();
    if (_viewMode != 'monitor') return;
    _refreshTimer = Timer.periodic(const Duration(milliseconds: _monitorRefreshMs), (_) {
      if (mounted) _loadShipments();
    });
  }

  bool _shipmentMatchesSearch(Map<String, dynamic> shipment, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final order = shipment['wholesale_order'] as Map<String, dynamic>?;
    final fields = <String>[
      order?['order_number']?.toString() ?? '',
      (order?['order_number']?.toString() ?? '').replaceFirst(RegExp(r'^WO-', caseSensitive: false), ''),
      order?['ref_no']?.toString() ?? '',
      order?['po_number']?.toString() ?? '',
      order?['wholesale_client']?['name']?.toString() ?? '',
    ].where((v) => v.trim().isNotEmpty).map((v) => v.toLowerCase());
    return fields.any((field) => field.contains(q));
  }

  List<Map<String, dynamic>> get _filteredShipments {
    final q = _search.trim();
    var list = q.isEmpty
        ? [..._shipments]
        : _shipments.where((s) => _shipmentMatchesSearch(s, q)).toList();

    if (_viewMode == 'monitor') {
      final cutoff = DateTime.now().subtract(Duration(days: _monitorCompletedDays));
      list = list.where((s) {
        if (s['status'] != 'completed') return true;
        final updatedAt = DateTime.tryParse(s['updated_at']?.toString() ?? '');
        return updatedAt != null && !updatedAt.isBefore(cutoff);
      }).toList();
    }
    list.sort(sortShipmentsByOrderTimeDesc);
    return list;
  }

  void _patchShipment(Map<String, dynamic> updated) {
    setState(() {
      _shipments = _shipments
          .map((s) => (s['id'] == updated['id'] ? mergeShipmentListRow(s, updated) : s))
          .toList();
    });
    widget.onShipmentsChanged?.call();
  }

  void _openShipment(Map<String, dynamic> shipment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentPackingDetailScreen(
          shipment: shipment,
          courierOptions: _courierOptions,
          onUpdated: (updated) {
            _patchShipment(updated);
            _loadShipments();
          },
        ),
      ),
    );
  }

  void _startPackingQueue(List<Map<String, dynamic>> queue) {
    final filtered = queue.where((s) => shipmentNeedsPacking(s['status']?.toString() ?? '')).toList();
    if (filtered.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentPackingQueueScreen(
          queue: filtered,
          courierOptions: _courierOptions,
          onShipmentPacked: _patchShipment,
        ),
      ),
    ).then((_) => _loadShipments());
  }

  void _startCourierPickup(List<Map<String, dynamic>> queue) {
    final filtered = queue.where((s) => s['status'] == 'packed').toList();
    if (filtered.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentCourierPickupScreen(
          queue: filtered,
          courierOptions: _courierOptions,
          onShipmentShipped: _patchShipment,
        ),
      ),
    ).then((_) => _loadShipments());
  }

  Future<void> _setViewMode(String mode) async {
    setState(() => _viewMode = mode);
    await _saveViewMode(mode);
    _configureRefreshTimer();
    await _loadShipments();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredShipments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wholesale shipments'),
        actions: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'monitor', icon: Icon(Icons.grid_view), label: Text('Monitor')),
              ButtonSegment(value: 'list', icon: Icon(Icons.view_list), label: Text('List')),
            ],
            selected: {_viewMode},
            onSelectionChanged: (values) => _setViewMode(values.first),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadShipments,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateWholesaleOrderScreen()),
          );
          if (mounted) _loadShipments();
        },
        icon: const Icon(Icons.add),
        label: const Text('New order'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search',
                    hintText: 'Order #, ref, PO, client',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                if (_viewMode == 'monitor')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Monitor refreshes every 30 seconds. Tap ▶ on a column to start packing or courier pickup.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _viewMode == 'monitor'
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return RefreshIndicator(
                          onRefresh: _loadShipments,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: constraints.maxHeight,
                              width: constraints.maxWidth,
                              child: _buildMonitorBody(filtered),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadShipments,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: _buildListBody(filtered),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorBody(List<Map<String, dynamic>> filtered) {
    if (_loading && filtered.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (filtered.isEmpty) {
      return const Center(child: Text('No shipments', style: TextStyle(color: Colors.grey)));
    }
    return ShipmentMonitorGrid(
      shipments: filtered,
      completedDaysLabel: _completedDaysLabel,
      onOpenShipment: _openShipment,
      onStartPackingQueue: _startPackingQueue,
      onStartCourierPickup: _startCourierPickup,
    );
  }

  List<Widget> _buildListBody(List<Map<String, dynamic>> filtered) {
    if (_loading && filtered.isEmpty) {
      return [const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      ];
    }
    if (filtered.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No shipments', style: TextStyle(color: Colors.grey))),
        ),
      ];
    }
    return filtered.map((s) => _buildListTile(s)).toList();
  }

  Widget _buildListTile(Map<String, dynamic> s) {
    final order = s['wholesale_order'] as Map<String, dynamic>?;
    final itemCount = (s['items'] as List<dynamic>? ?? []).length;
    final totalQty = (s['items'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().fold<double>(
          0,
          (sum, si) => sum + effectiveShipmentItemQty(si),
        );
    final needsPacking = shipmentNeedsPacking(s['status']?.toString() ?? '');
    return Card(
      child: ListTile(
        onTap: () => _openShipment(s),
        title: Text(order?['order_number']?.toString() ?? '#${s['wholesale_order_id']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          [
            if (order?['po_number'] != null) 'PO ${order!['po_number']}',
            order?['wholesale_client']?['name']?.toString(),
            if (itemCount > 0) '$itemCount items ($totalQty qty)',
            s['status']?.toString(),
          ].whereType<String>().join(' · '),
        ),
        trailing: FilledButton.tonal(
          onPressed: () => _openShipment(s),
          child: Text(needsPacking ? 'Process' : 'View'),
        ),
      ),
    );
  }
}
