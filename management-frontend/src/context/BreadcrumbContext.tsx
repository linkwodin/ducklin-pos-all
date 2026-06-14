import { createContext, useContext, useState, ReactNode } from 'react';

export type BreadcrumbSegment = { label: string; path?: string };

type BreadcrumbContextType = {
  segments: BreadcrumbSegment[] | null;
  setBreadcrumb: (segments: BreadcrumbSegment[] | null) => void;
};

const BreadcrumbContext = createContext<BreadcrumbContextType | undefined>(undefined);

export function BreadcrumbProvider({ children }: { children: ReactNode }) {
  const [segments, setSegments] = useState<BreadcrumbSegment[] | null>(null);
  return (
    <BreadcrumbContext.Provider value={{ segments, setBreadcrumb: setSegments }}>
      {children}
    </BreadcrumbContext.Provider>
  );
}

export function useBreadcrumb() {
  const ctx = useContext(BreadcrumbContext);
  if (ctx === undefined) throw new Error('useBreadcrumb must be used within BreadcrumbProvider');
  return ctx;
}
