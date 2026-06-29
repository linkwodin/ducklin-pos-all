/** Resolve a stored /uploads/... path or absolute URL for use in img src. */
export function resolveAssetUrl(url: string | undefined | null): string {
  const trimmed = (url ?? '').trim();
  if (!trimmed) return '';

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    try {
      const parsed = new URL(trimmed);
      if (parsed.hostname === 'localhost' && typeof window !== 'undefined') {
        const port = parsed.port || (parsed.protocol === 'https:' ? '443' : '80');
        const showPort =
          (parsed.protocol === 'http:' && port !== '80') ||
          (parsed.protocol === 'https:' && port !== '443');
        const host = `${window.location.hostname}${showPort ? `:${port}` : ''}`;
        return `${parsed.protocol}//${host}${parsed.pathname}${parsed.search}`;
      }
      return trimmed;
    } catch {
      return trimmed;
    }
  }

  if (trimmed.startsWith('/')) return trimmed;
  return `/${trimmed}`;
}
