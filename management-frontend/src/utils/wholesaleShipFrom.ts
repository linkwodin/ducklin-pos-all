import { stockAPI } from '../services/api';
import type { Stock } from '../types';

export function assignedStockRows(rows: Stock[]): Stock[] {
  return rows.filter((row) => row.track_prepacked !== false || row.track_weight);
}

export async function fetchProductStockAssignments(productId: number): Promise<Stock[]> {
  const rows = await stockAPI.getProductStockAssignments(productId);
  return assignedStockRows(rows);
}

export class WholesaleShipFromNotAssignedError extends Error {
  constructor() {
    super('NOT_ASSIGNED');
    this.name = 'WholesaleShipFromNotAssignedError';
  }
}

export async function setProductWholesaleShipStore(
  productId: number,
  storeId: number | '',
  assignments: Stock[],
): Promise<Stock[]> {
  const current = assignments.find((row) => row.wholesale_ship_from);
  if (storeId === '') {
    if (!current) return assignments;
    await stockAPI.setAssignments(current.store_id, [
      {
        product_id: productId,
        track_prepacked: current.track_prepacked !== false,
        track_weight: !!current.track_weight,
        wholesale_ship_from: false,
      },
    ]);
  } else {
    const target = assignments.find((row) => row.store_id === storeId);
    if (!target) throw new WholesaleShipFromNotAssignedError();
    await stockAPI.setAssignments(storeId, [
      {
        product_id: productId,
        track_prepacked: target.track_prepacked !== false,
        track_weight: !!target.track_weight,
        wholesale_ship_from: true,
      },
    ]);
  }
  return fetchProductStockAssignments(productId);
}
