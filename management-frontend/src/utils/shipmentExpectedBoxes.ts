import type { Shipment, ShipmentItem, WholesaleOrderItem } from '../types';

/** Catalog-based box estimate from line quantity and units per box. */
export function computedExpectedBoxes(
  quantity: number,
  wholesaleUnitsPerBox?: number | null,
): number {
  const qty = quantity ?? 0;
  const upb = wholesaleUnitsPerBox ?? 0;
  if (upb > 0 && qty > 0) return Math.ceil(qty / upb);
  return Math.round(qty);
}

/** Expected boxes for a shipment line: value from assign (case_qty), else catalog estimate. */
export function shipmentExpectedBoxes(si: Pick<ShipmentItem, 'case_qty' | 'wholesale_order_item'>): number {
  if (si.case_qty != null && si.case_qty > 0) {
    return si.case_qty;
  }
  const qty = si.wholesale_order_item?.quantity ?? 0;
  const upb = si.wholesale_order_item?.product?.wholesale_units_per_box;
  return computedExpectedBoxes(qty, upb);
}

export function orderItemExpectedBoxes(item: Pick<WholesaleOrderItem, 'quantity' | 'product'>): number {
  return computedExpectedBoxes(item.quantity, item.product?.wholesale_units_per_box);
}

/** Total boxes on a shipment (sum of line case_qty or catalog estimates). */
export function shipmentTotalBoxes(shipment: Pick<Shipment, 'items'>): number {
  return (shipment.items ?? []).reduce((sum, si) => sum + shipmentExpectedBoxes(si), 0);
}

/** case_qty saved on a shipment for this order line, if any. */
export function assignedCaseQtyForOrderItem(
  shipments: { items?: ShipmentItem[] }[] | undefined,
  wholesaleOrderItemId: number,
): number | undefined {
  for (const sh of shipments ?? []) {
    for (const si of sh.items ?? []) {
      if (
        si.wholesale_order_item_id === wholesaleOrderItemId &&
        si.case_qty != null &&
        si.case_qty > 0
      ) {
        return si.case_qty;
      }
    }
  }
  return undefined;
}
