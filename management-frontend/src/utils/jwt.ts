export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const json = atob(base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '='));
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function tokenExpiresAtMs(token: string): number | null {
  const payload = decodeJwtPayload(token);
  const exp = payload?.exp;
  if (typeof exp === 'number') return exp * 1000;
  return null;
}

export function tokenExpiresWithin(token: string, withinMs: number): boolean {
  const exp = tokenExpiresAtMs(token);
  if (exp == null) return true;
  return exp - Date.now() <= withinMs;
}

export function isTokenExpired(token: string): boolean {
  const exp = tokenExpiresAtMs(token);
  if (exp == null) return true;
  return Date.now() >= exp;
}
