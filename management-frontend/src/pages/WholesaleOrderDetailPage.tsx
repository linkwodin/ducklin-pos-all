import { useEffect, useMemo, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Box,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
  Button,
  TextField,
  Select,
  MenuItem,
  CircularProgress,
  Chip,
  Checkbox,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogContentText,
  DialogActions,
  ButtonGroup,
  Menu,
  MenuItem as MuiMenuItem,
  IconButton,
  Tooltip,
  Autocomplete,
} from '@mui/material';
import {
  ArrowBack as BackIcon,
  CheckCircle as CompleteIcon,
  Download as DownloadIcon,
  Refresh as RefreshIcon,
  Edit as EditIcon,
  LocalShipping as ShipmentIcon,
  Replay as RegenIcon,
  ArrowDropDown as ArrowDropDownIcon,
  ArrowDropUp as ArrowDropUpIcon,
  History as HistoryIcon,
} from '@mui/icons-material';
import { wholesaleOrdersAPI, storesAPI, stockAPI, shipmentsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { WholesaleOrder, Store, Shipment } from '../types';
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import UserDisplay from '../components/UserDisplay';
import { productDisplayName } from '../utils/productDisplay';
import ProductImageWithPopover from '../components/ProductImageWithPopover';

const ORDER_CHANNEL_OPTIONS: { value: string; label: string }[] = [
  { value: 'po', label: 'Client PO' },
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'email', label: 'Email' },
];

export default function WholesaleOrderDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { i18n } = useTranslation();
  const lang = i18n.language || 'en';
  const [order, setOrder] = useState<WholesaleOrder | null>(null);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [actioning, setActioning] = useState(false);
  const [assignmentDraft, setAssignmentDraft] = useState<Record<number, number | ''>>({});
  const [selectedItemIds, setSelectedItemIds] = useState<Set<number>>(new Set());
  const [assignToStoreId, setAssignToStoreId] = useState<number | ''>('');
  const [rejectReason, setRejectReason] = useState('');
  const [showReject, setShowReject] = useState(false);
  const [assignWarningOpen, setAssignWarningOpen] = useState(false);
  const [assignWarningRows, setAssignWarningRows] = useState<{ product: string; reason: string; detail?: string }[]>([]);
  const [regenConfirmLoading, setRegenConfirmLoading] = useState(false);
  const [editingShipment, setEditingShipment] = useState<Shipment | null>(null);
  const [shipmentCourier, setShipmentCourier] = useState('');
  const [shipmentTracking, setShipmentTracking] = useState('');
  const [shipmentSaving, setShipmentSaving] = useState(false);
  const [regenShipmentId, setRegenShipmentId] = useState<number | null>(null);
  const [completeShipmentDialog, setCompleteShipmentDialog] = useState<Shipment | null>(null);
  const [completeShipmentSubmitting, setCompleteShipmentSubmitting] = useState(false);
  const [caseQtyByOrderItemId, setCaseQtyByOrderItemId] = useState<Record<number, string>>({});
  const [editBoxesShipment, setEditBoxesShipment] = useState<Shipment | null>(null);
  const [editBoxesSaving, setEditBoxesSaving] = useState(false);
  const [shippingFeeDialogOpen, setShippingFeeDialogOpen] = useState(false);
  const [shippingFeeDraft, setShippingFeeDraft] = useState('');
  const [shippingFeeSaving, setShippingFeeSaving] = useState(false);
  const [showAssignment, setShowAssignment] = useState(true);
  const [docMenuAnchorEl, setDocMenuAnchorEl] = useState<null | HTMLElement>(null);
  const [invoiceMenuAnchorEl, setInvoiceMenuAnchorEl] = useState<null | HTMLElement>(null);
  const [regenInvoiceLoading, setRegenInvoiceLoading] = useState(false);
  const [editingItemId, setEditingItemId] = useState<number | null>(null);
  const [editingItemPrice, setEditingItemPrice] = useState('');
  const [poChannelDialogOpen, setPOChannelDialogOpen] = useState(false);
  const [editingRefNo, setEditingRefNo] = useState(false);
  const [editingPODate, setEditingPODate] = useState(false);
  const [poNumberDraft, setPONumberDraft] = useState('');
  const [orderChannelDraft, setOrderChannelDraft] = useState('');
  const [recentOrderChannels, setRecentOrderChannels] = useState<string[]>([]);
  const [poChannelSaving, setPOChannelSaving] = useState(false);
  const [refNoDraft, setRefNoDraft] = useState('');
  const [poDateDraft, setPODateDraft] = useState('');
  const { enqueueSnackbar } = useSnackbar();

  const orderId = id ? Number(id) : NaN;
  const canAssign = order?.status === 'assign_shipment' || order?.status === 'approved';

  useEffect(() => {
    if (!id || Number.isNaN(orderId)) return;
    const load = async () => {
      try {
        setLoading(true);
        const [orderData, storesData, channels] = await Promise.all([
          wholesaleOrdersAPI.get(orderId),
          storesAPI.list(),
          wholesaleOrdersAPI.getRecentOrderChannels().catch(() => []),
        ]);
        setOrder(orderData);
        setStores(storesData);
        setRecentOrderChannels(channels);
        const draft: Record<number, number | ''> = {};
        orderData.items?.forEach((it) => {
          draft[it.id] = it.assigned_store_id ?? '';
        });
        setAssignmentDraft(draft);
        const allAssignedInitial = !!orderData.items?.length && orderData.items.every((it) => it.assigned_store_id != null);
        setShowAssignment(!allAssignedInitial);
      } catch {
        enqueueSnackbar('Failed to load order', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [id, orderId, enqueueSnackbar]);

  useEffect(() => {
    const shipment = completeShipmentDialog ?? editBoxesShipment;
    if (!shipment?.items?.length) {
      setCaseQtyByOrderItemId({});
      return;
    }
    const next: Record<number, string> = {};
    shipment.items.forEach((it) => {
      const q = it.case_qty;
      next[it.wholesale_order_item_id] =
        q != null && q > 0 ? String(q) : '';
    });
    setCaseQtyByOrderItemId(next);
  }, [completeShipmentDialog, editBoxesShipment]);

  const totalForOrder = (o: WholesaleOrder) =>
    o.total_net != null
      ? o.total_net
      : o.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0;

  const orderChannelOptions = useMemo(() => {
    const seen = new Set(recentOrderChannels.map((c) => c.toLowerCase()));
    const standard = ORDER_CHANNEL_OPTIONS.map((o) => o.value).filter((v) => !seen.has(v.toLowerCase()));
    return [...recentOrderChannels, ...standard];
  }, [recentOrderChannels]);

  const openPOChannelDialog = () => {
    if (order) {
      setOrderChannelDraft(order.order_channel || '');
      setPONumberDraft(order.po_number || '');
      setPOChannelDialogOpen(true);
    }
  };

  const savePOAndChannel = async () => {
    if (!order) return;
    setPOChannelSaving(true);
    try {
      const isClientPO = orderChannelDraft.trim().toLowerCase() === 'po';
      const updated = await wholesaleOrdersAPI.update(order.id, {
        order_channel: orderChannelDraft.trim() || undefined,
        po_number: isClientPO ? (poNumberDraft.trim() || undefined) : '',
      });
      setOrder(updated);
      setPOChannelDialogOpen(false);
      enqueueSnackbar('PO & channel updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update', { variant: 'error' });
    } finally {
      setPOChannelSaving(false);
    }
  };

  const orderChannelDisplayLabel = (ch: string) =>
    ORDER_CHANNEL_OPTIONS.find((o) => o.value === ch)?.label ?? ch;

  const saveRefNo = async () => {
    if (!order) return;
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { ref_no: refNoDraft });
      setOrder(updated);
      setEditingRefNo(false);
      enqueueSnackbar('OC Number updated', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to update OC Number', { variant: 'error' });
      // Keep editing so user can fix and retry
    }
  };

  const savePODate = async () => {
    if (!order) return;
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { po_date: poDateDraft || '' });
      setOrder(updated);
      setEditingPODate(false);
      enqueueSnackbar('PO Date updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update PO Date', { variant: 'error' });
    }
  };

  const saveItemPrice = async (itemId: number) => {
    if (!order) return;
    const price = parseFloat(editingItemPrice);
    if (isNaN(price) || price < 0) return;
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { items: [{ id: itemId, unit_price: price }] });
      setOrder(updated);
      setEditingItemId(null);
      enqueueSnackbar('Unit price updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update unit price', { variant: 'error' });
    }
  };

  const toggleItemSelected = (itemId: number) => {
    setSelectedItemIds((prev) => {
      const next = new Set(prev);
      if (next.has(itemId)) next.delete(itemId);
      else next.add(itemId);
      return next;
    });
  };

  const performAssignment = async () => {
    if (!order?.items?.length || assignToStoreId === '') return;
    const selected = Array.from(selectedItemIds);
    const store = stores.find((s) => s.id === assignToStoreId);
    const storeName = store?.name ?? `Store #${assignToStoreId}`;
    try {
      setActioning(true);
      const assignments = order.items.map((it) => ({
        wholesale_order_item_id: it.id,
        store_id: selected.includes(it.id) ? (assignToStoreId as number) : ((assignmentDraft[it.id] ?? it.assigned_store_id ?? '') === '' ? null : Number(assignmentDraft[it.id] ?? it.assigned_store_id) as number),
      }));
      const updated = await wholesaleOrdersAPI.assignStores(order.id, assignments);
      setOrder(updated);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setSelectedItemIds(new Set());
      const allAssignedNow = !!updated.items?.length && updated.items.every((it) => it.assigned_store_id != null);
      if (allAssignedNow) setShowAssignment(false);
      enqueueSnackbar(`Assigned ${selected.length} line(s) to ${storeName}`, { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to assign', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleAssignToStore = async () => {
    if (!order?.items?.length || assignToStoreId === '') return;
    const selected = Array.from(selectedItemIds);
    if (selected.length === 0) {
      enqueueSnackbar('Select at least one line to assign (split shipment).', { variant: 'warning' });
      return;
    }
    const store = stores.find((s) => s.id === assignToStoreId);
    const storeName = store?.name ?? `Store #${assignToStoreId}`;
    try {
      const storeStock = await stockAPI.getStoreStock(assignToStoreId as number);
      const stockByProduct = new Map(storeStock.map((s) => [s.product_id, s]));
      const selectedItems = order.items.filter((it) => selected.includes(it.id));
      const warningRows: { product: string; reason: string; detail?: string }[] = [];

      selectedItems.forEach((it) => {
        const stock = stockByProduct.get(it.product_id);
        const name = productDisplayName(it.product, lang) || `Product #${it.product_id}`;
        if (!stock) {
          warningRows.push({ product: name, reason: 'product not exist', detail: '—' });
          return;
        }
        const stockBefore = stock.quantity;
        const stockAfter = stock.quantity - it.quantity;
        if (stock.quantity < it.quantity) {
          warningRows.push({
            product: name,
            reason: 'not enough stock',
            detail: `${stockBefore} -> ${stockAfter}`,
          });
        } else if (stockAfter < stock.low_stock_threshold) {
          warningRows.push({
            product: name,
            reason: 'not enough remaining stock',
            detail: `${stockBefore} -> ${stockAfter}`,
          });
        }
      });

      if (warningRows.length > 0) {
        setAssignWarningRows(warningRows);
        setAssignWarningOpen(true);
        return;
      }
      await performAssignment();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to check stock', { variant: 'error' });
    }
  };

  const handleAssignAnyway = async () => {
    setAssignWarningOpen(false);
    await performAssignment();
  };

  const handleCompleteAssignment = async () => {
    if (!order) return;
    try {
      setActioning(true);
      const updated = await wholesaleOrdersAPI.completeAssignment(order.id);
      setOrder(updated);
      enqueueSnackbar('Order marked approved; stores can now pack', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to complete', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleApprove = async () => {
    if (!order) return;
    try {
      setActioning(true);
      const updated = await wholesaleOrdersAPI.approve(order.id);
      setOrder(updated);
      enqueueSnackbar('Order endorsed; assign shipment', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to approve', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleReject = async () => {
    if (!order) return;
    try {
      setActioning(true);
      await wholesaleOrdersAPI.reject(order.id, rejectReason);
      enqueueSnackbar('Order rejected', { variant: 'success' });
      navigate('/wholesale-orders');
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to reject', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleRegenOrderConfirmation = async () => {
    if (!order?.id) return;
    setRegenConfirmLoading(true);
    try {
      const updated = await wholesaleOrdersAPI.regenerateOrderConfirmation(order.id);
      setOrder(updated);
      enqueueSnackbar('Order confirmation regenerated.', { variant: 'success' });
    } catch (e: unknown) {
      enqueueSnackbar(
        (e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Failed to regenerate',
        { variant: 'error' },
      );
    } finally {
      setRegenConfirmLoading(false);
      setDocMenuAnchorEl(null);
    }
  };

  const handleRegenInvoice = async () => {
    if (!order) return;
    try {
      setRegenInvoiceLoading(true);
      const updated = await wholesaleOrdersAPI.generateInvoice(order.id);
      setOrder(updated);
      enqueueSnackbar('Invoice generated.', { variant: 'success' });
    } catch (e: unknown) {
      enqueueSnackbar(
        (e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Failed to generate invoice',
        { variant: 'error' },
      );
    } finally {
      setRegenInvoiceLoading(false);
      setInvoiceMenuAnchorEl(null);
    }
  };

  if (loading || !order) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  // Process steps: Created → Confirmed (endorsed) → Shipment assigned → Completed (invoiced + all shipments done)
  const orderConfirmationDoc = order.documents?.find((d) => d.type === 'order_confirmation');
  const hasOrderConfirmation = !!orderConfirmationDoc;
  const invoiceDoc = order.documents?.find((d) => d.type === 'invoice');
  const hasInvoice = !!invoiceDoc;
  const allShipmentsCompleted =
    (order.shipments?.length ?? 0) > 0 &&
    order.shipments!.every((s) => s.status === 'completed');
  const stepCreated = true;
  const stepConfirmed = order.status !== 'pending_approval' && order.status !== 'rejected';
  const stepShipmentAssigned = order.status === 'approved';
  const stepInvoiced = !!hasInvoice && allShipmentsCompleted;
  const activeStep = stepInvoiced ? 4 : stepShipmentAssigned ? 3 : stepConfirmed ? 2 : 1;

  const processSteps = [
    { label: 'created', done: stepCreated },
    { label: 'confirmed', done: stepConfirmed },
    { label: 'in process', done: stepShipmentAssigned },
    { label: 'completed', done: stepInvoiced },
  ];

  const showDocButtons =
    orderConfirmationDoc ||
    invoiceDoc ||
    (order.shipments && order.shipments.length > 0 && order.shipments.every((s) => s.status === 'completed'));

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2, flexWrap: 'wrap', gap: 1 }}>
        <Button startIcon={<BackIcon />} onClick={() => navigate('/wholesale-orders')}>
          Back to list
        </Button>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <Tooltip title="Audit Log">
          <IconButton size="small" onClick={() => navigate(`/wholesale-orders/${order.id}/audit-log`)}>
            <HistoryIcon />
          </IconButton>
        </Tooltip>
        {showDocButtons && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Typography variant="subtitle2" color="text.secondary" sx={{ fontWeight: 600 }}>
              Re-print
            </Typography>
            <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
              {orderConfirmationDoc?.file_url && (
                <>
                  <ButtonGroup
                    size="small"
                    sx={{
                      '& .MuiButton-root': {
                        backgroundColor: '#0d47a1',
                        color: '#fff',
                        borderColor: '#0d47a1',
                      },
                      '& .MuiButton-root:hover': {
                        backgroundColor: '#1565c0',
                        color: '#fff',
                        borderColor: '#1565c0',
                      },
                      '& .MuiButton-root.Mui-disabled': {
                        backgroundColor: 'rgba(0,0,0,0.12)',
                        color: 'rgba(0,0,0,0.26)',
                      },
                    }}
                  >
                    <Button
                      component="a"
                      href={orderConfirmationDoc.file_url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Order confirmation
                    </Button>
                    <Button
                      aria-label="More actions for order confirmation"
                      onClick={(e) => setDocMenuAnchorEl(e.currentTarget)}
                    >
                      {docMenuAnchorEl ? <ArrowDropUpIcon fontSize="small" /> : <ArrowDropDownIcon fontSize="small" />}
                    </Button>
                  </ButtonGroup>
                  <Menu
                    anchorEl={docMenuAnchorEl}
                    open={Boolean(docMenuAnchorEl)}
                    onClose={() => setDocMenuAnchorEl(null)}
                  >
                    <MuiMenuItem onClick={handleRegenOrderConfirmation} disabled={regenConfirmLoading}>
                      {regenConfirmLoading ? (
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <CircularProgress size={16} />
                          <span>Re-generate</span>
                        </Box>
                      ) : (
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <RefreshIcon fontSize="small" />
                          <span>Re-generate</span>
                        </Box>
                      )}
                    </MuiMenuItem>
                  </Menu>
                </>
              )}
              {(invoiceDoc?.file_url || (order.shipments && order.shipments.length > 0 && order.shipments.every((s) => s.status === 'completed'))) && (
                <>
                  <ButtonGroup
                    size="small"
                    sx={{
                      '& .MuiButton-root': {
                        backgroundColor: '#0d47a1',
                        color: '#fff',
                        borderColor: '#0d47a1',
                      },
                      '& .MuiButton-root:hover': {
                        backgroundColor: '#1565c0',
                        color: '#fff',
                        borderColor: '#1565c0',
                      },
                      '& .MuiButton-root.Mui-disabled': {
                        backgroundColor: 'rgba(0,0,0,0.12)',
                        color: 'rgba(0,0,0,0.26)',
                      },
                    }}
                  >
                    <Button
                      component={invoiceDoc?.file_url ? 'a' : 'button'}
                      href={invoiceDoc?.file_url || undefined}
                      target={invoiceDoc?.file_url ? '_blank' : undefined}
                      rel={invoiceDoc?.file_url ? 'noopener noreferrer' : undefined}
                      disabled={!invoiceDoc?.file_url}
                    >
                      Invoice
                    </Button>
                    <Button
                      aria-label="More actions for invoice"
                      onClick={(e) => setInvoiceMenuAnchorEl(e.currentTarget)}
                    >
                      {invoiceMenuAnchorEl ? <ArrowDropUpIcon fontSize="small" /> : <ArrowDropDownIcon fontSize="small" />}
                    </Button>
                  </ButtonGroup>
                  <Menu
                    anchorEl={invoiceMenuAnchorEl}
                    open={Boolean(invoiceMenuAnchorEl)}
                    onClose={() => setInvoiceMenuAnchorEl(null)}
                  >
                    <MuiMenuItem onClick={handleRegenInvoice} disabled={regenInvoiceLoading}>
                      {regenInvoiceLoading ? (
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <CircularProgress size={16} />
                          <span>Re-generate</span>
                        </Box>
                      ) : (
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <RefreshIcon fontSize="small" />
                          <span>Re-generate</span>
                        </Box>
                      )}
                    </MuiMenuItem>
                  </Menu>
                </>
              )}
            </Box>
          </Box>
        )}
        </Box>
      </Box>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 2, mb: 2 }}>
          <Typography variant="h5">{order.order_number}</Typography>
          <Chip
            label={order.status.replace('_', ' ')}
            color={
              order.status === 'assign_shipment'
                ? 'primary'
                : order.status === 'approved'
                  ? 'success'
                  : order.status === 'rejected'
                    ? 'error'
                    : 'default'
            }
          />
        </Box>
        <Box sx={{ display: 'grid', gridTemplateColumns: 'auto 1fr', columnGap: 3, rowGap: 0.5, alignItems: 'center', maxWidth: 600 }}>
          <Typography variant="body2" color="text.secondary">Client</Typography>
          <Typography variant="body2">{order.wholesale_client?.name ?? order.wholesale_client_id}</Typography>

          <Typography variant="body2" color="text.secondary">PO Number / Channel</Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Typography variant="body2">
              {order.po_number || '-'} · {order.order_channel ? orderChannelDisplayLabel(order.order_channel) : '-'}
            </Typography>
            <EditIcon sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }} onClick={openPOChannelDialog} />
          </Box>

          <Typography variant="body2" color="text.secondary">OC Number</Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            {editingRefNo ? (
              <>
                <TextField size="small" value={refNoDraft} onChange={(e) => setRefNoDraft(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') saveRefNo(); if (e.key === 'Escape') setEditingRefNo(false); }} autoFocus sx={{ width: 200 }} />
                <Button size="small" onClick={saveRefNo}>Save</Button>
                <Button size="small" onClick={() => setEditingRefNo(false)}>Cancel</Button>
              </>
            ) : (
              <>
                <Typography variant="body2">{order.ref_no || '-'}</Typography>
                <EditIcon sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }} onClick={() => { setRefNoDraft(order.ref_no || ''); setEditingRefNo(true); }} />
              </>
            )}
          </Box>

          <Typography variant="body2" color="text.secondary">PO Date</Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            {editingPODate ? (
              <>
                <TextField size="small" type="date" value={poDateDraft} onChange={(e) => setPODateDraft(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') savePODate(); if (e.key === 'Escape') setEditingPODate(false); }} autoFocus sx={{ width: 200 }} InputLabelProps={{ shrink: true }} />
                <Button size="small" onClick={savePODate}>Save</Button>
                <Button size="small" onClick={() => setEditingPODate(false)}>Cancel</Button>
              </>
            ) : (
              <>
                <Typography variant="body2">{order.po_date ? format(new Date(order.po_date), 'dd MMM yyyy') : format(new Date(order.created_at), 'dd MMM yyyy')}</Typography>
                <EditIcon sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }} onClick={() => { setPODateDraft(order.po_date ? order.po_date.substring(0, 10) : order.created_at.substring(0, 10)); setEditingPODate(true); }} />
              </>
            )}
          </Box>

          <Typography variant="body2" color="text.secondary">Created by</Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            {order.user ? <UserDisplay user={order.user} /> : <Typography variant="body2">{`User #${order.user_id}`}</Typography>}
          </Box>

          <Typography variant="body2" color="text.secondary">Created</Typography>
          <Typography variant="body2">{format(new Date(order.created_at), 'dd MMM yyyy HH:mm')}</Typography>

          <Typography variant="body2" color="text.secondary">Subtotal</Typography>
          <Typography variant="body2">£{(order.subtotal ?? 0).toFixed(2)}</Typography>

          {(order.discount_amount ?? 0) > 0 && (
            <>
              <Typography variant="body2" color="text.secondary">Discount</Typography>
              <Typography variant="body2">£{(order.discount_amount ?? 0).toFixed(2)}</Typography>
            </>
          )}

          <Typography variant="body2" color="text.secondary" fontWeight={600}>Total (order)</Typography>
          <Typography variant="body2" fontWeight={600}>£{(order.total_net ?? totalForOrder(order)).toFixed(2)}</Typography>

          <Typography variant="body2" color="text.secondary">Shipping fee</Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            <Typography variant="body2">£{(Number(order.shipping_fee) || 0).toFixed(2)}</Typography>
            <EditIcon sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }} onClick={() => { setShippingFeeDraft(String(order.shipping_fee ?? '')); setShippingFeeDialogOpen(true); }} />
          </Box>

          <Typography variant="body2" color="text.secondary" fontWeight={700}>Total price</Typography>
          <Typography variant="body2" fontWeight={700}>
            £
            {((order.total_net ?? totalForOrder(order)) + (Number(order.shipping_fee) || 0)).toFixed(2)}
          </Typography>
        </Box>
        {order.notes && <Typography sx={{ mt: 1.5 }} variant="body2">Notes: {order.notes}</Typography>}
        {order.rejection_reason && <Typography sx={{ mt: 1.5 }} color="error" variant="body2">Rejection: {order.rejection_reason}</Typography>}
      </Paper>

      <Paper sx={{ p: 3, mb: 3, overflow: 'visible' }}>
        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 2 }}>
          Order progress
        </Typography>
        <Box
          sx={{
            mx: -3,
            width: 'calc(100% + 48px)',
            display: 'flex',
            alignItems: 'flex-start',
          }}
        >
          {[1, 2, 3, 4].map((num, index) => {
            const step = processSteps[index];
            const done = step?.done ?? false;
            const isRejected = order.status === 'rejected' && index === 1;
            return (
              <Box key={num} sx={{ display: 'contents' }}>
                {/* Step block (fixed), then segment (flex) so the three segments share space and there’s no gap inside the bar */}
                <Box
                  sx={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    flexShrink: 0,
                    pl: index === 0 ? 3 : 0,
                    pr: index === 3 ? 3 : 0,
                  }}
                >
                  <Box
                    sx={{
                      width: 32,
                      height: 32,
                      borderRadius: '50%',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontWeight: 700,
                      fontSize: '0.875rem',
                      ...(done
                        ? { bgcolor: isRejected ? 'error.main' : 'primary.main', color: isRejected ? 'error.contrastText' : 'primary.contrastText' }
                        : { border: 2, borderColor: isRejected ? 'error.main' : 'primary.main', color: 'text.secondary' }),
                    }}
                  >
                    {num}
                  </Box>
                  <Typography
                    variant="caption"
                    color="text.secondary"
                    sx={{ mt: 0.5, textAlign: 'center', lineHeight: 1.2 }}
                  >
                    {step?.label ?? ''}
                  </Typography>
                </Box>
                {index < 3 && (
                  <Box
                    sx={{
                      flex: 1,
                      height: 6,
                      borderRadius: 1,
                      bgcolor: 'action.hover',
                      overflow: 'hidden',
                      mx: 0.5,
                      minWidth: 8,
                      alignSelf: 'center',
                    }}
                  >
                    <Box
                      sx={{
                        width: processSteps[index]?.done ? '100%' : 0,
                        height: '100%',
                        bgcolor: order.status === 'rejected' && index === 1 ? 'error.main' : 'primary.main',
                        borderRadius: 1,
                        transition: 'width 0.2s ease',
                      }}
                    />
                  </Box>
                )}
              </Box>
            );
          })}
        </Box>
      </Paper>

      {order.items?.length ? (
        <Paper sx={{ p: 3, mb: 3 }}>
          <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 2 }}>
            Order entries
          </Typography>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 52 }}></TableCell>
                <TableCell>Product</TableCell>
                <TableCell align="right">Qty</TableCell>
                <TableCell align="right">Unit price</TableCell>
                <TableCell align="right">Discount</TableCell>
                <TableCell align="right">Total</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {order.items.map((it) => {
                const beforeDiscount = it.unit_price * it.quantity;
                const discountAmt = it.line_discount_amount ?? 0;
                const discountRate = beforeDiscount > 0 ? (discountAmt / beforeDiscount) * 100 : 0;
                const isEditingPrice = editingItemId === it.id;
                return (
                  <TableRow key={it.id}>
                    <TableCell sx={{ verticalAlign: 'middle' }}>
                      <ProductImageWithPopover imageUrl={it.product?.image_url} productName={productDisplayName(it.product, lang)} size={40} />
                    </TableCell>
                    <TableCell>{productDisplayName(it.product, lang) || `Product #${it.product_id}`}</TableCell>
                    <TableCell align="right">{it.quantity}</TableCell>
                    <TableCell align="right">
                      {isEditingPrice ? (
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, justifyContent: 'flex-end' }}>
                          <TextField
                            size="small"
                            type="number"
                            value={editingItemPrice}
                            onChange={(e) => setEditingItemPrice(e.target.value)}
                            onKeyDown={(e) => { if (e.key === 'Enter') saveItemPrice(it.id); if (e.key === 'Escape') setEditingItemId(null); }}
                            autoFocus
                            sx={{ width: 90 }}
                            inputProps={{ step: '0.01', min: 0 }}
                          />
                          <Button size="small" onClick={() => saveItemPrice(it.id)}>OK</Button>
                        </Box>
                      ) : (
                        <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5, cursor: 'pointer' }} onClick={() => { setEditingItemId(it.id); setEditingItemPrice(it.unit_price.toFixed(2)); }}>
                          £{it.unit_price.toFixed(2)}
                          <EditIcon sx={{ fontSize: 13, color: 'text.secondary' }} />
                        </Box>
                      )}
                    </TableCell>
                    <TableCell align="right">
                      {discountAmt > 0
                        ? `£${discountAmt.toFixed(2)} (${discountRate.toFixed(0)}%)`
                        : '—'}
                    </TableCell>
                    <TableCell align="right">£{it.line_total.toFixed(2)}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
          <Box sx={{ mt: 2, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 0.5 }}>
            <Typography variant="body2" color="text.secondary">
              Subtotal: £{(order.subtotal ?? order.items.reduce((s: number, it: any) => s + it.unit_price * it.quantity, 0)).toFixed(2)}
            </Typography>
            {(order.discount_amount ?? 0) > 0 && (
              <Typography variant="body2" color="text.secondary">
                Order discount: £{(order.discount_amount ?? 0).toFixed(2)}
              </Typography>
            )}
            <Typography fontWeight="bold">Total: £{totalForOrder(order).toFixed(2)}</Typography>
          </Box>
        </Paper>
      ) : null}

      {order.status === 'pending_approval' && (
        <Paper sx={{ p: 3, mb: 3 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>Endorse or reject</Typography>
          <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
            <Button variant="contained" color="success" startIcon={<CompleteIcon />} onClick={handleApprove} disabled={actioning}>
              Endorse (assign shipment)
            </Button>
            {!showReject ? (
              <Button variant="outlined" color="error" onClick={() => setShowReject(true)}>
                Reject
              </Button>
            ) : (
              <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap' }}>
                <TextField size="small" label="Reason (optional)" value={rejectReason} onChange={(e) => setRejectReason(e.target.value)} sx={{ minWidth: 200 }} />
                <Button variant="contained" color="error" onClick={handleReject} disabled={actioning}>Confirm reject</Button>
                <Button onClick={() => setShowReject(false)}>Cancel</Button>
              </Box>
            )}
          </Box>
        </Paper>
      )}

      {canAssign && showAssignment && (
        <>
          <Paper sx={{ p: 3, mb: 3 }}>
            <Typography variant="subtitle1" sx={{ mb: 2 }}>Assign lines to store</Typography>
            <Box sx={{ display: 'flex', gap: 2, alignItems: 'center', flexWrap: 'wrap', mb: 2 }}>
              <Typography component="span" variant="body2">Assign to</Typography>
              <Select
                size="small"
                value={assignToStoreId}
                onChange={(e) => setAssignToStoreId(e.target.value === '' ? '' : Number(e.target.value))}
                displayEmpty
                sx={{ minWidth: 220 }}
              >
                <MenuItem value="">Select store</MenuItem>
                {stores.map((s) => (
                  <MenuItem key={s.id} value={s.id}>{s.name}</MenuItem>
                ))}
              </Select>
              <Button variant="contained" onClick={handleAssignToStore} disabled={actioning || assignToStoreId === ''}>
                {actioning ? 'Assigning…' : 'OK'}
              </Button>
              {order.status === 'assign_shipment' && (
                <Button variant="contained" color="success" startIcon={<CompleteIcon />} onClick={handleCompleteAssignment} disabled={actioning} sx={{ ml: 'auto' }}>
                  Complete assignment
                </Button>
              )}
            </Box>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell padding="checkbox" sx={{ width: 48 }}></TableCell>
                    <TableCell>Product</TableCell>
                    <TableCell align="right">Qty</TableCell>
                    <TableCell>Assigned to</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {order.items?.map((it) => {
                    const sid = assignmentDraft[it.id] ?? it.assigned_store_id ?? '';
                    const assignedName = sid === '' ? '—' : (stores.find((s) => s.id === sid)?.name ?? `Store #${sid}`);
                    return (
                      <TableRow key={it.id}>
                        <TableCell padding="checkbox">
                          <Checkbox
                            checked={selectedItemIds.has(it.id)}
                            onChange={() => toggleItemSelected(it.id)}
                          />
                        </TableCell>
                        <TableCell>{productDisplayName(it.product, lang) || `Product #${it.product_id}`}</TableCell>
                        <TableCell align="right">{it.quantity}</TableCell>
                        <TableCell>{assignedName}</TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
          </Paper>
        </>
      )}

      {order.shipments && order.shipments.length > 0 && (
        <Paper sx={{ p: 3, mb: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
            <Typography variant="subtitle1" display="flex" alignItems="center" gap={1}>
              <ShipmentIcon fontSize="small" /> Shipments
            </Typography>
            {canAssign && !showAssignment && !!order.items?.length && order.items.every((it) => it.assigned_store_id != null) && (
              <Button
                size="small"
                variant="outlined"
                onClick={() => setShowAssignment(true)}
              >
                Re-assign shipment
              </Button>
            )}
          </Box>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Store</TableCell>
                <TableCell>Courier</TableCell>
                <TableCell>Tracking number</TableCell>
                <TableCell>Status</TableCell>
                <TableCell align="right">Number of case</TableCell>
                <TableCell>Delivery note</TableCell>
                <TableCell align="right">Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {order.shipments.map((s) => {
                const totalCase =
                  s.items?.reduce((sum, it) => sum + (typeof it.case_qty === 'number' ? it.case_qty : 0), 0) ?? 0;
                return (
                <TableRow key={s.id}>
                  <TableCell>{s.store?.name ?? `Store #${s.store_id}`}</TableCell>
                  <TableCell>{s.courier || '—'}</TableCell>
                  <TableCell>{s.tracking_number || '—'}</TableCell>
                  <TableCell>
                    <Chip size="small" label={s.status} color={s.status === 'completed' ? 'success' : 'default'} />
                  </TableCell>
                  <TableCell align="right">{totalCase > 0 ? totalCase : '—'}</TableCell>
                  <TableCell>
                    {s.delivery_note_pdf_url ? (
                      <Button size="small" href={s.delivery_note_pdf_url} target="_blank" rel="noopener noreferrer" component="a" startIcon={<DownloadIcon />}>
                        PDF
                      </Button>
                    ) : (
                      '—'
                    )}
                  </TableCell>
                  <TableCell align="right">
                    <Button
                      size="small"
                      startIcon={<EditIcon />}
                      onClick={() => {
                        setEditingShipment(s);
                        setShipmentCourier(s.courier ?? '');
                        setShipmentTracking(s.tracking_number ?? '');
                      }}
                    >
                      Edit
                    </Button>
                    {s.delivery_note_pdf_url && (
                      <Button
                        size="small"
                        startIcon={regenShipmentId === s.id ? <CircularProgress size={14} /> : <RegenIcon />}
                        disabled={regenShipmentId !== null}
                        onClick={async () => {
                          if (!order) return;
                          setRegenShipmentId(s.id);
                          try {
                            const updated = await shipmentsAPI.regenerateDeliveryNote(s.id);
                            setOrder((prev) =>
                              prev
                                ? {
                                    ...prev,
                                    shipments: prev.shipments?.map((sh) => (sh.id === updated.id ? updated : sh)) ?? [],
                                  }
                                : null,
                            );
                            enqueueSnackbar('Delivery note regenerated', { variant: 'success' });
                          } catch (e: any) {
                            enqueueSnackbar(e.response?.data?.error || 'Failed to regenerate delivery note', {
                              variant: 'error',
                            });
                          } finally {
                            setRegenShipmentId(null);
                          }
                        }}
                      >
                        Regen
                      </Button>
                    )}
                    {s.status === 'completed' && s.items?.length ? (
                      <Button
                        size="small"
                        sx={{ ml: 1 }}
                        variant="outlined"
                        onClick={() => setEditBoxesShipment(s)}
                      >
                        Edit boxes
                      </Button>
                    ) : null}
                    {s.status !== 'completed' && (
                      <Button
                        size="small"
                        color="error"
                        sx={{ ml: 1 }}
                        startIcon={<CompleteIcon />}
                        onClick={() => setCompleteShipmentDialog(s)}
                      >
                        Force complete
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              );
              })}
            </TableBody>
          </Table>
        </Paper>
      )}

      <Dialog open={poChannelDialogOpen} onClose={() => !poChannelSaving && setPOChannelDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>Edit PO Number & Channel</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
            <Autocomplete
              freeSolo
              size="small"
              options={orderChannelOptions}
              getOptionLabel={(v) => ORDER_CHANNEL_OPTIONS.find((o) => o.value === v)?.label ?? v}
              value={orderChannelDraft}
              onInputChange={(_, inputValue, reason) => {
                if (reason === 'input') setOrderChannelDraft(inputValue);
              }}
              onChange={(_, newValue) => {
                if (newValue != null) setOrderChannelDraft(String(newValue));
              }}
              renderInput={(params) => (
                <TextField {...params} label="Order channel" placeholder="e.g. WhatsApp, Email, Client PO" />
              )}
            />
            <TextField
              size="small"
              label="PO Number"
              value={poNumberDraft}
              onChange={(e) => setPONumberDraft(e.target.value)}
              placeholder={orderChannelDraft.trim().toLowerCase() === 'po' ? 'Client PO reference' : 'Used when channel is Client PO'}
              helperText={orderChannelDraft.trim().toLowerCase() !== 'po' ? 'PO number is only saved when channel is Client PO.' : undefined}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPOChannelDialogOpen(false)} disabled={poChannelSaving}>Cancel</Button>
          <Button variant="contained" onClick={savePOAndChannel} disabled={poChannelSaving}>
            {poChannelSaving ? 'Saving…' : 'Save'}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={shippingFeeDialogOpen}
        onClose={() => !shippingFeeSaving && setShippingFeeDialogOpen(false)}
        maxWidth="xs"
        fullWidth
      >
        <DialogTitle>Update shipping fee</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            {order?.shipments && order.shipments.length > 0 && order.shipments.every((sh) => sh.status === 'completed')
              ? 'All shipments for this order are completed. The invoice will be re-generated with the new total.'
              : 'Enter the order shipping fee (shown on invoice).'}
          </DialogContentText>
          <TextField
            fullWidth
            label="Shipping fee (£)"
            type="number"
            value={shippingFeeDraft}
            onChange={(e) => setShippingFeeDraft(e.target.value)}
            inputProps={{ min: 0, step: 0.01 }}
            placeholder="0"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setShippingFeeDialogOpen(false)} disabled={shippingFeeSaving}>
            Cancel
          </Button>
          <Button
            variant="contained"
            disabled={shippingFeeSaving}
            onClick={async () => {
              if (!order) return;
              const fee = parseFloat(shippingFeeDraft);
              if (!Number.isFinite(fee) || fee < 0) {
                enqueueSnackbar('Enter a valid fee (0 or more)', { variant: 'warning' });
                return;
              }
              setShippingFeeSaving(true);
              try {
                const updated = await wholesaleOrdersAPI.update(order.id, { shipping_fee: fee });
                setOrder(updated);
                setShippingFeeDialogOpen(false);
                enqueueSnackbar('Shipping fee updated', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to update shipping fee', { variant: 'error' });
              } finally {
                setShippingFeeSaving(false);
              }
            }}
          >
            {shippingFeeSaving ? 'Saving…' : 'Save'}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!editingShipment}
        onClose={() => setEditingShipment(null)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Edit shipment</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
            <TextField
              size="small"
              label="Courier"
              value={shipmentCourier}
              onChange={(e) => setShipmentCourier(e.target.value)}
              placeholder="e.g. DPD"
            />
            <TextField
              size="small"
              label="Tracking number"
              value={shipmentTracking}
              onChange={(e) => setShipmentTracking(e.target.value)}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditingShipment(null)}>Cancel</Button>
          <Button
            variant="contained"
            disabled={shipmentSaving || !editingShipment}
            onClick={async () => {
              if (!editingShipment || !order) return;
              setShipmentSaving(true);
              try {
                await shipmentsAPI.update(editingShipment.id, {
                  courier: shipmentCourier || undefined,
                  tracking_number: shipmentTracking || undefined,
                });
                const updated = await wholesaleOrdersAPI.get(order.id);
                setOrder(updated);
                setEditingShipment(null);
                enqueueSnackbar('Shipment updated', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to update shipment', { variant: 'error' });
              } finally {
                setShipmentSaving(false);
              }
            }}
          >
            {shipmentSaving ? 'Saving…' : 'Save'}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!completeShipmentDialog}
        onClose={() => !completeShipmentSubmitting && setCompleteShipmentDialog(null)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Complete shipment</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            This will generate a delivery note and mark the shipment as completed. Shipping fee is set at order level (edit on the order summary).
          </DialogContentText>
          {completeShipmentDialog?.items?.length ? (
            <Table size="small" sx={{ mb: 2 }}>
              <TableHead>
                <TableRow>
                  <TableCell>Product</TableCell>
                  <TableCell align="right" sx={{ width: 100 }}>
                    Box
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {completeShipmentDialog.items.map((si) => {
                  const product = si.wholesale_order_item?.product;
                  const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                  const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                  return (
                    <TableRow key={si.id}>
                      <TableCell>{name}</TableCell>
                      <TableCell align="right">
                        <TextField
                          type="number"
                          size="small"
                          inputProps={{ min: 0, step: 1 }}
                          value={value}
                          onChange={(e) =>
                            setCaseQtyByOrderItemId((prev) => ({
                              ...prev,
                              [si.wholesale_order_item_id]: e.target.value,
                            }))
                          }
                          sx={{ width: 80 }}
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCompleteShipmentDialog(null)} disabled={completeShipmentSubmitting}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="primary"
            disabled={completeShipmentSubmitting}
            onClick={async () => {
              if (!completeShipmentDialog || !order) return;
              setCompleteShipmentSubmitting(true);
              try {
                let baseOrder = order;
                if (baseOrder.status === 'assign_shipment') {
                  baseOrder = await wholesaleOrdersAPI.completeAssignment(baseOrder.id);
                  setOrder(baseOrder);
                }
                const case_qty =
                  completeShipmentDialog.items?.map((si) => ({
                    wholesale_order_item_id: si.wholesale_order_item_id,
                    case_qty: Math.max(0, parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0),
                  })) ?? [];
                await shipmentsAPI.completePacking(completeShipmentDialog.id, { case_qty });
                const freshOrder = await wholesaleOrdersAPI.get(order.id);
                setOrder(freshOrder);
                setCompleteShipmentDialog(null);
                enqueueSnackbar('Shipment completed', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to complete shipment', { variant: 'error' });
              } finally {
                setCompleteShipmentSubmitting(false);
              }
            }}
          >
            {completeShipmentSubmitting ? 'Completing…' : 'Complete'}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!editBoxesShipment}
        onClose={() => !editBoxesSaving && setEditBoxesShipment(null)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Edit number of boxes</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            Update case/box count per product. The delivery note PDF will be regenerated with the new values.
          </DialogContentText>
          {editBoxesShipment?.items?.length ? (
            <Table size="small" sx={{ mb: 2 }}>
              <TableHead>
                <TableRow>
                  <TableCell>Product</TableCell>
                  <TableCell align="right" sx={{ width: 100 }}>
                    Box
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {editBoxesShipment.items.map((si) => {
                  const product = si.wholesale_order_item?.product;
                  const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                  const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                  return (
                    <TableRow key={si.id}>
                      <TableCell>{name}</TableCell>
                      <TableCell align="right">
                        <TextField
                          type="number"
                          size="small"
                          inputProps={{ min: 0, step: 1 }}
                          value={value}
                          onChange={(e) =>
                            setCaseQtyByOrderItemId((prev) => ({
                              ...prev,
                              [si.wholesale_order_item_id]: e.target.value,
                            }))
                          }
                          sx={{ width: 80 }}
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditBoxesShipment(null)} disabled={editBoxesSaving}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="primary"
            disabled={editBoxesSaving}
            onClick={async () => {
              if (!editBoxesShipment || !order) return;
              setEditBoxesSaving(true);
              try {
                const case_qty =
                  editBoxesShipment.items?.map((si) => ({
                    wholesale_order_item_id: si.wholesale_order_item_id,
                    case_qty: Math.max(0, parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0),
                  })) ?? [];
                const updated = await shipmentsAPI.updateCaseQty(editBoxesShipment.id, { case_qty });
                setOrder((prev) =>
                  prev
                    ? {
                        ...prev,
                        shipments: prev.shipments?.map((sh) => (sh.id === updated.id ? updated : sh)) ?? [],
                      }
                    : null,
                );
                setEditBoxesShipment(null);
                enqueueSnackbar('Box counts updated', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to update box counts', { variant: 'error' });
              } finally {
                setEditBoxesSaving(false);
              }
            }}
          >
            {editBoxesSaving ? 'Saving…' : 'Save'}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={assignWarningOpen} onClose={() => setAssignWarningOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Assignment warning</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            Please double confirm the following assignment.
          </DialogContentText>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Product</TableCell>
                <TableCell>Reason</TableCell>
                <TableCell>Detail</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {assignWarningRows.map((row) => (
                <TableRow key={`${row.product}-${row.reason}-${row.detail ?? ''}`}>
                  <TableCell>{row.product}</TableCell>
                  <TableCell>{row.reason}</TableCell>
                  <TableCell>{row.detail ?? ''}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DialogContentText sx={{ mt: 2 }}>
            Do you want to assign anyway?
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAssignWarningOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleAssignAnyway} color="primary" disabled={actioning}>
            Assign anyway
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
