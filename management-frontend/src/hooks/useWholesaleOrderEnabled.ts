import { useCallback, useEffect, useState } from 'react';
import { settingsAPI } from '../services/api';

export const WHOLESALE_SETTINGS_CHANGED_EVENT = 'wholesale-settings-changed';
export const MODULE_SETTINGS_CHANGED_EVENT = 'module-settings-changed';

export function useWholesaleOrderEnabled() {
  const [enabled, setEnabled] = useState(true);
  const [loaded, setLoaded] = useState(false);

  const refresh = useCallback(() => {
    settingsAPI
      .getCompany()
      .then((data) => setEnabled(data.wholesale_order_enabled !== false))
      .catch(() => setEnabled(true))
      .finally(() => setLoaded(true));
  }, []);

  useEffect(() => {
    refresh();
    const onChanged = () => refresh();
    window.addEventListener(WHOLESALE_SETTINGS_CHANGED_EVENT, onChanged);
    window.addEventListener(MODULE_SETTINGS_CHANGED_EVENT, onChanged);
    return () => {
      window.removeEventListener(WHOLESALE_SETTINGS_CHANGED_EVENT, onChanged);
      window.removeEventListener(MODULE_SETTINGS_CHANGED_EVENT, onChanged);
    };
  }, [refresh]);

  return { enabled, loaded, refresh };
}

export function usePosModuleEnabled() {
  const [enabled, setEnabled] = useState(true);
  const [loaded, setLoaded] = useState(false);

  const refresh = useCallback(() => {
    settingsAPI
      .getCompany()
      .then((data) => setEnabled(data.pos_module_enabled !== false))
      .catch(() => setEnabled(true))
      .finally(() => setLoaded(true));
  }, []);

  useEffect(() => {
    refresh();
    const onChanged = () => refresh();
    window.addEventListener(MODULE_SETTINGS_CHANGED_EVENT, onChanged);
    window.addEventListener(WHOLESALE_SETTINGS_CHANGED_EVENT, onChanged);
    return () => {
      window.removeEventListener(MODULE_SETTINGS_CHANGED_EVENT, onChanged);
      window.removeEventListener(WHOLESALE_SETTINGS_CHANGED_EVENT, onChanged);
    };
  }, [refresh]);

  return { enabled, loaded, refresh };
}
