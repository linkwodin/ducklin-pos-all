import type { TFunction } from 'i18next';
import { format } from 'date-fns';
import type { AuditLog, WholesaleOrder } from '../types';
import i18n from '../i18n/config';

export type WholesaleOrderEmailType = 'order_confirm' | 'shipments_delivered' | 'invoice';

export const WHOLESALE_ORDER_EMAIL_ATTACHMENT_KINDS: Record<WholesaleOrderEmailType, string[]> = {
  order_confirm: ['order_confirmation', 'po_attachment'],
  shipments_delivered: ['signed_delivery_note'],
  invoice: ['invoice', 'delivery_note', 'signed_delivery_note'],
};

/** Attachments that are always included and cannot be unchecked for structured email flows. */
export const WHOLESALE_ORDER_EMAIL_REQUIRED_ATTACHMENTS: Record<WholesaleOrderEmailType, string[]> = {
  order_confirm: ['order_confirmation'],
  shipments_delivered: ['signed_delivery_note'],
  invoice: ['invoice'],
};

export function isWholesaleOrderEmailAttachmentRequired(
  emailKind: WholesaleOrderEmailType | null,
  attachmentKey: string,
): boolean {
  if (!emailKind) return false;
  return WHOLESALE_ORDER_EMAIL_REQUIRED_ATTACHMENTS[emailKind].includes(attachmentKey);
}

export type EmailContentLanguage = 'en' | 'zh-TW' | 'zh-CN';

export const EMAIL_CONTENT_LANGUAGES: { code: EmailContentLanguage; label: string }[] = [
  { code: 'en', label: 'English' },
  { code: 'zh-TW', label: '繁體' },
  { code: 'zh-CN', label: '简体' },
];

export function normalizeEmailContentLanguage(lang: string | undefined): EmailContentLanguage {
  if (!lang) return 'en';
  if (lang === 'zh-CN' || lang.startsWith('zh-CN') || lang === 'zh-Hans') return 'zh-CN';
  if (lang === 'zh-TW' || lang.startsWith('zh-TW') || lang.startsWith('zh-HK')) return 'zh-TW';
  if (lang.startsWith('zh')) return 'zh-TW';
  return 'en';
}

export function getEmailContentT(lang: EmailContentLanguage): TFunction {
  return i18n.getFixedT(lang);
}

export function wholesaleOrderRef(order: WholesaleOrder): string {
  const ref = (order.ref_no || '').trim();
  return ref || `D${order.id}`;
}

export function wholesaleOrderPoNumber(order: WholesaleOrder): string {
  return (order.po_number || '').trim() || wholesaleOrderRef(order);
}

export function wholesaleDeliveryNoteRef(order: WholesaleOrder, shipmentId?: number): string {
  const shipments = (order.shipments ?? [])
    .filter((s) => typeof s.id === 'number')
    .slice()
    .sort((a, b) => a.id - b.id);
  if (shipments.length === 0) return '';

  let target = shipments[shipments.length - 1];
  if (typeof shipmentId === 'number') {
    const hit = shipments.find((s) => s.id === shipmentId);
    if (hit) target = hit;
  } else {
    const signed = shipments.filter((s) => !!s.signed_delivery_note_pdf_url?.trim());
    if (signed.length > 0) target = signed[signed.length - 1];
  }
  const shipmentNum = Math.max(1, shipments.findIndex((s) => s.id === target.id) + 1);
  return `d${shipmentNum} - ${wholesaleOrderPoNumber(order)} / ${wholesaleOrderRef(order)}`;
}

export function isWholesaleOrderCompleted(order: WholesaleOrder): boolean {
  if (order.is_completed === true) return true;
  const allShipmentsCompleted =
    !!order.shipments &&
    order.shipments.length > 0 &&
    order.shipments.every((s) => s.status === 'completed');
  return !!allShipmentsCompleted && !!order.payment_confirmed_at;
}

import {
  wholesaleOrderStatusColor,
  wholesaleOrderStatusLabel,
  type WholesaleOrderStatusChipColor,
} from './wholesaleOrderWorkflow';

export { wholesaleOrderStatusColor, wholesaleOrderStatusLabel, type WholesaleOrderStatusChipColor };

export function wholesaleOrderEmailTotal(order: WholesaleOrder): number {
  const itemsTotal =
    order.total_net ?? order.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0;
  return itemsTotal + (Number(order.shipping_fee) || 0);
}

export function applyWholesaleOrderEmailSubjectTemplate(
  template: string,
  order: WholesaleOrder,
  t: TFunction,
  shipmentId?: number,
): string {
  const ref = wholesaleOrderRef(order);
  const poNumber = wholesaleOrderPoNumber(order);
  const orderNumber = (order.order_number || '').trim() || ref;
  const deliveryNumber = wholesaleDeliveryNoteRef(order, shipmentId);

  return template
    .replace(/\{order ref\}/g, ref)
    .replace(/\{ref\}/g, ref)
    .replace(/\{po number\}/g, poNumber)
    .replace(/\{po_number\}/g, poNumber)
    .replace(/\{delivery number\}/g, deliveryNumber)
    .replace(/\{delivery_number\}/g, deliveryNumber)
    .replace(/\{status\}/g, wholesaleOrderStatusLabel(order, t))
    .replace(/\{order_number\}/g, orderNumber)
    .replace(/\{client_name\}/g, (order.wholesale_client?.name || '').trim());
}

export function buildDefaultWholesaleOrderEmailSubject(
  order: WholesaleOrder,
  t: TFunction,
  companyTemplate?: string,
): string {
  const custom = companyTemplate?.trim();
  if (custom) {
    return applyWholesaleOrderEmailSubjectTemplate(custom, order, t);
  }
  return t('wholesaleOrderDetail:emailDefaultSubjectTemplate', {
    prefix: t('wholesaleOrderDetail:emailDefaultSubjectPrefix'),
    ref: wholesaleOrderRef(order),
    status: wholesaleOrderStatusLabel(order, t), // kept for backward-compat templates
    poNumber: wholesaleOrderPoNumber(order),
  });
}

export function buildDefaultWholesaleOrderDeliveryProofEmailSubject(
  order: WholesaleOrder,
  t: TFunction,
  shipmentId?: number,
  companyTemplate?: string,
): string {
  const custom = companyTemplate?.trim();
  if (custom) {
    return applyWholesaleOrderEmailSubjectTemplate(custom, order, t, shipmentId);
  }
  return t('wholesaleOrderDetail:emailDefaultDeliveryProofSubjectTemplate', {
    prefix: t('wholesaleOrderDetail:emailDefaultDeliveryProofSubjectPrefix'),
    ref: wholesaleOrderRef(order),
    poNumber: wholesaleOrderPoNumber(order),
    deliveryNumber: wholesaleDeliveryNoteRef(order, shipmentId),
  });
}

export function buildDefaultWholesaleOrderConfirmEmailSubject(
  order: WholesaleOrder,
  t: TFunction = getEmailContentT('en'),
): string {
  return t('wholesaleOrderDetail:emailDefaultOrderConfirmSubjectTemplate', {
    prefix: t('wholesaleOrderDetail:emailDefaultSubjectPrefix'),
    ref: wholesaleOrderRef(order),
    poNumber: wholesaleOrderPoNumber(order),
  });
}

export function buildDefaultWholesaleOrderShipmentsDeliveredEmailSubject(
  order: WholesaleOrder,
  t: TFunction = getEmailContentT('en'),
): string {
  return t('wholesaleOrderDetail:emailDefaultShipmentsDeliveredSubjectTemplate', {
    prefix: t('wholesaleOrderDetail:emailDefaultSubjectPrefix'),
    ref: wholesaleOrderRef(order),
    poNumber: wholesaleOrderPoNumber(order),
  });
}

export function buildDefaultWholesaleOrderInvoiceEmailSubject(
  order: WholesaleOrder,
  t: TFunction = getEmailContentT('en'),
): string {
  return t('wholesaleOrderDetail:emailDefaultInvoiceSubjectTemplate', {
    prefix: t('wholesaleOrderDetail:emailDefaultSubjectPrefix'),
    ref: wholesaleOrderRef(order),
    poNumber: wholesaleOrderPoNumber(order),
  });
}

export function buildDefaultWholesaleOrderEmailMessage(order: WholesaleOrder, t: TFunction): string {
  const ref = wholesaleOrderRef(order);
  const orderNumber = (order.order_number || '').trim() || ref;
  const poNumber = (order.po_number || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageNoValue');
  const clientName =
    (order.wholesale_client?.name || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageDearCustomer');

  return t('wholesaleOrderDetail:emailDefaultMessage', {
    clientName,
    ref,
    orderNumber,
    status: wholesaleOrderStatusLabel(order, t),
    poNumber,
    total: `£${wholesaleOrderEmailTotal(order).toFixed(2)}`,
  });
}

export function wholesaleOrderContactEmail(companyEmail?: string): string {
  const trimmed = (companyEmail || '').trim();
  return trimmed || 'hello@ducklincompany.co.uk';
}

const EMAIL_SPLIT_RE = /[\n\r,;]+/;

export function isValidEmailAddress(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

/** Parse comma/newline/semicolon-separated emails (e.g. company settings Cc list). */
export function parseEmailListFromRaw(raw?: string | null): string[] {
  const out: string[] = [];
  (raw ?? '')
    .split(EMAIL_SPLIT_RE)
    .map((v) => v.trim())
    .filter(Boolean)
    .forEach((email) => {
      if (!out.includes(email)) out.push(email);
    });
  return out;
}

export function serializeEmailListForSettings(emails: string[]): string {
  return emails.map((e) => e.trim()).filter(Boolean).join('\n');
}

/** Default Cc chips when opening wholesale order email dialog. Empty settings = no Cc. */
export function wholesaleOrderDefaultEmailCcList(
  settings?: { wholesale_order_email_default_cc?: string } | null,
): string[] {
  return parseEmailListFromRaw(settings?.wholesale_order_email_default_cc);
}

/** @deprecated Use wholesaleOrderDefaultEmailCcList */
export function wholesaleOrderDefaultEmailCc(settings?: {
  wholesale_order_email_default_cc?: string;
  email?: string;
} | null): string {
  const list = wholesaleOrderDefaultEmailCcList(settings);
  return list.join(', ');
}

export function buildDefaultWholesaleOrderDeliveryCompleteEmailMessage(
  order: WholesaleOrder,
  t: TFunction,
  companyEmail?: string,
): string {
  const ref = wholesaleOrderRef(order);
  const orderNumber = (order.order_number || '').trim() || ref;
  const poNumber = (order.po_number || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageNoValue');
  const clientName =
    (order.wholesale_client?.name || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageDearCustomer');

  return t('wholesaleOrderDetail:emailDefaultDeliveryCompleteMessage', {
    clientName,
    ref,
    orderNumber,
    poNumber,
    amountDue: `£${wholesaleOrderEmailTotal(order).toFixed(2)}`,
    contactEmail: wholesaleOrderContactEmail(companyEmail),
  });
}

export function buildDefaultWholesaleOrderDeliveryCompleteEmailMessageEnglish(
  order: WholesaleOrder,
  companyEmail?: string,
): string {
  return buildDefaultWholesaleOrderDeliveryCompleteEmailMessage(order, getEmailContentT('en'), companyEmail);
}

export function buildDefaultWholesaleOrderConfirmEmailMessageEnglish(
  order: WholesaleOrder,
  companyEmail?: string,
): string {
  const t = getEmailContentT('en');
  const ref = wholesaleOrderRef(order);
  const orderNumber = (order.order_number || '').trim() || ref;
  const poNumber = (order.po_number || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageNoValue');
  const clientName =
    (order.wholesale_client?.name || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageDearCustomer');

  return t('wholesaleOrderDetail:emailDefaultOrderConfirmMessage', {
    clientName,
    ref,
    orderNumber,
    poNumber,
    contactEmail: wholesaleOrderContactEmail(companyEmail),
  });
}

export function buildDefaultWholesaleOrderInvoiceEmailMessageEnglish(
  order: WholesaleOrder,
  companyEmail?: string,
): string {
  const t = getEmailContentT('en');
  const ref = wholesaleOrderRef(order);
  const orderNumber = (order.order_number || '').trim() || ref;
  const poNumber = (order.po_number || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageNoValue');
  const clientName =
    (order.wholesale_client?.name || '').trim() || t('wholesaleOrderDetail:emailDefaultMessageDearCustomer');

  return t('wholesaleOrderDetail:emailDefaultInvoiceMessage', {
    clientName,
    ref,
    orderNumber,
    poNumber,
    amountDue: `£${wholesaleOrderEmailTotal(order).toFixed(2)}`,
    contactEmail: wholesaleOrderContactEmail(companyEmail),
  });
}

export function buildWholesaleOrderEmailMessageEnglish(
  kind: WholesaleOrderEmailType,
  order: WholesaleOrder,
  companyEmail?: string,
): string {
  switch (kind) {
    case 'order_confirm':
      return buildDefaultWholesaleOrderConfirmEmailMessageEnglish(order, companyEmail);
    case 'shipments_delivered':
      return buildDefaultWholesaleOrderDeliveryCompleteEmailMessageEnglish(order, companyEmail);
    case 'invoice':
      return buildDefaultWholesaleOrderInvoiceEmailMessageEnglish(order, companyEmail);
  }
}

export function buildWholesaleOrderEmailSubjectEnglish(
  kind: WholesaleOrderEmailType,
  order: WholesaleOrder,
  companyTemplate?: string,
): string {
  switch (kind) {
    case 'order_confirm':
      return buildDefaultWholesaleOrderConfirmEmailSubject(order);
    case 'shipments_delivered':
      return buildDefaultWholesaleOrderShipmentsDeliveredEmailSubject(order);
    case 'invoice':
      return buildDefaultWholesaleOrderInvoiceEmailSubject(order);
  }
}

export type ShipmentDocumentAttachmentKind = 'delivery_note' | 'signed_delivery_note';

export function buildShipmentDocumentsEmailSubjectEnglish(
  order: WholesaleOrder,
  shipmentIds: number[],
  attachmentKinds: ShipmentDocumentAttachmentKind[],
  companyTemplate?: string,
): string {
  const t = getEmailContentT('en');
  const onlyProof =
    attachmentKinds.length === 1 && attachmentKinds[0] === 'signed_delivery_note';
  const onlyDn = attachmentKinds.length === 1 && attachmentKinds[0] === 'delivery_note';
  if (shipmentIds.length === 1 && (onlyProof || onlyDn)) {
    return buildDefaultWholesaleOrderDeliveryProofEmailSubject(
      order,
      t,
      shipmentIds[0],
      companyTemplate,
    );
  }
  if (onlyProof || attachmentKinds.includes('signed_delivery_note')) {
    return buildDefaultWholesaleOrderShipmentsDeliveredEmailSubject(order);
  }
  return buildDefaultWholesaleOrderEmailSubject(order, t, companyTemplate);
}

export function buildShipmentDocumentsEmailMessageEnglish(
  order: WholesaleOrder,
  companyEmail?: string,
): string {
  return buildDefaultWholesaleOrderDeliveryCompleteEmailMessageEnglish(order, companyEmail);
}

export function orderHasPoAttachments(order: WholesaleOrder): boolean {
  return (order.documents?.filter((d) => d.type === 'po_attachment').length ?? 0) > 0;
}

export function orderHasOrderConfirmationDocument(order: WholesaleOrder): boolean {
  return !!order.documents?.some((d) => d.type === 'order_confirmation');
}

export function orderHasInvoiceDocument(order: WholesaleOrder): boolean {
  return !!order.documents?.some((d) => d.type === 'invoice');
}

export function allShipmentsHaveSignedProof(order: WholesaleOrder): boolean {
  const shipments = order.shipments ?? [];
  return shipments.length > 0 && shipments.every((s) => !!s.signed_delivery_note_pdf_url?.trim());
}

export function parseWholesaleOrderEmailAuditBase(changesJson: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(changesJson) as { changes?: Record<string, unknown> } | Record<string, unknown>;
    return ((parsed as { changes?: Record<string, unknown> }).changes ?? parsed ?? {}) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export function isWholesaleOrderEmailSkippedAudit(changes: Record<string, unknown>): boolean {
  return changes.skipped === true || changes.skipped === 'true';
}

export function wholesaleOrderEmailSkipRemark(changes: Record<string, unknown>): string {
  const raw = changes.skip_remark ?? changes.remark;
  return typeof raw === 'string' ? raw.trim() : '';
}

export function isWholesaleOrderEmailSentAudit(changes: Record<string, unknown>): boolean {
  if (isWholesaleOrderEmailSkippedAudit(changes)) return false;
  return typeof changes.sent_at === 'string' && changes.sent_at.trim() !== '';
}

export function isWholesaleOrderEmailDoneAudit(changes: Record<string, unknown>): boolean {
  return isWholesaleOrderEmailSkippedAudit(changes) || isWholesaleOrderEmailSentAudit(changes);
}

export function classifyWholesaleOrderEmailAudit(changes: Record<string, unknown>): WholesaleOrderEmailType | null {
  const emailType = changes.email_type;
  if (emailType === 'order_confirm' || emailType === 'shipments_delivered' || emailType === 'invoice') {
    return emailType;
  }
  const kinds = Array.isArray(changes.attachment_kinds)
    ? (changes.attachment_kinds as string[]).filter((k) => typeof k === 'string' && k.trim())
    : [];
  if (kinds.length > 0 && kinds.every((k) => k === 'po_attachment' || k === 'order_confirmation')) {
    return 'order_confirm';
  }
  if (kinds.length > 0 && kinds.every((k) => k === 'signed_delivery_note')) {
    const rawShipmentId = changes.signed_delivery_shipment_id;
    if (rawShipmentId == null || rawShipmentId === '' || rawShipmentId === 0) {
      return 'shipments_delivered';
    }
  }
  if (
    kinds.length > 0 &&
    kinds.includes('invoice') &&
    kinds.every(
      (k) => k === 'invoice' || k === 'delivery_note' || k === 'signed_delivery_note',
    )
  ) {
    return 'invoice';
  }
  return null;
}

function isAuditLogNewer(a: AuditLog, b: AuditLog): boolean {
  const ta = new Date(a.created_at).getTime();
  const tb = new Date(b.created_at).getTime();
  if (ta !== tb) return ta > tb;
  return a.id > b.id;
}

export function getWholesaleOrderEmailAudits(
  auditLogs: AuditLog[],
): Partial<Record<WholesaleOrderEmailType, AuditLog>> {
  const result: Partial<Record<WholesaleOrderEmailType, AuditLog>> = {};
  for (const log of auditLogs) {
    if (log.action !== 'wholesale_order_email') continue;
    const type = classifyWholesaleOrderEmailAudit(parseWholesaleOrderEmailAuditBase(log.changes));
    if (!type) continue;
    const existing = result[type];
    if (!existing || isAuditLogNewer(log, existing)) {
      result[type] = log;
    }
  }
  return result;
}

export function wholesaleOrderEmailSentAtDisplay(
  changes: Record<string, unknown> | null,
  audit: AuditLog | undefined,
  sent: boolean,
): string | null {
  if (!sent || !changes) return null;
  if (typeof changes.sent_at === 'string' && changes.sent_at.trim()) {
    return changes.sent_at.trim();
  }
  return audit?.created_at ?? null;
}

export function wholesaleOrderEmailSkippedAtDisplay(
  changes: Record<string, unknown> | null,
  audit: AuditLog | undefined,
  skipped: boolean,
): string | null {
  if (!skipped || !changes) return null;
  if (typeof changes.skipped_at === 'string' && changes.skipped_at.trim()) {
    return changes.skipped_at.trim();
  }
  return audit?.created_at ?? null;
}

export function wholesaleOrderEmailTypeLabel(kind: WholesaleOrderEmailType, t: TFunction): string {
  switch (kind) {
    case 'order_confirm':
      return t('wholesaleOrderDetail:emailTypeOrderConfirm');
    case 'shipments_delivered':
      return t('wholesaleOrderDetail:emailTypeShipmentsDelivered');
    case 'invoice':
      return t('wholesaleOrderDetail:emailTypeInvoice');
  }
}

export function isWholesaleDeliveryCompleteEmail(
  attachments?: Record<string, boolean>,
  signedDeliveryShipmentId?: number,
): boolean {
  if (signedDeliveryShipmentId != null && signedDeliveryShipmentId > 0) return false;
  if (!attachments) return false;
  const selected = Object.entries(attachments).filter(([, checked]) => checked).map(([key]) => key);
  return selected.length > 0 && selected.every((key) => key === 'signed_delivery_note');
}

export function sortEmailContentLanguages(langs: EmailContentLanguage[]): EmailContentLanguage[] {
  const selected = new Set(langs);
  return EMAIL_CONTENT_LANGUAGES.filter(({ code }) => selected.has(code)).map(({ code }) => code);
}

export function buildMultiLanguageEmailSubject(
  order: WholesaleOrder,
  langs: EmailContentLanguage[],
  companyTemplate?: string,
): string {
  const ordered = sortEmailContentLanguages(langs);
  if (ordered.length === 0) return '';
  return ordered
    .map((lang) => buildDefaultWholesaleOrderEmailSubject(order, getEmailContentT(lang), companyTemplate))
    .join(' / ');
}

export function buildMultiLanguageEmailMessage(
  order: WholesaleOrder,
  langs: EmailContentLanguage[],
): string {
  const ordered = sortEmailContentLanguages(langs);
  if (ordered.length === 0) return '';
  return ordered
    .map((lang) => buildDefaultWholesaleOrderEmailMessage(order, getEmailContentT(lang)))
    .join('\n\n────────────────────────\n\n');
}

export function buildMultiLanguageEmailDeliveryCompleteMessage(
  order: WholesaleOrder,
  langs: EmailContentLanguage[],
  companyEmail?: string,
): string {
  return buildDefaultWholesaleOrderDeliveryCompleteEmailMessageEnglish(order, companyEmail);
}

const EMAIL_ATTACHMENT_KIND_I18N: Record<string, string> = {
  order_confirmation: 'wholesaleOrderDetail:orderConfirmation',
  invoice: 'wholesaleOrderDetail:invoice',
  po_attachment: 'wholesaleOrderDetail:emailAttachPo',
  payment_proof: 'wholesaleOrderDetail:emailAttachPaymentProof',
  delivery_note: 'wholesaleOrderDetail:deliveryNote',
  signed_delivery_note: 'wholesaleOrderDetail:deliveryProof',
};

export function wholesaleEmailAttachmentKindLabel(kind: string, t: TFunction): string {
  const key = EMAIL_ATTACHMENT_KIND_I18N[kind.trim()];
  return key ? t(key) : kind;
}

export type WholesaleEmailResendSummary = {
  typeLabel: string;
  skipped?: boolean;
  sentAt?: string;
  skippedAt?: string;
  skippedBy?: string;
  skipRemark?: string;
  attachmentTypeLabels: string[];
  filenames: string[];
  signedDeliveryShipmentId?: number;
};

export function buildWholesaleEmailResendSummary(
  auditChanges: Record<string, unknown>,
  order: WholesaleOrder,
  t: TFunction,
  fallbackAt?: string,
  kindHint?: WholesaleOrderEmailType | null,
): WholesaleEmailResendSummary {
  const kinds = Array.isArray(auditChanges.attachment_kinds)
    ? (auditChanges.attachment_kinds as string[]).filter((k) => typeof k === 'string' && k.trim())
    : [];
  const filenames = Array.isArray(auditChanges.filenames)
    ? (auditChanges.filenames as string[]).filter((f) => typeof f === 'string' && f.trim())
    : [];
  const rawShipmentId = auditChanges.signed_delivery_shipment_id;
  const signedDeliveryShipmentId =
    typeof rawShipmentId === 'number' && rawShipmentId > 0
      ? rawShipmentId
      : typeof rawShipmentId === 'string' && /^\d+$/.test(rawShipmentId)
        ? Number(rawShipmentId)
        : undefined;

  const emailType = kindHint ?? classifyWholesaleOrderEmailAudit(auditChanges);

  let typeLabel: string;
  if (emailType) {
    typeLabel = wholesaleOrderEmailTypeLabel(emailType, t);
  } else if (signedDeliveryShipmentId != null) {
    const deliveryRef = wholesaleDeliveryNoteRef(order, signedDeliveryShipmentId);
    typeLabel = deliveryRef
      ? t('wholesaleOrderDetail:emailTypeDeliveryComplete', { deliveryRef })
      : t('wholesaleOrderDetail:emailSendDeliveryComplete');
  } else {
    typeLabel = t('wholesaleOrderAudit:action.orderEmailed');
  }

  const skipped = isWholesaleOrderEmailSkippedAudit(auditChanges);
  const sent = isWholesaleOrderEmailSentAudit(auditChanges);
  const skippedAt = skipped
    ? (wholesaleOrderEmailSkippedAtDisplay(auditChanges, undefined, true) ??
        fallbackAt?.trim()) || undefined
    : undefined;
  const sentAt = sent
    ? (wholesaleOrderEmailSentAtDisplay(auditChanges, undefined, true) ??
        fallbackAt?.trim()) || undefined
    : undefined;
  const skippedBy =
    typeof auditChanges.initiated_by === 'string' && auditChanges.initiated_by.trim()
      ? auditChanges.initiated_by.trim()
      : undefined;
  const skipRemark = skipped ? wholesaleOrderEmailSkipRemark(auditChanges) || undefined : undefined;

  return {
    typeLabel,
    skipped,
    sentAt,
    skippedAt,
    skippedBy,
    skipRemark,
    attachmentTypeLabels: kinds.map((k) => wholesaleEmailAttachmentKindLabel(k, t)),
    filenames,
    signedDeliveryShipmentId,
  };
}

export function formatWholesaleEmailResendMenuSubtitle(summary: WholesaleEmailResendSummary): string {
  const lines: string[] = [summary.typeLabel];
  if (summary.skipped && summary.skippedAt) {
    lines.push(format(new Date(summary.skippedAt), 'dd MMM yyyy HH:mm'));
  } else if (summary.sentAt) {
    lines.push(format(new Date(summary.sentAt), 'dd MMM yyyy HH:mm'));
  }
  if (summary.attachmentTypeLabels.length > 0) {
    lines.push(summary.attachmentTypeLabels.join(', '));
  }
  return lines.join('\n');
}
