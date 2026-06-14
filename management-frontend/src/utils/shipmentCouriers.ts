export const DEFAULT_SHIPMENT_COURIERS = ['In-house', 'DPD', 'Royal Mail'];

/** One courier name per line from company settings; falls back to defaults when empty. */
export function shipmentCourierOptionsFromSettings(raw?: string | null): string[] {
  const lines = (raw ?? '')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  return lines.length > 0 ? lines : [...DEFAULT_SHIPMENT_COURIERS];
}
