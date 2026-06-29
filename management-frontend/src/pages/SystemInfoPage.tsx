import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  Paper,
  Switch,
  Table,
  TableBody,
  TableCell,
  TableRow,
  TextField,
  Typography,
} from '@mui/material';
import { ContentCopy as ContentCopyIcon } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { settingsAPI } from '../services/api';
import type { CompanySettings } from '../types';
import { WHOLESALE_SETTINGS_CHANGED_EVENT, MODULE_SETTINGS_CHANGED_EVENT } from '../hooks/useWholesaleOrderEnabled';

const FRONTEND_VERSION = import.meta.env.VITE_APP_VERSION ?? '—';

type SystemInfo = {
  backend_version: string;
  backend_build_date?: string;
  installation_id: string;
};

type FeatureModule = 'wholesale' | 'pos';

type PendingActivation = FeatureModule | null;

export default function SystemInfoPage() {
  const { t } = useTranslation('systemInfo');
  const { enqueueSnackbar } = useSnackbar();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [loading, setLoading] = useState(true);
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [settings, setSettings] = useState<CompanySettings | null>(null);
  const [activationDialogOpen, setActivationDialogOpen] = useState(false);
  const [pendingActivation, setPendingActivation] = useState<PendingActivation>(null);
  const [activationCode, setActivationCode] = useState('');
  const [activationSubmitting, setActivationSubmitting] = useState(false);
  const handledQueryRef = useRef(false);

  const loadData = useCallback(async () => {
    const [systemInfo, company] = await Promise.all([
      settingsAPI.getSystemInfo(),
      settingsAPI.getCompany(),
    ]);
    setInfo(systemInfo);
    setSettings(company);
  }, []);

  useEffect(() => {
    loadData()
      .catch(() => enqueueSnackbar(t('loadFailed'), { variant: 'error' }))
      .finally(() => setLoading(false));
  }, [enqueueSnackbar, loadData, t]);

  const wholesaleEnabled = settings?.wholesale_order_enabled !== false;
  const posEnabled = settings?.pos_module_enabled !== false;
  const needsWholesaleSerial = !settings?.wholesale_serial_activated;
  const needsPosSerial = !settings?.pos_dlc_activated;

  const companySettingsHash = (module: FeatureModule) => (
    module === 'wholesale' ? 'wholesale-order' : 'pos-module'
  );

  const openActivationDialog = (module: FeatureModule) => {
    setPendingActivation(module);
    setActivationCode('');
    setActivationDialogOpen(true);
  };

  const handleFeatureSwitch = (module: FeatureModule, currentlyEnabled: boolean) => {
    const needsSerial = module === 'wholesale' ? needsWholesaleSerial : needsPosSerial;
    if (!currentlyEnabled && needsSerial) {
      openActivationDialog(module);
      return;
    }
    navigate(`/company-settings#${companySettingsHash(module)}`);
  };

  useEffect(() => {
    if (loading || !settings || handledQueryRef.current) return;
    const module = searchParams.get('module');
    const action = searchParams.get('action');
    if (module !== 'wholesale' && module !== 'pos') return;
    if (action !== 'enable') return;

    handledQueryRef.current = true;
    setSearchParams({}, { replace: true });

    const needsSerial = module === 'wholesale' ? needsWholesaleSerial : needsPosSerial;
    if (needsSerial) {
      openActivationDialog(module);
      const sectionId = module === 'wholesale' ? 'feature-wholesale' : 'feature-pos';
      window.requestAnimationFrame(() => {
        document.getElementById(sectionId)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      });
      return;
    }
    navigate(`/company-settings#${companySettingsHash(module)}`);
  }, [loading, navigate, needsPosSerial, needsWholesaleSerial, searchParams, setSearchParams, settings]);

  const copyText = async (label: string, value: string) => {
    try {
      await navigator.clipboard.writeText(value);
      enqueueSnackbar(t('copied', { label }), { variant: 'success' });
    } catch {
      enqueueSnackbar(t('copyFailed'), { variant: 'error' });
    }
  };

  const handleConfirmActivation = async () => {
    if (!pendingActivation) return;
    try {
      setActivationSubmitting(true);
      const body = {
        enabled: true,
        product_serial_code: activationCode,
      };
      const updated = pendingActivation === 'wholesale'
        ? await settingsAPI.toggleWholesaleOrder(body)
        : await settingsAPI.togglePosModule(body);
      setSettings(updated);
      setActivationDialogOpen(false);
      if (pendingActivation === 'wholesale') {
        window.dispatchEvent(new Event(WHOLESALE_SETTINGS_CHANGED_EVENT));
        enqueueSnackbar(t('wholesaleEnableSuccess'), { variant: 'success' });
      } else {
        window.dispatchEvent(new Event(MODULE_SETTINGS_CHANGED_EVENT));
        enqueueSnackbar(t('posEnableSuccess'), { variant: 'success' });
      }
    } catch (err: any) {
      const fallback = pendingActivation === 'wholesale'
        ? t('wholesaleToggleFailed')
        : t('posToggleFailed');
      enqueueSnackbar(err.response?.data?.error || fallback, { variant: 'error' });
    } finally {
      setActivationSubmitting(false);
    }
  };

  const activationDialogTitle = pendingActivation === 'wholesale'
    ? t('wholesaleEnableTitle')
    : t('posEnableTitle');

  const activationDialogHint = pendingActivation === 'wholesale'
    ? t('wholesaleEnableSerialHint')
    : t('posEnableSerialHint');

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: 300 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!info || !settings) {
    return null;
  }

  const rows: { label: string; value: string; copyable?: boolean }[] = [
    { label: t('frontendVersion'), value: FRONTEND_VERSION },
    { label: t('backendVersion'), value: info.backend_version || '—' },
    {
      label: t('backendBuildDate'),
      value: info.backend_build_date?.trim() || '—',
    },
    {
      label: t('installationId'),
      value: info.installation_id || '—',
      copyable: true,
    },
  ];

  return (
    <Box sx={{ p: 3, maxWidth: 900 }}>
      <Typography variant="h5" sx={{ mb: 1 }}>{t('title')}</Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
        {t('subtitle')}
      </Typography>

      <Paper sx={{ p: 2, mb: 3 }}>
        <Table size="small">
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.label}>
                <TableCell sx={{ width: 220, fontWeight: 600, borderBottom: '1px solid', borderColor: 'divider' }}>
                  {row.label}
                </TableCell>
                <TableCell sx={{ fontFamily: row.copyable ? 'monospace' : 'inherit', borderBottom: '1px solid', borderColor: 'divider' }}>
                  {row.value}
                </TableCell>
                <TableCell align="right" sx={{ width: 120, borderBottom: '1px solid', borderColor: 'divider' }}>
                  {row.copyable && row.value !== '—' ? (
                    <Button
                      size="small"
                      startIcon={<ContentCopyIcon />}
                      onClick={() => copyText(row.label, row.value)}
                    >
                      {t('copy')}
                    </Button>
                  ) : null}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Paper>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {t('featuresHint')}
      </Typography>

      <Typography variant="h6" sx={{ mb: 2 }}>{t('featuresTitle')}</Typography>

      <Paper id="feature-wholesale" sx={{ p: 3, mb: 2 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap' }}>
          <Box>
            <Typography variant="subtitle1">{t('wholesaleModule')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {t('wholesaleModuleSubtitle')}
            </Typography>
            {needsWholesaleSerial ? (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('activationOnThisPageHint')}
              </Typography>
            ) : (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('manageOnCompanySettingsHint')}
              </Typography>
            )}
          </Box>
          <FormControlLabel
            control={
              <Switch
                checked={wholesaleEnabled}
                onClick={(e) => {
                  e.preventDefault();
                  handleFeatureSwitch('wholesale', wholesaleEnabled);
                }}
              />
            }
            label={wholesaleEnabled ? t('moduleEnabled') : t('moduleDisabled')}
            sx={{ m: 0 }}
          />
        </Box>
      </Paper>

      <Paper id="feature-pos" sx={{ p: 3 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap' }}>
          <Box>
            <Typography variant="subtitle1">{t('posModule')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {t('posModuleSubtitle')}
            </Typography>
            {needsPosSerial ? (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('activationOnThisPageHint')}
              </Typography>
            ) : (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('manageOnCompanySettingsHint')}
              </Typography>
            )}
          </Box>
          <FormControlLabel
            control={
              <Switch
                checked={posEnabled}
                onClick={(e) => {
                  e.preventDefault();
                  handleFeatureSwitch('pos', posEnabled);
                }}
              />
            }
            label={posEnabled ? t('moduleEnabled') : t('moduleDisabled')}
            sx={{ m: 0 }}
          />
        </Box>
      </Paper>

      <Dialog open={activationDialogOpen} onClose={() => !activationSubmitting && setActivationDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>{activationDialogTitle}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {activationDialogHint}
          </Typography>
          <TextField
            fullWidth
            autoFocus
            label={t('productSerialCode')}
            value={activationCode}
            onChange={(e) => setActivationCode(e.target.value)}
            type="password"
            autoComplete="off"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setActivationDialogOpen(false)} disabled={activationSubmitting}>
            {t('cancel')}
          </Button>
          <Button
            variant="contained"
            onClick={handleConfirmActivation}
            disabled={activationSubmitting || !activationCode.trim()}
          >
            {activationSubmitting ? <CircularProgress size={20} /> : t('confirm')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
