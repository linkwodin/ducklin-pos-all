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
import { restockAPI, storesAPI, productsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { RestockOrder, Store, Product } from '../types';
import { format } from 'date-fns';

export default function RestockOrdersPage() {
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
    if (!window.confirm('Mark this order as received? This will update stock levels.')) {
      return;
    }
    try {
      await restockAPI.receive(id);
      enqueueSnackbar('Order marked as received', { variant: 'success' });
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
      enqueueSnackbar('Shipment created', { variant: 'success' });
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

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">Shipment</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => setOpen(true)}
        >
          Create Shipment
        </Button>
      </Box>

      <Box sx={{ display: 'flex', gap: 2, mb: 2 }}>
        <TextField
          select
          label="Filter by Store"
          value={storeFilter}
          onChange={(e) => setStoreFilter(e.target.value ? Number(e.target.value) : '')}
          sx={{ minWidth: 200 }}
          size="small"
        >
          <MenuItem value="">All Stores</MenuItem>
          {stores.map((store) => (
            <MenuItem key={store.id} value={store.id}>
              {store.name}
            </MenuItem>
          ))}
        </TextField>
        <TextField
          select
          label="Filter by Status"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          sx={{ minWidth: 200 }}
          size="small"
        >
          <MenuItem value="">All Statuses</MenuItem>
          <MenuItem value="initiated">Initiated</MenuItem>
          <MenuItem value="in_transit">In Transit</MenuItem>
          <MenuItem value="received">Received</MenuItem>
          <MenuItem value="cancelled">Cancelled</MenuItem>
        </TextField>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Order ID</TableCell>
              <TableCell>Store</TableCell>
              <TableCell>Items</TableCell>
              <TableCell>Tracking Number</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Initiated At</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={7} align="center">
                  Loading...
                </TableCell>
              </TableRow>
            ) : orders.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} align="center">
                  No orders found
                </TableCell>
              </TableRow>
            ) : (
              orders.map((order) => (
                <TableRow key={order.id}>
                  <TableCell>#{order.id}</TableCell>
                  <TableCell>{order.store?.name || '-'}</TableCell>
                  <TableCell>
                    {order.items?.length || 0} item(s)
                    {order.items && order.items.length > 0 && (
                      <Box component="ul" sx={{ pl: 2, m: 0, fontSize: '0.875rem' }}>
                        {order.items.slice(0, 2).map((item) => (
                          <li key={item.id}>
                            {item.product?.name}: {item.quantity}
                          </li>
                        ))}
                        {order.items.length > 2 && (
                          <li>...and {order.items.length - 2} more</li>
                        )}
                      </Box>
                    )}
                  </TableCell>
                  <TableCell>{order.tracking_number || '-'}</TableCell>
                  <TableCell>
                    <Chip
                      label={order.status}
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
      />
    </Box>
  );
}

function RestockOrderDialog({
  open,
  onClose,
  onSave,
  stores,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: {
    store_id: number;
    items: { product_id: number; quantity: number }[];
    notes?: string;
  }) => void;
  stores: Store[];
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
      <DialogTitle>Create Shipment</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            select
            label="Store"
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
            label="Notes"
            fullWidth
            multiline
            rows={3}
            value={formData.notes}
            onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
          />
          <Box>
            <Button onClick={handleAddItem} startIcon={<AddIcon />}>
              Add Item
            </Button>
            {formData.items.map((item, index) => (
              <Box key={index} sx={{ display: 'flex', gap: 1, mt: 1 }}>
                <TextField
                  select
                  label="Product"
                  required
                  sx={{ flex: 2 }}
                  size="small"
                  value={item.product_id}
                  onChange={(e) =>
                    handleItemChange(index, 'product_id', Number(e.target.value))
                  }
                >
                  {products.map((product) => (
                    <MenuItem key={product.id} value={product.id}>
                      {product.name}
                    </MenuItem>
                  ))}
                </TextField>
                <TextField
                  label="Quantity"
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
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={handleSubmit} variant="contained">
          Create Order
        </Button>
      </DialogActions>
    </Dialog>
  );
}

