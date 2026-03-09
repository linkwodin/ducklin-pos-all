import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
  CircularProgress,
  Chip,
} from '@mui/material';
import { Add as AddIcon, Edit as EditIcon, Delete as DeleteIcon } from '@mui/icons-material';
import { wholesaleClientsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { WholesaleClient } from '../types';

export default function WholesaleClientsPage() {
  const navigate = useNavigate();
  const [clients, setClients] = useState<WholesaleClient[]>([]);
  const [loading, setLoading] = useState(true);
  const { enqueueSnackbar } = useSnackbar();

  const fetchClients = async () => {
    try {
      setLoading(true);
      const data = await wholesaleClientsAPI.list();
      setClients(data);
    } catch {
      enqueueSnackbar('Failed to load wholesale clients', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchClients();
  }, []);

  const handleDelete = async (client: WholesaleClient) => {
    if (!window.confirm(`Deactivate wholesale client "${client.name}"?`)) return;
    try {
      await wholesaleClientsAPI.delete(client.id);
      enqueueSnackbar('Client deactivated', { variant: 'success' });
      fetchClients();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to deactivate', { variant: 'error' });
    }
  };

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5">Wholesale clients</Typography>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => navigate('/wholesale-clients/new')}>
          Add client
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>Name</TableCell>
              <TableCell>Contact</TableCell>
              <TableCell>Email</TableCell>
              <TableCell>Phone</TableCell>
              <TableCell>VAT No.</TableCell>
              <TableCell>Company No.</TableCell>
              <TableCell>Account Code</TableCell>
              <TableCell>Sector</TableCell>
              <TableCell>Delivery locations</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={11} align="center">
                  <CircularProgress size={24} />
                </TableCell>
              </TableRow>
            ) : clients.length === 0 ? (
              <TableRow>
                <TableCell colSpan={11} align="center">
                  No wholesale clients
                </TableCell>
              </TableRow>
            ) : (
              clients.map((client) => {
                const activeStores = (client.stores ?? []).filter((s) => s.is_active);
                return (
                  <TableRow key={client.id} hover sx={{ cursor: 'pointer' }} onClick={() => navigate(`/wholesale-clients/${client.id}`)}>
                    <TableCell>{client.name}</TableCell>
                    <TableCell>{client.contact_name || '—'}</TableCell>
                    <TableCell>{client.email || '—'}</TableCell>
                    <TableCell>{client.phone || '—'}</TableCell>
                    <TableCell>{client.vat_number || '—'}</TableCell>
                    <TableCell>{client.company_number || '—'}</TableCell>
                    <TableCell>{client.account_code || '—'}</TableCell>
                    <TableCell>{client.sector?.name || '—'}</TableCell>
                    <TableCell>
                      {activeStores.length > 0 ? (
                        activeStores.map((s) => (
                          <Chip key={s.id} label={s.name} size="small" sx={{ mr: 0.5, mb: 0.25 }} />
                        ))
                      ) : '—'}
                    </TableCell>
                    <TableCell>{client.is_active ? 'Active' : 'Inactive'}</TableCell>
                    <TableCell onClick={(e) => e.stopPropagation()}>
                      <IconButton size="small" onClick={() => navigate(`/wholesale-clients/${client.id}`)} title="Edit">
                        <EditIcon fontSize="small" />
                      </IconButton>
                      {client.is_active && (
                        <IconButton size="small" color="error" onClick={() => handleDelete(client)} title="Deactivate">
                          <DeleteIcon fontSize="small" />
                        </IconButton>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </TableContainer>
    </Box>
  );
}
