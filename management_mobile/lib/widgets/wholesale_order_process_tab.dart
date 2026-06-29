import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/admin.dart';
import '../models/stock.dart';
import '../models/store.dart';
import '../models/wholesale_order.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/payment_transfer_accounts.dart';
import '../utils/wholesale_order_assignment.dart';
import '../utils/wholesale_order_email.dart';
import '../utils/wholesale_order_pipeline.dart';
import '../utils/wholesale_order_workflow.dart';
import '../widgets/media_picker.dart';
import '../widgets/status_chip.dart';
import '../widgets/wholesale_order_email_dialog.dart';
import '../widgets/wholesale_payment_proof_dialog.dart';
import '../widgets/date_picker_field.dart';
import '../screens/shipments_screen.dart';

class WholesaleOrderProcessTab extends StatefulWidget {
  const WholesaleOrderProcessTab({
    super.key,
    required this.order,
    required this.auditLogs,
    required this.actioning,
    required this.onOrderUpdated,
    required this.onDownloadDoc,
    required this.onReject,
  });

  final WholesaleOrder order;
  final List<AuditLogEntry> auditLogs;
  final bool actioning;
  final Future<void> Function(WholesaleOrder order) onOrderUpdated;
  final void Function(WholesaleOrderDocument doc) onDownloadDoc;
  final Future<void> Function() onReject;

  @override
  State<WholesaleOrderProcessTab> createState() => _WholesaleOrderProcessTabState();
}

class _WholesaleOrderProcessTabState extends State<WholesaleOrderProcessTab> {
  List<Store> _stores = [];
  final _storeByItem = <int, int?>{};
  List<StagedStoreAssignment> _staged = [];
  var _allocationConfirmed = false;
  var _stockLoading = false;
  Map<String, StockRow> _stockByStoreProduct = {};
  CompanySettings? _companySettings;

  WholesaleOrder get order => widget.order;

  bool get _usesStagedAssignment => order.status == 'pending_approval';

  Map<int, String> get _storeNameById => {for (final s in _stores) s.id: s.name};

  WholesaleWorkflowContext get _ctx => buildWholesaleWorkflowContext(order, widget.auditLogs);

  List<WholesaleProcessStep> get _steps => computeWholesaleOrderProcessSteps(order, _ctx);

  WholesaleProcessStepKey? get _currentStep => currentWholesaleProcessStepKey(_steps);

  Iterable<String> get _completedAssignmentActions => widget.auditLogs
      .where((l) => l.action == 'wholesale_order_complete_assignment')
      .map((l) => l.action);

  double _pendingQtyForItem(WholesaleOrderItem item) {
    if (_usesStagedAssignment) {
      return pendingQtyForOrderItemWithStaging(order, item, _staged);
    }
    return pendingQtyForOrderItem(order, item);
  }

  bool get _allLinesAssignedForConfirm {
    if (_usesStagedAssignment) return allOrderLinesFullyStaged(order, _staged);
    return allOrderLinesFullyAssigned(order);
  }

  @override
  void initState() {
    super.initState();
    _allocationConfirmed = allOrderLinesFullyAssigned(order);
    _loadStores();
    _loadCompanySettings();
  }

  Future<void> _loadCompanySettings() async {
    try {
      final settings = await ApiService.instance.getCompanySettings();
      if (!mounted) return;
      setState(() => _companySettings = settings);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant WholesaleOrderProcessTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != order.id) {
      _staged = [];
      _allocationConfirmed = allOrderLinesFullyAssigned(order);
    } else if (oldWidget.order.status == 'pending_approval' && order.status != 'pending_approval') {
      _staged = [];
      _allocationConfirmed = true;
    } else if (!_usesStagedAssignment && allOrderLinesFullyAssigned(order)) {
      _allocationConfirmed = true;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  void _setStateNextFrame(VoidCallback fn) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(fn);
    });
  }

  Future<void> _loadStores() async {
    try {
      final stores = await ApiService.instance.listStores();
      if (!mounted) return;
      setState(() => _stores = stores);
      await _loadStoreStock(stores);
    } catch (_) {}
  }

  Future<void> _loadStoreStock(List<Store> stores) async {
    if (stores.isEmpty) return;
    setState(() => _stockLoading = true);
    try {
      final results = await Future.wait(stores.map((s) => ApiService.instance.getStoreStock(s.id)));
      if (!mounted) return;
      final map = <String, StockRow>{};
      for (var i = 0; i < stores.length; i++) {
        for (final row in results[i]) {
          map['${stores[i].id}-${row.productId}'] = row;
        }
      }
      setState(() {
        _stockByStoreProduct = map;
        _stockLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _stockLoading = false);
    }
  }

  Future<void> _run(Future<WholesaleOrder> Function() fn, String message) async {
    try {
      final updated = await fn();
      await widget.onOrderUpdated(updated);
      _snack(message);
    } catch (e) {
      _snack(ApiService.instance.errorMessage(e));
    }
  }

  Future<void> _assignItem(WholesaleOrderItem item) async {
    final storeId = _storeByItem[item.id];
    if (storeId == null) {
      _snack(AppLocalizations.of(context)!.snackSelectStore);
      return;
    }
    if (!storeAllowsAssignmentTarget(order, storeId)) {
      _snack(AppLocalizations.of(context)!.snackShipmentPacked);
      return;
    }
    final pending = _pendingQtyForItem(item);
    if (pending <= 0) return;

    if (_usesStagedAssignment) {
      setState(() {
        _staged = addStagedAssignment(
          _staged,
          StagedStoreAssignment(
            wholesaleOrderItemId: item.id,
            storeId: storeId,
            quantity: pending,
          ),
        );
        _allocationConfirmed = false;
        _storeByItem[item.id] = null;
      });
      if (mounted) _snack(AppLocalizations.of(context)!.snackLineStaged);
      return;
    }

    await _run(
      () => ApiService.instance.assignWholesaleOrder(order.id, [
        {
          'wholesale_order_item_id': item.id,
          'store_id': storeId,
          'quantity': pending,
        },
      ]),
      AppLocalizations.of(context)!.lineAssigned,
    );
    if (mounted) setState(() => _allocationConfirmed = false);
  }

  Future<void> _assignByDefaults() async {
    if (_usesStagedAssignment) {
      try {
        final preview = await ApiService.instance.getEndorseAllocationPreview(order.id);
        if (!mounted) return;
        setState(() {
          _staged = preview.assignments
              .map(
                (a) => StagedStoreAssignment(
                  wholesaleOrderItemId: a.wholesaleOrderItemId,
                  storeId: a.storeId,
                  quantity: a.quantity,
                ),
              )
              .toList();
          _allocationConfirmed = false;
        });
        _snack(AppLocalizations.of(context)!.snackDefaultStaged);
      } catch (e) {
        _snack(ApiService.instance.errorMessage(e));
      }
      return;
    }
    await _run(
      () => ApiService.instance.assignWholesaleByDefaults(order.id),
      AppLocalizations.of(context)!.assignedByDefaults,
    );
    if (mounted) setState(() => _allocationConfirmed = false);
  }

  Future<void> _confirmAllocation() async {
    if (!_allLinesAssignedForConfirm) {
      _snack(AppLocalizations.of(context)!.snackAssignAllLines);
      return;
    }

    if (_usesStagedAssignment) {
      try {
        var updated = await ApiService.instance.approveWholesaleOrder(order.id);
        updated = await ApiService.instance.assignWholesaleOrder(
          order.id,
          _staged.map((a) => a.toJson()).toList(),
        );
        await widget.onOrderUpdated(updated);
        if (!mounted) return;
        setState(() {
          _staged = [];
          _allocationConfirmed = true;
        });
        _snack(AppLocalizations.of(context)!.snackOrderApproved);
      } catch (e) {
        _snack(ApiService.instance.errorMessage(e));
      }
      return;
    }

    setState(() => _allocationConfirmed = true);
    _snack(AppLocalizations.of(context)!.snackAllocationConfirmedContinue);
  }

  Future<void> _unassignAssignment(
    WholesaleOrderItem item,
    OrderItemStoreAssignment entry,
  ) async {
    if (_usesStagedAssignment && entry.staged) {
      setState(() {
        _staged = removeStagedAssignmentQty(_staged, item.id, entry.storeId, entry.quantity);
        _allocationConfirmed = false;
      });
      if (mounted) _snack(AppLocalizations.of(context)!.snackAssignmentRemoved);
      return;
    }

    try {
      final updated = await ApiService.instance.unassignWholesaleOrder(order.id, [
        {
          'wholesale_order_item_id': item.id,
          'store_id': entry.storeId,
          'quantity': entry.quantity,
        },
      ]);
      await widget.onOrderUpdated(updated);
      if (!mounted) return;
      _setStateNextFrame(() => _allocationConfirmed = false);
      _snack(AppLocalizations.of(context)!.snackAssignmentRemoved);
    } catch (e) {
      _snack(ApiService.instance.errorMessage(e));
    }
  }

  Future<void> _reassignAssignment(
    WholesaleOrderItem item,
    OrderItemStoreAssignment entry,
  ) async {
    final result = await showDialog<({int storeId, double qty})>(
      context: context,
      builder: (ctx) => _MoveAssignmentDialog(
        entry: entry,
        storeItems: _storeDropdownItems(item, entry.quantity)
            .where((e) => e.value != entry.storeId)
            .toList(),
      ),
    );
    if (result == null) return;
    final targetStoreId = result.storeId;
    final moveQty = result.qty;
    if (!storeAllowsAssignmentTarget(order, targetStoreId)) {
      _snack(AppLocalizations.of(context)!.snackShipmentPacked);
      return;
    }

    if (_usesStagedAssignment && entry.staged) {
      setState(() {
        _staged = addStagedAssignment(
          removeStagedAssignmentQty(_staged, item.id, entry.storeId, moveQty),
          StagedStoreAssignment(
            wholesaleOrderItemId: item.id,
            storeId: targetStoreId,
            quantity: moveQty,
          ),
        );
        _allocationConfirmed = false;
      });
      _snack(AppLocalizations.of(context)!.snackAssignmentMoved);
      return;
    }

    try {
      var updated = await ApiService.instance.unassignWholesaleOrder(order.id, [
        {
          'wholesale_order_item_id': item.id,
          'store_id': entry.storeId,
          'quantity': moveQty,
        },
      ]);
      updated = await ApiService.instance.assignWholesaleOrder(updated.id, [
        {
          'wholesale_order_item_id': item.id,
          'store_id': targetStoreId,
          'quantity': moveQty,
        },
      ]);
      await widget.onOrderUpdated(updated);
      if (!mounted) return;
      _setStateNextFrame(() => _allocationConfirmed = false);
      _snack(AppLocalizations.of(context)!.snackAssignmentMoved);
    } catch (e) {
      _snack(ApiService.instance.errorMessage(e));
    }
  }

  Widget _buildAssignedRows(WholesaleOrderItem item, bool actioning) {
    final l10n = AppLocalizations.of(context)!;
    final assignments = orderItemStoreAssignments(order, item.id, _staged, _storeNameById);
    if (assignments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(l10n.assigned, style: Theme.of(context).textTheme.labelMedium),
        ...assignments.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${entry.storeName} · ${formatAssignmentQty(entry.quantity)}'
                    '${entry.staged ? ' (staged)' : ''}',
                  ),
                ),
                if (entry.canUnassign) ...[
                  TextButton(
                    onPressed: actioning ? null : () => _reassignAssignment(item, entry),
                    child: Text(l10n.move),
                  ),
                  TextButton(
                    onPressed: actioning ? null : () => _unassignAssignment(item, entry),
                    child: Text(l10n.remove),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  List<DropdownMenuItem<int>> _storeDropdownItems(WholesaleOrderItem item, double needQty) {
    final eligible = _stores.where((s) => storeAllowsAssignmentTarget(order, s.id)).toList()
      ..sort((a, b) {
        final ha = storeStockHighlightLevel(a.id, order, _pendingQtyForItem, _stockByStoreProduct);
        final hb = storeStockHighlightLevel(b.id, order, _pendingQtyForItem, _stockByStoreProduct);
        int rank(StoreStockHighlight h) => switch (h) {
              StoreStockHighlight.full => 0,
              StoreStockHighlight.partial => 1,
              _ => 2,
            };
        final cmp = rank(ha).compareTo(rank(hb));
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

    return eligible.map((store) {
      final stock = _stockByStoreProduct['${store.id}-${item.productId}'];
      final hint = formatAssignStoreStockHint(stock?.quantity, needQty);
      return DropdownMenuItem(
        value: store.id,
        child: Row(
          children: [
            _StoreHighlightDot(highlight: storeStockHighlightLevel(
              store.id,
              order,
              _pendingQtyForItem,
              _stockByStoreProduct,
            )),
            const SizedBox(width: 8),
            Expanded(
              child: Text(store.name, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(
              hint.text,
              style: TextStyle(
                fontSize: 12,
                color: hint.sufficient ? Colors.green.shade700 : Colors.orange.shade800,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildStoreChipBar() {
    if (_stores.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _stores.map((store) {
        if (!storeAllowsAssignmentTarget(order, store.id)) return const SizedBox.shrink();
        final highlight = storeStockHighlightLevel(
          store.id,
          order,
          _pendingQtyForItem,
          _stockByStoreProduct,
        );
        Color borderColor;
        Color bgColor;
        switch (highlight) {
          case StoreStockHighlight.full:
            borderColor = Colors.green.shade600;
            bgColor = Colors.green.withValues(alpha: 0.12);
          case StoreStockHighlight.partial:
            borderColor = Colors.orange.shade700;
            bgColor = Colors.orange.withValues(alpha: 0.12);
          case StoreStockHighlight.none:
            borderColor = Theme.of(context).dividerColor;
            bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: highlight == StoreStockHighlight.none ? 1 : 2),
          ),
          child: Text(store.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        );
      }).toList(),
    );
  }

  Future<void> _openEmailForKind(WholesaleOrderEmailType kind) async {
    final existingAudit = getWholesaleOrderEmailAudits(widget.auditLogs)[kind];
    final dialogData = existingAudit != null
        ? WholesaleEmailDialogData.fromAudit(kind, order, existingAudit, _companySettings)
        : WholesaleEmailDialogData.fromDefaults(kind, order, _companySettings);

    final request = await showDialog<WholesaleEmailSendRequest>(
      context: context,
      builder: (ctx) => WholesaleOrderEmailDialog(order: order, data: dialogData),
    );
    if (request == null) return;

    await _run(
      () => ApiService.instance.sendWholesaleEmail(
        order.id,
        emailType: request.emailType.apiValue,
        attachments: request.attachments,
        to: request.to,
        recipient: request.to.join(', '),
        cc: request.cc.isEmpty ? null : request.cc.join(', '),
        ccList: request.cc.isEmpty ? null : request.cc,
        bcc: request.bcc.isEmpty ? null : request.bcc.join(', '),
        bccList: request.bcc.isEmpty ? null : request.bcc,
        subject: request.subject,
        message: request.message,
        shipmentIds: request.shipmentIds,
      ),
      AppLocalizations.of(context)!.emailSent,
    );
  }

  Widget _buildEmailActions({
    required WholesaleOrderEmailType type,
    required bool emailDone,
    required bool actioning,
    required String sendLabel,
    required String resendLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        emailDone
            ? OutlinedButton.icon(
                onPressed: actioning ? null : () => _openEmailForKind(type),
                icon: const Icon(Icons.email_outlined, size: 18),
                label: Text(resendLabel),
              )
            : FilledButton.icon(
                onPressed: actioning ? null : () => _openEmailForKind(type),
                icon: const Icon(Icons.email_outlined, size: 18),
                label: Text(sendLabel),
              ),
        if (!emailDone) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: actioning ? null : () => _skipEmail(type),
            child: Text(AppLocalizations.of(context)!.skip),
          ),
        ],
      ],
    );
  }

  Future<void> _skipEmail(WholesaleOrderEmailType emailType) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SkipEmailDialog(),
    );
    if (reason == null) return;
    try {
      await ApiService.instance.skipWholesaleEmail(
        order.id,
        emailType: emailType.apiValue,
        remark: reason,
      );
      await widget.onOrderUpdated(await ApiService.instance.getWholesaleOrder(order.id));
      _snack(AppLocalizations.of(context)!.emailSkipped);
    } catch (e) {
      _snack(ApiService.instance.errorMessage(e));
    }
  }

  Widget _buildEmailStatus(WholesaleEmailStepState state) {
    final l10n = AppLocalizations.of(context)!;
    if (state.skipped) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.skip_next, color: Colors.orange),
            title: Text(l10n.emailSkipped),
          ),
          if (state.skippedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.skippedAt(formatDateTime(state.skippedAt!)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (state.skippedBy.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                l10n.skippedBy(state.skippedBy),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (state.skipRemark.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.reasonPrefix(state.skipRemark),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      );
    }
    if (state.sent) {
      return ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(l10n.emailSent),
        subtitle: state.sentAt != null ? Text(formatDateTime(state.sentAt)) : null,
      );
    }
    return const SizedBox.shrink();
  }

  double _defaultProofAmount() {
    final orderTotal = wholesaleOrderGrandTotal(order);
    final proofTotal = _ctx.totalProofAmount ?? 0;
    final remaining = orderTotal - proofTotal;
    return remaining > 0 ? remaining : orderTotal;
  }

  Future<void> _confirmPaymentReceived() async {
    final l10n = AppLocalizations.of(context)!;
    final hasProof = hasPaymentProofDocument(order);
    final orderTotal = wholesaleOrderGrandTotal(order);
    final proofTotal = _ctx.totalProofAmount ?? 0;
    final proofShortfall = hasProof && proofTotal + 0.01 < orderTotal;

    final title = !hasProof
        ? l10n.noPaymentProof
        : proofShortfall
            ? l10n.forceConfirmPayment
            : l10n.confirmPaymentReceived;
    final message = !hasProof
        ? l10n.noPaymentProofWarning
        : proofShortfall
            ? l10n.forceConfirmWarning
            : l10n.confirmPaymentQuestion;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(
            style: (!hasProof || proofShortfall)
                ? FilledButton.styleFrom(backgroundColor: Colors.orange.shade800)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(proofShortfall ? l10n.forceComplete : l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final accounts = paymentTransferAccountOptions(_companySettings?.paymentTransferToInfo);
    final amount = _defaultProofAmount();
    await _run(
      () => ApiService.instance.confirmWholesalePayment(
        order.id,
        amount: amount > 0 ? amount : orderTotal,
        transferDate: formatApiDate(DateTime.now()),
        transferredTo: accounts.first,
      ),
      l10n.paymentConfirmed,
    );
  }

  Future<void> _openPaymentProofUpload() async {
    await MediaPicker.showSourceSheet(context, onPicked: (paths) async {
      if (paths.isEmpty || !mounted) return;
      final result = await showDialog<WholesalePaymentProofResult>(
        context: context,
        builder: (_) => WholesalePaymentProofDialog(
          filePaths: paths,
          defaultAmount: _defaultProofAmount(),
          accountOptions: paymentTransferAccountOptions(_companySettings?.paymentTransferToInfo),
        ),
      );
      if (result == null || !mounted) return;
      try {
        final updated = await ApiService.instance.uploadPaymentProofs(
          order.id,
          paths,
          amount: result.amount,
          transferDate: formatApiDate(result.transferDate),
          transferredTo: result.transferredTo,
        );
        await widget.onOrderUpdated(updated);
        if (!mounted) return;
        if (updated.paymentConfirmedAt != null) {
          _snack(AppLocalizations.of(context)!.snackPaymentProofAutoConfirmed);
        } else {
          _snack(AppLocalizations.of(context)!.snackPaymentProofUploaded);
        }
      } catch (e) {
        _snack(ApiService.instance.errorMessage(e));
      }
    });
  }

  bool _emailDone(WholesaleOrderEmailType type) {
    return wholesaleOrderEmailStepDone(
      type,
      widget.auditLogs,
      order: order,
      workflowInvoiceEmailDone: type == WholesaleOrderEmailType.invoice && order.workflowInvoiceEmailDone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final actioning = widget.actioning;
    final showAssign = wholesaleOrderShowsAssignmentPanel(
      order: order,
      currentStep: _currentStep,
      allocationConfirmed: _allocationConfirmed,
      staged: _staged,
      completedAssignmentActions: _completedAssignmentActions,
    );
    final canChangeAssignment = canChangeWholesaleAssignment(order, _allocationConfirmed);
    final showAssignmentSection = wholesaleOrderCanAssign(order) && (showAssign || _allocationConfirmed);
    final allShipmentsDone = order.shipments.isNotEmpty && order.shipments.every((s) => s.status == 'completed');
    final hasInvoice = orderHasInvoiceDocument(order);
    final orderConfirmEmailState = wholesaleEmailStepState(WholesaleOrderEmailType.orderConfirm, widget.auditLogs);
    final shipmentsDeliveredEmailState =
        wholesaleEmailStepState(WholesaleOrderEmailType.shipmentsDelivered, widget.auditLogs);
    final invoiceEmailState = wholesaleEmailStepState(WholesaleOrderEmailType.invoice, widget.auditLogs);
    final orderConfirmEmailDone = _emailDone(WholesaleOrderEmailType.orderConfirm);
    final shipmentsDeliveredEmailDone = _emailDone(WholesaleOrderEmailType.shipmentsDelivered);
    final invoiceEmailDone = _emailDone(WholesaleOrderEmailType.invoice);
    final paymentComplete = isPaymentConfirmationStepComplete(order, _ctx);
    final proofDocs = order.documents.where((d) => d.type == 'payment_proof').toList();
    final orderTotal = wholesaleOrderGrandTotal(order);
    final proofTotal = _ctx.totalProofAmount ?? 0;
    final pipeline = buildWholesalePipelineUiState(
      WholesalePipelineInputs(
        order: order,
        allocationConfirmed: _allocationConfirmed,
        orderConfirmEmailDone: orderConfirmEmailDone,
        allShipmentsCompleted: allShipmentsDone,
        shipmentsDeliveredEmailDone: shipmentsDeliveredEmailDone,
        invoiceEmailDone: invoiceEmailDone,
        paymentComplete: paymentComplete,
        hasInvoiceDocument: hasInvoice,
      ),
    );
    final assignSectionActive = wholesaleAssignSectionActive(
      order: order,
      showAssignPanel: showAssign,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.process, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),

        if (order.status == 'rejected') ...[
          _SectionCard(
            title: l10n.rejectedSection,
            pending: false,
            child: FilledButton(
              onPressed: actioning
                  ? null
                  : () => _run(() => ApiService.instance.resubmitWholesaleOrder(order.id), l10n.orderResubmitted),
              child: Text(l10n.resubmit),
            ),
          ),
        ],

        if (showAssignmentSection) ...[
          _SectionCard(
            title: l10n.orderConfirmation,
            active: assignSectionActive,
            pending: false,
            child: showAssign
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_usesStagedAssignment)
                        Text(
                          l10n.assignLinesHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Text(
                          l10n.assignLinesHintStaged,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 12),
                      if (_stockLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(),
                        )
                      else ...[
                        _buildStoreChipBar(),
                        const SizedBox(height: 12),
                      ],
                      ...order.items.map((item) {
                        final assigned = assignedQtyForOrderItem(order, item.id);
                        final stagedQty = stagedQtyForOrderItem(_staged, item.id);
                        final pending = _pendingQtyForItem(item);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(item.displayName(), style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  'Qty ${formatQty(item.quantity)} · Assigned ${formatQty(assigned)}'
                                  '${stagedQty > 0 ? ' · Staged ${formatQty(stagedQty)}' : ''}'
                                  ' · Pending ${formatQty(pending)}',
                                ),
                                _buildAssignedRows(item, actioning),
                                if (pending > 0.0001) ...[
                                  const SizedBox(height: 8),
                                  InputDecorator(
                                    decoration: InputDecoration(labelText: l10n.store, isDense: true),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        isExpanded: true,
                                        value: _storeByItem[item.id],
                                        hint: Text(l10n.selectStore),
                                        items: _storeDropdownItems(item, pending),
                                        onChanged: (v) => setState(() => _storeByItem[item.id] = v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: actioning ? null : () => _assignItem(item),
                                    child: Text(_usesStagedAssignment ? l10n.stageForStore : l10n.assignPendingQty),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                      OutlinedButton(
                        onPressed: actioning ? null : _assignByDefaults,
                        child: Text(l10n.assignByDefaults),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: actioning || !_allLinesAssignedForConfirm ? null : _confirmAllocation,
                        child: Text(_usesStagedAssignment ? l10n.confirmAllocationApprove : l10n.confirmAllocation),
                      ),
                      if (order.status == 'pending_approval') ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: actioning ? null : widget.onReject,
                          child: Text(l10n.rejectOrder),
                        ),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.allLinesAssigned,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.changeAssignmentWhilePacking,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      ...order.items.map((item) {
                        final assignments = orderItemStoreAssignments(order, item.id, _staged, _storeNameById);
                        if (assignments.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${item.displayName()}: ${assignments.map((a) => '${a.storeName} (${formatAssignmentQty(a.quantity)})').join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }),
                      if (canChangeAssignment) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: actioning
                              ? null
                              : () => setState(() => _allocationConfirmed = false),
                          child: Text(l10n.changeAssignment),
                        ),
                      ],
                    ],
                  ),
          ),
        ],

        if (pipeline.shouldShow(WholesalePipelineSection.orderConfirmEmail)) ...[
          _SectionCard(
            title: l10n.orderConfirmationEmail,
            active: pipeline.isActive(WholesalePipelineSection.orderConfirmEmail),
            pending: pipeline.isDimmed(WholesalePipelineSection.orderConfirmEmail),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEmailStatus(orderConfirmEmailState),
                const SizedBox(height: 8),
                _buildEmailActions(
                  type: WholesaleOrderEmailType.orderConfirm,
                  emailDone: orderConfirmEmailDone,
                  actioning: actioning,
                  sendLabel: l10n.sendOrderConfirmationEmail,
                  resendLabel: l10n.resendOrderConfirmationEmail,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: actioning
                      ? null
                      : () => _run(
                            () => ApiService.instance.regenerateOrderConfirmation(order.id),
                            l10n.orderConfirmationRegenerated,
                          ),
                  child: Text(l10n.regenerateOrderConfirmationPdf),
                ),
              ],
            ),
          ),
        ],

        if (pipeline.shouldShow(WholesalePipelineSection.shipments)) ...[
          _SectionCard(
            title: l10n.shipments,
            active: pipeline.isActive(WholesalePipelineSection.shipments),
            pending: pipeline.isDimmed(WholesalePipelineSection.shipments),
            child: order.shipments.isEmpty
                ? Text(
                    l10n.shipmentsAfterAssignment,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    children: order.shipments.map((sh) {
                      return Card(
                        child: ListTile(
                          title: Text(sh.store?.name ?? l10n.storeNumber(sh.storeId)),
                          subtitle: Text(l10n.linesCount(sh.items.length)),
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
                          onTap: pipeline.isDimmed(WholesalePipelineSection.shipments)
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: sh.id)),
                                  );
                                  await widget.onOrderUpdated(await ApiService.instance.getWholesaleOrder(order.id));
                                },
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],

        if (pipeline.shouldShow(WholesalePipelineSection.deliveryCompleteEmail)) ...[
          _SectionCard(
            title: l10n.deliveryCompleteEmail,
            active: pipeline.isActive(WholesalePipelineSection.deliveryCompleteEmail),
            pending: pipeline.isDimmed(WholesalePipelineSection.deliveryCompleteEmail),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEmailStatus(shipmentsDeliveredEmailState),
                const SizedBox(height: 8),
                _buildEmailActions(
                  type: WholesaleOrderEmailType.shipmentsDelivered,
                  emailDone: shipmentsDeliveredEmailDone,
                  actioning: actioning,
                  sendLabel: l10n.sendDeliveryCompleteEmail,
                  resendLabel: l10n.resendDeliveryCompleteEmail,
                ),
              ],
            ),
          ),
        ],

        if (pipeline.shouldShow(WholesalePipelineSection.invoiceEmail)) ...[
          _SectionCard(
            title: l10n.invoice,
            active: pipeline.isActive(WholesalePipelineSection.invoiceEmail),
            pending: pipeline.isDimmed(WholesalePipelineSection.invoiceEmail),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasInvoice)
                  OutlinedButton(
                    onPressed: actioning
                        ? null
                        : () => _run(() => ApiService.instance.generateInvoice(order.id), l10n.invoiceGenerated),
                    child: Text(l10n.generateInvoice),
                  ),
                if (hasInvoice) ...[
                  _buildEmailStatus(invoiceEmailState),
                  const SizedBox(height: 8),
                  _buildEmailActions(
                    type: WholesaleOrderEmailType.invoice,
                    emailDone: invoiceEmailDone,
                    actioning: actioning,
                    sendLabel: l10n.sendInvoiceEmail,
                    resendLabel: l10n.resendInvoiceEmail,
                  ),
                ],
              ],
            ),
          ),
        ],

        if (pipeline.shouldShow(WholesalePipelineSection.payment)) ...[
          _SectionCard(
            title: l10n.paymentConfirmationSection,
            active: pipeline.isActive(WholesalePipelineSection.payment),
            pending: pipeline.isDimmed(WholesalePipelineSection.payment),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.orderTotal(formatMoney(orderTotal))),
                if (proofTotal > 0) Text(l10n.proofTotal(formatMoney(proofTotal))),
                ...proofDocs.map(
                  (doc) => ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text(doc.originalFilename ?? l10n.paymentProofNumber(doc.id)),
                    trailing: const Icon(Icons.download),
                    onTap: () => widget.onDownloadDoc(doc),
                  ),
                ),
                if (order.paymentConfirmedAt == null) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: actioning ? null : _openPaymentProofUpload,
                    icon: const Icon(Icons.upload_file),
                    label: Text(l10n.uploadPaymentProof),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: actioning ? null : _confirmPaymentReceived,
                    child: Text(l10n.confirmPaymentReceived),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text(l10n.paymentConfirmed),
                    subtitle: Text(formatDateTime(order.paymentConfirmedAt)),
                  ),
                  if (proofTotal + 0.01 < orderTotal)
                    Text(
                      l10n.proofShortfallHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

String formatQty(double qty) {
  if (qty == qty.roundToDouble()) return qty.toInt().toString();
  return qty.toStringAsFixed(2);
}

class _StoreHighlightDot extends StatelessWidget {
  const _StoreHighlightDot({required this.highlight});
  final StoreStockHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final color = switch (highlight) {
      StoreStockHighlight.full => Colors.green.shade600,
      StoreStockHighlight.partial => Colors.orange.shade700,
      StoreStockHighlight.none => Colors.grey.shade400,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MoveAssignmentDialog extends StatefulWidget {
  const _MoveAssignmentDialog({
    required this.entry,
    required this.storeItems,
  });

  final OrderItemStoreAssignment entry;
  final List<DropdownMenuItem<int>> storeItems;

  @override
  State<_MoveAssignmentDialog> createState() => _MoveAssignmentDialogState();
}

class _MoveAssignmentDialogState extends State<_MoveAssignmentDialog> {
  late final TextEditingController _qtyController;
  int? _targetStoreId;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: formatAssignmentQty(widget.entry.quantity));
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  double get _moveQty => double.tryParse(_qtyController.text.trim()) ?? widget.entry.quantity;

  bool get _validQty => _moveQty > 0 && _moveQty <= widget.entry.quantity + 0.0001;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.moveReassign),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.moveFrom(widget.entry.storeName)),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.quantity,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(labelText: l10n.store, border: const OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _targetStoreId,
                  hint: Text(l10n.selectStore),
                  items: widget.storeItems,
                  onChanged: (v) => setState(() => _targetStoreId = v),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _validQty && _targetStoreId != null
              ? () => Navigator.pop(context, (storeId: _targetStoreId!, qty: _moveQty))
              : null,
          child: Text(l10n.move),
        ),
      ],
    );
  }
}

class _SkipEmailDialog extends StatefulWidget {
  const _SkipEmailDialog();

  @override
  State<_SkipEmailDialog> createState() => _SkipEmailDialogState();
}

class _SkipEmailDialogState extends State<_SkipEmailDialog> {
  late final TextEditingController _remark;
  String? _error;

  @override
  void initState() {
    super.initState();
    _remark = TextEditingController();
  }

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _remark.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.skipReasonRequired);
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.skipEmail),
      content: TextField(
        controller: _remark,
        decoration: InputDecoration(
          labelText: l10n.rejectReason,
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
        maxLines: 3,
        autofocus: true,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.skip)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.active = false,
    this.pending = false,
  });
  final String title;
  final Widget child;
  final bool active;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final borderSide = active
        ? BorderSide(color: theme.colorScheme.primary, width: 2)
        : pending
            ? BorderSide(color: theme.dividerColor, width: 1)
            : BorderSide.none;

    Widget content = child;
    if (pending) {
      content = Stack(
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: 0.55,
              child: child,
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.lock_outline, size: 28, color: theme.disabledColor),
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: pending ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: borderSide,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: pending ? theme.disabledColor : null,
                    ),
                  ),
                ),
                if (active)
                  StatusChip(
                    label: l10n.actionNeeded,
                    color: StatusChipColor.warning,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }
}
