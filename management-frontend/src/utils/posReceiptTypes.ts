export const POS_RECEIPT_TYPE_OPTIONS = [
  { id: 'audit_note', labelKey: 'storeDetail:receiptTypeAuditNote' },
  { id: 'no_price_with_barcode', labelKey: 'storeDetail:receiptTypeOrderClipStore' },
  { id: 'customer_counterfoil', labelKey: 'storeDetail:receiptTypeOrderClipCustomer' },
  { id: 'no_price_no_barcode', labelKey: 'storeDetail:receiptTypePickupReceipt' },
] as const;

export type PosReceiptTypeId = (typeof POS_RECEIPT_TYPE_OPTIONS)[number]['id'];

export const DEFAULT_POS_RECEIPT_TYPES: PosReceiptTypeId[] = [
  'audit_note',
  'no_price_with_barcode',
  'customer_counterfoil',
  'no_price_no_barcode',
];

export const DEFAULT_POS_AUTO_PRINT_RECEIPT_TYPES: PosReceiptTypeId[] = [
  'no_price_with_barcode',
  'customer_counterfoil',
  'no_price_no_barcode',
];

export function effectivePosReceiptTypes(store?: {
  pos_receipt_types?: string[] | null;
  pos_receipt_settings_configured?: boolean;
}): PosReceiptTypeId[] {
  if (!store?.pos_receipt_settings_configured) {
    return [...DEFAULT_POS_RECEIPT_TYPES];
  }
  const types = store?.pos_receipt_types?.filter(Boolean) ?? [];
  if (types.length === 0) return [...DEFAULT_POS_RECEIPT_TYPES];
  return types.filter((t): t is PosReceiptTypeId =>
    DEFAULT_POS_RECEIPT_TYPES.includes(t as PosReceiptTypeId),
  );
}

export function effectivePosAutoPrintReceiptTypes(store?: {
  pos_auto_print_receipt_types?: string[] | null;
  pos_receipt_types?: string[] | null;
  pos_receipt_settings_configured?: boolean;
}): PosReceiptTypeId[] {
  const enabled = new Set(effectivePosReceiptTypes(store));
  if (!store?.pos_receipt_settings_configured) {
    return DEFAULT_POS_AUTO_PRINT_RECEIPT_TYPES.filter((t) => enabled.has(t));
  }
  const auto = store?.pos_auto_print_receipt_types?.filter(Boolean) ?? [];
  return auto.filter((t): t is PosReceiptTypeId => enabled.has(t as PosReceiptTypeId));
}
