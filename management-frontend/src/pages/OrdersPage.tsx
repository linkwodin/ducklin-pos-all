import { useEffect, useState } from 'react';
import {
  Box,
  Paper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  Chip,
  TextField,
  MenuItem,
  IconButton,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Select,
  FormControl,
  InputLabel,
  CircularProgress,
  useMediaQuery,
} from '@mui/material';
import { useTheme } from '@mui/material/styles';
import { Refresh as RefreshIcon } from '@mui/icons-material';
import { ordersAPI, storesAPI, usersAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Order, Store, User } from '../types';
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import UserDisplay from '../components/UserDisplay';

export default function OrdersPage() {
  const { t } = useTranslation();
  const [orders, setOrders] = useState<Order[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedStore, setSelectedStore] = useState<number | ''>('');
  const [selectedStatus, setSelectedStatus] = useState<string>('');
  const [selectedStaffId, setSelectedStaffId] = useState<number | ''>('');
  const [staff, setStaff] = useState<User[]>([]);
  const [orderDialogOpen, setOrderDialogOpen] = useState(false);
  const [selectedOrder, setSelectedOrder] = useState<Order | null>(null);
  const { enqueueSnackbar } = useSnackbar();
  const theme = useTheme();
  const isListMobile = useMediaQuery(theme.breakpoints.down('md'));

  useEffect(() => {
    fetchStores();
    fetchStaff();
    fetchOrders();
  }, []);

  useEffect(() => {
    fetchOrders();
  }, [selectedStore, selectedStatus, selectedStaffId]);

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list({ exclude_warehouse_only: true });
      setStores(data);
    } catch (error) {
      enqueueSnackbar(t('orders.failedToFetchStores'), { variant: 'error' });
    }
  };

  const fetchStaff = async () => {
    try {
      const data = await usersAPI.list();
      setStaff(data || []);
    } catch (error) {
      enqueueSnackbar(t('orders.failedToFetchStaff'), { variant: 'error' });
    }
  };

  const fetchOrders = async () => {
    try {
      setLoading(true);
      const params: Record<string, unknown> = {};
      if (selectedStore) {
        params.store_id = Number(selectedStore);
      }
      if (selectedStatus) {
        params.status = selectedStatus;
      }
      if (selectedStaffId) {
        params.user_id = Number(selectedStaffId);
      }
      const data = await ordersAPI.list(params);
      setOrders(data);
    } catch (error) {
      enqueueSnackbar(t('orders.failedToFetchOrders'), { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleViewOrder = async (order: Order) => {
    try {
      const fullOrder = await ordersAPI.get(order.id);
      setSelectedOrder(fullOrder);
      setOrderDialogOpen(true);
    } catch (error) {
      enqueueSnackbar(t('orders.failedToLoadOrder'), { variant: 'error' });
    }
  };

  const refreshOrderInDialog = async (orderId: number) => {
    if (selectedOrder?.id !== orderId) return;
    try {
      const fullOrder = await ordersAPI.get(orderId);
      setSelectedOrder(fullOrder);
    } catch {
      // List refresh still runs; dialog may show stale data until closed.
    }
  };

  const handleMarkPaid = async (orderId: number) => {
    try {
      await ordersAPI.markPaid(orderId);
      enqueueSnackbar(t('orders.orderMarkedPaid'), { variant: 'success' });
      await refreshOrderInDialog(orderId);
      fetchOrders();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('orders.failedToUpdateOrder'), { variant: 'error' });
    }
  };

  const handleMarkComplete = async (orderId: number) => {
    try {
      await ordersAPI.markComplete(orderId);
      enqueueSnackbar(t('orders.orderMarkedComplete'), { variant: 'success' });
      await refreshOrderInDialog(orderId);
      fetchOrders();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('orders.failedToUpdateOrder'), { variant: 'error' });
    }
  };

  const handleCancel = async (orderId: number) => {
    if (!window.confirm(t('orders.confirmCancel'))) {
      return;
    }
    try {
      await ordersAPI.cancel(orderId);
      enqueueSnackbar(t('orders.orderCancelled'), { variant: 'success' });
      await refreshOrderInDialog(orderId);
      fetchOrders();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('orders.failedToUpdateOrder'), { variant: 'error' });
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending':
        return 'warning';
      case 'paid':
        return 'info';
      case 'completed':
        return 'success';
      case 'cancelled':
        return 'error';
      case 'picked_up':
        return 'secondary';
      default:
        return 'default';
    }
  };

  const statusLabel = (status: string) => {
    const suffix = status.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join('');
    return t(`orders.status${suffix}` as 'orders.statusPending');
  };

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          mb: 3,
          flexWrap: 'wrap',
          gap: 1.5,
        }}
      >
        <Typography variant="h4" sx={{ typography: { xs: 'h5', md: 'h4' } }}>
          {t('orders.title')}
        </Typography>
        <Tooltip title={t('orders.refresh')}>
          <IconButton onClick={fetchOrders} disabled={loading}>
            <RefreshIcon />
          </IconButton>
        </Tooltip>
      </Box>

      <Paper sx={{ p: 2, mb: 3 }}>
        <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
          <FormControl sx={{ minWidth: { xs: 0, sm: 200 }, width: { xs: '100%', sm: 'auto' } }}>
            <InputLabel>{t('orders.filterByStore')}</InputLabel>
            <Select
              value={selectedStore}
              onChange={(e) => setSelectedStore(e.target.value as number | '')}
              label={t('orders.filterByStore')}
            >
              <MenuItem value="">{t('orders.allStores')}</MenuItem>
              {stores.map((store) => (
                <MenuItem key={store.id} value={store.id}>
                  {store.name}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <FormControl sx={{ minWidth: { xs: 0, sm: 200 }, width: { xs: '100%', sm: 'auto' } }}>
            <InputLabel>{t('orders.filterByStatus')}</InputLabel>
            <Select
              value={selectedStatus}
              onChange={(e) => setSelectedStatus(e.target.value)}
              label={t('orders.filterByStatus')}
            >
              <MenuItem value="">{t('orders.allStatuses')}</MenuItem>
              <MenuItem value="pending">{t('orders.statusPending')}</MenuItem>
              <MenuItem value="paid">{t('orders.statusPaid')}</MenuItem>
              <MenuItem value="completed">{t('orders.statusCompleted')}</MenuItem>
              <MenuItem value="cancelled">{t('orders.statusCancelled')}</MenuItem>
              <MenuItem value="picked_up">{t('orders.statusPickedUp')}</MenuItem>
            </Select>
          </FormControl>

          <FormControl sx={{ minWidth: { xs: 0, sm: 200 }, width: { xs: '100%', sm: 'auto' } }}>
            <InputLabel>{t('orders.filterByStaff')}</InputLabel>
            <Select
              value={selectedStaffId === '' ? '' : selectedStaffId}
              onChange={(e) => setSelectedStaffId(e.target.value === '' ? '' : (e.target.value as number))}
              label={t('orders.filterByStaff')}
            >
              <MenuItem value="">{t('orders.allStaff')}</MenuItem>
              {staff.map((u) => (
                <MenuItem key={u.id} value={u.id}>
                  {u.first_name || u.last_name ? `${u.first_name} ${u.last_name}`.trim() : u.username}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        </Box>
      </Paper>

      {isListMobile ? (
        <Stack spacing={1.5} component={Paper} sx={{ p: 1.5 }}>
          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress size={28} />
            </Box>
          ) : orders.length === 0 ? (
            <Typography align="center" color="text.secondary" sx={{ py: 4 }}>
              {t('orders.noOrders')}
            </Typography>
          ) : (
            orders.map((order) => (
              <Paper
                key={order.id}
                variant="outlined"
                onClick={() => handleViewOrder(order)}
                sx={{ p: 1.5, borderRadius: 2, cursor: 'pointer' }}
              >
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 1, mb: 1 }}>
                  <Typography variant="subtitle1" sx={{ fontWeight: 700, wordBreak: 'break-word', lineHeight: 1.3, flex: 1, minWidth: 0 }}>
                    {order.order_number}
                  </Typography>
                  <Chip
                    label={statusLabel(order.status)}
                    color={getStatusColor(order.status) as any}
                    size="small"
                    sx={{ flexShrink: 0, maxWidth: '48%', height: 'auto', '& .MuiChip-label': { whiteSpace: 'normal', textAlign: 'right', py: 0.5 } }}
                  />
                </Box>
                <Stack spacing={0.5} sx={{ mb: 1.5 }}>
                  <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
                    <Box component="span" sx={{ color: 'text.secondary' }}>
                      {t('orders.store')}{' '}
                    </Box>
                    {order.store?.name || `Store ${order.store_id}`}
                  </Typography>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
                    <Typography variant="caption" color="text.secondary">
                      {t('orders.user')}
                    </Typography>
                    <UserDisplay user={order.user} showName={true} size="small" />
                  </Box>
                  <Typography variant="body2">
                    <Box component="span" sx={{ color: 'text.secondary' }}>
                      {t('orders.total')}{' '}
                    </Box>
                    £{order.total_amount.toFixed(2)}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {format(new Date(order.created_at), 'yyyy-MM-dd HH:mm')}
                  </Typography>
                </Stack>
              </Paper>
            ))
          )}
        </Stack>
      ) : (
        <TableContainer component={Paper}>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>{t('orders.orderNumber')}</TableCell>
                <TableCell>{t('orders.store')}</TableCell>
                <TableCell>{t('orders.user')}</TableCell>
                <TableCell>{t('orders.status')}</TableCell>
                <TableCell>{t('orders.total')}</TableCell>
                <TableCell>{t('orders.createdAt')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell colSpan={6} align="center">
                    {t('orders.loading')}
                  </TableCell>
                </TableRow>
              ) : orders.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={6} align="center">
                    {t('orders.noOrders')}
                  </TableCell>
                </TableRow>
              ) : (
                orders.map((order) => (
                  <TableRow
                    key={order.id}
                    hover
                    onClick={() => handleViewOrder(order)}
                    sx={{ cursor: 'pointer' }}
                  >
                    <TableCell>{order.order_number}</TableCell>
                    <TableCell>{order.store?.name || `Store ${order.store_id}`}</TableCell>
                    <TableCell>
                      <UserDisplay user={order.user} showName={true} size="small" />
                    </TableCell>
                    <TableCell>
                      <Chip label={statusLabel(order.status)} color={getStatusColor(order.status) as any} size="small" />
                    </TableCell>
                    <TableCell>£{order.total_amount.toFixed(2)}</TableCell>
                    <TableCell>{format(new Date(order.created_at), 'yyyy-MM-dd HH:mm')}</TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      {/* Order Details Dialog */}
      <Dialog open={orderDialogOpen} onClose={() => setOrderDialogOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle>
          {t('orders.orderDetails')} - {selectedOrder?.order_number}
        </DialogTitle>
        <DialogContent>
          {selectedOrder && (
            <Box>
              <Typography variant="subtitle2" gutterBottom>
                <strong>{t('orders.store')}:</strong> {selectedOrder.store?.name || `Store ${selectedOrder.store_id}`}
              </Typography>
              <Typography variant="subtitle2" gutterBottom>
                <strong>{t('orders.user')}:</strong>{' '}
                <UserDisplay user={selectedOrder.user} showName={true} size="small" />
              </Typography>
              <Typography variant="subtitle2" gutterBottom>
                <strong>{t('orders.status')}:</strong>{' '}
                <Chip label={statusLabel(selectedOrder.status)} color={getStatusColor(selectedOrder.status) as any} size="small" />
              </Typography>
              <Typography variant="subtitle2" gutterBottom>
                <strong>{t('orders.createdAt')}:</strong>{' '}
                {format(new Date(selectedOrder.created_at), 'yyyy-MM-dd HH:mm:ss')}
              </Typography>
              {selectedOrder.paid_at && (
                <Typography variant="subtitle2" gutterBottom>
                  <strong>{t('orders.paidAt')}:</strong>{' '}
                  {format(new Date(selectedOrder.paid_at), 'yyyy-MM-dd HH:mm:ss')}
                </Typography>
              )}
              {selectedOrder.completed_at && (
                <Typography variant="subtitle2" gutterBottom>
                  <strong>{t('orders.completedAt')}:</strong>{' '}
                  {format(new Date(selectedOrder.completed_at), 'yyyy-MM-dd HH:mm:ss')}
                </Typography>
              )}
              {selectedOrder.picked_up_at && (
                <Typography variant="subtitle2" gutterBottom>
                  <strong>{t('orders.pickedUpAt')}:</strong>{' '}
                  {format(new Date(selectedOrder.picked_up_at), 'yyyy-MM-dd HH:mm:ss')}
                </Typography>
              )}

              <Typography variant="h6" sx={{ mt: 2, mb: 1 }}>
                {t('orders.items')}
              </Typography>
              <TableContainer>
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell>{t('orders.product')}</TableCell>
                      <TableCell align="right">{t('orders.quantity')}</TableCell>
                      <TableCell align="right">{t('orders.unitPrice')}</TableCell>
                      <TableCell align="right">{t('orders.discount')}</TableCell>
                      <TableCell align="right">{t('orders.lineTotal')}</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {selectedOrder.items?.map((item) => (
                      <TableRow key={item.id}>
                        <TableCell>
                          {item.product?.name || item.product?.name_chinese || `Product ${item.product_id}`}
                        </TableCell>
                        <TableCell align="right">{item.quantity}</TableCell>
                        <TableCell align="right">£{item.unit_price.toFixed(2)}</TableCell>
                        <TableCell align="right">
                          {item.discount_percent > 0 ? `${item.discount_percent}%` : '-'}
                        </TableCell>
                        <TableCell align="right">£{item.line_total.toFixed(2)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>

              <Box sx={{ mt: 2, display: 'flex', justifyContent: 'space-between' }}>
                <Typography variant="subtitle1">
                  <strong>{t('orders.subtotal')}:</strong> £{selectedOrder.subtotal.toFixed(2)}
                </Typography>
                {selectedOrder.discount_amount > 0 && (
                  <Typography variant="subtitle1">
                    <strong>{t('orders.discount')}:</strong> -£{selectedOrder.discount_amount.toFixed(2)}
                  </Typography>
                )}
                <Typography variant="h6">
                  <strong>{t('orders.total')}:</strong> £{selectedOrder.total_amount.toFixed(2)}
                </Typography>
              </Box>
            </Box>
          )}
        </DialogContent>
        <DialogActions>
          {selectedOrder?.status === 'pending' && (
            <>
              <Button color="primary" onClick={() => handleMarkPaid(selectedOrder.id)}>
                {t('orders.markPaid')}
              </Button>
              <Button color="error" onClick={() => handleCancel(selectedOrder.id)}>
                {t('orders.cancel')}
              </Button>
            </>
          )}
          {selectedOrder?.status === 'paid' && (
            <Button color="success" onClick={() => handleMarkComplete(selectedOrder.id)}>
              {t('orders.markComplete')}
            </Button>
          )}
          <Button onClick={() => setOrderDialogOpen(false)}>{t('orders.close')}</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

