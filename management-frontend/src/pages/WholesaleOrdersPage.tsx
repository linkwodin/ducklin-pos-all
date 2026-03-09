import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
  Button,
  IconButton,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Fab,
  Autocomplete,
} from '@mui/material';
import {
  Visibility as VisibilityIcon,
  CheckCircle as CheckCircleIcon,
  Cancel as CancelIcon,
  Refresh as RefreshIcon,
  Add as AddIcon,
  LocalShipping as AssignIcon,
} from '@mui/icons-material';
import { wholesaleOrdersAPI, storesAPI, wholesaleClientsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { WholesaleOrder, Store, WholesaleClient } from '../types';
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import UserDisplay from '../components/UserDisplay';

export default function WholesaleOrdersPage() {
  const navigate = useNavigate();
  const { t, i18n } = useTranslation();
  const lang = i18n.language || 'en';
  const [orders, setOrders] = useState<WholesaleOrder[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [clients, setClients] = useState<WholesaleClient[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [clientFilter, setClientFilter] = useState<WholesaleClient | null>(null);
  const [poNumberFilter, setPONumberFilter] = useState('');
  const [orderNumberFilter, setOrderNumberFilter] = useState('');
  const [refNoFilter, setRefNoFilter] = useState('');
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectOrderId, setRejectOrderId] = useState<number | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [actioning, setActioning] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  const fetchStores = async () => {
    try {
      const [storesData, clientsData] = await Promise.all([
        storesAPI.list(),
        wholesaleClientsAPI.list(),
      ]);
      setStores(storesData);
      setClients(clientsData);
    } catch {
      enqueueSnackbar('Failed to load data', { variant: 'error' });
    }
  };

  const fetchOrders = async () => {
    try {
      setLoading(true);
      const params: Record<string, string> = {};
      if (statusFilter) params.status = statusFilter;
      if (clientFilter) params.client = clientFilter.name;
      if (poNumberFilter.trim()) params.po_number = poNumberFilter.trim();
      if (orderNumberFilter.trim()) params.order_number = orderNumberFilter.trim();
      if (refNoFilter.trim()) params.ref_no = refNoFilter.trim();
      const data = await wholesaleOrdersAPI.list(params);
      setOrders(data);
    } catch {
      enqueueSnackbar('Failed to load wholesale orders', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStores();
  }, []);

  useEffect(() => {
    fetchOrders();
  }, [statusFilter, clientFilter, poNumberFilter, orderNumberFilter, refNoFilter]);

  const handleView = (order: WholesaleOrder) => {
    navigate(`/wholesale-orders/${order.id}`);
  };

  const handleApprove = async (id: number) => {
    try {
      setActioning(true);
      await wholesaleOrdersAPI.approve(id);
      enqueueSnackbar('Order endorsed (assign shipment)', { variant: 'success' });
      fetchOrders();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to approve', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const openRejectDialog = (orderId: number) => {
    setRejectOrderId(orderId);
    setRejectReason('');
    setRejectDialogOpen(true);
  };

  const handleRejectSubmit = async () => {
    if (rejectOrderId == null) return;
    try {
      setActioning(true);
      await wholesaleOrdersAPI.reject(rejectOrderId, rejectReason);
      enqueueSnackbar('Order rejected', { variant: 'success' });
      fetchOrders();
      setRejectDialogOpen(false);
      setRejectOrderId(null);
      setRejectReason('');
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to reject', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const totalForOrder = (order: WholesaleOrder) =>
    order.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0;

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending_approval':
        return 'warning';
      case 'assign_shipment':
        return 'primary';
      case 'approved':
        return 'success';
      case 'rejected':
        return 'error';
      default:
        return 'default';
    }
  };

  return (
    <Box sx={{ p: 3, position: 'relative' }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5">Wholesale orders</Typography>
        <Box sx={{ display: 'flex', gap: 1 }}>
          <Button variant="contained" startIcon={<AddIcon />} onClick={() => navigate('/wholesale-orders/new')}>
            Create wholesale order
          </Button>
          <Tooltip title="Refresh">
            <IconButton onClick={fetchOrders} disabled={loading}>
              <RefreshIcon />
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      <Paper sx={{ p: 2, mb: 3 }}>
        <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
          <FormControl size="small" sx={{ minWidth: 170 }}>
            <InputLabel>Status</InputLabel>
            <Select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              label="Status"
            >
              <MenuItem value="">All</MenuItem>
              <MenuItem value="pending_approval">Pending approval</MenuItem>
              <MenuItem value="assign_shipment">Assign shipment</MenuItem>
              <MenuItem value="approved">Approved</MenuItem>
              <MenuItem value="rejected">Rejected</MenuItem>
            </Select>
          </FormControl>
          <Autocomplete
            size="small"
            options={clients}
            getOptionLabel={(o) => o.name}
            value={clientFilter}
            onChange={(_, v) => setClientFilter(v)}
            renderInput={(params) => <TextField {...params} label="Client" />}
            sx={{ width: 200 }}
            isOptionEqualToValue={(o, v) => o.id === v.id}
          />
          <TextField size="small" label="PO Number" value={poNumberFilter} onChange={(e) => setPONumberFilter(e.target.value)} sx={{ width: 140 }} />
          <TextField size="small" label="Order Number" value={orderNumberFilter} onChange={(e) => setOrderNumberFilter(e.target.value)} sx={{ width: 180 }} />
          <TextField size="small" label="OC Number" value={refNoFilter} onChange={(e) => setRefNoFilter(e.target.value)} sx={{ width: 140 }} />
        </Box>
      </Paper>

      <TableContainer component={Paper}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>Order #</TableCell>
              <TableCell>PO / Ref</TableCell>
              <TableCell>Client</TableCell>
              <TableCell>Created by</TableCell>
              <TableCell>Status</TableCell>
              <TableCell align="right">Total</TableCell>
              <TableCell>Date</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={8} align="center"><CircularProgress size={24} /></TableCell>
              </TableRow>
            ) : orders.length === 0 ? (
              <TableRow>
                <TableCell colSpan={8} align="center">No wholesale orders found</TableCell>
              </TableRow>
            ) : (
              orders.map((order) => (
                <TableRow key={order.id}>
                  <TableCell>{order.order_number}</TableCell>
                  <TableCell sx={{ fontSize: 12 }}>{[order.po_number, order.ref_no].filter(Boolean).join(' / ') || '-'}</TableCell>
                  <TableCell>{order.wholesale_client?.name ?? `Client #${order.wholesale_client_id}`}</TableCell>
                  <TableCell>
                    {order.user ? (
                      <UserDisplay user={order.user} />
                    ) : (
                      `User #${order.user_id}`
                    )}
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={order.status.replace('_', ' ')}
                      color={getStatusColor(order.status) as any}
                      size="small"
                    />
                  </TableCell>
                  <TableCell align="right">£{totalForOrder(order).toFixed(2)}</TableCell>
                  <TableCell>{format(new Date(order.created_at), 'dd MMM yyyy HH:mm')}</TableCell>
                  <TableCell>
                    <Tooltip title={order.status === 'assign_shipment' ? 'Assign shipment' : 'View'}>
                      <IconButton size="small" onClick={() => handleView(order)}>
                        {order.status === 'assign_shipment' ? <AssignIcon fontSize="small" /> : <VisibilityIcon fontSize="small" />}
                      </IconButton>
                    </Tooltip>
                    {order.status === 'pending_approval' && (
                      <>
                        <Tooltip title="Endorse">
                          <IconButton size="small" color="success" onClick={() => handleApprove(order.id)} disabled={actioning}>
                            <CheckCircleIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title="Reject">
                          <IconButton size="small" color="error" onClick={() => openRejectDialog(order.id)} disabled={actioning}>
                            <CancelIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                      </>
                    )}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <Dialog open={rejectDialogOpen} onClose={() => { setRejectDialogOpen(false); setRejectOrderId(null); setRejectReason(''); }}>
        <DialogTitle>Reject wholesale order</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            label="Reason (optional)"
            fullWidth
            variant="outlined"
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => { setRejectDialogOpen(false); setRejectOrderId(null); setRejectReason(''); }}>Cancel</Button>
          <Button onClick={handleRejectSubmit} color="error" variant="contained" disabled={actioning}>
            Reject
          </Button>
        </DialogActions>
      </Dialog>

      <Fab
        color="primary"
        aria-label="Create wholesale order"
        sx={{ position: 'fixed', bottom: 24, right: 24 }}
        onClick={() => navigate('/wholesale-orders/new')}
      >
        <AddIcon />
      </Fab>

    </Box>
  );
}
