import JsBarcode from 'jsbarcode';

/** GTIN-13 check digit for the first 12 digits (returns 0–9). */
export function ean13CheckDigit(first12: string): number {
  if (!/^\d{12}$/.test(first12)) return -1;
  let sum = 0;
  for (let i = 0; i < 12; i++) {
    const digit = first12.charCodeAt(i) - 48;
    sum += i % 2 === 0 ? digit : digit * 3;
  }
  return (10 - (sum % 10)) % 10;
}

export function isValidEan13(code: string): boolean {
  if (!/^\d{13}$/.test(code)) return false;
  return ean13CheckDigit(code.slice(0, 12)) === Number(code[12]);
}

function detectFormat(code: string): string {
  if (/^\d{13}$/.test(code) && isValidEan13(code)) return 'EAN13';
  if (/^\d{8}$/.test(code)) return 'EAN8';
  if (/^\d{12}$/.test(code)) return 'UPC';
  return 'CODE128';
}

export type RenderBarcodeOptions = JsBarcode.Options & {
  /** Use one symbology (Code 128) for all codes — consistent layout on reference sheets. */
  uniformCode128?: boolean;
};

export function renderBarcodeSvg(
  code: string,
  options?: RenderBarcodeOptions,
): string | null {
  const value = code.trim();
  if (!value || typeof document === 'undefined') return null;

  const { uniformCode128, ...barcodeOptions } = options ?? {};

  const base: JsBarcode.Options = {
    displayValue: true,
    fontSize: 11,
    height: 42,
    margin: 4,
    width: 1.4,
    ...barcodeOptions,
  };

  const tryRender = (format: string) => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    JsBarcode(svg, value, { ...base, format });
    return new XMLSerializer().serializeToString(svg);
  };

  const format = uniformCode128 ? 'CODE128' : detectFormat(value);

  try {
    return tryRender(format);
  } catch {
    try {
      return tryRender('CODE128');
    } catch {
      return null;
    }
  }
}

export type ProductBarcodeEntry = {
  code: string;
  kind: 'qty' | 'weight';
};

export function productBarcodeEntries(product: {
  barcode?: string;
  weight_barcode?: string;
}): ProductBarcodeEntry[] {
  const entries: ProductBarcodeEntry[] = [];
  const qty = product.barcode?.trim();
  const weight = product.weight_barcode?.trim();
  if (qty) entries.push({ code: qty, kind: 'qty' });
  if (weight && weight !== qty) entries.push({ code: weight, kind: 'weight' });
  return entries;
}

export function categorySortKey(category?: string): string {
  const trimmed = category?.trim();
  return trimmed || '\uFFFF';
}
