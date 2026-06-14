import type { Shipment } from '../types';

function normalizeScan(raw: string): string {
  return raw.trim().toLowerCase();
}

/** Values that may appear on a delivery note barcode or label. */
export function deliveryNoteScanKeys(shipment: Shipment): string[] {
  const order = shipment.wholesale_order;
  const keys = [
    order?.order_number,
    order?.po_number,
    order?.ref_no,
    order?.order_number?.replace(/^WO-/i, ''),
    String(shipment.id),
    String(shipment.wholesale_order_id),
    `shipment:${shipment.id}`,
    `shipment-${shipment.id}`,
    shipment.tracking_number,
  ];
  return [...new Set(keys.filter((k) => k != null && String(k).trim() !== '').map((k) => normalizeScan(String(k))))];
}

export function shipmentMatchesDeliveryNoteScan(shipment: Shipment, raw: string): boolean {
  const q = normalizeScan(raw);
  if (!q) return false;
  const keys = deliveryNoteScanKeys(shipment);
  return keys.some((k) => k === q || k.includes(q) || q.includes(k));
}

export function shipmentMatchesCouriers(shipment: Shipment, couriers: string[]): boolean {
  if (couriers.length === 0) return true;
  const assigned = (shipment.courier ?? '').trim().toLowerCase();
  if (!assigned) return true;
  return couriers.some((c) => c.trim().toLowerCase() === assigned);
}
