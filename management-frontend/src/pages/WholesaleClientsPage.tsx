import { useEffect, useState, useRef } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
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
  CircularProgress,
  Chip,
} from '@mui/material';
import { Add as AddIcon } from '@mui/icons-material';
import { wholesaleClientsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { WholesaleClient } from '../types';

export default function WholesaleClientsPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const { t } = useTranslation();
  const [clients, setClients] = useState<WholesaleClient[]>([]);
  const [loading, setLoading] = useState(true);
  const [highlightClientId, setHighlightClientId] = useState<number | null>(null);
  const { enqueueSnackbar } = useSnackbar();
  const hasHandledCreateRef = useRef(false);

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

  // After create: show snackbar, flash the new row, clear location state
  useEffect(() => {
    const state = location.state as { createdClientId?: number } | null;
    const createdId = state?.createdClientId;
    if (createdId != null && !hasHandledCreateRef.current) {
      hasHandledCreateRef.current = true;
      enqueueSnackbar('Client created', { variant: 'success' });
      setHighlightClientId(createdId);
      navigate(location.pathname, { replace: true, state: {} });
      const t = setTimeout(() => setHighlightClientId(null), 5000);
      return () => clearTimeout(t);
    }
  }, [location.state, location.pathname, navigate, enqueueSnackbar]);

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5">{t('nav.wholesaleClients')}</Typography>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => navigate('/wholesale-clients/new')}>
          {t('wholesaleClientsPage.addClient')}
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>{t('common.name')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.contact')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.email')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.phone')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.vatNo')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.companyNo')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.accountCode')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.sector')}</TableCell>
              <TableCell>{t('wholesaleClientsPage.deliveryLocations')}</TableCell>
              <TableCell>{t('common.status')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={10} align="center">
                  <CircularProgress size={24} />
                </TableCell>
              </TableRow>
            ) : clients.length === 0 ? (
              <TableRow>
                <TableCell colSpan={10} align="center">
                  {t('wholesaleClientsPage.noClients')}
                </TableCell>
              </TableRow>
            ) : (
              clients.map((client) => {
                const activeStores = (client.stores ?? []).filter((s) => s.is_active);
                const isHighlighted = highlightClientId === client.id;
                return (
                  <TableRow
                    key={client.id}
                    hover
                    sx={(theme) => ({
                      cursor: 'pointer',
                      ...(isHighlighted && {
                        animation: 'flashTwice 5s ease-in-out forwards',
                        '@keyframes flashTwice': {
                          '0%': { backgroundColor: theme.palette.success.light },
                          '20%': { backgroundColor: 'transparent' },
                          '40%': { backgroundColor: theme.palette.success.light },
                          '60%': { backgroundColor: 'transparent' },
                          '100%': { backgroundColor: 'transparent' },
                        },
                      }),
                    })}
                    onClick={() => navigate(`/wholesale-clients/${client.id}`)}
                  >
                    <TableCell>{client.name}</TableCell>
                    <TableCell>{client.contact_name || '—'}</TableCell>
                    <TableCell>{client.email || '—'}</TableCell>
                    <TableCell>{client.phone || '—'}</TableCell>
                    <TableCell>{client.vat_number || '—'}</TableCell>
                    <TableCell>{client.company_number || '—'}</TableCell>
                    <TableCell>{client.account_code || '—'}</TableCell>
                    <TableCell>{client.sector?.name || '—'}</TableCell>
                    <TableCell>
                      {activeStores.length > 0
                        ? t('wholesaleClientsPage.shippingAddressCount', { count: activeStores.length })
                        : '—'}
                    </TableCell>
                    <TableCell>{client.is_active ? 'Active' : 'Inactive'}</TableCell>
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
