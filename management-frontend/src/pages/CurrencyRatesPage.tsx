import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  CircularProgress,
  Alert,
  Checkbox,
  FormControlLabel,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
  Sync as SyncIcon,
  PushPin as PinIcon,
  PushPinOutlined as PinOutlinedIcon,
} from '@mui/icons-material';
import { currencyRatesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { CurrencyRate } from '../types';
import { format } from 'date-fns';

export default function CurrencyRatesPage() {
  const [rates, setRates] = useState<CurrencyRate[]>([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [open, setOpen] = useState(false);
  const [editingRate, setEditingRate] = useState<CurrencyRate | null>(null);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchRates();
  }, []);

  const fetchRates = async () => {
    try {
      setLoading(true);
      const data = await currencyRatesAPI.list();
      setRates(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch currency rates', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleSync = async () => {
    try {
      setSyncing(true);
      const result = await currencyRatesAPI.sync();
      enqueueSnackbar(
        `Synced ${result.updated_count} currency rates successfully`,
        { variant: 'success' }
      );
      fetchRates();
    } catch (error: any) {
      enqueueSnackbar(
        error.response?.data?.error || 'Failed to sync currency rates',
        { variant: 'error' }
      );
    } finally {
      setSyncing(false);
    }
  };

  const handleTogglePin = async (code: string, currentPinStatus: boolean) => {
    try {
      await currencyRatesAPI.togglePin(code, !currentPinStatus);
      enqueueSnackbar(
        `Currency ${!currentPinStatus ? 'pinned' : 'unpinned'}`,
        { variant: 'success' }
      );
      fetchRates();
    } catch (error: any) {
      enqueueSnackbar(
        error.response?.data?.error || 'Failed to toggle pin',
        { variant: 'error' }
      );
    }
  };

  const handleDelete = async (code: string) => {
    if (!window.confirm(`Are you sure you want to delete currency rate for ${code}?`)) {
      return;
    }
    try {
      await currencyRatesAPI.delete(code);
      enqueueSnackbar('Currency rate deleted', { variant: 'success' });
      fetchRates();
    } catch (error) {
      enqueueSnackbar('Failed to delete currency rate', { variant: 'error' });
    }
  };

  const handleSave = async (rateData: { currency_code?: string; rate_to_gbp: number; is_pinned?: boolean }) => {
    try {
      if (editingRate) {
        await currencyRatesAPI.update(editingRate.currency_code, rateData);
        enqueueSnackbar('Currency rate updated', { variant: 'success' });
      } else {
        if (!rateData.currency_code) {
          enqueueSnackbar('Currency code is required', { variant: 'error' });
          return;
        }
        await currencyRatesAPI.create({
          currency_code: rateData.currency_code,
          rate_to_gbp: rateData.rate_to_gbp,
          is_pinned: rateData.is_pinned || false,
        });
        enqueueSnackbar('Currency rate created', { variant: 'success' });
      }
      setOpen(false);
      setEditingRate(null);
      fetchRates();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to save currency rate', {
        variant: 'error',
      });
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">Currency Rates</Typography>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <Button
            variant="outlined"
            startIcon={syncing ? <CircularProgress size={20} /> : <SyncIcon />}
            onClick={handleSync}
            disabled={syncing}
          >
            Sync from API
          </Button>
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={() => {
              setEditingRate(null);
              setOpen(true);
            }}
          >
            Add Currency Rate
          </Button>
        </Box>
      </Box>

      <Alert severity="info" sx={{ mb: 2 }}>
        Currency rates are relative to GBP (base currency). Pin main purchasing currencies (CNY, USD, HKD, JPY)
        to show them at the top. Use the "Sync from API" button to automatically fetch the latest rates,
        or manually add/edit rates as needed.
      </Alert>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell width={60}>Pin</TableCell>
              <TableCell>Currency Code</TableCell>
              <TableCell>Rate to GBP</TableCell>
              <TableCell>Last Updated</TableCell>
              <TableCell>Updated By</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={6} align="center">
                  <CircularProgress />
                </TableCell>
              </TableRow>
            ) : rates.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} align="center">
                  No currency rates found. Click "Sync from API" to fetch rates or add manually.
                </TableCell>
              </TableRow>
            ) : (
              rates.map((rate: CurrencyRate) => (
                <TableRow 
                  key={rate.id}
                  sx={{ 
                    bgcolor: rate.is_pinned ? 'action.hover' : 'inherit',
                    '&:hover': { bgcolor: 'action.hover' }
                  }}
                >
                  <TableCell>
                    <IconButton
                      size="small"
                      onClick={() => handleTogglePin(rate.currency_code, rate.is_pinned)}
                      color={rate.is_pinned ? 'primary' : 'default'}
                    >
                      {rate.is_pinned ? <PinIcon /> : <PinOutlinedIcon />}
                    </IconButton>
                  </TableCell>
                  <TableCell>
                    <Typography variant="body1" fontWeight={rate.is_pinned ? 'bold' : 'normal'}>
                      {rate.currency_code}
                    </Typography>
                  </TableCell>
                  <TableCell>{rate.rate_to_gbp.toFixed(6)}</TableCell>
                  <TableCell>
                    {format(new Date(rate.last_updated), 'PPp')}
                  </TableCell>
                  <TableCell>
                    {rate.updated_by === 'api_sync' ? (
                      <Typography variant="body2" color="primary">
                        API Sync
                      </Typography>
                    ) : (
                      <Typography variant="body2" color="text.secondary">
                        Manual
                      </Typography>
                    )}
                  </TableCell>
                  <TableCell>
                    <IconButton
                      size="small"
                      onClick={() => {
                        setEditingRate(rate);
                        setOpen(true);
                      }}
                    >
                      <EditIcon />
                    </IconButton>
                    <IconButton
                      size="small"
                      onClick={() => handleDelete(rate.currency_code)}
                      color="error"
                    >
                      <DeleteIcon />
                    </IconButton>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <CurrencyRateDialog
        open={open}
        onClose={() => {
          setOpen(false);
          setEditingRate(null);
        }}
        onSave={handleSave}
        rate={editingRate}
      />
    </Box>
  );
}

function CurrencyRateDialog({
  open,
  onClose,
  onSave,
  rate,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: { currency_code?: string; rate_to_gbp: number; is_pinned?: boolean }) => void;
  rate: CurrencyRate | null;
}) {
  const [formData, setFormData] = useState({
    currency_code: '',
    rate_to_gbp: 0,
    is_pinned: false,
  });

  useEffect(() => {
    if (rate) {
      setFormData({
        currency_code: rate.currency_code,
        rate_to_gbp: rate.rate_to_gbp,
        is_pinned: rate.is_pinned,
      });
    } else {
      setFormData({
        currency_code: '',
        rate_to_gbp: 0,
        is_pinned: false,
      });
    }
  }, [rate, open]);

  const handleSubmit = () => {
    if (!rate && !formData.currency_code) {
      return;
    }
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{rate ? 'Edit Currency Rate' : 'Add Currency Rate'}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label="Currency Code"
            required
            fullWidth
            disabled={!!rate}
            value={formData.currency_code}
            onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
              setFormData({ ...formData, currency_code: e.target.value.toUpperCase() })
            }
            helperText="ISO 4217 currency code (e.g., USD, EUR, HKD, CNY, JPY)"
            inputProps={{ maxLength: 3 }}
          />
          <TextField
            label="Rate to GBP"
            type="number"
            required
            fullWidth
            inputProps={{ min: 0, step: 0.000001 }}
            value={formData.rate_to_gbp}
            onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
              setFormData({ ...formData, rate_to_gbp: parseFloat(e.target.value) || 0 })
            }
            helperText="Exchange rate to convert to GBP (base currency)"
          />
          <FormControlLabel
            control={
              <Checkbox
                checked={formData.is_pinned}
                onChange={(e) =>
                  setFormData({ ...formData, is_pinned: e.target.checked })
                }
              />
            }
            label="Pin currency (show at top of list)"
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={handleSubmit} variant="contained" disabled={!formData.currency_code || formData.rate_to_gbp <= 0}>
          Save
        </Button>
      </DialogActions>
    </Dialog>
  );
}

