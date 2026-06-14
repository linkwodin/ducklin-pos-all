import type { TFunction } from 'i18next';
import type { AuditLog, WholesaleOrder } from '../types';
import { isWholesaleOrderCompleted } from './wholesaleOrderEmail';

export type RegenLockDocumentType =
  | 'order_confirmation'
  | 'invoice'
  | 'delivery_note'
  | 'signed_delivery_note';

function parseAuditChanges(changesJson: string): Record<string, unknown> {
  try {
    return JSON.parse(changesJson) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function asStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x): x is string => typeof x === 'string' && x.trim() !== '')
    .map((x) => x.trim());
}

function asUint(v: unknown): number | undefined {
  if (typeof v === 'number' && Number.isFinite(v) && v > 0) return v;
  if (typeof v === 'string' && /^\d+$/.test(v)) return Number(v);
  return undefined;
}

function asUintArray(v: unknown): number[] {
  if (!Array.isArray(v)) return [];
  return v
    .map((x) => asUint(x))
    .filter((n): n is number => n != null);
}

function bulkEmailLocksDocType(
  changes: Record<string, unknown>,
  docType: RegenLockDocumentType,
  shipmentId?: number,
): boolean {
  const kinds = asStringArray(changes.attachment_kinds);
  if (kinds.length === 0) return false;
  const kindSet = new Set(kinds);
  if (docType === 'order_confirmation') return kindSet.has('order_confirmation');
  if (docType === 'invoice') return kindSet.has('invoice');
  if (docType === 'delivery_note') {
    if (!kindSet.has('delivery_note')) return false;
    const shipmentIds = asUintArray(changes.shipment_ids);
    if (shipmentIds.length === 0 || shipmentId == null) return true;
    return shipmentIds.includes(shipmentId);
  }
  if (docType === 'signed_delivery_note') {
    if (!kindSet.has('signed_delivery_note')) return false;
    const signedShipmentId = asUint(changes.signed_delivery_shipment_id);
    if (signedShipmentId != null && shipmentId != null) return signedShipmentId === shipmentId;
    const shipmentIds = asUintArray(changes.shipment_ids);
    if (shipmentIds.length === 0 || shipmentId == null) return true;
    return shipmentIds.includes(shipmentId);
  }
  return false;
}

function auditLogLocksDocumentRegen(
  action: string,
  changes: Record<string, unknown>,
  docType: RegenLockDocumentType,
  shipmentId?: number,
): boolean {
  switch (action) {
    case 'wholesale_order_email_oc':
      return docType === 'order_confirmation';
    case 'wholesale_order_email_invoice':
      return docType === 'invoice';
    case 'wholesale_order_email_dn':
      if (docType !== 'delivery_note') return false;
      {
        const sid = asUint(changes.shipment_id);
        if (sid == null) return true;
        return shipmentId == null ? true : sid === shipmentId;
      }
    case 'wholesale_order_email':
      return bulkEmailLocksDocType(changes, docType, shipmentId);
    default:
      return false;
  }
}

export function isDocumentRegenLocked(
  auditLogs: AuditLog[],
  docType: RegenLockDocumentType,
  shipmentId?: number,
): boolean {
  for (const log of auditLogs) {
    const changes = parseAuditChanges(log.changes);
    if (auditLogLocksDocumentRegen(log.action, changes, docType, shipmentId)) {
      return true;
    }
  }
  return false;
}

export function isOrderUploadLockedByCompletion(order: WholesaleOrder): boolean {
  return isWholesaleOrderCompleted(order);
}

/** True when uploads or emailed-document regen are locked on this order. */
export function orderHasActiveLocks(auditLogs: AuditLog[], order: WholesaleOrder): boolean {
  if (isOrderUploadLockedByCompletion(order)) return true;
  if (isDocumentRegenLocked(auditLogs, 'order_confirmation')) return true;
  if (isDocumentRegenLocked(auditLogs, 'invoice')) return true;
  for (const s of order.shipments ?? []) {
    if (isDocumentRegenLocked(auditLogs, 'delivery_note', s.id)) return true;
  }
  return false;
}

export function isOrderUploadBlocked(order: WholesaleOrder, orderUnlocked: boolean): boolean {
  if (!isOrderUploadLockedByCompletion(order)) return false;
  return !orderUnlocked;
}

/** True when the document was emailed and the user has not unlocked the order on this page. */
export function isRegenBlockedByEmailLock(
  auditLogs: AuditLog[],
  docType: RegenLockDocumentType,
  orderUnlocked: boolean,
  shipmentId?: number,
): boolean {
  if (!isDocumentRegenLocked(auditLogs, docType, shipmentId)) return false;
  return !orderUnlocked;
}

export function shouldSendRegenUnlockFlag(
  auditLogs: AuditLog[],
  docType: RegenLockDocumentType,
  orderUnlocked: boolean,
  shipmentId?: number,
): boolean {
  return isDocumentRegenLocked(auditLogs, docType, shipmentId) && orderUnlocked;
}

export function shouldSendUploadUnlockFlag(order: WholesaleOrder, orderUnlocked: boolean): boolean {
  return isOrderUploadLockedByCompletion(order) && orderUnlocked;
}

export function confirmUnlockForRegen(t: TFunction, documentLabel: string): boolean {
  return window.confirm(t('wholesaleOrderDetail:confirmRegenAfterEmail', { document: documentLabel }));
}

export function confirmUnlockOrder(t: TFunction): boolean {
  return window.confirm(t('wholesaleOrderDetail:confirmUnlockOrder'));
}
