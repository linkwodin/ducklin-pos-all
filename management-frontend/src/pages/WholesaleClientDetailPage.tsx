import { useEffect, useState } from 'react';
import { useNavigate, useParams, Link as RouterLink } from 'react-router-dom';
import {
  Box,
  Button,
  Paper,
  Typography,
  CircularProgress,
  Link,
  Chip,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
} from '@mui/material';
import { Edit as EditIcon, Delete as DeleteIcon, ChevronRight as ChevronRightIcon } from '@mui/icons-material';
import { wholesaleClientsAPI, wholesaleOrdersAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { WholesaleClient, WholesaleOrder } from '../types';
import { wholesaleOrderStatusColor, wholesaleOrderStatusLabel } from '../utils/wholesaleOrderEmail';
import { format } from 'date-fns';

export default function WholesaleClientDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation();
  const [client, setClient] = useState<WholesaleClient | null>(null);
  const [recentOrders, setRecentOrders] = useState<WholesaleOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [ordersLoading, setOrdersLoading] = useState(true);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    if (!id) return;
    const numId = Number(id);
    if (Number.isNaN(numId)) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        setLoading(true);
        const data = await wholesaleClientsAPI.get(numId);
        if (!cancelled) setClient(data);
      } catch {
        if (!cancelled) enqueueSnackbar('Failed to load client', { variant: 'error' });
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [id, enqueueSnackbar]);

  useEffect(() => {
    if (!client) return;
    let cancelled = false;
    (async () => {
      try {
        setOrdersLoading(true);
        const data = await wholesaleOrdersAPI.list({ client: client.name });
        if (!cancelled) setRecentOrders((data ?? []).slice(0, 5));
      } catch {
        if (!cancelled) setRecentOrders([]);
      } finally {
        if (!cancelled) setOrdersLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [client]);

  const handleDeactivate = async () => {
    if (!client) return;
    if (!window.confirm(`Deactivate wholesale client "${client.name}"?`)) return;
    try {
      await wholesaleClientsAPI.delete(client.id);
      enqueueSnackbar('Client deactivated', { variant: 'success' });
      navigate('/wholesale-clients');
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to deactivate', { variant: 'error' });
    }
  };

  const totalForOrder = (order: WholesaleOrder) =>
    order.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0;

  if (loading) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!client) {
    return (
      <Box sx={{ p: 3 }}>
        <Typography color="text.secondary">{t('wholesaleClientDetail.clientNotFound')}</Typography>
        <Button sx={{ mt: 2 }} onClick={() => navigate('/wholesale-clients')}>{t('wholesaleClientDetail.backToList')}</Button>
      </Box>
    );
  }

  const activeStores = (client.stores ?? []).filter((s) => s.is_active);

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2 }}>
        <Link component={RouterLink} to="/" color="primary" underline="none">{t('common.home')}</Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <Link component={RouterLink} to="/wholesale-clients" color="primary" underline="none">
          {t('nav.wholesaleClients')}
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <span>{client.name}</span>
      </Typography>

      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 2, mb: 3 }}>
        <Typography variant="h5">{client.name}</Typography>
        <Box sx={{ display: 'flex', gap: 1 }}>
          <Button variant="contained" startIcon={<EditIcon />} onClick={() => navigate(`/wholesale-clients/${client.id}/edit`)}>
            {t('wholesaleClientDetail.edit')}
          </Button>
          {client.is_active && (
            <Button variant="outlined" color="error" startIcon={<DeleteIcon />} onClick={handleDeactivate}>
              {t('wholesaleClientDetail.deactivate')}
            </Button>
          )}
        </Box>
      </Box>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 2 }}>{t('wholesaleClientDetail.details')}</Typography>
        <Box
          sx={{
            display: 'grid',
            gridTemplateColumns: 'auto 1fr',
            columnGap: 3,
            rowGap: 0.5,
            alignItems: 'center',
          }}
        >
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.contact')}</Typography>
          <Typography variant="body2">{client.contact_name || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.email')}</Typography>
          <Typography variant="body2">{client.email || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.phone')}</Typography>
          <Typography variant="body2">{client.phone || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.vatNo')}</Typography>
          <Typography variant="body2">{client.vat_number || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.companyNo')}</Typography>
          <Typography variant="body2">{client.company_number || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.accountCode')}</Typography>
          <Typography variant="body2">{client.account_code || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.sector')}</Typography>
          <Typography variant="body2">{client.sector?.name || '—'}</Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.deliveryLocations')}</Typography>
          <Typography variant="body2">
            {activeStores.length > 0 ? activeStores.length : '—'}
          </Typography>
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.status')}</Typography>
          <Typography variant="body2">{client.is_active ? t('wholesaleClientDetail.active') : t('wholesaleClientDetail.inactive')}</Typography>
        </Box>
      </Paper>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>{t('wholesaleClientDetail.recentOrders')}</Typography>
          <Button variant="outlined" size="small" onClick={() => navigate(`/wholesale-orders?client_id=${client.id}`)}>
            {t('wholesaleClientDetail.viewAll')}
          </Button>
        </Box>
        {ordersLoading ? (
          <Box sx={{ py: 2, display: 'flex', justifyContent: 'center' }}>
            <CircularProgress size={24} />
          </Box>
        ) : recentOrders.length === 0 ? (
          <Typography variant="body2" color="text.secondary">{t('wholesaleClientDetail.noOrdersYet')}</Typography>
        ) : (
          <TableContainer>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>{t('wholesaleClientDetail.orderNumber')}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.date')}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.status')}</TableCell>
                  <TableCell align="right">{t('wholesaleClientDetail.total')}</TableCell>
                  <TableCell></TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {recentOrders.map((order) => (
                  <TableRow key={order.id}>
                    <TableCell>{order.order_number}</TableCell>
                    <TableCell>{format(new Date(order.created_at), 'dd MMM yyyy')}</TableCell>
                    <TableCell>
                      <Chip label={wholesaleOrderStatusLabel(order, t)} color={wholesaleOrderStatusColor(order)} size="small" />
                    </TableCell>
                    <TableCell align="right">£{totalForOrder(order).toFixed(2)}</TableCell>
                    <TableCell>
                      <Button size="small" onClick={() => navigate(`/wholesale-orders/${order.id}`)}>{t('wholesaleClientDetail.view')}</Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </Paper>

      <Paper sx={{ p: 3 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 2 }}>
          {t('wholesaleClientDetail.deliveryLocations')}
        </Typography>
        {activeStores.length === 0 ? (
          <Typography variant="body2" color="text.secondary">—</Typography>
        ) : (
          <TableContainer>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>{t('wholesaleClientDetail.locationName') ?? 'Name'}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.address')}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.postcode')}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.contact')}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.phone')}</TableCell>
                  <TableCell>{t('wholesaleClientDetail.email')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {activeStores.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell>{s.name}</TableCell>
                    <TableCell>
                      {[s.address_line1, s.address_line2].filter(Boolean).join(', ') || '—'}
                    </TableCell>
                    <TableCell>{s.postcode || '—'}</TableCell>
                    <TableCell>{s.contact_name || '—'}</TableCell>
                    <TableCell>{s.phone || '—'}</TableCell>
                    <TableCell>{s.email || '—'}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </Paper>
    </Box>
  );
}
