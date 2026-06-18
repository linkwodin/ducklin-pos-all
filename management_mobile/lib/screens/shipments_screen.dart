import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/shipment.dart';
import '../models/store.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/shipment_packing.dart';
import '../utils/shipment_scan.dart';
import '../widgets/async_body.dart';
import '../widgets/detail_info_table.dart';
import '../widgets/status_chip.dart';
import 'shipment_courier_pickup_screen.dart';
import 'shipment_courier_screen.dart';
import 'shipment_delivery_handoff_screen.dart';
import 'shipment_packing_queue_screen.dart';
import 'shipment_packing_scan_screen.dart';

class ShipmentsScreen extends StatefulWidget {
  const ShipmentsScreen({super.key});

  @override
  State<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends State<ShipmentsScreen> with SingleTickerProviderStateMixin {
  var _loading = true;
  var _error = '';
  List<Shipment> _shipments = [];
  List<Store> _stores = [];
  List<String> _courierOptions = [];
  int? _storeId;
  final _search = TextEditingController();
  late final TabController _viewTabs;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _viewTabs = TabController(length: 2, vsync: this);
    _viewTabs.addListener(() {
      if (_viewTabs.indexIsChanging) return;
      _configureAutoRefresh();
    });
    _loadInitial();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    _viewTabs.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final auth = context.read<AuthProvider>();
      final stores = await ApiService.instance.listStores();
      final settings = await ApiService.instance.getCompanySettings();
      final userStores = auth.user?.stores ?? [];
      final filtered = userStores.isNotEmpty
          ? stores.where((s) => userStores.any((u) => u.id == s.id)).toList()
          : stores;
      setState(() {
        _stores = filtered.isNotEmpty ? filtered : stores;
        _storeId = _stores.firstOrNull?.id;
        _courierOptions = courierOptionsFromSettings(settings.shipmentCouriers);
      });
    } catch (_) {}
    await _load();
    _configureAutoRefresh();
  }

  void _configureAutoRefresh() {
    _refreshTimer?.cancel();
    if (_viewTabs.index == 0) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final shipments = await ApiService.instance.listShipments(
        storeId: _storeId,
        includeOldCompleted: _viewTabs.index == 1,
      );
      if (!mounted) return;
      setState(() {
        _shipments = shipments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.instance.errorMessage(e);
        _loading = false;
      });
    }
  }

  List<Shipment> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _shipments;
    return _shipments.where((s) {
      final order = s.wholesaleOrder;
      final orderNumber = order?.orderNumber;
      final fields = <String?>[
        orderNumber,
        order?.refNo,
        order?.poNumber,
        order?.clientName,
        orderNumber?.replaceFirst(RegExp(r'^WO-', caseSensitive: false), ''),
      ];
      return fields.whereType<String>().any((f) => f.toLowerCase().contains(q));
    }).toList();
  }

  List<Shipment> _byStatuses(List<String> statuses) =>
      _filtered.where((s) => statuses.contains(s.status)).toList()
        ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

  List<Shipment> get _packingQueue => _byStatuses(['assigned', 'packing']);
  List<Shipment> get _packedQueue => _byStatuses(['packed']);
  List<Shipment> get _shipped => _byStatuses(['shipped']);
  List<Shipment> get _completed => _filtered.where((s) => s.status == 'completed').toList()
    ..sort((a, b) => (b.updatedAt ?? b.createdAt ?? '').compareTo(a.updatedAt ?? a.createdAt ?? ''));

  Future<void> _openPacking(Shipment shipment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentPackingScanScreen(
          shipmentId: shipment.id,
          courierOptions: _courierOptions,
          onFinished: (_) => _load(),
        ),
      ),
    );
    _load();
  }

  Future<void> _startPackingQueue(List<Shipment> queue) async {
    if (queue.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentPackingQueueScreen(
          queue: queue,
          courierOptions: _courierOptions,
          onShipmentPacked: (_) => _load(),
        ),
      ),
    );
    _load();
  }

  Future<void> _startCourierPickup(List<Shipment> queue) async {
    if (queue.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentCourierPickupScreen(
          queue: queue,
          courierOptions: _courierOptions,
          onShipmentShipped: (_) => _load(),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _storeId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.store, isDense: true),
                      items: _stores
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      selectedItemBuilder: (context) => _stores
                          .map(
                            (s) => Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() => _storeId = v);
                        _load();
                      },
                    ),
                  ),
                  IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
                ],
              ),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: l10n.searchOrderPoClient,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              TabBar(
                controller: _viewTabs,
                tabs: [
                  Tab(text: l10n.tabDashboard),
                  Tab(text: l10n.tabList),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: () => _load(),
            child: TabBarView(
              controller: _viewTabs,
              children: [
                _MonitorView(
                  packing: _packingQueue,
                  packed: _packedQueue,
                  shipped: _shipped,
                  completed: _completed.take(12).toList(),
                  onRefresh: () => _load(),
                  onOpen: (s) => _openPacking(s),
                  onOpenDetail: (s) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: s.id)),
                  ).then((_) => _load()),
                  onBatchPack: () => _startPackingQueue(_packingQueue),
                  onCourierPickup: () => _startCourierPickup(_packedQueue),
                ),
                _ListView(
                  shipments: _filtered,
                  onTap: (s) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: s.id)),
                  ).then((_) => _load()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonitorView extends StatelessWidget {
  const _MonitorView({
    required this.packing,
    required this.packed,
    required this.shipped,
    required this.completed,
    required this.onOpen,
    required this.onOpenDetail,
    required this.onBatchPack,
    required this.onCourierPickup,
    required this.onRefresh,
  });

  final List<Shipment> packing;
  final List<Shipment> packed;
  final List<Shipment> shipped;
  final List<Shipment> completed;
  final ValueChanged<Shipment> onOpen;
  final ValueChanged<Shipment> onOpenDetail;
  final VoidCallback onBatchPack;
  final VoidCallback onCourierPickup;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _MonitorSection(
            title: l10n.monitorPacking,
            color: Colors.orange,
            shipments: packing,
            actionLabel: l10n.batchPack,
            onAction: packing.isEmpty ? null : onBatchPack,
            onTap: (s) => shipmentNeedsPacking(s.status) ? onOpen(s) : onOpenDetail(s),
            actionIcon: Icons.qr_code_scanner,
          ),
          _MonitorSection(
            title: l10n.monitorPackedAwaitingCourier,
            color: Colors.blue,
            shipments: packed,
            actionLabel: l10n.courierPickup,
            onAction: packed.isEmpty ? null : onCourierPickup,
            onTap: onOpenDetail,
            actionIcon: Icons.local_shipping_outlined,
          ),
          _MonitorSection(
            title: l10n.monitorShipped,
            color: Colors.green,
            shipments: shipped,
            onTap: onOpenDetail,
          ),
          _MonitorSection(
            title: l10n.monitorCompletedRecent,
            color: Colors.grey,
            shipments: completed,
            onTap: onOpenDetail,
          ),
        ],
      ),
    );
  }
}

class _MonitorSection extends StatelessWidget {
  const _MonitorSection({
    required this.title,
    required this.color,
    required this.shipments,
    required this.onTap,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final String title;
  final Color color;
  final List<Shipment> shipments;
  final ValueChanged<Shipment> onTap;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(width: 4, height: 24, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Chip(label: Text('${shipments.length}'), visualDensity: VisualDensity.compact),
                if (onAction != null && actionLabel != null)
                  TextButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon ?? Icons.play_arrow),
                    label: Text(actionLabel!),
                  ),
              ],
            ),
          ),
          if (shipments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(l10n.nothingHere, textAlign: TextAlign.center),
            )
          else
            ...shipments.map(
              (s) => ListTile(
                title: Text(
                  s.orderNumber ?? l10n.shipmentNumber(s.id),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    s.wholesaleOrder?.clientName,
                    s.store?.name,
                    if (s.items.isNotEmpty) l10n.boxesCount(shipmentTotalBoxes(s)),
                  ].whereType<String>().where((p) => p.isNotEmpty).join(' · '),
                ),
                trailing: shipmentNeedsPacking(s.status)
                    ? const Icon(Icons.qr_code_scanner, color: Colors.orange)
                    : const Icon(Icons.chevron_right),
                onTap: () => onTap(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({required this.shipments, required this.onTap});

  final List<Shipment> shipments;
  final ValueChanged<Shipment> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: shipments.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final shipment = shipments[index];
        return Card(
          child: ListTile(
            title: Text(
              shipment.orderNumber ?? l10n.shipmentNumber(shipment.id),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${shipment.store?.name ?? '—'} · ${formatDate(shipment.deliveryDate ?? shipment.createdAt)}'),
            trailing: StatusChip(
              label: l10n.shipmentStatusLabel(shipment.status),
              color: shipmentStatusChipColor(shipment.status),
            ),
            onTap: () => onTap(shipment),
          ),
        );
      },
    );
  }
}

class ShipmentDetailScreen extends StatefulWidget {
  const ShipmentDetailScreen({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  var _loading = true;
  var _error = '';
  Shipment? _shipment;
  List<String> _courierOptions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final shipment = await ApiService.instance.getShipment(widget.shipmentId);
      final settings = await ApiService.instance.getCompanySettings();
      if (!mounted) return;
      setState(() {
        _shipment = shipment;
        _courierOptions = courierOptionsFromSettings(settings.shipmentCouriers);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.instance.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _openPickPack(Shipment shipment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentPackingScanScreen(
          shipmentId: shipment.id,
          courierOptions: _courierOptions,
        ),
      ),
    );
    _load();
  }

  Future<void> _openCourierPickup(Shipment shipment) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ShipmentCourierScreen(shipmentId: shipment.id),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.shipmentUpdated)),
      );
    }
    _load();
  }

  Future<void> _openDeliveryHandoff(Shipment shipment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentDeliveryHandoffScreen(shipmentId: shipment.id),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(shipment?.orderNumber ?? l10n.shipmentTitle),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: shipment == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DetailInfoTable(
                    rows: [
                      DetailInfoRow(
                        l10n.status,
                        StatusChip(
                          label: l10n.shipmentStatusLabel(shipment.status),
                          color: shipmentStatusChipColor(shipment.status),
                        ),
                      ),
                      DetailInfoRow(l10n.store, Text(shipment.store?.name ?? '—', style: valueStyle)),
                      DetailInfoRow(
                        l10n.client,
                        Text(shipment.wholesaleOrder?.clientName ?? '—', style: valueStyle),
                      ),
                      DetailInfoRow(
                        l10n.created,
                        Text(formatDateTime(shipment.createdAt), style: valueStyle),
                      ),
                      if ((shipment.courier ?? '').trim().isNotEmpty)
                        DetailInfoRow(l10n.courier, Text(shipment.courier!.trim(), style: valueStyle)),
                      if ((shipment.trackingNumber ?? '').trim().isNotEmpty)
                        DetailInfoRow(
                          l10n.tracking,
                          Text(shipment.trackingNumber!.trim(), style: valueStyle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _WorkflowCard(
                    icon: Icons.qr_code_scanner,
                    color: Colors.orange,
                    title: l10n.workflowPickPack,
                    subtitle: l10n.workflowPickPackSub,
                    stepState: shipmentPickPackStepState(shipment),
                    onTap: () => _openPickPack(shipment),
                  ),
                  const SizedBox(height: 12),
                  _WorkflowCard(
                    icon: Icons.local_shipping_outlined,
                    color: theme.colorScheme.primary,
                    title: l10n.workflowCourier,
                    subtitle: l10n.workflowCourierSub,
                    stepState: shipmentCourierDetailsStepState(shipment),
                    onTap: () => _openCourierPickup(shipment),
                  ),
                  const SizedBox(height: 12),
                  _WorkflowCard(
                    icon: Icons.assignment_turned_in_outlined,
                    color: Colors.teal,
                    title: l10n.workflowHandoff,
                    subtitle: shipmentHasDeliveryProof(shipment)
                        ? l10n.workflowHandoffUploaded
                        : shipment.status == 'shipped'
                            ? l10n.workflowHandoffUploadShipped
                            : l10n.workflowHandoffUploadAndShip,
                    stepState: shipmentDeliveryHandoffStepState(shipment),
                    onTap: () => _openDeliveryHandoff(shipment),
                  ),
                ],
              ),
      ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.stepState,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final ShipmentWorkflowStepState stepState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = stepState == ShipmentWorkflowStepState.locked;
    final done = stepState == ShipmentWorkflowStepState.done;
    final active = stepState == ShipmentWorkflowStepState.active;
    final trailingIcon = locked
        ? Icons.lock_outline
        : done
            ? Icons.check_circle
            : Icons.chevron_right;
    final trailingColor = locked
        ? Colors.grey
        : done
            ? Colors.green.shade700
            : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: !active
          ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        onTap: active ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: active
                    ? color.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                foregroundColor: active ? color : Colors.grey,
                child: Icon(icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: active ? null : Colors.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: active ? null : Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(trailingIcon, color: trailingColor),
            ],
          ),
        ),
      ),
    );
  }
}

extension _StoreFirst<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
