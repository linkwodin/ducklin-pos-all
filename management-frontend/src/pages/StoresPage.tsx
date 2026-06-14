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
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Checkbox,
  FormControlLabel,
  Link,
} from '@mui/material';
import { Add as AddIcon } from '@mui/icons-material';
import { Link as RouterLink, useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { storesAPI, devicesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Store, POSDevice } from '../types';

export default function StoresPage() {
  const { t } = useTranslation(['stores', 'storesPage']);
  const navigate = useNavigate();
  const [stores, setStores] = useState<Store[]>([]);
  const [devices, setDevices] = useState<POSDevice[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchStores();
  }, []);

  const fetchStores = async () => {
    try {
      setLoading(true);
      const data = await storesAPI.list();
      setStores(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch stores', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (storeData: Partial<Store>) => {
    try {
      await storesAPI.create(storeData);
      enqueueSnackbar('Store created', { variant: 'success' });
      setOpen(false);
      fetchStores();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to save store', {
        variant: 'error',
      });
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">{t('storesPage:title')}</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => setOpen(true)}
        >
          {t('stores:addStore')}
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>{t('storesPage:name')}</TableCell>
              <TableCell>{t('storesPage:address')}</TableCell>
              <TableCell>{t('stores:warehouseOnly')}</TableCell>
              <TableCell>{t('storesPage:status')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={4} align="center">
                  {t('storesPage:loading')}
                </TableCell>
              </TableRow>
            ) : stores.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} align="center">
                  {t('storesPage:noStores')}
                </TableCell>
              </TableRow>
            ) : (
              stores.map((store) => (
                <TableRow key={store.id} hover sx={{ cursor: 'pointer' }} onClick={() => navigate(`/stores/${store.id}`)}>
                  <TableCell>
                    <Link component={RouterLink} to={`/stores/${store.id}`} underline="hover" onClick={(e) => e.stopPropagation()}>
                      {store.name}
                    </Link>
                  </TableCell>
                  <TableCell>{store.address || '-'}</TableCell>
                  <TableCell>{store.is_warehouse_only ? t('stores:yes') : t('stores:no')}</TableCell>
                  <TableCell>{store.is_active ? t('storesPage:active') : t('storesPage:inactive')}</TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <StoreDialog
        open={open}
        onClose={() => setOpen(false)}
        onSave={handleSave}
      />
    </Box>
  );
}

function StoreDialog({
  open,
  onClose,
  onSave,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: Partial<Store>) => void;
}) {
  const { t } = useTranslation('stores');
  const [formData, setFormData] = useState({
    name: '',
    address: '',
    is_warehouse_only: false,
  });

  useEffect(() => {
    if (!open) {
      setFormData({ name: '', address: '', is_warehouse_only: false });
    }
  }, [open]);

  const handleSubmit = () => {
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{t('addStore')}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label={t('storeName')}
            required
            fullWidth
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          />
          <TextField
            label={t('address')}
            fullWidth
            multiline
            rows={3}
            value={formData.address}
            onChange={(e) => setFormData({ ...formData, address: e.target.value })}
          />
          <FormControlLabel
            control={
              <Checkbox
                checked={formData.is_warehouse_only}
                onChange={(e) => setFormData({ ...formData, is_warehouse_only: e.target.checked })}
              />
            }
            label={t('warehouseOnly')}
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('cancel')}</Button>
        <Button onClick={handleSubmit} variant="contained">
          {t('save')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

