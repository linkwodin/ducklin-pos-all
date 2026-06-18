import type { Product } from '../types';
import type { ShipmentPackingLine } from './shipmentPacking';
import {
  barcodeDigitsOnly,
  effectivePrefixForProduct,
  normalizePrefixScan,
  parseReceiptBarcode,
} from './weightBarcode';
import {
  productIsWeight,
  productSellByQty,
  productSellByWeight,
} from './productInventory';

export type ScannedProduct = Product & {
  _scan_mode?: 'qty' | 'weight';
  _parsed_weight_g?: number;
  _sale_mode_blocked?: boolean;
};

export function normalizeBarcodeScanInput(raw: string): string {
  return raw.trim().replace(/[\r\n\t]/g, '');
}

export function barcodesMatchForLookup(stored: string, scanned: string): boolean {
  const a = barcodeDigitsOnly(stored);
  const b = barcodeDigitsOnly(scanned);
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.length === 13 && b.length === 13 && a.substring(0, 12) === b.substring(0, 12)) {
    return true;
  }
  if (a.length === 13 && b.length === 12 && a.startsWith('0') && a.substring(1) === b) {
    return true;
  }
  if (b.length === 13 && a.length === 12 && b.startsWith('0') && b.substring(1) === a) {
    return true;
  }
  return false;
}

function storedQtyBarcodes(product: Product): string[] {
  return [product.barcode, product.sku]
    .map((v) => v?.trim())
    .filter((v): v is string => !!v);
}

function storedWeightBarcodes(product: Product): string[] {
  return [product.weight_barcode, product.weight_barcode_prefix]
    .map((v) => v?.trim())
    .filter((v): v is string => !!v);
}

function shortScanDigits(code: string): string | null {
  const digits = barcodeDigitsOnly(code);
  if (digits.length >= 6 && digits.length <= 8) return digits;
  return null;
}

function suffixDigitsMatch(storedFull: string, shortDigits: string): boolean {
  const full = barcodeDigitsOnly(storedFull);
  if (!full || !shortDigits) return false;
  return full === shortDigits || full.endsWith(shortDigits);
}

function oneDigitApart(a: string, b: string): boolean {
  if (a.length !== b.length || a.length < 6) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      diff++;
      if (diff > 1) return false;
    }
  }
  return diff === 1;
}

function shortQtySuffixMatch(shortDigits: string, products: Product[]): ScannedProduct | null {
  let hit: Product | null = null;
  for (const product of products) {
    if (!productSellByQty(product)) continue;
    const barcode = product.barcode?.trim();
    if (!barcode || !suffixDigitsMatch(barcode, shortDigits)) continue;
    if (hit) return null;
    hit = product;
  }
  return hit ? { ...hit, _scan_mode: 'qty' } : null;
}

function fuzzyShortWeightMatch(shortDigits: string, products: Product[]): ScannedProduct | null {
  if (shortDigits.length < 6) return null;
  let hit: Product | null = null;
  for (const product of products) {
    if (!productSellByWeight(product)) continue;
    const productMatched = storedWeightBarcodes(product).some((stored) => {
      const digits = barcodeDigitsOnly(stored);
      return (
        !!digits &&
        digits.length === shortDigits.length &&
        oneDigitApart(digits, shortDigits)
      );
    });
    if (!productMatched) continue;
    if (hit) return null;
    hit = product;
  }
  return hit ? { ...hit, _scan_mode: 'weight' } : null;
}

function fuzzyShortQtyMatch(shortDigits: string, products: Product[]): ScannedProduct | null {
  if (shortDigits.length < 7) return null;
  let hit: Product | null = null;
  for (const product of products) {
    if (!productSellByQty(product)) continue;
    const full = barcodeDigitsOnly(product.barcode);
    if (full.length < 7) continue;
    const suffix = full.substring(full.length - 7);
    if (!oneDigitApart(suffix, shortDigits)) continue;
    if (hit) return null;
    hit = product;
  }
  return hit ? { ...hit, _scan_mode: 'qty' } : null;
}

function exactQtyProductMatch(code: string, product: Product): ScannedProduct | null {
  if (!productSellByQty(product)) return null;
  for (const stored of storedQtyBarcodes(product)) {
    if (barcodesMatchForLookup(stored, code)) {
      return { ...product, _scan_mode: 'qty' };
    }
  }
  return null;
}

function exactWeightProductMatch(code: string, product: Product): ScannedProduct | null {
  if (!productSellByWeight(product)) return null;
  for (const stored of storedWeightBarcodes(product)) {
    if (barcodesMatchForLookup(stored, code)) {
      return { ...product, _scan_mode: 'weight' };
    }
  }
  const qty = product.barcode?.trim();
  if (qty && barcodesMatchForLookup(qty, code)) {
    return { ...product, _scan_mode: 'weight' };
  }
  const legacyWeightOnly =
    productIsWeight(product) &&
    product.sell_by_qty !== true &&
    (product.sell_by_weight == null || product.sell_by_weight === false);
  if (legacyWeightOnly && qty && barcodesMatchForLookup(qty, code)) {
    return { ...product, _scan_mode: 'weight' };
  }
  return null;
}

export function resolveProductScanFromList(
  barcode: string,
  products: Product[],
): ScannedProduct | null {
  const code = normalizeBarcodeScanInput(barcode);
  if (!code) return null;

  // 1) Quantity products: full EAN / SKU exact match.
  for (const product of products) {
    const hit = exactQtyProductMatch(code, product);
    if (hit) return hit;
  }

  // 2) Weight products: weight barcode / prefix exact match.
  for (const product of products) {
    const hit = exactWeightProductMatch(code, product);
    if (hit) return hit;
  }

  const shortDigits = shortScanDigits(code);
  if (shortDigits) {
    const suffixHit = shortQtySuffixMatch(shortDigits, products);
    if (suffixHit) return suffixHit;
    const fuzzyWeightHit = fuzzyShortWeightMatch(shortDigits, products);
    if (fuzzyWeightHit) return fuzzyWeightHit;
    const fuzzyQtyHit = fuzzyShortQtyMatch(shortDigits, products);
    if (fuzzyQtyHit) return fuzzyQtyHit;
  }

  // 3) Weight-only products blocked from qty sale still resolve for visibility.
  for (const product of products) {
    const qty = product.barcode?.trim();
    if (qty && barcodesMatchForLookup(qty, code)) {
      return { ...product, _scan_mode: 'qty', _sale_mode_blocked: true };
    }
    const weight = product.weight_barcode?.trim();
    if (weight && barcodesMatchForLookup(weight, code)) {
      return { ...product, _scan_mode: 'weight', _sale_mode_blocked: true };
    }
  }

  // 4) Receipt / prefix barcodes — weight products only (skip if code is exact qty barcode above).
  const parsed = parseReceiptBarcode(code);
  if (parsed) {
    for (const product of products) {
      if (!productSellByWeight(product)) continue;
      const productPrefix = effectivePrefixForProduct(product);
      if (productPrefix && productPrefix === parsed.prefix) {
        return { ...product, _scan_mode: 'weight', _parsed_weight_g: parsed.weightGrams };
      }
    }
  }

  const normalizedPrefix = normalizePrefixScan(code);
  if (normalizedPrefix) {
    for (const product of products) {
      if (!productSellByWeight(product)) continue;
      const productPrefix = effectivePrefixForProduct(product);
      if (productPrefix && productPrefix === normalizedPrefix) {
        return { ...product, _scan_mode: 'weight' };
      }
    }
  }

  return null;
}

function pickNonEmpty(...values: (string | undefined | null)[]): string | undefined {
  for (const value of values) {
    const trimmed = value?.trim();
    if (trimmed) return trimmed;
  }
  return undefined;
}

function mergeLineProduct(line: ShipmentPackingLine, catalog?: Product): Product {
  if (!catalog) return line.product;
  return {
    ...catalog,
    ...line.product,
    barcode: pickNonEmpty(catalog.barcode, line.product.barcode),
    sku: pickNonEmpty(catalog.sku, line.product.sku),
    weight_barcode: pickNonEmpty(catalog.weight_barcode, line.product.weight_barcode),
    weight_barcode_prefix: pickNonEmpty(catalog.weight_barcode_prefix, line.product.weight_barcode_prefix),
    product_line_id: line.product.product_line_id ?? catalog.product_line_id,
    product_line: line.product.product_line ?? catalog.product_line,
    unit_type: line.product.unit_type ?? catalog.unit_type,
    sell_by_qty: line.product.sell_by_qty ?? catalog.sell_by_qty,
    sell_by_weight: line.product.sell_by_weight ?? catalog.sell_by_weight,
  };
}

/** Barcodes accepted during packing: exact match only (check-digit tolerant via barcodesMatchForLookup). */
function storedBarcodesForPacking(product: Product): string[] {
  return [product.barcode, product.sku]
    .map((v) => v?.trim())
    .filter((v): v is string => !!v);
}

/** Map a catalog barcode hit to the shipment line with the same product id only. */
function mapCatalogBarcodeToPackingLine(
  code: string,
  packingLines: ShipmentPackingLine[],
  lineProducts: Product[],
  catalog: Product[],
): ScannedProduct | null {
  const catalogHits = catalog.filter((product) =>
    storedBarcodesForPacking(product).some((stored) => barcodesMatchForLookup(stored, code)),
  );
  if (catalogHits.length === 0) return null;

  for (const hit of catalogHits) {
    const directIdx = packingLines.findIndex((line) => line.productId === hit.id);
    if (directIdx >= 0) {
      return { ...lineProducts[directIdx]!, _scan_mode: 'qty' };
    }
  }

  return null;
}

/** Resolve a scan only to products on this shipment (exact barcode match only). */
export function resolveProductScanForPacking(
  barcode: string,
  packingLines: ShipmentPackingLine[],
  catalog: Product[],
): ScannedProduct | null {
  if (packingLines.length === 0) return null;
  const code = normalizeBarcodeScanInput(barcode);
  if (!code) return null;

  const catalogById = new Map(catalog.map((p) => [p.id, p]));
  const lineProducts = packingLines.map((line) => mergeLineProduct(line, catalogById.get(line.productId)));

  for (let i = 0; i < packingLines.length; i++) {
    const product = lineProducts[i]!;
    for (const stored of storedBarcodesForPacking(product)) {
      if (barcodesMatchForLookup(stored, code)) {
        return { ...product, _scan_mode: 'qty' };
      }
    }
  }

  return mapCatalogBarcodeToPackingLine(code, packingLines, lineProducts, catalog);
}

export function scanIsWeightMode(product: ScannedProduct): boolean {
  return product._scan_mode === 'weight';
}

/** Weight dialog during packing: only for receipt/prefix scans, never exact product barcodes. */
export function shouldPromptWeightForPackingScan(product: ScannedProduct): boolean {
  return product._scan_mode === 'weight';
}

/** Units to add per scan in wholesale packing (always count boxes/units, not scale grams). */
export function packingScanDelta(product: Product, _scanned: ScannedProduct): number {
  return 1;
}

export function shouldPromptWeightForScan(product: ScannedProduct): boolean {
  return scanIsWeightMode(product) && productIsWeight(product);
}

export function productIsLegacyWeightOnly(product: Product): boolean {
  return productIsWeight(product);
}

export function parsedWeightGramsFromScan(product: ScannedProduct): number | null {
  const v = product._parsed_weight_g;
  return v != null && v > 0 ? v : null;
}
