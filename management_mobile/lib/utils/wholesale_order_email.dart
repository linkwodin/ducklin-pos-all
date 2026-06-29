import 'dart:convert';

import '../models/admin.dart';
import '../models/wholesale_order.dart';
import 'formatters.dart';
import 'wholesale_order_workflow.dart';

enum WholesaleOrderEmailType {
  orderConfirm,
  shipmentsDelivered,
  invoice,
}

extension WholesaleOrderEmailTypeApi on WholesaleOrderEmailType {
  String get apiValue => switch (this) {
        WholesaleOrderEmailType.orderConfirm => 'order_confirm',
        WholesaleOrderEmailType.shipmentsDelivered => 'shipments_delivered',
        WholesaleOrderEmailType.invoice => 'invoice',
      };

  static WholesaleOrderEmailType? fromApi(String? raw) => switch (raw) {
        'order_confirm' => WholesaleOrderEmailType.orderConfirm,
        'shipments_delivered' => WholesaleOrderEmailType.shipmentsDelivered,
        'invoice' => WholesaleOrderEmailType.invoice,
        _ => null,
      };
}

class WholesaleEmailStepState {
  const WholesaleEmailStepState({
    this.sent = false,
    this.skipped = false,
    this.skipRemark = '',
    this.skippedBy = '',
    this.skippedAt,
    this.sentAt,
  });

  final bool sent;
  final bool skipped;
  final String skipRemark;
  final String skippedBy;
  final String? skippedAt;
  final String? sentAt;

  bool get done => sent || skipped;
}

Map<String, dynamic> parseWholesaleOrderEmailAuditBase(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return {};
    final nested = parsed['changes'];
    if (nested is Map<String, dynamic>) return nested;
    return parsed;
  } catch (_) {
    return {};
  }
}

bool isWholesaleOrderEmailSkippedAudit(Map<String, dynamic> changes) {
  final skipped = changes['skipped'];
  return skipped == true || skipped == 'true';
}

bool isWholesaleOrderEmailSentAudit(Map<String, dynamic> changes) {
  if (isWholesaleOrderEmailSkippedAudit(changes)) return false;
  final sentAt = changes['sent_at'];
  return sentAt is String && sentAt.trim().isNotEmpty;
}

String wholesaleOrderEmailSkipRemark(Map<String, dynamic> changes) {
  final raw = changes['skip_remark'] ?? changes['remark'];
  return raw is String ? raw.trim() : '';
}

WholesaleOrderEmailType? classifyWholesaleOrderEmailAudit(Map<String, dynamic> changes) {
  final emailType = WholesaleOrderEmailTypeApi.fromApi(changes['email_type']?.toString());
  if (emailType != null) return emailType;

  final kindsRaw = changes['attachment_kinds'];
  if (kindsRaw is! List) return null;
  final kinds = kindsRaw.map((k) => '$k').where((k) => k.trim().isNotEmpty).toList();
  if (kinds.isEmpty) return null;

  if (kinds.every((k) => k == 'po_attachment' || k == 'order_confirmation')) {
    return WholesaleOrderEmailType.orderConfirm;
  }
  if (kinds.every((k) => k == 'signed_delivery_note')) {
    final rawShipmentId = changes['signed_delivery_shipment_id'];
    if (rawShipmentId == null || rawShipmentId == '' || rawShipmentId == 0) {
      return WholesaleOrderEmailType.shipmentsDelivered;
    }
  }
  if (kinds.contains('invoice') &&
      kinds.every((k) => k == 'invoice' || k == 'delivery_note' || k == 'signed_delivery_note')) {
    return WholesaleOrderEmailType.invoice;
  }
  return null;
}

bool _isAuditLogNewer(AuditLogEntry a, AuditLogEntry b) {
  final ta = DateTime.tryParse(a.createdAt ?? '')?.millisecondsSinceEpoch ?? 0;
  final tb = DateTime.tryParse(b.createdAt ?? '')?.millisecondsSinceEpoch ?? 0;
  if (ta != tb) return ta > tb;
  return a.id > b.id;
}

Map<WholesaleOrderEmailType, AuditLogEntry> getWholesaleOrderEmailAudits(List<AuditLogEntry> auditLogs) {
  final result = <WholesaleOrderEmailType, AuditLogEntry>{};
  for (final log in auditLogs) {
    if (log.action != 'wholesale_order_email') continue;
    final type = classifyWholesaleOrderEmailAudit(parseWholesaleOrderEmailAuditBase(log.changes));
    if (type == null) continue;
    final existing = result[type];
    if (existing == null || _isAuditLogNewer(log, existing)) {
      result[type] = log;
    }
  }
  return result;
}

WholesaleEmailStepState wholesaleEmailStepState(
  WholesaleOrderEmailType type,
  List<AuditLogEntry> auditLogs,
) {
  final audit = getWholesaleOrderEmailAudits(auditLogs)[type];
  if (audit == null) return const WholesaleEmailStepState();
  final changes = parseWholesaleOrderEmailAuditBase(audit.changes);
  final skipped = isWholesaleOrderEmailSkippedAudit(changes);
  final sent = isWholesaleOrderEmailSentAudit(changes);
  final skippedAtRaw = changes['skipped_at'];
  final sentAtRaw = changes['sent_at'];
  final initiatedBy = changes['initiated_by'];
  return WholesaleEmailStepState(
    sent: sent,
    skipped: skipped,
    skipRemark: skipped ? wholesaleOrderEmailSkipRemark(changes) : '',
    skippedBy: skipped && initiatedBy is String ? initiatedBy.trim() : '',
    skippedAt: skipped
        ? (skippedAtRaw is String && skippedAtRaw.trim().isNotEmpty ? skippedAtRaw.trim() : audit.createdAt)
        : null,
    sentAt: sent
        ? (sentAtRaw is String && sentAtRaw.trim().isNotEmpty ? sentAtRaw.trim() : audit.createdAt)
        : null,
  );
}

bool wholesaleOrderEmailStepDone(
  WholesaleOrderEmailType type,
  List<AuditLogEntry> auditLogs, {
  WholesaleOrder? order,
  bool workflowInvoiceEmailDone = false,
}) {
  final state = wholesaleEmailStepState(type, auditLogs);
  if (state.done) return true;
  if (order == null) {
    if (type == WholesaleOrderEmailType.invoice && workflowInvoiceEmailDone) return true;
    return false;
  }
  final paymentClosed = order.paymentConfirmedAt?.trim().isNotEmpty ?? false;
  switch (type) {
    case WholesaleOrderEmailType.invoice:
      if (workflowInvoiceEmailDone) return true;
      if (order.invoiceSentAt?.trim().isNotEmpty ?? false) return true;
      if (paymentClosed) return true;
      return false;
    case WholesaleOrderEmailType.shipmentsDelivered:
      if (paymentClosed &&
          order.shipments.isNotEmpty &&
          order.shipments.every((s) => s.status == 'completed')) {
        return true;
      }
      return false;
    case WholesaleOrderEmailType.orderConfirm:
      if (order.shipments.any(shipmentHasDeliveryNoteStarted)) return true;
      if (paymentClosed && order.shipments.isNotEmpty) return true;
      return false;
  }
}

const Map<WholesaleOrderEmailType, List<String>> wholesaleOrderEmailAttachmentKinds = {
  WholesaleOrderEmailType.orderConfirm: ['order_confirmation', 'po_attachment'],
  WholesaleOrderEmailType.shipmentsDelivered: ['signed_delivery_note'],
  WholesaleOrderEmailType.invoice: ['invoice', 'delivery_note', 'signed_delivery_note'],
};

const Map<WholesaleOrderEmailType, List<String>> wholesaleOrderEmailRequiredAttachments = {
  WholesaleOrderEmailType.orderConfirm: ['order_confirmation'],
  WholesaleOrderEmailType.shipmentsDelivered: ['signed_delivery_note'],
  WholesaleOrderEmailType.invoice: ['invoice'],
};

bool isWholesaleOrderEmailAttachmentRequired(WholesaleOrderEmailType kind, String attachmentKey) {
  return wholesaleOrderEmailRequiredAttachments[kind]?.contains(attachmentKey) ?? false;
}

String wholesaleOrderRef(WholesaleOrder order) {
  final ref = order.refNo?.trim() ?? '';
  return ref.isNotEmpty ? ref : 'D${order.id}';
}

String wholesaleOrderPoNumber(WholesaleOrder order) {
  final po = order.poNumber?.trim() ?? '';
  return po.isNotEmpty ? po : wholesaleOrderRef(order);
}

String wholesaleOrderContactEmail(String? companyEmail) {
  final trimmed = companyEmail?.trim() ?? '';
  return trimmed.isNotEmpty ? trimmed : 'hello@ducklincompany.co.uk';
}

List<String> parseEmailListFromRaw(String? raw) {
  final out = <String>[];
  for (final part in (raw ?? '').split(RegExp(r'[\n\r,;]+'))) {
    final email = part.trim();
    if (email.isEmpty || out.contains(email)) continue;
    out.add(email);
  }
  return out;
}

String serializeEmailList(List<String> emails) => emails.map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');

List<String> wholesaleOrderDefaultEmailCcList(CompanySettings? settings) {
  return parseEmailListFromRaw(settings?.wholesaleOrderEmailDefaultCc);
}

bool isValidEmailAddress(String email) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

List<String> dedupeEmailList(Iterable<String> values) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    for (final email in parseEmailListFromRaw(raw)) {
      final key = email.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(email);
    }
  }
  return out;
}

bool orderHasPoAttachments(WholesaleOrder order) {
  return order.documents.any((d) => d.type == 'po_attachment');
}

bool orderHasOrderConfirmationDocument(WholesaleOrder order) {
  return order.documents.any((d) => d.type == 'order_confirmation');
}

String applyWholesaleOrderEmailSubjectTemplate(String template, WholesaleOrder order) {
  final ref = wholesaleOrderRef(order);
  final poNumber = wholesaleOrderPoNumber(order);
  final orderNumber = order.orderNumber.trim().isNotEmpty ? order.orderNumber : ref;
  return template
      .replaceAll('{order ref}', ref)
      .replaceAll('{ref}', ref)
      .replaceAll('{po number}', poNumber)
      .replaceAll('{po_number}', poNumber)
      .replaceAll('{order_number}', orderNumber)
      .replaceAll('{client_name}', order.client?.name.trim() ?? '');
}

String buildWholesaleOrderEmailSubject(
  WholesaleOrderEmailType kind,
  WholesaleOrder order, {
  String? companyTemplate,
}) {
  final custom = companyTemplate?.trim() ?? '';
  if (custom.isNotEmpty) {
    return applyWholesaleOrderEmailSubjectTemplate(custom, order);
  }
  final ref = wholesaleOrderRef(order);
  final poNumber = wholesaleOrderPoNumber(order);
  const prefix = 'DUCKLIN COMPANY LTD';
  return switch (kind) {
    WholesaleOrderEmailType.orderConfirm => '$prefix Order Confirmed - PO $poNumber / $ref',
    WholesaleOrderEmailType.shipmentsDelivered => '$prefix Order Delivered - PO $poNumber / $ref',
    WholesaleOrderEmailType.invoice => '$prefix Order Invoice - PO $poNumber / $ref',
  };
}

String buildWholesaleOrderEmailMessage(
  WholesaleOrderEmailType kind,
  WholesaleOrder order, {
  String? companyEmail,
}) {
  final ref = wholesaleOrderRef(order);
  final orderNumber = order.orderNumber.trim().isNotEmpty ? order.orderNumber : ref;
  final poNumber = wholesaleOrderPoNumber(order);
  final clientName = order.client?.name.trim().isNotEmpty == true ? order.client!.name.trim() : 'Customer';
  final contactEmail = wholesaleOrderContactEmail(companyEmail);
  final amountDue = formatMoney(wholesaleOrderGrandTotal(order));

  return switch (kind) {
    WholesaleOrderEmailType.orderConfirm =>
      'Dear $clientName,\n\nPlease find attached PO documents for the following wholesale order:\n\nOrder ref: $ref\nOrder number: $orderNumber\nPO number: $poNumber\n\nPlease confirm receipt at your earliest convenience.\n\nPlease contact us by email $contactEmail if you have any queries regarding this order.\n\nPlease do not reply this email. This message was sent from the Ducklin POS management portal.',
    WholesaleOrderEmailType.shipmentsDelivered =>
      'Dear $clientName,\n\nPlease find the attached documents for the following wholesale order:\n\nOrder ref: $ref\nOrder number: $orderNumber\nPO number: $poNumber\nAmount due: $amountDue\n\nPlease contact us by email $contactEmail if you have any queries regarding this order.\n\nPlease do not reply this email. This message was sent from the Ducklin POS management portal.',
    WholesaleOrderEmailType.invoice =>
      'Dear $clientName,\n\nPlease find attached invoice for the following wholesale order:\n\nOrder ref: $ref\nOrder number: $orderNumber\nPO number: $poNumber\nAmount due: $amountDue\n\nPlease contact us by email $contactEmail if you have any queries regarding this order.\n\nPlease do not reply this email. This message was sent from the Ducklin POS management portal.',
  };
}

String wholesaleEmailAttachmentKindLabel(String kind) => switch (kind) {
      'order_confirmation' => 'Order confirmation',
      'invoice' => 'Invoice',
      'po_attachment' => 'PO attachment',
      'payment_proof' => 'Payment proof',
      'delivery_note' => 'Delivery note',
      'signed_delivery_note' => 'Delivery proof',
      _ => kind,
    };

class WholesaleEmailAttachmentOption {
  const WholesaleEmailAttachmentOption({
    required this.key,
    required this.label,
    required this.available,
    this.hint,
  });

  final String key;
  final String label;
  final bool available;
  final String? hint;
}

List<WholesaleEmailAttachmentOption> buildWholesaleEmailAttachmentOptions(WholesaleOrder order) {
  final poCount = order.documents.where((d) => d.type == 'po_attachment').length;
  final proofCount = order.documents.where((d) => d.type == 'payment_proof').length +
      ((order.paymentProofUrl?.trim().isNotEmpty ?? false) &&
              !order.documents.any((d) => d.type == 'payment_proof')
          ? 1
          : 0);
  final dnCount = order.shipments.where((s) => s.deliveryNotePdfUrl?.trim().isNotEmpty ?? false).length;
  final signedDnCount =
      order.shipments.where((s) => s.signedDeliveryNotePdfUrl?.trim().isNotEmpty ?? false).length;

  String? countHint(int count) => count > 1 ? '×$count' : null;

  return [
    WholesaleEmailAttachmentOption(
      key: 'order_confirmation',
      label: wholesaleEmailAttachmentKindLabel('order_confirmation'),
      available: orderHasOrderConfirmationDocument(order),
    ),
    WholesaleEmailAttachmentOption(
      key: 'invoice',
      label: wholesaleEmailAttachmentKindLabel('invoice'),
      available: orderHasInvoiceDocument(order),
    ),
    WholesaleEmailAttachmentOption(
      key: 'po_attachment',
      label: wholesaleEmailAttachmentKindLabel('po_attachment'),
      available: poCount > 0,
      hint: countHint(poCount),
    ),
    WholesaleEmailAttachmentOption(
      key: 'payment_proof',
      label: wholesaleEmailAttachmentKindLabel('payment_proof'),
      available: proofCount > 0,
      hint: countHint(proofCount),
    ),
    WholesaleEmailAttachmentOption(
      key: 'delivery_note',
      label: wholesaleEmailAttachmentKindLabel('delivery_note'),
      available: dnCount > 0,
      hint: countHint(dnCount),
    ),
    WholesaleEmailAttachmentOption(
      key: 'signed_delivery_note',
      label: wholesaleEmailAttachmentKindLabel('signed_delivery_note'),
      available: signedDnCount > 0,
      hint: countHint(signedDnCount),
    ),
  ];
}

Map<String, bool> buildDefaultWholesaleEmailAttachments(WholesaleOrderEmailType kind, WholesaleOrder order) {
  final attachments = <String, bool>{};
  for (final key in wholesaleOrderEmailRequiredAttachments[kind] ?? const []) {
    attachments[key] = true;
  }
  if (kind == WholesaleOrderEmailType.orderConfirm && orderHasPoAttachments(order)) {
    attachments['po_attachment'] = true;
  }
  return attachments;
}

String wholesaleOrderEmailTypeLabel(WholesaleOrderEmailType kind) => switch (kind) {
      WholesaleOrderEmailType.orderConfirm => 'Order confirmation email',
      WholesaleOrderEmailType.shipmentsDelivered => 'Delivery complete email',
      WholesaleOrderEmailType.invoice => 'Invoice email',
    };

class WholesaleEmailResendSummary {
  const WholesaleEmailResendSummary({
    required this.typeLabel,
    this.skipped = false,
    this.sentAt,
    this.skippedAt,
    this.skippedBy = '',
    this.skipRemark = '',
    this.attachmentTypeLabels = const [],
    this.filenames = const [],
  });

  final String typeLabel;
  final bool skipped;
  final String? sentAt;
  final String? skippedAt;
  final String skippedBy;
  final String skipRemark;
  final List<String> attachmentTypeLabels;
  final List<String> filenames;
}

WholesaleEmailResendSummary buildWholesaleEmailResendSummary(
  Map<String, dynamic> auditChanges,
  WholesaleOrder order, {
  String? fallbackAt,
  WholesaleOrderEmailType? kindHint,
}) {
  final kinds = (auditChanges['attachment_kinds'] is List)
      ? (auditChanges['attachment_kinds'] as List)
          .map((k) => '$k')
          .where((k) => k.trim().isNotEmpty)
          .toList()
      : <String>[];
  final filenames = (auditChanges['filenames'] is List)
      ? (auditChanges['filenames'] as List)
          .map((f) => '$f')
          .where((f) => f.trim().isNotEmpty)
          .toList()
      : <String>[];

  final emailType = kindHint ?? classifyWholesaleOrderEmailAudit(auditChanges);
  final typeLabel = emailType != null ? wholesaleOrderEmailTypeLabel(emailType) : 'Order emailed';

  final skipped = isWholesaleOrderEmailSkippedAudit(auditChanges);
  final sent = isWholesaleOrderEmailSentAudit(auditChanges);
  final skippedAtRaw = auditChanges['skipped_at'];
  final sentAtRaw = auditChanges['sent_at'];
  final initiatedBy = auditChanges['initiated_by'];

  String? pickAt(dynamic raw, String? fallback) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final fb = fallback?.trim();
    return (fb != null && fb.isNotEmpty) ? fb : null;
  }

  return WholesaleEmailResendSummary(
    typeLabel: typeLabel,
    skipped: skipped,
    sentAt: sent ? pickAt(sentAtRaw, fallbackAt) : null,
    skippedAt: skipped ? pickAt(skippedAtRaw, fallbackAt) : null,
    skippedBy: skipped && initiatedBy is String ? initiatedBy.trim() : '',
    skipRemark: skipped ? wholesaleOrderEmailSkipRemark(auditChanges) : '',
    attachmentTypeLabels: kinds.map(wholesaleEmailAttachmentKindLabel).toList(),
    filenames: filenames,
  );
}

class WholesaleEmailSendRequest {
  const WholesaleEmailSendRequest({
    required this.emailType,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.message,
    required this.attachments,
    this.shipmentIds,
  });

  final WholesaleOrderEmailType emailType;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String message;
  final List<String> attachments;
  final List<int>? shipmentIds;
}

class WholesaleEmailDialogData {
  const WholesaleEmailDialogData({
    required this.emailType,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.message,
    required this.attachments,
    this.resendSummary,
  });

  final WholesaleOrderEmailType emailType;
  final String to;
  final String cc;
  final String bcc;
  final String subject;
  final String message;
  final Map<String, bool> attachments;
  final WholesaleEmailResendSummary? resendSummary;

  factory WholesaleEmailDialogData.fromDefaults(
    WholesaleOrderEmailType kind,
    WholesaleOrder order,
    CompanySettings? settings,
  ) {
    return WholesaleEmailDialogData(
      emailType: kind,
      to: order.client?.email?.trim() ?? '',
      cc: serializeEmailList(wholesaleOrderDefaultEmailCcList(settings)),
      bcc: '',
      subject: buildWholesaleOrderEmailSubject(
        kind,
        order,
        companyTemplate: settings?.wholesaleOrderEmailSubjectTemplate,
      ),
      message: buildWholesaleOrderEmailMessage(kind, order, companyEmail: settings?.email),
      attachments: buildDefaultWholesaleEmailAttachments(kind, order),
    );
  }

  factory WholesaleEmailDialogData.fromAudit(
    WholesaleOrderEmailType kind,
    WholesaleOrder order,
    AuditLogEntry audit,
    CompanySettings? settings,
  ) {
    final base = parseWholesaleOrderEmailAuditBase(audit.changes);
    final toFromList = base['to'] is List && (base['to'] as List).isNotEmpty
        ? serializeEmailList((base['to'] as List).map((e) => '$e').toList())
        : '${base['recipient'] ?? ''}'.trim();
    final ccFromList = base['cc_list'] is List && (base['cc_list'] as List).isNotEmpty
        ? serializeEmailList((base['cc_list'] as List).map((e) => '$e').toList())
        : '${base['cc'] ?? ''}'.trim();
    final bccFromList = base['bcc_list'] is List && (base['bcc_list'] as List).isNotEmpty
        ? serializeEmailList((base['bcc_list'] as List).map((e) => '$e').toList())
        : '${base['bcc'] ?? ''}'.trim();
    final attachmentKinds = base['attachment_kinds'] is List
        ? (base['attachment_kinds'] as List).map((k) => '$k').where((k) => k.trim().isNotEmpty).toList()
        : wholesaleOrderEmailAttachmentKinds[kind] ?? const [];
    final attachments = <String, bool>{};
    for (final key in attachmentKinds) {
      attachments[key] = true;
    }
    return WholesaleEmailDialogData(
      emailType: kind,
      to: toFromList.isNotEmpty ? toFromList : (order.client?.email?.trim() ?? ''),
      cc: ccFromList.isNotEmpty ? ccFromList : serializeEmailList(wholesaleOrderDefaultEmailCcList(settings)),
      bcc: bccFromList,
      subject: base['subject'] is String && (base['subject'] as String).trim().isNotEmpty
          ? (base['subject'] as String).trim()
          : buildWholesaleOrderEmailSubject(
              kind,
              order,
              companyTemplate: settings?.wholesaleOrderEmailSubjectTemplate,
            ),
      message: base['message'] is String && (base['message'] as String).trim().isNotEmpty
          ? (base['message'] as String).trim()
          : buildWholesaleOrderEmailMessage(kind, order, companyEmail: settings?.email),
      attachments: attachments.isNotEmpty ? attachments : buildDefaultWholesaleEmailAttachments(kind, order),
      resendSummary: buildWholesaleEmailResendSummary(
        base,
        order,
        fallbackAt: audit.createdAt,
        kindHint: kind,
      ),
    );
  }
}
