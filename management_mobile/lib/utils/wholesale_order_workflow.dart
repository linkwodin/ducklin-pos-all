import 'dart:convert';

import '../models/admin.dart';
import '../models/shipment.dart';
import '../models/wholesale_order.dart';
import 'status_chip_style.dart';
import 'wholesale_order_assignment.dart';

enum WholesaleProcessStepKey {
  stepCreate,
  stepOrderConfirmation,
  stepStartShipment,
  stepFinishShipment,
  stepSendInvoiceEmail,
  stepPaymentConfirmation,
  stepComplete,
}

class WholesaleProcessStep {
  const WholesaleProcessStep({required this.key, required this.done});
  final WholesaleProcessStepKey key;
  final bool done;
}

class WholesaleWorkflowContext {
  const WholesaleWorkflowContext({this.auditLogs = const [], this.totalProofAmount});
  final List<AuditLogEntry> auditLogs;
  final double? totalProofAmount;
}

bool shipmentHasDeliveryNoteStarted(Shipment shipment) {
  return shipment.status == 'packed' ||
      shipment.status == 'shipped' ||
      shipment.status == 'completed' ||
      (shipment.deliveryNotePdfUrl?.trim().isNotEmpty ?? false);
}

bool orderHasInvoiceDocument(WholesaleOrder order) {
  return order.documents.any((d) => d.type == 'invoice');
}

bool hasPaymentProofDocument(WholesaleOrder order) {
  if (order.paymentProofUrl?.trim().isNotEmpty ?? false) return true;
  return order.documents.any((d) => d.type == 'payment_proof');
}

double wholesaleOrderGrandTotal(WholesaleOrder order) {
  final itemsTotal = order.totalNet ?? order.itemsTotal;
  return itemsTotal + (order.shippingFee ?? 0);
}

Map<String, dynamic>? _parseAuditChanges(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return null;
    final nested = parsed['changes'];
    if (nested is Map<String, dynamic>) return nested;
    return parsed;
  } catch (_) {
    return null;
  }
}

bool _invoiceEmailDone(WholesaleOrder order, List<AuditLogEntry> auditLogs) {
  if (!orderHasInvoiceDocument(order)) return true;
  for (final log in auditLogs) {
    if (!log.action.contains('email') || log.changes == null) continue;
    final changes = _parseAuditChanges(log.changes);
    if (changes == null) continue;
    final emailType = changes['email_type']?.toString();
    if (emailType != 'invoice') continue;
    if (changes['skipped_at'] != null || changes['sent_at'] != null || changes['done'] == true) {
      return true;
    }
  }
  if (order.workflowInvoiceEmailDone) return true;
  if (order.invoiceSentAt?.trim().isNotEmpty ?? false) return true;
  if (order.paymentConfirmedAt?.trim().isNotEmpty ?? false) return true;
  return false;
}

double computeTotalProofAmountFromAudits(WholesaleOrder order, List<AuditLogEntry> auditLogs) {
  final proofDocs = order.documents.where((d) => d.type == 'payment_proof').toList();
  if (proofDocs.isEmpty) return 0;

  final uploadAudits = auditLogs
      .where((l) => l.action == 'wholesale_order_upload_payment_proof')
      .map((l) {
        final base = _parseAuditChanges(l.changes);
        if (base == null) return null;
        final fileCountRaw = base['file_count'] ?? base['files'] ?? 1;
        final fileCount = double.tryParse('$fileCountRaw') ?? 1;
        final amountNum = double.tryParse('${base['amount']}');
        return (createdAt: l.createdAt, fileCount: fileCount, amount: amountNum);
      })
      .whereType<({String? createdAt, double fileCount, double? amount})>()
      .toList();

  if (uploadAudits.isEmpty) return order.workflowPaymentProofTotal ?? 0;

  proofDocs.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
  uploadAudits.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));

  var docIndex = 0;
  var total = 0.0;
  for (final audit in uploadAudits) {
    var remaining = audit.fileCount <= 0 ? 1.0 : audit.fileCount;
    final perFile = audit.amount != null && remaining > 0 ? audit.amount! / remaining : null;
    while (remaining > 0 && docIndex < proofDocs.length) {
      if (perFile != null) total += perFile;
      docIndex += 1;
      remaining -= 1;
    }
  }
  return total;
}

WholesaleWorkflowContext buildWholesaleWorkflowContext(
  WholesaleOrder order,
  List<AuditLogEntry> auditLogs,
) {
  final totalProof = auditLogs.isNotEmpty
      ? computeTotalProofAmountFromAudits(order, auditLogs)
      : order.workflowPaymentProofTotal;
  return WholesaleWorkflowContext(
    auditLogs: auditLogs,
    totalProofAmount: totalProof,
  );
}

bool isPaymentConfirmationStepComplete(WholesaleOrder order, WholesaleWorkflowContext ctx) {
  // Order complete date (payment confirmed) always completes this step.
  if (order.paymentConfirmedAt != null && order.paymentConfirmedAt!.trim().isNotEmpty) {
    return true;
  }

  final orderTotal = wholesaleOrderGrandTotal(order);
  final totalProof = ctx.totalProofAmount;
  if (totalProof != null) {
    return orderTotal - totalProof < 0.01;
  }
  if (hasPaymentProofDocument(order)) return false;
  return false;
}

bool isWholesaleOrderPaymentSettled(WholesaleOrder order, WholesaleWorkflowContext ctx) {
  if (order.paymentConfirmedAt != null && order.paymentConfirmedAt!.trim().isNotEmpty) {
    return true;
  }
  final orderTotal = wholesaleOrderGrandTotal(order);
  final totalProof = ctx.totalProofAmount ?? order.workflowPaymentProofTotal;
  if (totalProof != null) {
    return orderTotal - totalProof < 0.01;
  }
  return false;
}

List<String> _completedAssignmentActions(List<AuditLogEntry> auditLogs) {
  return auditLogs
      .where((l) => l.action == 'wholesale_order_complete_assignment')
      .map((l) => l.action)
      .toList();
}

List<WholesaleProcessStep> computeWholesaleOrderProcessSteps(
  WholesaleOrder order,
  WholesaleWorkflowContext ctx,
) {
  final shipments = order.shipments;
  final hasShipments = shipments.isNotEmpty;
  final allStarted = hasShipments && shipments.every(shipmentHasDeliveryNoteStarted);
  final allCompleted = hasShipments && shipments.every((s) => s.status == 'completed');
  final hasInvoice = orderHasInvoiceDocument(order);
  final assignmentActions = _completedAssignmentActions(ctx.auditLogs);

  final stepOrderConfirmation = order.status != 'pending_approval' &&
      order.status != 'rejected' &&
      order.status != 'deleted' &&
      isAssignmentComplete(order, completedAssignmentActions: assignmentActions);
  final stepSendInvoiceEmail = _invoiceEmailDone(order, ctx.auditLogs);
  final stepPaymentConfirmation = isPaymentConfirmationStepComplete(order, ctx);

  final steps = <WholesaleProcessStep>[
    const WholesaleProcessStep(key: WholesaleProcessStepKey.stepCreate, done: true),
    WholesaleProcessStep(key: WholesaleProcessStepKey.stepOrderConfirmation, done: stepOrderConfirmation),
    WholesaleProcessStep(key: WholesaleProcessStepKey.stepStartShipment, done: allStarted),
    WholesaleProcessStep(key: WholesaleProcessStepKey.stepFinishShipment, done: allCompleted),
  ];

  if (hasInvoice) {
    steps.add(WholesaleProcessStep(key: WholesaleProcessStepKey.stepSendInvoiceEmail, done: stepSendInvoiceEmail));
  }

  steps.addAll([
    WholesaleProcessStep(key: WholesaleProcessStepKey.stepPaymentConfirmation, done: stepPaymentConfirmation),
    WholesaleProcessStep(
      key: WholesaleProcessStepKey.stepComplete,
      done: stepOrderConfirmation && allCompleted && stepSendInvoiceEmail && stepPaymentConfirmation,
    ),
  ]);

  return steps;
}

WholesaleProcessStepKey? currentWholesaleProcessStepKey(List<WholesaleProcessStep> steps) {
  for (final step in steps) {
    if (!step.done) return step.key;
  }
  return null;
}

bool isWholesaleOrderCompleted(WholesaleOrder order) {
  if (order.isCompleted) return true;
  if (order.shipments.isEmpty) return false;
  final allShipmentsCompleted = order.shipments.every((s) => s.status == 'completed');
  return allShipmentsCompleted && (order.paymentConfirmedAt?.trim().isNotEmpty ?? false);
}

bool isWholesaleOrderPaymentConfirmationPhase(
  WholesaleOrder order, [
  WholesaleWorkflowContext? ctx,
]) {
  final workflowCtx = ctx ?? buildWholesaleWorkflowContext(order, const []);
  final steps = computeWholesaleOrderProcessSteps(order, workflowCtx);
  return currentWholesaleProcessStepKey(steps) == WholesaleProcessStepKey.stepPaymentConfirmation;
}

/// API status query — derived filters fetch `approved` then filter client-side (portal parity).
String? wholesaleOrderStatusFilterForApi(String? statusFilter) {
  if (statusFilter == null || statusFilter.isEmpty) return null;
  if (statusFilter == 'awaiting_payment' || statusFilter == 'completed') {
    return 'approved';
  }
  return statusFilter;
}

List<WholesaleOrder> filterWholesaleOrdersByStatus(List<WholesaleOrder> orders, String? statusFilter) {
  if (statusFilter == null || statusFilter.isEmpty) return orders;
  switch (statusFilter) {
    case 'awaiting_payment':
      return orders.where(isWholesaleOrderPaymentConfirmationPhase).toList();
    case 'completed':
      return orders.where(isWholesaleOrderCompleted).toList();
    default:
      return orders.where((o) => o.status == statusFilter).toList();
  }
}

const wholesaleOrderStatusFilterOptions = <({String? value, String label})>[
  (value: null, label: 'All'),
  (value: 'pending_approval', label: 'Pending approval'),
  (value: 'assign_shipment', label: 'Assign shipment'),
  (value: 'awaiting_payment', label: 'Awaiting payment'),
  (value: 'completed', label: 'Completed'),
  (value: 'rejected', label: 'Rejected'),
  (value: 'deleted', label: 'Deleted'),
];

bool wholesaleOrderAllowsStoreAssignment(
  WholesaleOrder order,
  WholesaleProcessStepKey? currentStep, {
  Iterable<String>? completedAssignmentActions,
}) {
  if (order.status != 'approved' && order.status != 'assign_shipment') return false;
  if (currentStep != WholesaleProcessStepKey.stepOrderConfirmation) return false;
  if (isAssignmentComplete(order, completedAssignmentActions: completedAssignmentActions)) {
    return false;
  }
  return orderAllowsAssignmentChange(order);
}

bool wholesaleOrderShowsAssignmentPanel({
  required WholesaleOrder order,
  required WholesaleProcessStepKey? currentStep,
  required bool allocationConfirmed,
  required List<StagedStoreAssignment> staged,
  Iterable<String>? completedAssignmentActions,
}) {
  if (!wholesaleOrderCanAssign(order)) return false;
  if (order.status == 'pending_approval') {
    return !allocationConfirmed || !allOrderLinesFullyStaged(order, staged);
  }
  // Match portal: once allocation is confirmed show summary; re-open editor when user changes assignment.
  if (!allocationConfirmed) return true;
  return false;
}

String wholesaleProcessStepLabel(WholesaleProcessStepKey key) {
  switch (key) {
    case WholesaleProcessStepKey.stepCreate:
      return 'Created';
    case WholesaleProcessStepKey.stepOrderConfirmation:
      return 'Order confirmation';
    case WholesaleProcessStepKey.stepStartShipment:
      return 'Start shipment';
    case WholesaleProcessStepKey.stepFinishShipment:
      return 'Finish shipment';
    case WholesaleProcessStepKey.stepSendInvoiceEmail:
      return 'Invoice email';
    case WholesaleProcessStepKey.stepPaymentConfirmation:
      return 'Payment confirmation';
    case WholesaleProcessStepKey.stepComplete:
      return 'Complete';
  }
}

String wholesaleOrderWorkflowStatusLabel(WholesaleOrder order, WholesaleWorkflowContext ctx) {
  if (order.status == 'rejected') return 'Rejected';
  if (order.status == 'deleted') return 'Deleted';

  if (isWholesaleOrderPaymentSettled(order, ctx)) return 'Completed';
  if (hasPaymentProofDocument(order)) return 'Pending payment confirmation';

  final steps = computeWholesaleOrderProcessSteps(order, ctx);
  if (steps.every((s) => s.done)) return 'Completed';

  switch (currentWholesaleProcessStepKey(steps)) {
    case WholesaleProcessStepKey.stepOrderConfirmation:
      return 'Pending order confirmation';
    case WholesaleProcessStepKey.stepStartShipment:
      return 'Pending packing';
    case WholesaleProcessStepKey.stepFinishShipment:
      return 'In transit';
    case WholesaleProcessStepKey.stepSendInvoiceEmail:
      return 'Pending invoice email';
    case WholesaleProcessStepKey.stepPaymentConfirmation:
      return 'Pending payment confirmation';
    case WholesaleProcessStepKey.stepComplete:
      return 'Completed';
    default:
      return wholesaleStatusLabel(order.status);
  }
}

StatusChipColor wholesaleOrderStatusColor(WholesaleOrder order, WholesaleWorkflowContext ctx) {
  if (order.status == 'rejected') return StatusChipColor.error;
  if (order.status == 'deleted') return StatusChipColor.defaultColor;

  if (isWholesaleOrderPaymentSettled(order, ctx)) return StatusChipColor.success;
  if (hasPaymentProofDocument(order)) return StatusChipColor.secondary;

  final steps = computeWholesaleOrderProcessSteps(order, ctx);
  if (steps.every((s) => s.done)) return StatusChipColor.success;

  switch (currentWholesaleProcessStepKey(steps)) {
    case WholesaleProcessStepKey.stepOrderConfirmation:
      return StatusChipColor.primary;
    case WholesaleProcessStepKey.stepStartShipment:
      return StatusChipColor.warning;
    case WholesaleProcessStepKey.stepFinishShipment:
      return StatusChipColor.info;
    case WholesaleProcessStepKey.stepSendInvoiceEmail:
      return StatusChipColor.warning;
    case WholesaleProcessStepKey.stepPaymentConfirmation:
      return StatusChipColor.secondary;
    default:
      return StatusChipColor.defaultColor;
  }
}

String wholesaleStatusLabel(String status) {
  switch (status) {
    case 'pending_approval':
      return 'Pending approval';
    case 'assign_shipment':
      return 'Assign shipment';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    case 'deleted':
      return 'Deleted';
    default:
      return status.replaceAll('_', ' ');
  }
}
