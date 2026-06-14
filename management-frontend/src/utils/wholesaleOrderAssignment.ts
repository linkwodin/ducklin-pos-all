import type { ShipmentItem, Stock, WholesaleOrder, WholesaleOrderItem } from '../types';
import { stockLevelValue } from './productInventory';

/** Units on a shipment line; legacy rows without quantity use the full order line qty. */
export function effectiveShipmentItemQty(
  si: Pick<ShipmentItem, 'quantity' | 'wholesale_order_item_id' | 'wholesale_order_item'>,
): number {
  if (si.quantity != null && si.quantity > 0) {
    return si.quantity;
  }
  return si.wholesale_order_item?.quantity ?? 0;
}

export function assignedQtyForOrderItem(order: WholesaleOrder, wholesaleOrderItemId: number): number {
  let sum = 0;
  for (const sh of order.shipments ?? []) {
    for (const si of sh.items ?? []) {
      if (si.wholesale_order_item_id === wholesaleOrderItemId) {
        sum += effectiveShipmentItemQty(si);
      }
    }
  }
  return sum;
}

export function assignedQtyForOrderItemToStore(
  order: WholesaleOrder,
  wholesaleOrderItemId: number,
  storeId: number,
): number {
  let sum = 0;
  for (const sh of order.shipments ?? []) {
    if (sh.store_id !== storeId) continue;
    for (const si of sh.items ?? []) {
      if (si.wholesale_order_item_id === wholesaleOrderItemId) {
        sum += effectiveShipmentItemQty(si);
      }
    }
  }
  return sum;
}

export function formatAssignmentQty(qty: number | null | undefined): string {
  return formatQty(qty);
}

export function shipmentAssignedSummary(shipment: { items?: ShipmentItem[] }) {
  const items = shipment.items ?? [];
  const productCount = items.length;
  const totalQty = items.reduce((sum, si) => sum + effectiveShipmentItemQty(si), 0);
  const totalBoxes = items.reduce((sum, si) => sum + (si.case_qty != null && si.case_qty > 0 ? si.case_qty : 0), 0);
  return { productCount, totalQty, totalBoxes };
}

export function pendingQtyForOrderItem(order: WholesaleOrder, item: Pick<WholesaleOrderItem, 'id' | 'quantity'>): number {
  return Math.max(0, item.quantity - assignedQtyForOrderItem(order, item.id));
}

export function orderLineFullyAssigned(order: WholesaleOrder, item: Pick<WholesaleOrderItem, 'id' | 'quantity'>): boolean {
  return pendingQtyForOrderItem(order, item) <= 0.0001;
}

export function allOrderLinesFullyAssigned(order: WholesaleOrder): boolean {
  return (
    (order.items?.length ?? 0) > 0 &&
    order.items!.every((it) => orderLineFullyAssigned(order, it))
  );
}

/** True when shipment lines on this shipment can still be assigned or unassigned. */
export function shipmentStatusAllowsAssignmentChange(status: string | undefined): boolean {
  const normalized = (status ?? 'assigned').toLowerCase();
  return normalized === 'assigned' || normalized === 'packing';
}

export function storeShipmentForOrder(order: WholesaleOrder, storeId: number) {
  return order.shipments?.find((s) => s.store_id === storeId);
}

/** False when the store already has a shipment that is past the assign/pack stage. */
export function storeAllowsAssignmentTarget(order: WholesaleOrder, storeId: number): boolean {
  const shipment = storeShipmentForOrder(order, storeId);
  if (!shipment) return true;
  return shipmentStatusAllowsAssignmentChange(shipment.status);
}

/** True when the user can still change assignments (pending qty or movable assigned lines). */
export function orderAllowsAssignmentChange(
  order: WholesaleOrder,
  pendingQtyForItem: (item: Pick<WholesaleOrderItem, 'id' | 'quantity'>) => number,
): boolean {
  for (const it of order.items ?? []) {
    if (pendingQtyForItem(it) > 0.0001) return true;
  }
  for (const sh of order.shipments ?? []) {
    if (!shipmentStatusAllowsAssignmentChange(sh.status)) continue;
    if ((sh.items?.length ?? 0) > 0) return true;
  }
  return false;
}

export type StagedStoreAssignment = {
  wholesale_order_item_id: number;
  store_id: number;
  quantity: number;
  case_qty?: number;
};

export function stagedQtyForOrderItem(staged: StagedStoreAssignment[], itemId: number): number {
  return staged
    .filter((a) => a.wholesale_order_item_id === itemId)
    .reduce((sum, a) => sum + a.quantity, 0);
}

export function stagedQtyForOrderItemToStore(
  staged: StagedStoreAssignment[],
  itemId: number,
  storeId: number,
): number {
  return staged
    .filter((a) => a.wholesale_order_item_id === itemId && a.store_id === storeId)
    .reduce((sum, a) => sum + a.quantity, 0);
}

export function pendingQtyForOrderItemWithStaging(
  order: WholesaleOrder,
  item: Pick<WholesaleOrderItem, 'id' | 'quantity'>,
  staged: StagedStoreAssignment[],
): number {
  return Math.max(0, item.quantity - assignedQtyForOrderItem(order, item.id) - stagedQtyForOrderItem(staged, item.id));
}

export function stagedAssignmentSummaryForOrderItem(
  staged: StagedStoreAssignment[],
  itemId: number,
  storeNameById: Map<number, string>,
): string {
  const parts = staged
    .filter((a) => a.wholesale_order_item_id === itemId)
    .map((a) => {
      const storeName = storeNameById.get(a.store_id) ?? `Store #${a.store_id}`;
      return `${storeName} (${formatQty(a.quantity)})`;
    });
  return parts.length > 0 ? parts.join(', ') : '—';
}

export function allOrderLinesFullyStaged(order: WholesaleOrder, staged: StagedStoreAssignment[]): boolean {
  return (
    (order.items?.length ?? 0) > 0 &&
    order.items!.every((it) => pendingQtyForOrderItemWithStaging(order, it, staged) <= 0.0001)
  );
}

export type AssignmentBoardCard = {
  dragId: string;
  item_id: number;
  store_id: number | null;
  quantity: number;
  staged: boolean;
  can_unassign: boolean;
};

export function buildAssignmentBoardCards(
  order: WholesaleOrder,
  staged: StagedStoreAssignment[],
  pendingQtyForItem: (item: Pick<WholesaleOrderItem, 'id' | 'quantity'>) => number,
  storeNameById: Map<number, string>,
): {
  unassigned: AssignmentBoardCard[];
  byStoreId: Map<number, AssignmentBoardCard[]>;
  byItemId: Map<number, { unassigned: AssignmentBoardCard[]; byStore: Map<number, AssignmentBoardCard[]> }>;
} {
  const unassigned: AssignmentBoardCard[] = [];
  const byStoreId = new Map<number, AssignmentBoardCard[]>();
  const byItemId = new Map<number, { unassigned: AssignmentBoardCard[]; byStore: Map<number, AssignmentBoardCard[]> }>();

  for (const it of order.items ?? []) {
    const pending = pendingQtyForItem(it);
    const row = { unassigned: [] as AssignmentBoardCard[], byStore: new Map<number, AssignmentBoardCard[]>() };
    if (pending > 0.0001) {
      const card: AssignmentBoardCard = {
        dragId: `unassigned-${it.id}`,
        item_id: it.id,
        store_id: null,
        quantity: pending,
        staged: false,
        can_unassign: true,
      };
      unassigned.push(card);
      row.unassigned.push(card);
    }

    for (const entry of orderItemStoreAssignments(order, it.id, staged, storeNameById)) {
      const card: AssignmentBoardCard = {
        dragId: `${entry.staged ? 'staged' : 'assigned'}-${it.id}-${entry.store_id}`,
        item_id: it.id,
        store_id: entry.store_id,
        quantity: entry.quantity,
        staged: entry.staged,
        can_unassign: entry.can_unassign,
      };
      const list = byStoreId.get(entry.store_id) ?? [];
      list.push(card);
      byStoreId.set(entry.store_id, list);
      const storeList = row.byStore.get(entry.store_id) ?? [];
      storeList.push(card);
      row.byStore.set(entry.store_id, storeList);
    }
    byItemId.set(it.id, row);
  }

  return { unassigned, byStoreId, byItemId };
}

export function cellDroppableId(itemId: number, storeId: number | null): string {
  return storeId == null ? `cell-${itemId}-unassigned` : `cell-${itemId}-${storeId}`;
}

export function parseCellDroppableId(id: string): { itemId: number; storeId: number | null } | null {
  if (!id.startsWith('cell-')) return null;
  const rest = id.slice(5);
  if (rest.endsWith('-unassigned')) {
    return { itemId: Number(rest.replace('-unassigned', '')), storeId: null };
  }
  const dash = rest.lastIndexOf('-');
  if (dash <= 0) return null;
  return { itemId: Number(rest.slice(0, dash)), storeId: Number(rest.slice(dash + 1)) };
}

export type OrderItemStoreAssignment = {
  store_id: number;
  store_name: string;
  quantity: number;
  can_unassign: boolean;
  staged: boolean;
};

export function orderItemStoreAssignments(
  order: WholesaleOrder,
  itemId: number,
  staged: StagedStoreAssignment[] = [],
  storeNameById?: Map<number, string>,
): OrderItemStoreAssignment[] {
  const entries: OrderItemStoreAssignment[] = [];
  for (const sh of order.shipments ?? []) {
    const canUnassign = shipmentStatusAllowsAssignmentChange(sh.status);
    for (const si of sh.items ?? []) {
      if (si.wholesale_order_item_id !== itemId) continue;
      entries.push({
        store_id: sh.store_id,
        store_name: sh.store?.name?.trim() || `Store #${sh.store_id}`,
        quantity: effectiveShipmentItemQty(si),
        can_unassign: canUnassign,
        staged: false,
      });
    }
  }
  for (const a of staged) {
    if (a.wholesale_order_item_id !== itemId) continue;
    entries.push({
      store_id: a.store_id,
      store_name: storeNameById?.get(a.store_id) ?? `Store #${a.store_id}`,
      quantity: a.quantity,
      can_unassign: true,
      staged: true,
    });
  }
  return entries;
}

export function removeStagedAssignment(
  staged: StagedStoreAssignment[],
  itemId: number,
  storeId: number,
): StagedStoreAssignment[] {
  return staged.filter((a) => !(a.wholesale_order_item_id === itemId && a.store_id === storeId));
}

export function removeStagedAssignmentQty(
  staged: StagedStoreAssignment[],
  itemId: number,
  storeId: number,
  quantity: number,
): StagedStoreAssignment[] {
  let remaining = quantity;
  const result: StagedStoreAssignment[] = [];
  for (const a of staged) {
    if (a.wholesale_order_item_id === itemId && a.store_id === storeId && remaining > 0.0001) {
      if (a.quantity <= remaining + 0.0001) {
        remaining -= a.quantity;
        continue;
      }
      result.push({ ...a, quantity: a.quantity - remaining });
      remaining = 0;
    } else {
      result.push(a);
    }
  }
  return result;
}

export function addStagedAssignment(
  staged: StagedStoreAssignment[],
  assignment: StagedStoreAssignment,
): StagedStoreAssignment[] {
  let merged = false;
  const next = staged.map((a) => {
    if (a.wholesale_order_item_id === assignment.wholesale_order_item_id && a.store_id === assignment.store_id) {
      merged = true;
      return {
        ...a,
        quantity: a.quantity + assignment.quantity,
        ...(assignment.case_qty !== undefined ? { case_qty: (a.case_qty ?? 0) + assignment.case_qty } : {}),
      };
    }
    return a;
  });
  return merged ? next : [...next, assignment];
}

export function storeCanFulfillItemQty(
  storeId: number,
  item: Pick<WholesaleOrderItem, 'product_id' | 'product'>,
  needQty: number,
  stockByStoreProduct: Map<string, Stock>,
): boolean {
  if (needQty <= 0.0001) return true;
  const stock = stockByStoreProduct.get(`${storeId}-${item.product_id}`);
  const available = stock ? stockLevelValue(stock, item.product) : null;
  return available != null && available + 0.0001 >= needQty;
}

export type StoreStockHighlight = 'none' | 'partial' | 'full';

export function storeStockHighlightLevel(
  storeId: number,
  order: WholesaleOrder,
  pendingQtyForItem: (item: Pick<WholesaleOrderItem, 'id' | 'quantity' | 'product_id' | 'product'>) => number,
  stockByStoreProduct: Map<string, Stock>,
): StoreStockHighlight {
  let anyPending = false;
  let allFulfill = true;
  let anyFulfill = false;
  for (const it of order.items ?? []) {
    const pending = pendingQtyForItem(it);
    if (pending <= 0.0001) continue;
    anyPending = true;
    const ok = storeCanFulfillItemQty(storeId, it, pending, stockByStoreProduct);
    if (ok) anyFulfill = true;
    else allFulfill = false;
  }
  if (!anyPending) return 'none';
  if (allFulfill) return 'full';
  if (anyFulfill) return 'partial';
  return 'none';
}

export function collectAssignmentStockWarnings(
  order: WholesaleOrder,
  byItemId: Map<number, { unassigned: AssignmentBoardCard[]; byStore: Map<number, AssignmentBoardCard[]> }>,
  stockByStoreProduct: Map<string, Stock>,
): Array<{
  item_id: number;
  store_id: number;
  quantity: number;
  available: number | null;
}> {
  const warnings: Array<{
    item_id: number;
    store_id: number;
    quantity: number;
    available: number | null;
  }> = [];
  for (const it of order.items ?? []) {
    const row = byItemId.get(it.id);
    if (!row) continue;
    for (const [storeId, cards] of row.byStore) {
      const qty = cards.reduce((sum, c) => sum + c.quantity, 0);
      if (qty <= 0.0001) continue;
      const stock = stockByStoreProduct.get(`${storeId}-${it.product_id}`);
      const available = stock ? stockLevelValue(stock, it.product) : null;
      if (available == null || available + 0.0001 < qty) {
        warnings.push({ item_id: it.id, store_id: storeId, quantity: qty, available });
      }
    }
  }
  return warnings;
}

export function formatAssignStoreStockHint(
  available: number | null | undefined,
  needQty: number,
  selected: boolean,
): { text: string; sufficient: boolean } {
  if (available == null || Number.isNaN(available)) {
    return { text: '—', sufficient: false };
  }
  const sufficient = available + 0.0001 >= needQty;
  if (needQty <= 0.0001) {
    return { text: formatQty(available), sufficient: true };
  }
  const after = available - needQty;
  const text = selected
    ? `${formatQty(available)} → ${formatQty(after)}`
    : `${formatQty(available)} / ${formatQty(needQty)}`;
  return { text, sufficient };
}

export function assignmentSummaryForOrderItem(order: WholesaleOrder, wholesaleOrderItemId: number): string {
  const parts: string[] = [];
  for (const sh of order.shipments ?? []) {
    for (const si of sh.items ?? []) {
      if (si.wholesale_order_item_id !== wholesaleOrderItemId) continue;
      const qty = effectiveShipmentItemQty(si);
      const storeName = sh.store?.name?.trim() || `Store #${sh.store_id}`;
      parts.push(`${storeName} (${formatQty(qty)})`);
    }
  }
  return parts.length > 0 ? parts.join(', ') : '—';
}

function formatQty(qty: number | null | undefined): string {
  if (qty == null || Number.isNaN(qty)) return '—';
  return qty === Math.round(qty) ? String(Math.round(qty)) : qty.toFixed(3).replace(/\.?0+$/, '');
}

/** Remaining stock at a store after an endorse preview assignment. */
export function endorseAssignmentStockAfter(assignment: {
  stock_after?: number;
  stock_available?: number;
  quantity?: number;
}): number | undefined {
  if (assignment.stock_after != null) return assignment.stock_after;
  if (assignment.stock_available == null || assignment.quantity == null) return undefined;
  return assignment.stock_available - assignment.quantity;
}

export function formatEndorseStockChange(
  assignments: Array<{
    store_id: number;
    store_name?: string;
    stock_available?: number;
    stock_after?: number;
    quantity?: number;
  }>,
): string {
  if (assignments.length === 0) return '—';
  const multi = assignments.length > 1;
  return assignments
    .map((a) => {
      const prefix = multi ? `${a.store_name?.trim() || `Store #${a.store_id}`}: ` : '';
      return `${prefix}${formatQty(a.stock_available)} → ${formatQty(endorseAssignmentStockAfter(a))}`;
    })
    .join(', ');
}
