import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/admin.dart';
import '../models/wholesale_order.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/wholesale_order_workflow.dart';
import '../widgets/async_body.dart';
import '../widgets/detail_info_table.dart';
import '../widgets/status_chip.dart';
import '../widgets/wholesale_order_stepper.dart';
import '../widgets/media_picker.dart';
import '../widgets/wholesale_order_process_tab.dart';
import 'shipments_screen.dart';
import 'wholesale_audit_log_screen.dart';

class WholesaleOrderDetailScreen extends StatefulWidget {
  const WholesaleOrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<WholesaleOrderDetailScreen> createState() => _WholesaleOrderDetailScreenState();
}

class _WholesaleOrderDetailScreenState extends State<WholesaleOrderDetailScreen>
    with SingleTickerProviderStateMixin {
  var _loading = true;
  var _error = '';
  var _actioning = false;
  WholesaleOrder? _order;
  List<AuditLogEntry> _auditLogs = [];
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getWholesaleOrder(widget.orderId),
        ApiService.instance.getWholesaleAuditLogs(widget.orderId),
      ]);
      if (!mounted) return;
      setState(() {
        _order = results[0] as WholesaleOrder;
        _auditLogs = results[1] as List<AuditLogEntry>;
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

  Future<void> _setOrder(WholesaleOrder order) async {
    setState(() => _order = order);
    try {
      final logs = await ApiService.instance.getWholesaleAuditLogs(widget.orderId);
      if (mounted) setState(() => _auditLogs = logs);
    } catch (_) {}
  }

  Future<void> _reject() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.rejectOrder),
        content: TextField(
          controller: reason,
          decoration: InputDecoration(labelText: l10n.rejectReason),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.reject)),
        ],
      ),
    );
    if (ok != true) {
      reason.dispose();
      return;
    }
    setState(() => _actioning = true);
    try {
      final updated = await ApiService.instance.rejectWholesaleOrder(
        widget.orderId,
        reason: reason.text.trim(),
      );
      await _setOrder(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      reason.dispose();
      if (mounted) setState(() => _actioning = false);
    }
  }

  Future<void> _downloadDoc(WholesaleOrderDocument doc) async {
    try {
      final bytes = await ApiService.instance.downloadWholesaleDocument(widget.orderId, doc.id);
      final dir = await getTemporaryDirectory();
      final name = doc.originalFilename ?? '${doc.type}_${doc.id}.pdf';
      final file = File('${dir.path}/${name.split('/').last}');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    }
  }

  Future<void> _uploadPo() async {
    await MediaPicker.showSourceSheet(context, onPicked: (paths) async {
      setState(() => _actioning = true);
      try {
        await ApiService.instance.uploadPoAttachments(widget.orderId, paths);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.instance.errorMessage(e))),
          );
        }
      } finally {
        if (mounted) setState(() => _actioning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final workflowCtx = order == null ? null : buildWholesaleWorkflowContext(order, _auditLogs);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(order?.orderNumber ?? l10n.menuWholesaleOrders),
        actions: [
          IconButton(
            tooltip: l10n.auditLog,
            icon: const Icon(Icons.history),
            onPressed: order == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WholesaleAuditLogScreen(orderId: order.id),
                      ),
                    ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: order == null
            ? null
            : TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: l10n.overview),
                  Tab(text: l10n.process),
                  Tab(text: l10n.documents),
                ],
              ),
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: order == null || workflowCtx == null
            ? const SizedBox.shrink()
            : Column(
                children: [
                  if (_actioning) const LinearProgressIndicator(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _OverviewTab(order: order, workflowCtx: workflowCtx, auditLogs: _auditLogs),
                        WholesaleOrderProcessTab(
                          order: order,
                          auditLogs: _auditLogs,
                          actioning: _actioning,
                          onOrderUpdated: (_) async {
                            setState(() => _actioning = true);
                            await _load();
                            if (mounted) setState(() => _actioning = false);
                          },
                          onDownloadDoc: _downloadDoc,
                          onReject: _reject,
                        ),
                        _DocumentsTab(
                          order: order,
                          onDownload: _downloadDoc,
                          onUploadPo: _uploadPo,
                          onOpenShipment: (id) => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: id)),
                          ).then((_) => _load()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.order,
    required this.workflowCtx,
    required this.auditLogs,
  });

  final WholesaleOrder order;
  final WholesaleWorkflowContext workflowCtx;
  final List<AuditLogEntry> auditLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium;
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        WholesaleOrderStepperCard(order: order, auditLogs: auditLogs),
        const SizedBox(height: 16),
        DetailInfoTable(
          rows: [
            DetailInfoRow(l10n.client, Text(order.client?.name ?? '—', style: valueStyle)),
            DetailInfoRow(
              l10n.status,
              StatusChip(
                label: l10n.wholesaleOrderWorkflowStatusLabel(order, workflowCtx),
                color: wholesaleOrderStatusColor(order, workflowCtx),
              ),
            ),
            DetailInfoRow(l10n.po, Text(order.poNumber ?? '—', style: valueStyle)),
            DetailInfoRow(l10n.ref, Text(order.refNo ?? '—', style: valueStyle)),
            DetailInfoRow(l10n.channel, Text(order.orderChannel ?? '—', style: valueStyle)),
            DetailInfoRow(l10n.created, Text(formatDateTime(order.createdAt), style: valueStyle)),
            DetailInfoRow(l10n.total, Text(formatMoney(order.amountDue ?? order.itemsTotal), style: valueStyle)),
            if (order.rejectionReason?.isNotEmpty == true)
              DetailInfoRow(l10n.reject, Text(order.rejectionReason!, style: valueStyle)),
          ],
        ),
        const SizedBox(height: 16),
        Text(l10n.items, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...order.items.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(item.displayName())),
                      const SizedBox(width: 12),
                      Text(formatMoney(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.qtyAssigned(
                      item.quantity.toString(),
                      item.assignedStore?.name ?? l10n.unassigned,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab({
    required this.order,
    required this.onDownload,
    required this.onUploadPo,
    required this.onOpenShipment,
  });

  final WholesaleOrder order;
  final void Function(WholesaleOrderDocument doc) onDownload;
  final VoidCallback onUploadPo;
  final void Function(int shipmentId) onOpenShipment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          onPressed: onUploadPo,
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.uploadPoAttachment),
        ),
        const SizedBox(height: 16),
        Text(l10n.documents, style: Theme.of(context).textTheme.titleMedium),
        if (order.documents.isEmpty) Text(l10n.noDocumentsYet),
        ...order.documents.map(
          (doc) => Card(
            child: ListTile(
              title: Text(doc.type.replaceAll('_', ' ')),
              subtitle: Text(doc.originalFilename ?? doc.fileUrl),
              trailing: const Icon(Icons.download),
              onTap: () => onDownload(doc),
            ),
          ),
        ),
        if (order.shipments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.shipments, style: Theme.of(context).textTheme.titleMedium),
          ...order.shipments.map(
            (sh) => ListTile(
              title: Text(sh.store?.name ?? l10n.shipmentNumber(sh.id)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusChip(
                    label: l10n.shipmentStatusLabel(sh.status),
                    color: shipmentStatusChipColor(sh.status),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => onOpenShipment(sh.id),
            ),
          ),
        ],
      ],
    );
  }
}
