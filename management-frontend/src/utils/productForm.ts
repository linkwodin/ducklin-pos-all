import type { Product, ProductLine } from '../types';

const WEIGHT_GRAMS_PATTERN = /^\d+(\.\d+)?$/;

export function sanitizeWeightVariantGramsInput(raw: string): string {
  return raw.replace(/[^\d.]/g, '');
}

/** Grams stored in variant_label (weight) or derived from price/prepack weight. */
export function weightVariantGramsFromProduct(product: Product): string {
  const label = (product.variant_label || '').trim();
  if (WEIGHT_GRAMS_PATTERN.test(label)) return label;
  const pw = product.price_weight_g;
  if (pw != null && pw > 0) {
    return Number.isInteger(pw) ? String(pw) : String(pw);
  }
  const pp = product.prepack_weight_g;
  if (pp != null && pp > 0) {
    return Number.isInteger(pp) ? String(pp) : String(pp);
  }
  return '';
}

export function formatPerWeightVariantLabel(grams: string): string {
  const trimmed = grams.trim();
  if (!trimmed || !WEIGHT_GRAMS_PATTERN.test(trimmed)) return '';
  const n = parseFloat(trimmed);
  const display = Number.isInteger(n) ? String(n) : String(n);
  return `per ${display}g`;
}

export type VariantRowEdit = {
  unit_type: 'quantity' | 'weight';
  variant_label: string;
  barcode: string;
  sku: string;
  retail_price: string;
};

export type NewVariantDraft = Omit<VariantRowEdit, 'unit_type'> & { unit_type: UnitTypeChoice };

export function emptyNewVariantDraft(): NewVariantDraft {
  return {
    unit_type: '',
    variant_label: '',
    barcode: '',
    sku: '',
    retail_price: '',
  };
}

export function variantRowFromProduct(product: Product): VariantRowEdit {
  return {
    unit_type: product.unit_type === 'weight' ? 'weight' : 'quantity',
    variant_label:
      product.unit_type === 'weight'
        ? weightVariantGramsFromProduct(product)
        : product.variant_label || '',
    barcode:
      product.unit_type === 'weight'
        ? product.weight_barcode || product.barcode || ''
        : product.barcode || '',
    sku: product.sku || '',
    retail_price:
      product.current_cost?.direct_retail_online_store_price_gbp != null
        ? String(product.current_cost.direct_retail_online_store_price_gbp)
        : '',
  };
}

export function variantRowsFromProducts(products: Product[]): Record<number, VariantRowEdit> {
  const rows: Record<number, VariantRowEdit> = {};
  for (const product of products) {
    rows[product.id] = variantRowFromProduct(product);
  }
  return rows;
}

export type UnitTypeChoice = 'quantity' | 'weight' | '';

export type ProductFormData = {
  lineName: string;
  name_chinese: string;
  barcode: string;
  sku: string;
  category: string;
  unit_type: UnitTypeChoice;
  variant_label: string;
  units_per_pack: string;
  wholesale_units_per_box: string;
  selling_weight_g: string;
};

export function isSaleTypeSelected(unitType: UnitTypeChoice): unitType is 'quantity' | 'weight' {
  return unitType === 'quantity' || unitType === 'weight';
}

export function lineHasWeightVariant(
  line: ProductLine | null | undefined,
  excludeProductId?: number,
): boolean {
  return (line?.variants ?? []).some(
    (v) => v.unit_type === 'weight' && v.is_active !== false && v.id !== excludeProductId,
  );
}

export function resolveLineWithVariants(
  line: ProductLine | null | undefined,
  productLines: ProductLine[],
): ProductLine | null {
  if (!line) return null;
  return productLines.find((l) => l.id === line.id) ?? line;
}

export function productToFormData(product: Product): ProductFormData {
  return {
    lineName: product.product_line?.name || product.name || '',
    name_chinese: product.name_chinese || '',
    barcode:
      product.unit_type === 'weight'
        ? (product.weight_barcode || product.barcode || '')
        : (product.barcode || ''),
    sku: product.sku || '',
    category: product.category || product.product_line?.category || '',
    unit_type: product.unit_type === 'weight' ? 'weight' : 'quantity',
    variant_label:
      product.unit_type === 'weight'
        ? weightVariantGramsFromProduct(product)
        : product.variant_label || '',
    units_per_pack: product.units_per_pack ? String(product.units_per_pack) : '',
    wholesale_units_per_box: product.wholesale_units_per_box
      ? String(product.wholesale_units_per_box)
      : '',
    selling_weight_g:
      product.prepack_weight_g && product.prepack_weight_g > 0
        ? String(product.prepack_weight_g)
        : product.price_weight_g && product.price_weight_g > 0
          ? String(product.price_weight_g)
          : '',
  };
}

export function resolveSelectedLine(product: Product, lines: ProductLine[]): ProductLine | null {
  if (product.product_line) return product.product_line;
  if (product.product_line_id) {
    return lines.find((l) => l.id === product.product_line_id) ?? null;
  }
  return null;
}

export function validateProductForm(
  formData: ProductFormData,
  selectedLine: ProductLine | null,
): string | null {
  if (!selectedLine && !formData.lineName.trim()) {
    return 'lineNameRequired';
  }
  if (!isSaleTypeSelected(formData.unit_type)) {
    return 'saleTypeRequired';
  }
  if (!formData.barcode.trim()) {
    return 'barcodeRequired';
  }
  return null;
}

export function buildProductPayload(
  formData: ProductFormData,
  selectedLine: ProductLine | null,
): Partial<Product> & Record<string, unknown> {
  if (!isSaleTypeSelected(formData.unit_type)) {
    throw new Error('sale type is required');
  }
  const payload: Partial<Product> & Record<string, unknown> = {
    name_chinese: formData.name_chinese,
    sku: formData.sku,
    category: formData.category,
    unit_type: formData.unit_type,
    variant_label:
      formData.unit_type === 'weight'
        ? sanitizeWeightVariantGramsInput(formData.variant_label).trim()
        : formData.variant_label.trim(),
    units_per_pack:
      formData.unit_type === 'weight'
        ? 0
        : formData.units_per_pack.trim()
          ? parseFloat(formData.units_per_pack)
          : 0,
    wholesale_units_per_box: formData.wholesale_units_per_box.trim()
      ? parseFloat(formData.wholesale_units_per_box)
      : 0,
    product_line_id: selectedLine?.id,
    name: selectedLine?.name || formData.lineName.trim(),
  };
  const barcode = formData.barcode.trim();
  if (formData.unit_type === 'quantity') {
    payload.barcode = barcode;
  } else {
    payload.weight_barcode = barcode;
    const gramsStr = sanitizeWeightVariantGramsInput(formData.variant_label).trim();
    if (gramsStr) {
      const grams = parseFloat(gramsStr);
      payload.prepack_weight_g = grams;
      payload.price_weight_g = grams;
    } else if (formData.selling_weight_g.trim()) {
      const grams = parseFloat(formData.selling_weight_g);
      payload.prepack_weight_g = grams;
      payload.price_weight_g = grams;
    }
  }
  return payload;
}

export function appendProductFormToFormData(fd: FormData, formData: ProductFormData, selectedLine: ProductLine | null) {
  fd.append('unit_type', formData.unit_type);
  if (selectedLine) {
    fd.append('product_line_id', String(selectedLine.id));
    fd.append('name', selectedLine.name);
  } else {
    fd.append('name', formData.lineName.trim());
  }
  fd.append(
    'variant_label',
    formData.unit_type === 'weight'
      ? sanitizeWeightVariantGramsInput(formData.variant_label).trim()
      : formData.variant_label.trim(),
  );
  if (formData.unit_type === 'quantity' && formData.units_per_pack.trim()) {
    fd.append('units_per_pack', formData.units_per_pack.trim());
  }
  if (formData.wholesale_units_per_box.trim()) {
    fd.append('wholesale_units_per_box', formData.wholesale_units_per_box.trim());
  }
  const barcode = formData.barcode.trim();
  if (formData.unit_type === 'quantity') {
    fd.append('barcode', barcode);
  } else {
    fd.append('weight_barcode', barcode);
    const gramsStr = sanitizeWeightVariantGramsInput(formData.variant_label).trim();
    if (gramsStr) {
      fd.append('selling_weight_g', gramsStr);
    } else if (formData.selling_weight_g.trim()) {
      fd.append('selling_weight_g', formData.selling_weight_g.trim());
    }
  }
}
