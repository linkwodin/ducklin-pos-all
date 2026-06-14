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
  Chip,
  TextField,
  MenuItem,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  IconButton,
} from '@mui/material';
import {
  Add as AddIcon,
  Delete as DeleteIcon,
  CheckCircle as CheckCircleIcon,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { restockAPI, storesAPI, productsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { RestockOrder, Store, Product } from '../types';
import { format } from 'date-fns';
import ProductAutocomplete from '../components/ProductAutocomplete';

export default function RestockOrdersPage() {
  const { t } = useTranslation('shipment');
  const [orders, setOrders] = useState<RestockOrder[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [statusFilter, setStatusFilter] = useState('');
  const [storeFilter, setStoreFilter] = useState<number | ''>('');
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchStores();
    fetchOrders();
  }, []);

  useEffect(() => {
    fetchOrders();
  }, [statusFilter, storeFilter]);

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list();
      setStores(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch stores', { variant: 'error' });
    }
  };

  const fetchOrders = async () => {
    try {
      setLoading(true);
      const data = await restockAPI.list(
        storeFilter ? Number(storeFilter) : undefined,
        statusFilter || undefined
      );
      setOrders(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch shipments', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleReceive = async (id: number) => {
    if (!window.confirm(t('markReceived'))) {
      return;
    }
    try {
      await restockAPI.receive(id);
      enqueueSnackbar(t('orderReceived'), { variant: 'success' });
      fetchOrders();
    } catch (error) {
      enqueueSnackbar('Failed to receive order', { variant: 'error' });
    }
  };

  const handleSave = async (orderData: {
    store_id: number;
    items: { product_id: number; quantity: number }[];
    notes?: string;
  }) => {
    try {
      await restockAPI.create(orderData);
      enqueueSnackbar(t('shipmentCreated'), { variant: 'success' });
      setOpen(false);
      fetchOrders();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to create order', {
        variant: 'error',
      });
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'initiated':
        return 'default';
      case 'in_transit':
        return 'warning';
      case 'received':
        return 'success';
      case 'cancelled':
        return 'error';
      default:
        return 'default';
    }
  };

  const statusToLabel = (status: string) => {
    const map: Record<string, string> = {
      initiated: t('initiated'),
      in_transit: t('inTransit'),
      received: t('received'),
      cancelled: t('cancelled'),
    };
    return map[status] || status;
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">{t('title')}</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => setOpen(true)}
        >
          {t('createShipment')}
        </Button>
      </Box>

      <Box sx={{ display: 'flex', gap: 2, mb: 2 }}>
        <TextField
          select
          label={t('filterByStore')}
          value={storeFilter}
          onChange={(e) => setStoreFilter(e.target.value ? Number(e.target.value) : '')}
          sx={{ minWidth: 200 }}
          size="small"
        >
          <MenuItem value="">{t('allStores')}</MenuItem>
          {stores.map((store) => (
            <MenuItem key={store.id} value={store.id}>
              {store.name}
            </MenuItem>
          ))}
        </TextField>
        <TextField
          select
          label={t('filterByStatus')}
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          sx={{ minWidth: 200 }}
          size="small"
        >
          <MenuItem value="">{t('allStatuses')}</MenuItem>
          <MenuItem value="initiated">{t('initiated')}</MenuItem>
          <MenuItem value="in_transit">{t('inTransit')}</MenuItem>
          <MenuItem value="received">{t('received')}</MenuItem>
          <MenuItem value="cancelled">{t('cancelled')}</MenuItem>
        </TextField>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>{t('orderId')}</TableCell>
              <TableCell>{t('store')}</TableCell>
              <TableCell>{t('items')}</TableCell>
              <TableCell>{t('trackingNumber')}</TableCell>
              <TableCell>{t('status')}</TableCell>
              <TableCell>{t('initiatedAt')}</TableCell>
              <TableCell>{t('actions')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={7} align="center">
                  {t('loading')}
                </TableCell>
              </TableRow>
            ) : orders.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} align="center">
                  {t('noOrders')}
                </TableCell>
              </TableRow>
            ) : (
              orders.map((order) => (
                <TableRow key={order.id}>
                  <TableCell>#{order.id}</TableCell>
                  <TableCell>{order.store?.name || '-'}</TableCell>
                  <TableCell>
                    {t('itemsCount', { count: order.items?.length || 0 })}
                    {order.items && order.items.length > 0 && (
                      <Box component="ul" sx={{ pl: 2, m: 0, fontSize: '0.875rem' }}>
                        {order.items.slice(0, 2).map((item) => (
                          <li key={item.id}>
                            {item.product?.name}: {item.quantity}
                          </li>
                        ))}
                        {order.items.length > 2 && (
                          <li>{t('andMore', { count: order.items.length - 2 })}</li>
                        )}
                      </Box>
                    )}
                  </TableCell>
                  <TableCell>{order.tracking_number || '-'}</TableCell>
                  <TableCell>
                    <Chip
                      label={statusToLabel(order.status)}
                      size="small"
                      color={getStatusColor(order.status) as any}
                    />
                  </TableCell>
                  <TableCell>
                    {format(new Date(order.initiated_at), 'MMM dd, yyyy HH:mm')}
                  </TableCell>
                  <TableCell>
                    {order.status !== 'received' && (
                      <IconButton
                        size="small"
                        onClick={() => handleReceive(order.id)}
                        color="success"
                      >
                        <CheckCircleIcon />
                      </IconButton>
                    )}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <RestockOrderDialog
        open={open}
        onClose={() => setOpen(false)}
        onSave={handleSave}
        stores={stores}
        t={t}
      />
    </Box>
  );
}

function RestockOrderDialog({
  open,
  onClose,
  onSave,
  stores,
  t,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: {
    store_id: number;
    items: { product_id: number; quantity: number }[];
    notes?: string;
  }) => void;
  stores: Store[];
  t: (key: string) => string;
}) {
  const [formData, setFormData] = useState({
    store_id: 0,
    items: [] as { product_id: number; quantity: number }[],
    notes: '',
  });
  const [products, setProducts] = useState<Product[]>([]);

  useEffect(() => {
    if (open) {
      fetchProducts();
    }
  }, [open]);

  const fetchProducts = async () => {
    try {
      const data = await productsAPI.list();
      setProducts(data);
    } catch (error) {
      console.error('Failed to fetch products:', error);
    }
  };

  const handleAddItem = () => {
    setFormData({
      ...formData,
      items: [...formData.items, { product_id: 0, quantity: 0 }],
    });
  };

  const handleItemChange = (index: number, field: string, value: any) => {
    const newItems = [...formData.items];
    newItems[index] = { ...newItems[index], [field]: value };
    setFormData({ ...formData, items: newItems });
  };

  const handleRemoveItem = (index: number) => {
    setFormData({
      ...formData,
      items: formData.items.filter((_, i) => i !== index),
    });
  };

  const handleSubmit = () => {
    if (formData.store_id === 0 || formData.items.length === 0) {
      return;
    }
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>{t('createShipment')}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            select
            label={t('store')}
            required
            fullWidth
            value={formData.store_id}
            onChange={(e) =>
              setFormData({ ...formData, store_id: Number(e.target.value) })
            }
          >
            {stores.map((store) => (
              <MenuItem key={store.id} value={store.id}>
                {store.name}
              </MenuItem>
            ))}
          </TextField>
          <TextField
            label={t('notes')}
            fullWidth
            multiline
            rows={3}
            value={formData.notes}
            onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
          />
          <Box>
            <Button onClick={handleAddItem} startIcon={<AddIcon />}>
              {t('addItem')}
            </Button>
            {formData.items.map((item, index) => (
              <Box key={index} sx={{ display: 'flex', gap: 1, mt: 1 }}>
                <Box sx={{ flex: 2 }}>
                  <ProductAutocomplete
                    products={products}
                    value={item.product_id || null}
                    onChange={(id) => handleItemChange(index, 'product_id', id ?? 0)}
                    label={t('product')}
                  />
                </Box>
                <TextField
                  label={t('quantity')}
                  type="number"
                  required
                  sx={{ flex: 1 }}
                  size="small"
                  value={item.quantity}
                  onChange={(e) =>
                    handleItemChange(index, 'quantity', parseFloat(e.target.value))
                  }
                />
                <IconButton onClick={() => handleRemoveItem(index)} color="error">
                  <DeleteIcon />
                </IconButton>
              </Box>
            ))}
          </Box>
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('cancel')}</Button>
        <Button onClick={handleSubmit} variant="contained">
          {t('createOrder')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

