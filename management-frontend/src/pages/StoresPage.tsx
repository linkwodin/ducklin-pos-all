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
} from '@mui/material';
import { Add as AddIcon } from '@mui/icons-material';
import { storesAPI, devicesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Store, POSDevice } from '../types';

export default function StoresPage() {
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
        <Typography variant="h4">Stores & Devices</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => setOpen(true)}
        >
          Add Store
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Name</TableCell>
              <TableCell>Address</TableCell>
              <TableCell>Status</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={3} align="center">
                  Loading...
                </TableCell>
              </TableRow>
            ) : stores.length === 0 ? (
              <TableRow>
                <TableCell colSpan={3} align="center">
                  No stores found
                </TableCell>
              </TableRow>
            ) : (
              stores.map((store) => (
                <TableRow key={store.id}>
                  <TableCell>{store.name}</TableCell>
                  <TableCell>{store.address || '-'}</TableCell>
                  <TableCell>{store.is_active ? 'Active' : 'Inactive'}</TableCell>
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
  const [formData, setFormData] = useState({
    name: '',
    address: '',
  });

  useEffect(() => {
    if (!open) {
      setFormData({ name: '', address: '' });
    }
  }, [open]);

  const handleSubmit = () => {
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Add Store</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label="Name"
            required
            fullWidth
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          />
          <TextField
            label="Address"
            fullWidth
            multiline
            rows={3}
            value={formData.address}
            onChange={(e) => setFormData({ ...formData, address: e.target.value })}
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={handleSubmit} variant="contained">
          Save
        </Button>
      </DialogActions>
    </Dialog>
  );
}

