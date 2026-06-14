import type { ShipmentStatus } from './shipmentStatus';

export type MonitorBoardColumnId = 'packing' | 'packed' | 'shipped' | 'completed';

export const MONITOR_BOARD_COLUMNS: MonitorBoardColumnId[] = [
  'packing',
  'packed',
  'shipped',
  'completed',
];

export function columnIdForShipmentStatus(status: string): MonitorBoardColumnId {
  if (status === 'assigned' || status === 'packing') return 'packing';
  if (status === 'packed') return 'packed';
  if (status === 'shipped') return 'shipped';
  if (status === 'completed') return 'completed';
  return 'packing';
}

export function shipmentStatusForColumnId(columnId: MonitorBoardColumnId): ShipmentStatus {
  switch (columnId) {
    case 'packing':
      return 'assigned';
    case 'packed':
      return 'packed';
    case 'shipped':
      return 'shipped';
    case 'completed':
      return 'completed';
    default:
      return 'assigned';
  }
}

export function shipmentDndId(shipmentId: number): string {
  return `shipment:${shipmentId}`;
}

export function columnDndId(columnId: MonitorBoardColumnId): string {
  return `column:${columnId}`;
}

export function parseShipmentDndId(id: string | number): number | null {
  const s = String(id);
  if (!s.startsWith('shipment:')) return null;
  const n = Number(s.slice(9));
  return Number.isFinite(n) ? n : null;
}

export function parseColumnDndId(id: string | number): MonitorBoardColumnId | null {
  const s = String(id);
  if (!s.startsWith('column:')) return null;
  const col = s.slice(7) as MonitorBoardColumnId;
  return MONITOR_BOARD_COLUMNS.includes(col) ? col : null;
}

export function resolveDropColumnId(
  overId: string | number | undefined,
  getColumnForShipment: (shipmentId: number) => MonitorBoardColumnId | undefined,
): MonitorBoardColumnId | null {
  if (overId == null) return null;
  const column = parseColumnDndId(overId);
  if (column) return column;
  const shipmentId = parseShipmentDndId(overId);
  if (shipmentId != null) return getColumnForShipment(shipmentId) ?? null;
  return null;
}
