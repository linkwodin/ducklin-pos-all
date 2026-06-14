import type { Shipment } from '../types';

function parseDateMs(value?: string | null): number {
  if (!value?.trim()) return 0;
  const trimmed = value.trim();
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(trimmed);
  const ms = new Date(dateOnly ? `${trimmed}T12:00:00` : trimmed).getTime();
  return Number.isFinite(ms) ? ms : 0;
}

/** Sort key from wholesale order date (order_date), then order created_at, then shipment created_at. */
export function shipmentOrderTimeMs(s: Shipment): number {
  const order = s.wholesale_order;
  const orderDateMs = parseDateMs(order?.order_date);
  if (orderDateMs > 0) return orderDateMs;
  const orderCreatedMs = parseDateMs(order?.created_at);
  if (orderCreatedMs > 0) return orderCreatedMs;
  return parseDateMs(s.created_at);
}

/** YYYY-MM-DD for monitor cards (matches sort key). */
export function formatShipmentOrderDate(shipment: Shipment): string | null {
  const order = shipment.wholesale_order;
  const raw = order?.order_date?.trim() || order?.created_at?.trim() || shipment.created_at?.trim();
  if (!raw) return null;
  const dateOnly = raw.substring(0, 10);
  if (/^\d{4}-\d{2}-\d{2}$/.test(dateOnly)) return dateOnly;
  const ms = parseDateMs(raw);
  if (ms <= 0) return null;
  const d = new Date(ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function sortShipmentsByOrderTimeDesc(a: Shipment, b: Shipment): number {
  const diff = shipmentOrderTimeMs(b) - shipmentOrderTimeMs(a);
  if (diff !== 0) return diff;
  const orderCreatedDiff =
    parseDateMs(b.wholesale_order?.created_at) - parseDateMs(a.wholesale_order?.created_at);
  if (orderCreatedDiff !== 0) return orderCreatedDiff;
  return b.id - a.id;
}

export function sortShipmentsByOrderTimeAsc(a: Shipment, b: Shipment): number {
  const diff = shipmentOrderTimeMs(a) - shipmentOrderTimeMs(b);
  if (diff !== 0) return diff;
  const orderCreatedDiff =
    parseDateMs(a.wholesale_order?.created_at) - parseDateMs(b.wholesale_order?.created_at);
  if (orderCreatedDiff !== 0) return orderCreatedDiff;
  return a.id - b.id;
}

/** Merge shipment list row after API update without dropping nested wholesale_order fields. */
export function mergeShipmentListRow(existing: Shipment, updated: Shipment): Shipment {
  return {
    ...existing,
    ...updated,
    wholesale_order: updated.wholesale_order
      ? { ...existing.wholesale_order, ...updated.wholesale_order }
      : existing.wholesale_order,
    store: updated.store ? { ...existing.store, ...updated.store } : existing.store,
    items: updated.items ?? existing.items,
  };
}
