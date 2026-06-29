import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from 'react';
import { settingsAPI } from '../services/api';
import { resolveAssetUrl } from '../utils/assetUrl';

const FALLBACK_LOGO = '/logo.png';

type BrandingContextValue = {
  companyName: string;
  logoSrc: string;
  loaded: boolean;
  fallbackLogo: string;
  refreshBranding: () => Promise<void>;
};

const BrandingContext = createContext<BrandingContextValue | null>(null);

function cacheBustUrl(url: string): string {
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}v=${Date.now()}`;
}

export function BrandingProvider({ children }: { children: ReactNode }) {
  const [companyName, setCompanyName] = useState('');
  const [logoSrc, setLogoSrc] = useState(FALLBACK_LOGO);
  const [loaded, setLoaded] = useState(false);

  const refreshBranding = useCallback(async () => {
    try {
      const data = await settingsAPI.getPublicBranding();
      setCompanyName(data.company_name?.trim() ?? '');
      const raw = data.web_logo_url || data.logo_url;
      const resolved = resolveAssetUrl(raw);
      setLogoSrc(resolved ? cacheBustUrl(resolved) : FALLBACK_LOGO);
    } catch {
      setLogoSrc(FALLBACK_LOGO);
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    refreshBranding();
  }, [refreshBranding]);

  return (
    <BrandingContext.Provider
      value={{
        companyName,
        logoSrc,
        loaded,
        fallbackLogo: FALLBACK_LOGO,
        refreshBranding,
      }}
    >
      {children}
    </BrandingContext.Provider>
  );
}

export function useBrandingContext(): BrandingContextValue {
  const ctx = useContext(BrandingContext);
  if (!ctx) {
    throw new Error('useBrandingContext must be used within BrandingProvider');
  }
  return ctx;
}
