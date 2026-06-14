import type { Product, Stock } from '../types';
import { normalizeCategory } from './category';
import { formatPerWeightVariantLabel, weightVariantGramsFromProduct } from './productForm';

/** Sale type is exactly one of: quantity or weight (via unit_type). */
export function productIsWeight(product?: Product | null): boolean {
  return (product?.unit_type ?? 'quantity').toLowerCase() === 'weight';
}

export function productIsQuantity(product?: Product | null): boolean {
  return !productIsWeight(product);
}

/** @deprecated use productIsQuantity */
export function productSellByQty(product?: Product | null): boolean {
  return productIsQuantity(product);
}

/** @deprecated use productIsWeight */
export function productSellByWeight(product?: Product | null): boolean {
  return productIsWeight(product);
}

/** Dual qty+weight on one SKU is not supported. */
export function productSupportsDualInventory(_product?: Product | null): boolean {
  return false;
}

const GENERIC_VARIANT_LABELS = new Set(['standard', 'unit', 'weight']);

export type DisplayVariantLabelOptions = {
  /** How many variants share this product line (used to disambiguate unlabeled variants). */
  siblingCount?: number;
  t?: (key: string, options?: Record<string, unknown>) => string;
};

/** User-facing variant label for product lines list. */
export function displayVariantLabel(
  product?: Product | null,
  opts?: DisplayVariantLabelOptions,
): string {
  if (!product) return '—';

  if (productIsWeight(product)) {
    const grams = weightVariantGramsFromProduct(product);
    const perLabel = formatPerWeightVariantLabel(grams);
    if (perLabel) return perLabel;
  }

  const label = (product.variant_label || '').trim();
  if (label && !GENERIC_VARIANT_LABELS.has(label.toLowerCase())) {
    return label;
  }

  const pack = product.units_per_pack || product.wholesale_units_per_box;
  if (pack && pack > 0) {
    const n = Number(pack);
    const pcs = Number.isInteger(n) ? `${n}` : `${pack}`;
    return opts?.t?.('productLines:packPcs', { count: pcs }) ?? `${pcs} pcs`;
  }

  const base = productIsWeight(product)
    ? (opts?.t?.('productLines:looseWeight') ?? 'Loose weight')
    : (opts?.t?.('productLines:eachUnit') ?? 'Each');

  if ((opts?.siblingCount ?? 1) > 1) {
    const sku = product.sku?.trim();
    if (sku) return `${base} · ${sku}`;
    const barcode = productDisplayBarcode(product);
    if (barcode) return `${base} · ${barcode}`;
  }

  return base;
}

export function productVariantLabel(product?: Product | null): string {
  if (!product) return '';
  return (product.variant_label || '').trim();
}

export function productLineName(product?: Product | null): string {
  if (!product) return '';
  return (product.product_line?.name || product.name || '').trim();
}

export function productDisplayBarcode(product?: Product | null): string {
  if (!product) return '';
  if (productIsWeight(product)) {
    return (product.weight_barcode || product.barcode || '').trim();
  }
  return (product.barcode || '').trim();
}

export function effectivePrepackedQuantity(stock?: Stock | null, product?: Product | null): number {
  if (!stock || !productIsQuantity(product)) return 0;
  return stock.quantity ?? 0;
}

export function effectiveWeightQuantityG(stock?: Stock | null, product?: Product | null): number {
  if (!stock || !productIsWeight(product)) return 0;
  return stock.weight_quantity_g ?? stock.quantity ?? 0;
}

export function effectivePrepackWeightG(product?: Product | null): number {
  if (!product) return 0;
  return product.prepack_weight_g ?? 0;
}

export type AggregatedProductStock = {
  quantity: number;
  weight_quantity_g: number;
};

/** Sum stock rows by product (across stores). */
export function aggregateStockByProductId(stockRows: Stock[]): Map<number, AggregatedProductStock> {
  const map = new Map<number, AggregatedProductStock>();
  for (const row of stockRows) {
    const prev = map.get(row.product_id) ?? { quantity: 0, weight_quantity_g: 0 };
    prev.quantity += row.quantity ?? 0;
    prev.weight_quantity_g += row.weight_quantity_g ?? row.quantity ?? 0;
    map.set(row.product_id, prev);
  }
  return map;
}

/** Stock level for a variant row (quantity units or grams). */
export function formatVariantStockLevel(product?: Product | null): string {
  if (!product) return '—';
  if (productIsWeight(product)) {
    const g = product.total_stock_weight_g;
    if (g == null) return '—';
    if (g <= 0) return '0 g';
    return `${g} g`;
  }
  const q = product.total_stock_quantity;
  if (q == null) return '—';
  if (q <= 0) return '0';
  return Number.isInteger(q) ? String(q) : String(q);
}

export function stockLevelValue(stock?: Stock | null, product?: Product | null): number {
  if (!stock || !product) return 0;
  if (productIsWeight(product)) return effectiveWeightQuantityG(stock, product);
  return effectivePrepackedQuantity(stock, product);
}

export function formatStockLevelAtStore(stock?: Stock | null, product?: Product | null): string {
  if (!stock || !product) return '—';
  const value = stockLevelValue(stock, product);
  if (productIsWeight(product)) return `${value} g`;
  return Number.isInteger(value) ? String(value) : String(value);
}

export function stockLevelInputLabel(
  product?: Product | null,
  t?: (key: string) => string,
): string {
  if (productIsWeight(product)) {
    return t?.('stock:weightInventory') ?? 'Weight (g)';
  }
  return t?.('stock:quantityInput') ?? 'Quantity';
}

export function assignmentFlagsForVariant(product?: Product | null): {
  track_prepacked: boolean;
  track_weight: boolean;
} {
  if (productIsWeight(product)) {
    return { track_prepacked: false, track_weight: true };
  }
  return { track_prepacked: true, track_weight: false };
}

export function stockProductLabel(
  product?: Product | null,
  language = 'en',
  t?: (key: string, options?: Record<string, unknown>) => string,
): string {
  if (!product) return '—';
  const line = productLineName(product) || product.name || '';
  const variant = displayVariantLabel(product, { t });
  if (line && variant && variant !== '—' && variant !== line) {
    return `${line} · ${variant}`;
  }
  return line || variant || product.name || '—';
}

/** Lowercase haystack for variant picker search (name, line, barcode, sku). */
export function variantSearchHaystack(
  product?: Product | null,
  t?: (key: string, options?: Record<string, unknown>) => string,
): string {
  if (!product) return '';
  const parts = [
    productLineName(product),
    product.name,
    product.name_chinese,
    product.variant_label,
    displayVariantLabel(product, { t }),
    product.category,
    normalizeCategory(product.category || ''),
    product.product_line?.category,
    normalizeCategory(product.product_line?.category || ''),
    product.product_line?.name_chinese,
    product.barcode,
    product.weight_barcode,
    product.sku,
  ];
  return parts
    .map((p) => (p ?? '').trim())
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}

export function variantPickerOptionLabel(
  product?: Product | null,
  t?: (key: string, options?: Record<string, unknown>) => string,
): string {
  if (!product) return '';
  return displayVariantLabel(product, { t });
}
