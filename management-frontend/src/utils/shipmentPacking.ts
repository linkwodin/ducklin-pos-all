import type { Product, Shipment, ShipmentItem, Stock } from '../types';
import { orderItemExpectedBoxes } from './shipmentExpectedBoxes';
import { effectiveShipmentItemQty } from './wholesaleOrderAssignment';
import {
  effectivePrepackedQuantity,
  effectiveWeightQuantityG,
  productIsWeight,
} from './productInventory';

export type ShipmentPackingLine = {
  productId: number;
  expectedQty: number;
  expectedBoxes: number;
  product: Product;
};

function aggregatePackingLine(
  byProduct: Map<number, ShipmentPackingLine>,
  productId: number,
  product: Product,
  expectedQty: number,
  expectedBoxes: number,
) {
  const existing = byProduct.get(productId);
  if (existing) {
    existing.expectedQty += expectedQty;
    existing.expectedBoxes += expectedBoxes;
  } else {
    byProduct.set(productId, {
      productId,
      expectedQty,
      expectedBoxes,
      product,
    });
  }
}

function buildLinesFromShipmentItems(items: ShipmentItem[]): ShipmentPackingLine[] {
  const byProduct = new Map<number, ShipmentPackingLine>();
  for (const si of items) {
    const woItem = si.wholesale_order_item;
    if (!woItem?.product_id || !woItem.product) continue;
    const expectedQty = effectiveShipmentItemQty(si);
    const caseQty = si.case_qty != null && si.case_qty > 0 ? si.case_qty : 0;
    aggregatePackingLine(byProduct, woItem.product_id, woItem.product, expectedQty, caseQty);
  }
  return Array.from(byProduct.values());
}

/** Shipment lines for packing UI; falls back to wholesale order lines when shipment items are missing. */
export function effectiveShipmentItemsForPacking(shipment: Shipment): ShipmentItem[] {
  const items = shipment.items ?? [];
  const hasLines = items.some((si) => si.wholesale_order_item?.product_id && si.wholesale_order_item.product);
  if (hasLines) return items;

  const orderItems = shipment.wholesale_order?.items ?? [];
  const storeId = shipment.store_id;
  const forStore = orderItems.filter(
    (oi) =>
      oi.product &&
      (oi.assigned_store_id == null || oi.assigned_store_id === storeId),
  );
  const source = forStore.length > 0 ? forStore : orderItems.filter((oi) => oi.product);

  return source.map(
    (oi) =>
      ({
        id: -oi.id,
        shipment_id: shipment.id,
        wholesale_order_item_id: oi.id,
        quantity: oi.quantity,
        wholesale_order_item: oi,
      }) as ShipmentItem,
  );
}

export function buildShipmentPackingLines(shipment: Shipment): ShipmentPackingLine[] {
  const fromItems = buildLinesFromShipmentItems(effectiveShipmentItemsForPacking(shipment));
  if (fromItems.length > 0) return fromItems;

  const byProduct = new Map<number, ShipmentPackingLine>();
  const orderItems = shipment.wholesale_order?.items ?? [];
  const storeId = shipment.store_id;
  for (const oi of orderItems) {
    if (!oi.product_id || !oi.product) continue;
    if (oi.assigned_store_id != null && oi.assigned_store_id !== storeId) continue;
    const boxes = orderItemExpectedBoxes(oi);
    aggregatePackingLine(byProduct, oi.product_id, oi.product, oi.quantity, boxes > 0 ? boxes : 0);
  }
  return Array.from(byProduct.values());
}

export function stockByProductId(rows: Stock[]): Map<number, Stock> {
  const map = new Map<number, Stock>();
  for (const row of rows) {
    map.set(row.product_id, row);
  }
  return map;
}

export function availableStockForProduct(stock: Stock | undefined, product: Product): number {
  if (productIsWeight(product)) return effectiveWeightQuantityG(stock, product);
  return effectivePrepackedQuantity(stock, product);
}

export function hasNoStock(available: number): boolean {
  return available <= 0.0001;
}

export function formatStockAmount(product: Product, amount: number): string {
  if (productIsWeight(product)) {
    if (amount <= 0) return '0 g';
    if (amount >= 1000 && amount % 100 === 0) return `${(amount / 1000).toFixed(2)} kg`;
    return `${amount % 1 === 0 ? amount : amount.toFixed(2)} g`;
  }
  return amount % 1 === 0 ? String(Math.round(amount)) : amount.toFixed(3).replace(/\.?0+$/, '');
}

export function formatPackingQty(qty: number): string {
  return qty % 1 === 0 ? String(Math.round(qty)) : qty.toFixed(2);
}

export function packingLineSubtitle(line: ShipmentPackingLine): string {
  const parts: string[] = [];
  if (line.expectedBoxes > 0) {
    parts.push(`Expected boxes: ${formatPackingQty(line.expectedBoxes)}`);
  }
  parts.push(`Qty: ${formatPackingQty(line.expectedQty)}`);
  return parts.join(' · ');
}

export function caseQtyPayloadFromShipment(shipment: Shipment): {
  wholesale_order_item_id: number;
  case_qty: number;
}[] {
  return effectiveShipmentItemsForPacking(shipment).map((si: ShipmentItem) => ({
    wholesale_order_item_id: si.wholesale_order_item_id,
    case_qty: si.case_qty != null && si.case_qty > 0 ? si.case_qty : 0,
  }));
}

/** Catalog for barcode lookup: shipment line products only, with full barcode fields merged from store catalog. */
export function packingScanCatalog(products: Product[], shipment: Shipment): Product[] {
  const byId = new Map<number, Product>();
  for (const p of products) byId.set(p.id, p);
  return buildShipmentPackingLines(shipment).map((line) => {
    const catalog = byId.get(line.productId);
    return catalog
      ? {
          ...catalog,
          ...line.product,
          barcode: catalog.barcode?.trim() || line.product.barcode?.trim() || undefined,
          sku: catalog.sku?.trim() || line.product.sku?.trim() || undefined,
          weight_barcode: catalog.weight_barcode?.trim() || line.product.weight_barcode?.trim() || undefined,
          weight_barcode_prefix:
            catalog.weight_barcode_prefix?.trim() || line.product.weight_barcode_prefix?.trim() || undefined,
          sell_by_qty: line.product.sell_by_qty ?? catalog.sell_by_qty,
          sell_by_weight: line.product.sell_by_weight ?? catalog.sell_by_weight,
          unit_type: line.product.unit_type ?? catalog.unit_type,
        }
      : line.product;
  });
}
