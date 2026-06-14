/** Digits only from a product barcode string. */
export function barcodeDigitsOnly(barcode?: string): string {
  return (barcode ?? '').replace(/\D/g, '');
}

/** Prefix used on weight receipt barcodes (explicit or last 8 digits of product barcode). */
export function effectiveWeightBarcodePrefix(
  prefix?: string,
  productBarcode?: string,
): string {
  const p = (prefix ?? '').trim();
  if (/^\d{1,8}$/.test(p)) return p;
  const digits = barcodeDigitsOnly(productBarcode);
  if (!digits) return '';
  return digits.length <= 8 ? digits : digits.slice(-8);
}

export function weightProductNeedsPrefixWarning(
  unitType: string | undefined,
  prefix?: string,
): boolean {
  return unitType === 'weight' && !(prefix ?? '').trim();
}

export function normalizePrefixScan(scanned: string): string | null {
  const digits = scanned.replace(/\D/g, '');
  if (!digits || digits.length > 8) return null;
  return digits.padStart(8, '0');
}

export function parseReceiptBarcode(scanned: string): { prefix: string; weightGrams: number } | null {
  const digits = scanned.replace(/\D/g, '');
  if (digits.length < 13) return null;
  const prefix = digits.substring(0, 8);
  const weightPart = digits.substring(8, 12);
  const weightHundredthsKg = parseInt(weightPart, 10);
  if (!Number.isFinite(weightHundredthsKg) || weightHundredthsKg <= 0) return null;
  const weightGrams = weightHundredthsKg * 10;
  return { prefix, weightGrams };
}

export function resolveWeightBarcodePrefix(prefix?: string, productBarcode?: string): string | null {
  const p = (prefix ?? '').trim();
  if (p) {
    if (!/^\d{1,8}$/.test(p)) return null;
    return p;
  }
  const digits = barcodeDigitsOnly(productBarcode);
  if (!digits) return null;
  if (digits.length <= 8) return digits;
  return digits.slice(-8);
}

export function effectivePrefixForProduct(product: {
  weight_barcode_prefix?: string;
  weight_barcode?: string;
  barcode?: string;
}): string | null {
  const explicit = product.weight_barcode_prefix?.trim();
  if (explicit) {
    const resolved = resolveWeightBarcodePrefix(explicit);
    return resolved?.padStart(8, '0') ?? null;
  }
  const weightBarcode = product.weight_barcode?.trim();
  if (weightBarcode) {
    const resolved = resolveWeightBarcodePrefix('', weightBarcode);
    return resolved?.padStart(8, '0') ?? null;
  }
  const resolved = resolveWeightBarcodePrefix('', product.barcode);
  return resolved?.padStart(8, '0') ?? null;
}
