import { useEffect, useState } from 'react';
import {
  Box,
  Button,
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
  updated_at: '',
};

export default function CompanySettingsPage() {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState<CompanySettings>(emptyForm);
  const { enqueueSnackbar } = useSnackbar();

  const fetchSettings = async () => {
    try {
      setLoading(true);
      const data = await settingsAPI.getCompany();
      setForm(data);
    } catch {
      enqueueSnackbar('Failed to load company settings', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSettings();
  }, []);

  const PAYMENT_MAX_LINES = 5;

  const handleChange = (field: keyof CompanySettings) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const value = e.target.value;
    if (field === 'payment_info') {
      const lines = value.split('\n');
      if (lines.length > PAYMENT_MAX_LINES) return;
      setForm((prev) => ({ ...prev, [field]: value }));
      return;
    }
    setForm((prev) => ({ ...prev, [field]: value }));
  };

  const paymentLineCount = form.payment_info.split('\n').length;
  const paymentOverLimit = paymentLineCount > PAYMENT_MAX_LINES;

  const handleSave = async () => {
    if (paymentOverLimit) {
      enqueueSnackbar('Payment details must not exceed 5 lines.', { variant: 'error' });
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
      });
      enqueueSnackbar('Company settings saved. They will appear on order confirmation PDFs.', {
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
        <Typography variant="h5">{t('layout.companySettings')}</Typography>
        <Button
          variant="contained"
          startIcon={saving ? <CircularProgress size={20} /> : <SaveIcon />}
          onClick={handleSave}
          disabled={saving}
        >
          {t('common.save')}
        </Button>
      </Box>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Company details appear on order confirmation PDFs (header). Payment details appear at the end of the invoice.
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 2 }}>Company</Typography>
        <Grid container spacing={2}>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label="Company name"
              value={form.company_name}
              onChange={handleChange('company_name')}
            />
          </Grid>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label="Address line 1"
              value={form.address_line1}
              onChange={handleChange('address_line1')}
            />
          </Grid>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label="Address line 2"
              value={form.address_line2}
              onChange={handleChange('address_line2')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label="City"
              value={form.city}
              onChange={handleChange('city')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label="Postcode"
              value={form.postcode}
              onChange={handleChange('postcode')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label="Telephone"
              value={form.telephone}
              onChange={handleChange('telephone')}
            />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              label="Email"
              type="email"
              value={form.email}
              onChange={handleChange('email')}
            />
          </Grid>
        </Grid>
      </Paper>

      <Paper id="payment" sx={{ p: 3 }}>
        <Typography variant="subtitle1" sx={{ mb: 1 }}>Payment (appears on invoice)</Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          Free-form payment details shown at the end of the invoice PDF (max 5 lines).
        </Typography>
        <TextField
          fullWidth
          multiline
          rows={5}
          label="Payment details"
          value={form.payment_info}
          onChange={handleChange('payment_info')}
          placeholder="e.g. Account: Heartwood Trading Ltd, Sort code: 23-08-01, Account number: 25307108"
          helperText={paymentLineCount > 0 ? `${paymentLineCount} of ${PAYMENT_MAX_LINES} lines` : `Maximum ${PAYMENT_MAX_LINES} lines (invoice layout)`}
          error={paymentOverLimit}
          inputProps={{ maxLength: 500 }}
        />
      </Paper>
    </Box>
  );
}
