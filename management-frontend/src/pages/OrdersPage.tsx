import { useEffect, useState } from 'react';
import {
  Box,
  Paper,
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
} from '@mui/material';
import {
  Visibility as VisibilityIcon,
  CheckCircle as CheckCircleIcon,
  Cancel as CancelIcon,
  Refresh as RefreshIcon,
} from '@mui/icons-material';
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
      const data = await storesAPI.list();
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

  const handleMarkPaid = async (orderId: number) => {
    try {
      await ordersAPI.markPaid(orderId);
      enqueueSnackbar(t('orders.orderMarkedPaid'), { variant: 'success' });
      fetchOrders();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('orders.failedToUpdateOrder'), { variant: 'error' });
    }
  };

  const handleMarkComplete = async (orderId: number) => {
    try {
      await ordersAPI.markComplete(orderId);
      enqueueSnackbar(t('orders.orderMarkedComplete'), { variant: 'success' });
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

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4">{t('orders.title')}</Typography>
        <Tooltip title={t('orders.refresh')}>
          <IconButton onClick={fetchOrders} disabled={loading}>
            <RefreshIcon />
          </IconButton>
        </Tooltip>
      </Box>

      <Paper sx={{ p: 2, mb: 3 }}>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <FormControl sx={{ minWidth: 200 }}>
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

          <FormControl sx={{ minWidth: 200 }}>
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

          <FormControl sx={{ minWidth: 200 }}>
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
              <TableCell>{t('orders.actions')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={7} align="center">
                  {t('orders.loading')}
                </TableCell>
              </TableRow>
            ) : orders.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} align="center">
                  {t('orders.noOrders')}
                </TableCell>
              </TableRow>
            ) : (
              orders.map((order) => (
                <TableRow key={order.id}>
                  <TableCell>{order.order_number}</TableCell>
                  <TableCell>{order.store?.name || `Store ${order.store_id}`}</TableCell>
                  <TableCell>
                    <UserDisplay user={order.user} showName={true} size="small" />
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={t(`orders.status${order.status.charAt(0).toUpperCase() + order.status.slice(1)}`)}
                      color={getStatusColor(order.status) as any}
                      size="small"
                    />
                  </TableCell>
                  <TableCell>£{order.total_amount.toFixed(2)}</TableCell>
                  <TableCell>
                    {format(new Date(order.created_at), 'yyyy-MM-dd HH:mm')}
                  </TableCell>
                  <TableCell>
                    <Tooltip title={t('orders.viewDetails')}>
                      <IconButton size="small" onClick={() => handleViewOrder(order)}>
                        <VisibilityIcon />
                      </IconButton>
                    </Tooltip>
                    {order.status === 'pending' && (
                      <>
                        <Tooltip title={t('orders.markPaid')}>
                          <IconButton
                            size="small"
                            color="primary"
                            onClick={() => handleMarkPaid(order.id)}
                          >
                            <CheckCircleIcon />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title={t('orders.cancel')}>
                          <IconButton
                            size="small"
                            color="error"
                            onClick={() => handleCancel(order.id)}
                          >
                            <CancelIcon />
                          </IconButton>
                        </Tooltip>
                      </>
                    )}
                    {order.status === 'paid' && (
                      <Tooltip title={t('orders.markComplete')}>
                        <IconButton
                          size="small"
                          color="success"
                          onClick={() => handleMarkComplete(order.id)}
                        >
                          <CheckCircleIcon />
                        </IconButton>
                      </Tooltip>
                    )}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

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
                <Chip
                  label={t(`orders.status${selectedOrder.status.charAt(0).toUpperCase() + selectedOrder.status.slice(1)}`)}
                  color={getStatusColor(selectedOrder.status) as any}
                  size="small"
                />
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
          <Button onClick={() => setOrderDialogOpen(false)}>{t('orders.close')}</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

