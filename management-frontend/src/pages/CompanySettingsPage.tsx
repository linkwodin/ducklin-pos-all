import { useEffect, useState } from 'react';
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
} from '@mui/material';
import { Save as SaveIcon } from '@mui/icons-material';
import { settingsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { CompanySettings } from '../types';
import {
  isValidEmailAddress,
  parseEmailListFromRaw,
  serializeEmailListForSettings,
} from '../utils/wholesaleOrderEmail';

const emptyForm: CompanySettings = {
  id: 0,
  company_name: '',
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
  updated_at: '',
};

const PAYMENT_MAX_LINES = 5;
const PAYMENT_TRANSFER_TO_MAX_LINES = 5;
const SHIPMENT_COURIERS_MAX_LINES = 30;

export default function CompanySettingsPage() {
  const { t } = useTranslation('companySettings');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState<CompanySettings>(emptyForm);
  const [defaultCcEmails, setDefaultCcEmails] = useState<string[]>([]);
  const [defaultCcInput, setDefaultCcInput] = useState('');
  const { enqueueSnackbar } = useSnackbar();

  const fetchSettings = async () => {
    try {
      setLoading(true);
      const data = await settingsAPI.getCompany();
      setForm(data);
      setDefaultCcEmails(parseEmailListFromRaw(data.wholesale_order_email_default_cc));
      setDefaultCcInput('');
    } catch {
      enqueueSnackbar('Failed to load company settings', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSettings();
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

  const handleSave = async () => {
    if (paymentOverLimit) {
      enqueueSnackbar(t('paymentMaxLinesError'), { variant: 'error' });
      return;
    }
    if (defaultCcInvalid.length > 0) {
      enqueueSnackbar(t('wholesaleOrderEmailDefaultCcInvalid', { email: defaultCcInvalid[0] }), { variant: 'error' });
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
      });
      enqueueSnackbar(t('saveSuccess'), {
        variant: 'success',
      });
      fetchSettings();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to save', { variant: 'error' });
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

      <Paper id="wholesale-email" sx={{ p: 3, mb: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 1 }}>{t('emailSection')}</Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          {t('emailSectionSubtitle')}
        </Typography>
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
          id="default-email-cc"
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
      </Paper>

      <Paper id="payment" sx={{ p: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 1 }}>{t('paymentSection')}</Typography>
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
      </Paper>

      <Paper id="shipment-couriers" sx={{ p: 3, mt: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 1 }}>{t('shipmentCouriersSection')}</Typography>
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
      </Paper>

      <Paper id="payment-transfer" sx={{ p: 3, mt: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 1 }}>{t('paymentTransferToSection')}</Typography>
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
      </Paper>
    </Box>
  );
}
