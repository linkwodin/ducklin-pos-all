// Invisible / zero-width chars that can make two strings look the same but compare different
const INVISIBLE_RE = /[\u200B-\u200D\u2060\uFEFF\u00AD]/g;

/**
 * Normalize category for grouping/sorting: trim, NFKC, remove invisible chars
 * so duplicate-looking names (spaces, full‑width, compatibility variants) merge as one.
 */
export function normalizeCategory(c: string): string {
  if (c == null) return '';
  let s = String(c)
    .replace(/\s+/g, ' ')
    .trim()
    .replace(INVISIBLE_RE, '');
  s = s ? s.normalize('NFKC') : '';
  return s.trim();
}
