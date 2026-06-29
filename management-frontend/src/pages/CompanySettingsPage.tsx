import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Autocomplete,
  Box,
  Button,
  Chip,
  Paper,
  Typography,
  TextField,
  CircularProgress,
  Grid,
  Menu,
  MenuItem,
  Switch,
  FormControlLabel,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
} from '@mui/material';
import {
  Save as SaveIcon,
  Upload as UploadIcon,
  ContentCopy as ContentCopyIcon,
} from '@mui/icons-material';
import { settingsAPI } from '../services/api';
import type { LogoType } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { CompanySettings } from '../types';
import {
  isValidEmailAddress,
  parseEmailListFromRaw,
  serializeEmailListForSettings,
} from '../utils/wholesaleOrderEmail';
import { resolveAssetUrl } from '../utils/assetUrl';
import { useCompanyBranding } from '../hooks/useCompanyBranding';
import { WHOLESALE_SETTINGS_CHANGED_EVENT, MODULE_SETTINGS_CHANGED_EVENT } from '../hooks/useWholesaleOrderEnabled';

const COPY_SOURCE_TYPES: LogoType[] = ['pdf', 'web', 'pos'];

type FeatureModule = 'wholesale' | 'pos';

type PendingPasswordToggle = {
  module: FeatureModule;
  enabled: boolean;
} | null;

const emptyForm: CompanySettings = {
  id: 0,
  company_name: '',
  logo_url: '',
  pdf_logo_url: '',
  web_logo_url: '',
  pos_logo_url: '',
  address_line1: '',
  address_line2: '',
  city: '',
  postcode: '',
  telephone: '',
  email: '',
  bank_account_name: '',
  bank_account_number: '',
  bank_sort_code: '',
  bank_address: '',
  bank_iban: '',
  payment_info: '',
  payment_transfer_to_info: '',
  shipment_couriers: '',
  wholesale_order_email_default_cc: '',
  wholesale_order_email_default_bcc: '',
  wholesale_order_enabled: true,
  wholesale_serial_activated: false,
  pos_module_enabled: true,
  pos_dlc_activated: false,
  updated_at: '',
};

const PAYMENT_MAX_LINES = 5;
const PAYMENT_TRANSFER_TO_MAX_LINES = 5;
const SHIPMENT_COURIERS_MAX_LINES = 30;

function effectiveLogoUrl(form: CompanySettings, type: LogoType): string {
  switch (type) {
    case 'pdf':
      return form.pdf_logo_url || form.logo_url || '';
    case 'web':
      return form.web_logo_url || form.logo_url || '';
    case 'pos':
      return form.pos_logo_url || form.logo_url || '';
    default:
      return '';
  }
}

/** Preview URL for a slot — prefers the type-specific icon so copy results are visible. */
function previewLogoUrl(form: CompanySettings, type: LogoType): string {
  switch (type) {
    case 'pdf':
      return form.pdf_logo_url || '';
    case 'web':
      return form.web_logo_url || '';
    case 'pos':
      return form.pos_logo_url || '';
    default:
      return '';
  }
}

function hasCopySource(form: CompanySettings, type: LogoType): boolean {
  return effectiveLogoUrl(form, type) !== '';
}

export default function CompanySettingsPage() {
  const { t } = useTranslation('companySettings');
  const { t: tSys } = useTranslation('systemInfo');
  const navigate = useNavigate();
  const { refreshBranding } = useCompanyBranding();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploadingType, setUploadingType] = useState<LogoType | null>(null);
  const [uploadingAll, setUploadingAll] = useState(false);
  const [copyingTo, setCopyingTo] = useState<LogoType | null>(null);
  const [logoVersions, setLogoVersions] = useState<Record<LogoType, number>>({
    pdf: 0,
    web: 0,
    pos: 0,
  });
  const [copyMenu, setCopyMenu] = useState<{ anchor: HTMLElement; target: LogoType } | null>(null);
  const uploadRefs = useRef<Record<LogoType, HTMLInputElement | null>>({
    pdf: null,
    web: null,
    pos: null,
  });
  const uploadAllRef = useRef<HTMLInputElement | null>(null);
  const [form, setForm] = useState<CompanySettings>(emptyForm);
  const [defaultCcEmails, setDefaultCcEmails] = useState<string[]>([]);
  const [defaultCcInput, setDefaultCcInput] = useState('');
  const [defaultBccEmails, setDefaultBccEmails] = useState<string[]>([]);
  const [defaultBccInput, setDefaultBccInput] = useState('');
  const [uploadingPdfLogo, setUploadingPdfLogo] = useState(false);
  const [pdfLogoVersion, setPdfLogoVersion] = useState(0);
  const pdfLogoUploadRef = useRef<HTMLInputElement | null>(null);
  const [passwordDialogOpen, setPasswordDialogOpen] = useState(false);
  const [pendingPasswordToggle, setPendingPasswordToggle] = useState<PendingPasswordToggle>(null);
  const [togglePassword, setTogglePassword] = useState('');
  const [toggleSubmitting, setToggleSubmitting] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  const fetchSettings = async () => {
    try {
      setLoading(true);
      const data = await settingsAPI.getCompany();
      setForm(data);
      setDefaultCcEmails(parseEmailListFromRaw(data.wholesale_order_email_default_cc));
      setDefaultCcInput('');
      setDefaultBccEmails(parseEmailListFromRaw(data.wholesale_order_email_default_bcc));
      setDefaultBccInput('');
    } catch {
      enqueueSnackbar(t('loadFailed'), { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSettings();
  }, []);

  useEffect(() => {
    const refresh = () => { fetchSettings(); };
    window.addEventListener(WHOLESALE_SETTINGS_CHANGED_EVENT, refresh);
    window.addEventListener(MODULE_SETTINGS_CHANGED_EVENT, refresh);
    return () => {
      window.removeEventListener(WHOLESALE_SETTINGS_CHANGED_EVENT, refresh);
      window.removeEventListener(MODULE_SETTINGS_CHANGED_EVENT, refresh);
    };
  }, []);

  useEffect(() => {
    if (loading) return;
    const hash = window.location.hash.replace(/^#/, '');
    if (!hash) return;
    const el = document.getElementById(hash);
    if (el) {
      window.requestAnimationFrame(() => {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      });
    }
  }, [loading]);

  const handleChange = (field: keyof CompanySettings) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const value = e.target.value;
    if (field === 'payment_info') {
      const lines = value.split('\n');
      if (lines.length > PAYMENT_MAX_LINES) return;
      setForm((prev) => ({ ...prev, [field]: value }));
      return;
    }
    if (field === 'payment_transfer_to_info') {
      const lines = value.split('\n');
      if (lines.length > PAYMENT_TRANSFER_TO_MAX_LINES) return;
      setForm((prev) => ({ ...prev, [field]: value }));
      return;
    }
    if (field === 'shipment_couriers') {
      const lines = value.split('\n');
      if (lines.length > SHIPMENT_COURIERS_MAX_LINES) return;
      setForm((prev) => ({ ...prev, [field]: value }));
      return;
    }
    setForm((prev) => ({ ...prev, [field]: value }));
  };

  const paymentLineCount = form.payment_info.split('\n').length;
  const paymentOverLimit = paymentLineCount > PAYMENT_MAX_LINES;
  const paymentTransferToLineCount = (form.payment_transfer_to_info ?? '').split('\n').length;
  const paymentTransferToOverLimit = paymentTransferToLineCount > PAYMENT_TRANSFER_TO_MAX_LINES;
  const shipmentCouriersLineCount = (form.shipment_couriers ?? '').split('\n').length;
  const shipmentCouriersOverLimit = shipmentCouriersLineCount > SHIPMENT_COURIERS_MAX_LINES;

  const defaultCcInvalid = defaultCcEmails.filter((e) => !isValidEmailAddress(e));
  const defaultBccInvalid = defaultBccEmails.filter((e) => !isValidEmailAddress(e));

  const wholesaleEnabled = form.wholesale_order_enabled !== false;
  const posEnabled = form.pos_module_enabled !== false;
  const needsWholesaleSerial = !form.wholesale_serial_activated;
  const needsPosSerial = !form.pos_dlc_activated;
  const visiblePortalLogoTypes: LogoType[] = posEnabled ? ['web', 'pos'] : ['web'];
  const showUploadAllIcons = wholesaleEnabled || posEnabled;

  const openPasswordToggle = (module: FeatureModule, nextEnabled: boolean) => {
    setPendingPasswordToggle({ module, enabled: nextEnabled });
    setTogglePassword('');
    setPasswordDialogOpen(true);
  };

  const handleFeatureSwitch = (module: FeatureModule, currentlyEnabled: boolean) => {
    const needsSerial = module === 'wholesale' ? needsWholesaleSerial : needsPosSerial;
    if (!currentlyEnabled && needsSerial) {
      navigate(`/system-info?module=${module}&action=enable`);
      return;
    }
    openPasswordToggle(module, !currentlyEnabled);
  };

  const handleConfirmPasswordToggle = async () => {
    if (!pendingPasswordToggle) return;
    try {
      setToggleSubmitting(true);
      const body = {
        enabled: pendingPasswordToggle.enabled,
        password: togglePassword,
      };
      const updated = pendingPasswordToggle.module === 'wholesale'
        ? await settingsAPI.toggleWholesaleOrder(body)
        : await settingsAPI.togglePosModule(body);
      setForm(updated);
      setPasswordDialogOpen(false);
      if (pendingPasswordToggle.module === 'wholesale') {
        window.dispatchEvent(new Event(WHOLESALE_SETTINGS_CHANGED_EVENT));
        enqueueSnackbar(
          pendingPasswordToggle.enabled ? tSys('wholesaleEnableSuccess') : tSys('wholesaleDisableSuccess'),
          { variant: 'success' },
        );
      } else {
        window.dispatchEvent(new Event(MODULE_SETTINGS_CHANGED_EVENT));
        enqueueSnackbar(
          pendingPasswordToggle.enabled ? tSys('posEnableSuccess') : tSys('posDisableSuccess'),
          { variant: 'success' },
        );
      }
    } catch (err: any) {
      const fallback = pendingPasswordToggle.module === 'wholesale'
        ? tSys('wholesaleToggleFailed')
        : tSys('posToggleFailed');
      enqueueSnackbar(err.response?.data?.error || fallback, { variant: 'error' });
    } finally {
      setToggleSubmitting(false);
    }
  };

  const passwordDialogTitle = (() => {
    if (!pendingPasswordToggle) return '';
    if (pendingPasswordToggle.module === 'wholesale') {
      return pendingPasswordToggle.enabled
        ? tSys('wholesaleEnableTitle')
        : tSys('wholesaleDisableTitle');
    }
    return pendingPasswordToggle.enabled ? tSys('posEnableTitle') : tSys('posDisableTitle');
  })();

  const passwordDialogHint = (() => {
    if (!pendingPasswordToggle) return '';
    if (pendingPasswordToggle.module === 'wholesale') {
      return pendingPasswordToggle.enabled
        ? tSys('wholesaleEnablePasswordHint')
        : tSys('wholesaleDisablePasswordHint');
    }
    return pendingPasswordToggle.enabled
      ? tSys('posEnablePasswordHint')
      : tSys('posDisablePasswordHint');
  })();

  const handlePdfLogoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      enqueueSnackbar(t('logoInvalidType'), { variant: 'error' });
      return;
    }
    try {
      setUploadingPdfLogo(true);
      const formData = new FormData();
      formData.append('logo', file);
      const updated = await settingsAPI.uploadCompanyLogoByType('pdf', formData);
      applyLogoUpdate(updated, 'pdf');
      setPdfLogoVersion((v) => v + 1);
      enqueueSnackbar(t('logoUploadSuccess'), { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || t('logoUploadFailed'), { variant: 'error' });
    } finally {
      setUploadingPdfLogo(false);
    }
  };

  const pdfLogoUrl = previewLogoUrl(form, 'pdf') || effectiveLogoUrl(form, 'pdf');
  const pdfLogoResolved = pdfLogoUrl ? resolveAssetUrl(pdfLogoUrl) || pdfLogoUrl : '';
  const pdfLogoPreviewSrc = pdfLogoResolved
    ? `${pdfLogoResolved}${pdfLogoResolved.includes('?') ? '&' : '?'}v=${pdfLogoVersion}`
    : '';

  const bumpLogoVersion = (type: LogoType) => {
    setLogoVersions((prev) => ({ ...prev, [type]: prev[type] + 1 }));
  };

  const applyLogoUpdate = (updated: CompanySettings, type: LogoType) => {
    setForm((prev) => ({
      ...prev,
      logo_url: updated.logo_url !== undefined ? updated.logo_url : prev.logo_url,
      pdf_logo_url: updated.pdf_logo_url !== undefined ? updated.pdf_logo_url : prev.pdf_logo_url,
      web_logo_url: updated.web_logo_url !== undefined ? updated.web_logo_url : prev.web_logo_url,
      pos_logo_url: updated.pos_logo_url !== undefined ? updated.pos_logo_url : prev.pos_logo_url,
    }));
    bumpLogoVersion(type);
    if (type === 'web') {
      void refreshBranding();
    }
  };

  const applyAllLogoUpdate = (updated: CompanySettings) => {
    setForm((prev) => ({
      ...prev,
      logo_url: updated.logo_url !== undefined ? updated.logo_url : prev.logo_url,
      pdf_logo_url: updated.pdf_logo_url !== undefined ? updated.pdf_logo_url : prev.pdf_logo_url,
      web_logo_url: updated.web_logo_url !== undefined ? updated.web_logo_url : prev.web_logo_url,
      pos_logo_url: updated.pos_logo_url !== undefined ? updated.pos_logo_url : prev.pos_logo_url,
    }));
    setLogoVersions((prev) => ({
      pdf: prev.pdf + 1,
      web: prev.web + 1,
      pos: prev.pos + 1,
    }));
    void refreshBranding();
  };

  const handleUploadAllIcons = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      enqueueSnackbar(t('logoInvalidType'), { variant: 'error' });
      return;
    }
    try {
      setUploadingAll(true);
      const formData = new FormData();
      formData.append('logo', file);
      const updated = await settingsAPI.uploadCompanyLogoAll(formData);
      applyAllLogoUpdate(updated);
      enqueueSnackbar(t('uploadAllIconsSuccess'), { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || t('uploadAllIconsFailed'), { variant: 'error' });
    } finally {
      setUploadingAll(false);
    }
  };

  const handleLogoUpload = async (type: LogoType, e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      enqueueSnackbar(t('logoInvalidType'), { variant: 'error' });
      return;
    }
    try {
      setUploadingType(type);
      const formData = new FormData();
      formData.append('logo', file);
      const updated = await settingsAPI.uploadCompanyLogoByType(type, formData);
      applyLogoUpdate(updated, type);
      enqueueSnackbar(t('logoUploadSuccess'), { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || t('logoUploadFailed'), { variant: 'error' });
    } finally {
      setUploadingType(null);
    }
  };

  const handleCopyLogo = async (from: LogoType, to: LogoType) => {
    setCopyMenu(null);
    try {
      setCopyingTo(to);
      const updated = await settingsAPI.copyCompanyLogo(from, to);
      applyLogoUpdate(updated, to);
      enqueueSnackbar(t('iconCopySuccess'), { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || t('iconCopyFailed'), { variant: 'error' });
    } finally {
      setCopyingTo(null);
    }
  };

  const logoTitleKey = (type: LogoType) => {
    switch (type) {
      case 'pdf':
        return 'iconPdf';
      case 'web':
        return 'iconWeb';
      case 'pos':
        return 'iconPos';
    }
  };

  const logoHintKey = (type: LogoType) => {
    switch (type) {
      case 'pdf':
        return 'iconPdfHint';
      case 'web':
        return 'iconWebHint';
      case 'pos':
        return 'iconPosHint';
    }
  };

  const copyFromLabelKey = (type: LogoType) => {
    switch (type) {
      case 'pdf':
        return 'copyFromPdf';
      case 'web':
        return 'copyFromWeb';
      case 'pos':
        return 'copyFromPos';
    }
  };

  const previewStyleForType = (type: LogoType) => {
    if (type === 'pos') {
      return { width: 96, height: 96 };
    }
    if (type === 'pdf') {
      return { width: 200, height: 60 };
    }
    return { width: 220, height: 66 };
  };

  const handleSave = async () => {
    if (paymentOverLimit) {
      enqueueSnackbar(t('paymentMaxLinesError'), { variant: 'error' });
      return;
    }
    if (defaultCcInvalid.length > 0) {
      enqueueSnackbar(t('wholesaleOrderEmailDefaultCcInvalid', { email: defaultCcInvalid[0] }), { variant: 'error' });
      return;
    }
    if (defaultBccInvalid.length > 0) {
      enqueueSnackbar(t('wholesaleOrderEmailDefaultBccInvalid', { email: defaultBccInvalid[0] }), { variant: 'error' });
      return;
    }
    try {
      setSaving(true);
      await settingsAPI.updateCompany({
        company_name: form.company_name,
        address_line1: form.address_line1,
        address_line2: form.address_line2,
        city: form.city,
        postcode: form.postcode,
        telephone: form.telephone,
        email: form.email,
        payment_info: form.payment_info,
        payment_transfer_to_info: form.payment_transfer_to_info ?? '',
        shipment_couriers: form.shipment_couriers ?? '',
        wholesale_order_email_default_cc: serializeEmailListForSettings(defaultCcEmails),
        wholesale_order_email_default_bcc: serializeEmailListForSettings(defaultBccEmails),
      });
      enqueueSnackbar(t('saveSuccess'), {
        variant: 'success',
      });
      fetchSettings();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('saveFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: 300 }}>
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5">{t('title')}</Typography>
        <Button
          variant="contained"
          startIcon={saving ? <CircularProgress size={20} /> : <SaveIcon />}
          onClick={handleSave}
          disabled={saving}
        >
          {t('save')}
        </Button>
      </Box>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {t('subtitle')}
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 2 }}>{t('companySection')}</Typography>
        <Grid container spacing={2}>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label={t('companyName')}
              value={form.company_name}
              onChange={handleChange('company_name')}
            />
          </Grid>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label={t('addressLine1')}
              value={form.address_line1}
              onChange={handleChange('address_line1')}
            />
          </Grid>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label={t('addressLine2')}
              value={form.address_line2}
              onChange={handleChange('address_line2')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label={t('city')}
              value={form.city}
              onChange={handleChange('city')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label={t('postcode')}
              value={form.postcode}
              onChange={handleChange('postcode')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label={t('telephone')}
              value={form.telephone}
              onChange={handleChange('telephone')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label={t('email')}
              type="email"
              value={form.email}
              onChange={handleChange('email')}
            />
          </Grid>
        </Grid>
      </Paper>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 1 }}>{t('iconsSection')}</Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          {posEnabled ? t('iconsSubtitle') : t('iconsSubtitleWebOnly')}
        </Typography>
        {showUploadAllIcons ? (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap', mb: 3 }}>
            <Button
              variant="contained"
              startIcon={uploadingAll ? <CircularProgress size={18} color="inherit" /> : <UploadIcon />}
              disabled={uploadingAll || uploadingType !== null || copyingTo !== null}
              onClick={() => uploadAllRef.current?.click()}
            >
              {t('uploadAllIcons')}
            </Button>
            <Typography variant="body2" color="text.secondary" sx={{ flex: 1, minWidth: 200 }}>
              {t('uploadAllIconsHint')}
            </Typography>
            <input
              ref={uploadAllRef}
              type="file"
              hidden
              accept="image/*"
              onChange={handleUploadAllIcons}
            />
          </Box>
        ) : null}
        <Grid container spacing={3}>
          {visiblePortalLogoTypes.map((type) => {
            const logoUrl = previewLogoUrl(form, type) || effectiveLogoUrl(form, type);
            const resolved = logoUrl ? resolveAssetUrl(logoUrl) || logoUrl : '';
            const previewSrc = resolved
              ? `${resolved}${resolved.includes('?') ? '&' : '?'}v=${logoVersions[type]}`
              : '';
            const isUploading = uploadingType === type;
            const isCopying = copyingTo === type;
            const iconsBusy = uploadingAll || uploadingType !== null || copyingTo !== null;

            return (
              <Grid item xs={12} md={4} key={type}>
                <Typography variant="subtitle2" sx={{ mb: 0.5 }}>
                  {t(logoTitleKey(type))}
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5, minHeight: 40 }}>
                  {t(logoHintKey(type))}
                </Typography>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
                  {previewSrc ? (
                    <Box
                      component="img"
                      src={previewSrc}
                      alt={t(logoTitleKey(type))}
                      sx={{
                        ...previewStyleForType(type),
                        objectFit: 'contain',
                        border: '1px solid',
                        borderColor: 'divider',
                        borderRadius: 1,
                        p: 1,
                        bgcolor: 'background.paper',
                        alignSelf: 'flex-start',
                      }}
                    />
                  ) : (
                    <Typography variant="body2" color="text.secondary">
                      {t('logoNone')}
                    </Typography>
                  )}
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                    <Button
                      variant="outlined"
                      size="small"
                      startIcon={isUploading ? <CircularProgress size={16} /> : <UploadIcon />}
                      disabled={iconsBusy}
                      onClick={() => uploadRefs.current[type]?.click()}
                    >
                      {logoUrl ? t('logoReplace') : t('logoUpload')}
                    </Button>
                    <input
                      ref={(el) => {
                        uploadRefs.current[type] = el;
                      }}
                      type="file"
                      hidden
                      accept="image/*"
                      onChange={(e) => handleLogoUpload(type, e)}
                    />
                    <Button
                      variant="outlined"
                      size="small"
                      startIcon={isCopying ? <CircularProgress size={16} /> : <ContentCopyIcon />}
                      disabled={iconsBusy}
                      onClick={(e) => setCopyMenu({ anchor: e.currentTarget, target: type })}
                    >
                      {t('copyFrom')}
                    </Button>
                  </Box>
                </Box>
              </Grid>
            );
          })}
        </Grid>
        <Menu
          anchorEl={copyMenu?.anchor ?? null}
          open={Boolean(copyMenu)}
          onClose={() => setCopyMenu(null)}
        >
          {copyMenu &&
            COPY_SOURCE_TYPES.filter((source) => {
              if (source === copyMenu.target) return false;
              if (source === 'pdf' && !wholesaleEnabled) return false;
              if (source === 'pos' && !posEnabled) return false;
              return true;
            }).map((source) => (
              <MenuItem
                key={source}
                onClick={() => handleCopyLogo(source, copyMenu.target)}
                disabled={!hasCopySource(form, source)}
              >
                {t(copyFromLabelKey(source))}
              </MenuItem>
            ))}
        </Menu>
      </Paper>

      <Paper id="wholesale-order" sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, mb: 2, flexWrap: 'wrap' }}>
          <Box>
            <Typography variant="subtitle1">{t('wholesaleOrderSection')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {wholesaleEnabled ? t('wholesaleOrderSectionSubtitle') : t('wholesaleOrderDisabledHint')}
            </Typography>
            {!wholesaleEnabled && needsWholesaleSerial ? (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('moduleActivationHint')}
              </Typography>
            ) : null}
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
            label={t('wholesaleOrderEnabled')}
            sx={{ m: 0 }}
          />
        </Box>

        {wholesaleEnabled ? (
        <>
        <Grid container spacing={3}>
          <Grid item xs={12} md={4}>
            <Typography variant="subtitle2" sx={{ mb: 0.5 }}>{t('iconPdf')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>
              {t('iconPdfHint')}
            </Typography>
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
              {pdfLogoPreviewSrc ? (
                <Box
                  component="img"
                  src={pdfLogoPreviewSrc}
                  alt={t('iconPdf')}
                  sx={{
                    width: 200,
                    height: 60,
                    objectFit: 'contain',
                    border: '1px solid',
                    borderColor: 'divider',
                    borderRadius: 1,
                    p: 1,
                    bgcolor: 'background.paper',
                    alignSelf: 'flex-start',
                  }}
                />
              ) : (
                <Typography variant="body2" color="text.secondary">{t('logoNone')}</Typography>
              )}
              <Button
                variant="outlined"
                size="small"
                startIcon={uploadingPdfLogo ? <CircularProgress size={16} /> : <UploadIcon />}
                disabled={uploadingPdfLogo}
                onClick={() => pdfLogoUploadRef.current?.click()}
                sx={{ alignSelf: 'flex-start' }}
              >
                {pdfLogoUrl ? t('logoReplace') : t('logoUpload')}
              </Button>
              <input
                ref={pdfLogoUploadRef}
                type="file"
                hidden
                accept="image/*"
                onChange={handlePdfLogoUpload}
              />
            </Box>
          </Grid>
          <Grid item xs={12} md={8}>
            <Autocomplete
              multiple
              freeSolo
              options={[]}
              value={defaultCcEmails}
              inputValue={defaultCcInput}
              onInputChange={(_, value, reason) => {
                if (reason === 'reset') return;
                setDefaultCcInput(value);
              }}
              onChange={(_, next) => {
                setDefaultCcEmails(parseEmailListFromRaw((next as string[]).join('\n')));
                setDefaultCcInput('');
              }}
              id="wholesale-default-email-cc"
              sx={{ mb: 2 }}
              renderTags={(tagValue, getTagProps) =>
                tagValue.map((option, index) => {
                  const { key, ...tagProps } = getTagProps({ index });
                  return (
                    <Chip
                      key={key}
                      label={option}
                      size="small"
                      {...tagProps}
                      color={isValidEmailAddress(option) ? 'default' : 'error'}
                    />
                  );
                })
              }
              renderInput={(params) => (
                <TextField
                  {...params}
                  label={t('wholesaleOrderEmailDefaultCc')}
                  placeholder={t('wholesaleOrderEmailDefaultCcPlaceholder')}
                  helperText={t('wholesaleOrderEmailDefaultCcHint')}
                  error={defaultCcInvalid.length > 0}
                />
              )}
            />
            <Autocomplete
              multiple
              freeSolo
              options={[]}
              value={defaultBccEmails}
              inputValue={defaultBccInput}
              onInputChange={(_, value, reason) => {
                if (reason === 'reset') return;
                setDefaultBccInput(value);
              }}
              onChange={(_, next) => {
                setDefaultBccEmails(parseEmailListFromRaw((next as string[]).join('\n')));
                setDefaultBccInput('');
              }}
              id="wholesale-default-email-bcc"
              renderTags={(tagValue, getTagProps) =>
                tagValue.map((option, index) => {
                  const { key, ...tagProps } = getTagProps({ index });
                  return (
                    <Chip
                      key={key}
                      label={option}
                      size="small"
                      {...tagProps}
                      color={isValidEmailAddress(option) ? 'default' : 'error'}
                    />
                  );
                })
              }
              renderInput={(params) => (
                <TextField
                  {...params}
                  label={t('wholesaleOrderEmailDefaultBcc')}
                  placeholder={t('wholesaleOrderEmailDefaultBccPlaceholder')}
                  helperText={t('wholesaleOrderEmailDefaultBccHint')}
                  error={defaultBccInvalid.length > 0}
                />
              )}
            />
          </Grid>
        </Grid>

        <Box id="payment" sx={{ mt: 4 }}>
          <Typography variant="subtitle2" sx={{ mb: 0.5 }}>{t('paymentSection')}</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {t('paymentSubtitle')}
          </Typography>
          <TextField
            fullWidth
            multiline
            rows={5}
            label={t('paymentDetails')}
            value={form.payment_info}
            onChange={handleChange('payment_info')}
            placeholder={t('paymentPlaceholder')}
            helperText={paymentLineCount > 0 ? t('paymentHelper', { current: paymentLineCount, max: PAYMENT_MAX_LINES }) : t('paymentHelperMax', { max: PAYMENT_MAX_LINES })}
            error={paymentOverLimit}
            inputProps={{ maxLength: 500 }}
          />
        </Box>

        <Box id="shipment-couriers" sx={{ mt: 4 }}>
          <Typography variant="subtitle2" sx={{ mb: 0.5 }}>{t('shipmentCouriersSection')}</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {t('shipmentCouriersSubtitle')}
          </Typography>
          <TextField
            fullWidth
            multiline
            rows={5}
            label={t('shipmentCouriersDetails')}
            value={form.shipment_couriers ?? ''}
            onChange={handleChange('shipment_couriers')}
            placeholder={t('shipmentCouriersPlaceholder')}
            helperText={
              shipmentCouriersLineCount > 0
                ? t('shipmentCouriersHelper', { current: shipmentCouriersLineCount, max: SHIPMENT_COURIERS_MAX_LINES })
                : t('shipmentCouriersHelperMax', { max: SHIPMENT_COURIERS_MAX_LINES })
            }
            error={shipmentCouriersOverLimit}
            inputProps={{ maxLength: 1000 }}
          />
        </Box>

        <Box id="payment-transfer" sx={{ mt: 4 }}>
          <Typography variant="subtitle2" sx={{ mb: 0.5 }}>{t('paymentTransferToSection')}</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {t('paymentTransferToSubtitle')}
          </Typography>
          <TextField
            fullWidth
            multiline
            rows={5}
            label={t('paymentTransferToDetails')}
            value={form.payment_transfer_to_info}
            onChange={handleChange('payment_transfer_to_info')}
            placeholder={t('paymentTransferToPlaceholder')}
            helperText={
              paymentTransferToLineCount > 0
                ? t('paymentTransferToHelper', { current: paymentTransferToLineCount, max: PAYMENT_TRANSFER_TO_MAX_LINES })
                : t('paymentTransferToHelperMax', { max: PAYMENT_TRANSFER_TO_MAX_LINES })
            }
            error={paymentTransferToOverLimit}
            inputProps={{ maxLength: 500 }}
          />
        </Box>
        </>
        ) : null}
      </Paper>

      <Paper id="pos-module" sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap' }}>
          <Box>
            <Typography variant="subtitle1">{t('posModuleSection')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {posEnabled ? t('posModuleSectionSubtitle') : t('posModuleDisabledHint')}
            </Typography>
            {!posEnabled && needsPosSerial ? (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('moduleActivationHint')}
              </Typography>
            ) : null}
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
            label={t('posModuleEnabled')}
            sx={{ m: 0 }}
          />
        </Box>
      </Paper>

      <Dialog open={passwordDialogOpen} onClose={() => !toggleSubmitting && setPasswordDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>{passwordDialogTitle}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {passwordDialogHint}
          </Typography>
          <TextField
            fullWidth
            autoFocus
            label={tSys('confirmPassword')}
            value={togglePassword}
            onChange={(e) => setTogglePassword(e.target.value)}
            type="password"
            autoComplete="current-password"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPasswordDialogOpen(false)} disabled={toggleSubmitting}>
            {tSys('cancel')}
          </Button>
          <Button
            variant="contained"
            onClick={handleConfirmPasswordToggle}
            disabled={toggleSubmitting || !togglePassword.trim()}
          >
            {toggleSubmitting ? <CircularProgress size={20} /> : tSys('confirm')}
          </Button>
        </DialogActions>
      </Dialog>

    </Box>
  );
}
