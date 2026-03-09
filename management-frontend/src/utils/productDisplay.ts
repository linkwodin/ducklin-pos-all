import type { Product } from '../types';

/**
 * Returns product name for display: Chinese name when language is zh, otherwise primary name.
 * Falls back to the other name if the preferred one is empty.
 */
export function productDisplayName(
  product: { name?: string; name_chinese?: string } | null | undefined,
  language: string
): string {
  if (!product) return '—';
  const name = product.name ?? '';
  const nameZh = product.name_chinese ?? '';
  const useChinese = language.startsWith('zh');
  if (useChinese && nameZh) return nameZh;
  if (name) return name;
  return nameZh || '—';
}
