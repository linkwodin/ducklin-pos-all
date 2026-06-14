import type { Shipment, ShipmentItem, WholesaleOrderItem } from '../types';
import { productDisplayName } from './productDisplay';
import { effectiveShipmentItemQty } from './wholesaleOrderAssignment';
import { orderItemExpectedBoxes, shipmentExpectedBoxes } from './shipmentExpectedBoxes';

export type MonitorLine = {
  key: string;
  name: string;
  qty: number;
  boxes: number | null;
  imageUrl?: string;
};

function lineFromShipmentItem(
  si: ShipmentItem,
  lang: string,
  itemFallback: (id: number) => string,
): MonitorLine {
  const product = si.wholesale_order_item?.product;
  const name = product
    ? productDisplayName(product, lang)
    : itemFallback(si.wholesale_order_item_id);
  const boxes = shipmentExpectedBoxes(si);
  return {
    key: `si-${si.id}`,
    name,
    qty: effectiveShipmentItemQty(si),
    boxes: boxes > 0 ? boxes : null,
    imageUrl: product?.image_url,
  };
}

function lineFromOrderItem(oi: WholesaleOrderItem, lang: string): MonitorLine {
  const product = oi.product;
  const name = product ? productDisplayName(product, lang) : `Item #${oi.id}`;
  const boxes = orderItemExpectedBoxes(oi);
  return {
    key: `oi-${oi.id}`,
    name,
    qty: oi.quantity,
    boxes: boxes > 0 ? boxes : null,
    imageUrl: product?.image_url,
  };
}

/** Lines to show on packing monitor cards; falls back to order items when shipment lines are missing. */
export function monitorLinesForShipment(
  shipment: Shipment,
  lang: string,
  itemFallback: (id: number) => string,
): MonitorLine[] {
  const items = shipment.items ?? [];
  if (items.length > 0) {
    return items.map((si) => lineFromShipmentItem(si, lang, itemFallback));
  }

  const orderItems = shipment.wholesale_order?.items ?? [];
  if (orderItems.length === 0) return [];

  const storeId = shipment.store_id;
  const forStore = orderItems.filter(
    (oi) => oi.assigned_store_id == null || oi.assigned_store_id === storeId,
  );
  return (forStore.length > 0 ? forStore : orderItems).map((oi) => lineFromOrderItem(oi, lang));
}
