import type { TFunction } from 'i18next';
import type { AuditLog, WholesaleOrder } from '../types';
import { allOrderLinesFullyAssigned, shipmentStatusAllowsAssignmentChange } from './wholesaleOrderAssignment';
import {
  getWholesaleOrderEmailAudits,
  isWholesaleOrderEmailSkippedAudit,
  isWholesaleOrderEmailSentAudit,
  isWholesaleOrderInvoiceEmailDone,
  orderHasInvoiceDocument,
  parseWholesaleOrderEmailAuditBase,
} from './wholesaleOrderEmail';
import { shipmentHasDeliveryNoteStarted } from './shipmentStatus';

export type WholesaleOrderProcessStepKey =
  | 'stepCreate'
  | 'stepOrderConfirmation'
  | 'stepStartShipment'
  | 'stepFinishShipment'
  | 'stepSendInvoiceEmail'
  | 'stepPaymentConfirmation'
  | 'stepComplete';

export type WholesaleOrderStatusChipColor =
  | 'success'
  | 'warning'
  | 'primary'
  | 'error'
  | 'default'
  | 'secondary'
  | 'info';

export interface WholesaleOrderProcessStep {
  labelKey: WholesaleOrderProcessStepKey;
  done: boolean;
}

export interface WholesaleOrderWorkflowContext {
  auditLogs?: AuditLog[];
  /** When set with totalProofAmount, payment step stays open until fully received. */
  orderTotal?: number;
  totalProofAmount?: number;
}

function shipmentMetrics(order: WholesaleOrder) {
  const shipments = order.shipments ?? [];
  const hasShipments = shipments.length > 0;
  const allShipmentsStarted =
    hasShipments && shipments.every((s) => shipmentHasDeliveryNoteStarted(s));
  const allShipmentsCompleted =
    hasShipments && shipments.every((s) => s.status === 'completed');
  return { hasShipments, allShipmentsStarted, allShipmentsCompleted };
}

function hasPaymentProofDocument(order: WholesaleOrder): boolean {
  return (
    !!order.payment_proof_url?.trim() ||
    (order.documents?.some((d) => d.type === 'payment_proof') ?? false)
  );
}

export function wholesaleOrderGrandTotal(order: WholesaleOrder): number {
  const itemsTotal =
    order.total_net ?? order.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0;
  return itemsTotal + (Number(order.shipping_fee) || 0);
}

function resolveTotalProofAmount(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext,
): number | undefined {
  if (ctx.totalProofAmount != null && Number.isFinite(ctx.totalProofAmount)) {
    return ctx.totalProofAmount;
  }
  const fromOrder = order.workflow_payment_proof_total;
  if (fromOrder != null && Number.isFinite(fromOrder)) {
    return fromOrder;
  }
  return undefined;
}

export function buildWholesaleOrderWorkflowContext(
  order: WholesaleOrder,
  auditLogs?: AuditLog[],
): WholesaleOrderWorkflowContext {
  const orderTotal = wholesaleOrderGrandTotal(order);
  if (auditLogs?.length) {
    return {
      auditLogs,
      orderTotal,
      totalProofAmount: computeTotalProofAmountFromAudits(order, auditLogs),
    };
  }
  const totalProofAmount = resolveTotalProofAmount(order, { orderTotal });
  return totalProofAmount != null ? { orderTotal, totalProofAmount } : { orderTotal };
}

function parseAuditChanges(raw: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== 'object') return null;
    const obj = parsed as Record<string, unknown>;
    const nested = obj.changes;
    if (nested && typeof nested === 'object') {
      return nested as Record<string, unknown>;
    }
    return obj;
  } catch {
    return null;
  }
}

/** Mirrors detail-page payment proof total from upload audits. */
export function computeTotalProofAmountFromAudits(
  order: WholesaleOrder,
  auditLogs: AuditLog[],
): number {
  const proofDocs = order.documents?.filter((d) => d.type === 'payment_proof') ?? [];
  if (proofDocs.length === 0) return 0;

  const uploadAudits = auditLogs
    .filter((l) => l.action === 'wholesale_order_upload_payment_proof')
    .map((l) => {
      const base = parseAuditChanges(l.changes);
      if (!base) return null;
      const fileCountRaw = base.file_count ?? base.files ?? 1;
      const file_count = Number.isFinite(Number(fileCountRaw)) ? Number(fileCountRaw) : 1;
      const amountRaw = base.amount;
      const amountNum = typeof amountRaw === 'number' ? amountRaw : Number(amountRaw);
      const amount = Number.isFinite(amountNum) ? amountNum : undefined;
      return { created_at: l.created_at, file_count, amount };
    })
    .filter(Boolean) as { created_at: string; file_count: number; amount?: number }[];

  if (uploadAudits.length === 0) return 0;

  const docsSorted = [...proofDocs].sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
  );
  const auditsSorted = [...uploadAudits].sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
  );

  let docIndex = 0;
  let totalProofAmount = 0;
  for (const audit of auditsSorted) {
    let remaining = audit.file_count || 1;
    const perFileAmount =
      audit.amount != null && remaining > 0 ? audit.amount / remaining : undefined;
    while (remaining > 0 && docIndex < docsSorted.length) {
      if (perFileAmount != null) {
        totalProofAmount += perFileAmount;
      }
      docIndex += 1;
      remaining -= 1;
    }
  }
  return totalProofAmount;
}

export function isPaymentConfirmationStepComplete(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext,
): boolean {
  // Order complete date (payment confirmed) always completes this step.
  if (order.payment_confirmed_at) return true;

  const orderTotal = ctx.orderTotal ?? wholesaleOrderGrandTotal(order);
  const totalProofAmount = resolveTotalProofAmount(order, ctx);

  if (totalProofAmount != null) {
    const pending = Math.max(0, orderTotal - totalProofAmount);
    return pending < 0.01;
  }
  if (hasPaymentProofDocument(order)) {
    return false;
  }
  return false;
}

/** True when payment is fully received (confirmed date or proof totals cover order total). */
export function isWholesaleOrderPaymentSettled(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext = {},
): boolean {
  if (order.payment_confirmed_at) return true;

  const orderTotal = ctx.orderTotal ?? wholesaleOrderGrandTotal(order);
  const totalProofAmount = resolveTotalProofAmount(order, ctx);
  if (totalProofAmount != null) {
    return Math.max(0, orderTotal - totalProofAmount) < 0.01;
  }
  return false;
}

function orderLinesHaveAssignedStore(order: WholesaleOrder): boolean {
  return (
    (order.items?.length ?? 0) > 0 &&
    order.items!.every((it) => it.assigned_store_id != null)
  );
}

/** Works on list payloads that omit shipment line items or nested wholesale_order_item qty. */
function isAssignmentComplete(order: WholesaleOrder, auditLogs?: AuditLog[]): boolean {
  if (allOrderLinesFullyAssigned(order)) return true;
  if (auditLogs?.some((l) => l.action === 'wholesale_order_complete_assignment')) {
    return true;
  }
  const shipments = order.shipments ?? [];
  if (shipments.length === 0) return false;
  const shipmentLinesLoaded = shipments.some((s) => (s.items?.length ?? 0) > 0);
  if (!shipmentLinesLoaded) {
    return orderLinesHaveAssignedStore(order);
  }
  // List payloads may omit nested shipment line qty while detail loads full rows.
  // Once stores are assigned and shipments have started or finished, treat allocation as done.
  if (orderLinesHaveAssignedStore(order)) {
    if (shipments.some((s) => !shipmentStatusAllowsAssignmentChange(s.status))) {
      return true;
    }
  }
  return false;
}

function isOrderConfirmationComplete(order: WholesaleOrder, auditLogs?: AuditLog[]): boolean {
  if (order.status === 'pending_approval' || order.status === 'rejected' || order.status === 'deleted') {
    return false;
  }
  return isAssignmentComplete(order, auditLogs);
}

/** Shared step list for the detail stepper and list/detail status chips. */
export function computeWholesaleOrderProcessSteps(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext = {},
): WholesaleOrderProcessStep[] {
  const { allShipmentsStarted, allShipmentsCompleted } = shipmentMetrics(order);
  const hasInvoice = orderHasInvoiceDocument(order);

  const stepCreated = true;
  const stepOrderConfirmation = isOrderConfirmationComplete(order, ctx.auditLogs);
  const stepStartShipment = allShipmentsStarted;
  const stepFinishShipment = allShipmentsCompleted;
  const stepSendInvoiceEmail = isWholesaleOrderInvoiceEmailDone(order, ctx.auditLogs);
  const stepPaymentConfirmation = isPaymentConfirmationStepComplete(order, ctx);
  const stepComplete =
    stepOrderConfirmation &&
    stepFinishShipment &&
    stepSendInvoiceEmail &&
    stepPaymentConfirmation;

  const steps: WholesaleOrderProcessStep[] = [
    { labelKey: 'stepCreate', done: stepCreated },
    { labelKey: 'stepOrderConfirmation', done: stepOrderConfirmation },
    { labelKey: 'stepStartShipment', done: stepStartShipment },
    { labelKey: 'stepFinishShipment', done: stepFinishShipment },
  ];

  if (hasInvoice) {
    steps.push({ labelKey: 'stepSendInvoiceEmail', done: stepSendInvoiceEmail });
  }

  steps.push(
    { labelKey: 'stepPaymentConfirmation', done: stepPaymentConfirmation },
    { labelKey: 'stepComplete', done: stepComplete },
  );

  return steps;
}

export function getCurrentWholesaleOrderProcessStepKey(
  steps: WholesaleOrderProcessStep[],
): WholesaleOrderProcessStepKey | null {
  return steps.find((s) => !s.done)?.labelKey ?? null;
}

export function isWholesaleOrderPaymentConfirmationPhase(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext = {},
): boolean {
  return (
    getCurrentWholesaleOrderProcessStepKey(computeWholesaleOrderProcessSteps(order, ctx)) ===
    'stepPaymentConfirmation'
  );
}

/** @deprecated Use isWholesaleOrderPaymentConfirmationPhase */
export function isWholesaleOrderAwaitingPaymentPhase(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext = {},
): boolean {
  return isWholesaleOrderPaymentConfirmationPhase(order, ctx);
}

/** Status chip label — operational state (what is pending now), not the stepper milestone name. */
export function wholesaleOrderStatusLabel(
  order: WholesaleOrder,
  t: TFunction,
  ctx: WholesaleOrderWorkflowContext = {},
): string {
  if (order.status === 'rejected') return t('wholesaleOrdersPage:statusRejected');
  if (order.status === 'deleted') return t('wholesaleOrdersPage:statusDeleted');

  if (isWholesaleOrderPaymentSettled(order, ctx)) {
    return t('wholesaleOrderDetail:statusCompleted');
  }
  if (hasPaymentProofDocument(order)) {
    return t('wholesaleOrderDetail:orderStatusPendingPaymentConfirmation');
  }

  const steps = computeWholesaleOrderProcessSteps(order, ctx);
  if (steps.every((s) => s.done)) return t('wholesaleOrderDetail:statusCompleted');

  const current = getCurrentWholesaleOrderProcessStepKey(steps);
  switch (current) {
    case 'stepOrderConfirmation':
      return t('wholesaleOrderDetail:orderStatusPendingOrderConfirmation');
    case 'stepStartShipment':
      return t('wholesaleOrderDetail:orderStatusPendingPacking');
    case 'stepFinishShipment':
      return t('wholesaleOrderDetail:orderStatusInTransit');
    case 'stepSendInvoiceEmail':
      return t('wholesaleOrderDetail:orderStatusPendingInvoiceEmail');
    case 'stepPaymentConfirmation':
      return t('wholesaleOrderDetail:orderStatusPendingPaymentConfirmation');
    case 'stepComplete':
      return t('wholesaleOrderDetail:statusCompleted');
    default:
      return String(order.status).replace(/_/g, ' ');
  }
}

/** Status chip color aligned with the first incomplete process step. */
export function wholesaleOrderStatusColor(
  order: WholesaleOrder,
  ctx: WholesaleOrderWorkflowContext = {},
): WholesaleOrderStatusChipColor {
  if (order.status === 'rejected') return 'error';
  if (order.status === 'deleted') return 'default';

  if (isWholesaleOrderPaymentSettled(order, ctx)) return 'success';
  if (hasPaymentProofDocument(order)) return 'secondary';

  const steps = computeWholesaleOrderProcessSteps(order, ctx);
  if (steps.every((s) => s.done)) return 'success';

  const current = getCurrentWholesaleOrderProcessStepKey(steps);
  switch (current) {
    case 'stepOrderConfirmation':
      return 'primary';
    case 'stepStartShipment':
      return 'warning';
    case 'stepFinishShipment':
      return 'info';
    case 'stepSendInvoiceEmail':
      return 'warning';
    case 'stepPaymentConfirmation':
      return 'secondary';
    default:
      return 'default';
  }
}

export function getWholesaleOrderProcessStepCompletedAt(
  order: WholesaleOrder,
  labelKey: WholesaleOrderProcessStepKey,
  opts: {
    auditLogs?: AuditLog[];
    assignmentCompletedAt?: string | null;
    stepFinishShipment?: boolean;
  } = {},
): string | null {
  const steps = computeWholesaleOrderProcessSteps(order, {
    auditLogs: opts.auditLogs,
  });
  const step = steps.find((s) => s.labelKey === labelKey);
  if (!step?.done) return null;

  const auditLogs = opts.auditLogs ?? [];
  const emailAudits = getWholesaleOrderEmailAudits(auditLogs);

  switch (labelKey) {
    case 'stepCreate':
      return order.created_at ?? null;
    case 'stepOrderConfirmation':
      return opts.assignmentCompletedAt ?? order.reviewed_at ?? null;
    case 'stepStartShipment':
      if (order.shipments?.length) {
        return order.shipments.reduce<string | null>((a, s) => {
          const at = s.created_at;
          if (!at) return a;
          return !a || at < a ? at : a;
        }, null);
      }
      return null;
    case 'stepFinishShipment':
      if (opts.stepFinishShipment && order.shipments?.length) {
        return order.shipments
          .filter((s) => s.status === 'completed')
          .reduce<string | null>((a, s) => {
            const at = s.updated_at ?? s.delivery_date ?? s.created_at;
            if (!at) return a;
            return !a || at > a ? at : a;
          }, null);
      }
      return null;
    case 'stepSendInvoiceEmail': {
      const changes = emailAudits.invoice
        ? parseWholesaleOrderEmailAuditBase(emailAudits.invoice.changes)
        : null;
      if (changes && isWholesaleOrderEmailSkippedAudit(changes)) {
        return (
          (typeof changes.skipped_at === 'string' && changes.skipped_at.trim()
            ? changes.skipped_at.trim()
            : null) ?? emailAudits.invoice?.created_at ?? null
        );
      }
      if (changes && isWholesaleOrderEmailSentAudit(changes)) {
        return (
          (typeof changes.sent_at === 'string' && changes.sent_at.trim()
            ? changes.sent_at.trim()
            : null) ?? emailAudits.invoice?.created_at ?? null
        );
      }
      return null;
    }
    case 'stepPaymentConfirmation':
    case 'stepComplete':
      return order.payment_confirmed_at ?? null;
    default:
      return null;
  }
}
