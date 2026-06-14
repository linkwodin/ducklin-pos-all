import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link as RouterLink, useNavigate, useParams } from 'react-router-dom';
import {
  Autocomplete,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  Divider,
  IconButton,
  Paper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from '@mui/material';
import {
  ArrowBack as BackIcon,
  Download as DownloadIcon,
  Edit as EditIcon,
  LocalShipping as ShipmentIcon,
  Refresh as RefreshIcon,
} from '@mui/icons-material';
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import DeliveryProofCourierWarningDialog from '../components/DeliveryProofCourierWarningDialog';
import ShipmentPackingScanPanel, {
  type ShipmentPackingFinishPayload,
} from '../components/ShipmentPackingScanPanel';
import { productsAPI, shipmentsAPI, settingsAPI, stockAPI, wholesaleOrdersAPI } from '../services/api';
import type { CompanySettings, Product, Shipment, Stock } from '../types';
import { productDisplayName } from '../utils/productDisplay';
import { effectiveShipmentItemQty } from '../utils/wholesaleOrderAssignment';
import { shipmentExpectedBoxes } from '../utils/shipmentExpectedBoxes';
import { shipmentCourierOptionsFromSettings } from '../utils/shipmentCouriers';
import {
  canEditShipmentDetails,
  canUploadDeliveryProof,
  isShipmentCompleted,
  shipmentAwaitingCourierPickup,
  shipmentHasDeliveryNoteStarted,
  shipmentNeedsPacking,
  shipmentStatusChipColor,
  shipmentStatusLabel,
} from '../utils/shipmentStatus';

export default function WholesaleShipmentDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { t, i18n } = useTranslation('wholesaleShipments');
  const { t: tOrder } = useTranslation('wholesaleOrderDetail');
  const { enqueueSnackbar } = useSnackbar();
  const lang = i18n.language;

  const [shipment, setShipment] = useState<Shipment | null>(null);
  const [loading, setLoading] = useState(true);
  const [companySettings, setCompanySettings] = useState<CompanySettings | null>(null);
  const [deliveryDateDraft, setDeliveryDateDraft] = useState('');
  const [packingSubmitting, setPackingSubmitting] = useState(false);
  const [courierDraft, setCourierDraft] = useState('');
  const [trackingDraft, setTrackingDraft] = useState('');
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editSubmitting, setEditSubmitting] = useState(false);
  const [uploadSubmitting, setUploadSubmitting] = useState(false);
  const [courierPickupWarnOpen, setCourierPickupWarnOpen] = useState(false);
  const deliveryProofInputRef = useRef<HTMLInputElement>(null);
  const [catalogProducts, setCatalogProducts] = useState<Product[]>([]);
  const [storeStock, setStoreStock] = useState<Stock[]>([]);
  const [packingDataLoading, setPackingDataLoading] = useState(false);

  const shipmentId = Number(id);

  const courierOptions = useMemo(
    () => shipmentCourierOptionsFromSettings(companySettings?.shipment_couriers),
    [companySettings?.shipment_couriers],
  );

  const loadShipment = useCallback(async () => {
    if (!shipmentId || Number.isNaN(shipmentId)) return;
    try {
      setLoading(true);
      const data = await shipmentsAPI.get(shipmentId);
      setShipment(data);
      setDeliveryDateDraft(
        data.delivery_date
          ? String(data.delivery_date).substring(0, 10)
          : format(new Date(), 'yyyy-MM-dd'),
      );
      setCourierDraft(data.courier ?? '');
      setTrackingDraft(data.tracking_number ?? '');
    } catch {
      enqueueSnackbar(t('loadFailed'), { variant: 'error' });
      setShipment(null);
    } finally {
      setLoading(false);
    }
  }, [enqueueSnackbar, shipmentId, t]);

  useEffect(() => {
    settingsAPI.getCompany().then(setCompanySettings).catch(() => {});
  }, []);

  useEffect(() => {
    loadShipment();
  }, [loadShipment]);

  const loadPackingData = useCallback(async (storeId: number) => {
    setPackingDataLoading(true);
    try {
      const [products, stock] = await Promise.all([
        productsAPI.list(),
        stockAPI.getStoreStock(storeId),
      ]);
      setCatalogProducts(products);
      setStoreStock(stock);
    } catch {
      enqueueSnackbar(t('packingDataLoadFailed'), { variant: 'error' });
    } finally {
      setPackingDataLoading(false);
    }
  }, [enqueueSnackbar, t]);

  useEffect(() => {
    if (!shipment || !shipmentNeedsPacking(shipment.status)) return;
    void loadPackingData(shipment.store_id);
  }, [shipment, loadPackingData]);

  const completeAssignmentIfNeeded = async (orderId: number) => {
    const order = await wholesaleOrdersAPI.get(orderId);
    if (order.status === 'assign_shipment') {
      await wholesaleOrdersAPI.completeAssignment(orderId);
    }
  };

  const handlePackingFinish = async (payload: ShipmentPackingFinishPayload) => {
    if (!shipment) return;
    setPackingSubmitting(true);
    try {
      await completeAssignmentIfNeeded(shipment.wholesale_order_id);
      await shipmentsAPI.startShipment(shipment.id, payload);
      enqueueSnackbar(t('shipmentPacked'), { variant: 'success' });
      await loadShipment();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } } };
      enqueueSnackbar(err.response?.data?.error || t('startFailed'), { variant: 'error' });
    } finally {
      setPackingSubmitting(false);
    }
  };

  const handleSaveEdit = async () => {
    if (!shipment) return;
    setEditSubmitting(true);
    try {
      await shipmentsAPI.update(shipment.id, {
        courier: courierDraft.trim(),
        tracking_number: trackingDraft.trim(),
        delivery_date: deliveryDateDraft.trim(),
      });
      enqueueSnackbar(t('saved'), { variant: 'success' });
      setEditDialogOpen(false);
      await loadShipment();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } } };
      enqueueSnackbar(err.response?.data?.error || t('saveFailed'), { variant: 'error' });
    } finally {
      setEditSubmitting(false);
    }
  };

  const handleUploadSigned = async (file: File) => {
    if (!shipment) return;
    setUploadSubmitting(true);
    try {
      await completeAssignmentIfNeeded(shipment.wholesale_order_id);
      await shipmentsAPI.uploadSignedDeliveryNote(shipment.id, file);
      enqueueSnackbar(tOrder('uploadSignedDeliveryNoteSuccess'), { variant: 'success' });
      await loadShipment();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } } };
      enqueueSnackbar(err.response?.data?.error || tOrder('uploadSignedDeliveryNoteFailed'), {
        variant: 'error',
      });
    } finally {
      setUploadSubmitting(false);
    }
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!shipment) {
    return (
      <Box>
        <Button startIcon={<BackIcon />} onClick={() => navigate('/wholesale-shipments')} sx={{ mb: 2 }}>
          {t('backToList')}
        </Button>
        <Typography color="text.secondary">{t('notFound')}</Typography>
      </Box>
    );
  }

  const order = shipment.wholesale_order;
  const needsPacking = shipmentNeedsPacking(shipment.status);
  const hasDn = shipmentHasDeliveryNoteStarted(shipment);
  const canEdit = canEditShipmentDetails(shipment);
  const canUpload = canUploadDeliveryProof(shipment);
  const awaitingCourier = shipmentAwaitingCourierPickup(shipment);

  const requestDeliveryProofUpload = () => {
    if (awaitingCourier) {
      setCourierPickupWarnOpen(true);
      return;
    }
    deliveryProofInputRef.current?.click();
  };

  const proceedDeliveryProofUpload = () => {
    setCourierPickupWarnOpen(false);
    deliveryProofInputRef.current?.click();
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2, gap: 1, flexWrap: 'wrap' }}>
        <Button startIcon={<BackIcon />} onClick={() => navigate('/wholesale-shipments')}>
          {t('backToList')}
        </Button>
        <IconButton onClick={loadShipment} aria-label={t('refresh')}>
          <RefreshIcon />
        </IconButton>
      </Box>

      <Paper sx={{ p: { xs: 2, md: 3 }, mb: 2 }}>
        <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap', mb: 2 }}>
          <Box>
            <Typography variant="h5" sx={{ display: 'flex', alignItems: 'center', gap: 1, fontWeight: 700 }}>
              <ShipmentIcon color="primary" />
              {t('processTitle', { order: order?.order_number ?? `#${shipment.wholesale_order_id}` })}
            </Typography>
            {order?.po_number ? (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('poNumber')}: {order.po_number}
              </Typography>
            ) : null}
          </Box>
          <Chip
            label={shipmentStatusLabel(shipment.status, tOrder)}
            color={shipmentStatusChipColor(shipment.status)}
          />
        </Box>

        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={3} divider={<Divider orientation="vertical" flexItem />}>
          <Box>
            <Typography variant="caption" color="text.secondary">{t('client')}</Typography>
            <Typography variant="body2">{order?.wholesale_client?.name || '—'}</Typography>
          </Box>
          <Box>
            <Typography variant="caption" color="text.secondary">{t('store')}</Typography>
            <Typography variant="body2">{shipment.store?.name ?? `Store #${shipment.store_id}`}</Typography>
          </Box>
          <Box>
            <Typography variant="caption" color="text.secondary">{t('courier')}</Typography>
            <Typography variant="body2">{shipment.courier?.trim() || '—'}</Typography>
          </Box>
          <Box>
            <Typography variant="caption" color="text.secondary">{t('trackingNumber')}</Typography>
            <Typography variant="body2">{shipment.tracking_number?.trim() || '—'}</Typography>
          </Box>
          <Box>
            <Typography variant="caption" color="text.secondary">{t('deliveryDate')}</Typography>
            <Typography variant="body2">
              {shipment.delivery_date
                ? format(new Date(String(shipment.delivery_date).substring(0, 10)), 'dd MMM yyyy')
                : '—'}
            </Typography>
          </Box>
        </Stack>

        <Box sx={{ mt: 2, display: 'flex', flexWrap: 'wrap', gap: 1 }}>
          <Button
            size="small"
            variant="outlined"
            component={RouterLink}
            to={`/wholesale-orders/${shipment.wholesale_order_id}`}
          >
            {t('viewOrder')}
          </Button>
          {shipment.delivery_note_pdf_url ? (
            <Button
              size="small"
              variant="outlined"
              startIcon={<DownloadIcon />}
              component="a"
              href={shipment.delivery_note_pdf_url}
              target="_blank"
              rel="noopener noreferrer"
            >
              {t('viewDeliveryNote')}
            </Button>
          ) : null}
          {shipment.signed_delivery_note_pdf_url ? (
            <Button
              size="small"
              variant="outlined"
              startIcon={<DownloadIcon />}
              component="a"
              href={shipment.signed_delivery_note_pdf_url}
              target="_blank"
              rel="noopener noreferrer"
            >
              {t('viewDeliveryProof')}
            </Button>
          ) : null}
          {canEdit && hasDn ? (
            <Button size="small" variant="outlined" startIcon={<EditIcon />} onClick={() => setEditDialogOpen(true)}>
              {tOrder('edit')}
            </Button>
          ) : null}
        </Box>
      </Paper>

      {needsPacking && canEdit ? (
        packingDataLoading ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
            <CircularProgress />
          </Box>
        ) : (
          <ShipmentPackingScanPanel
            shipment={shipment}
            products={catalogProducts}
            storeStock={storeStock}
            courierOptions={courierOptions}
            lang={lang}
            submitting={packingSubmitting}
            onFinish={handlePackingFinish}
            t={t}
            tOrder={tOrder}
          />
        )
      ) : (
        <Paper sx={{ p: { xs: 2, md: 3 }, mb: 2 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 2 }}>
            {t('lineItems')}
          </Typography>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 56 }} />
                <TableCell>{tOrder('product')}</TableCell>
                <TableCell align="right">{tOrder('qty')}</TableCell>
                <TableCell align="right">{tOrder('expectedBoxes', 'Expected boxes')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {(shipment.items ?? []).map((si) => {
                const product = si.wholesale_order_item?.product;
                const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                const qty = effectiveShipmentItemQty(si);
                const expected = shipmentExpectedBoxes(si);
                return (
                  <TableRow key={si.id}>
                    <TableCell>
                      <ProductImageWithPopover
                        imageUrl={product?.image_url}
                        productName={name}
                        size={40}
                      />
                    </TableCell>
                    <TableCell>{name}</TableCell>
                    <TableCell align="right">{qty}</TableCell>
                    <TableCell align="right">{expected}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Paper>
      )}

      <Paper sx={{ p: { xs: 2, md: 3 } }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>
          {t('actions')}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          {needsPacking ? t('packingHint') : hasDn ? t('postPackingHint') : t('noActionsHint')}
        </Typography>

        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} flexWrap="wrap">
          {canUpload ? (
            <>
              <Button
                variant="contained"
                disabled={uploadSubmitting}
                onClick={requestDeliveryProofUpload}
              >
                {uploadSubmitting ? tOrder('uploading') : tOrder('uploadSignedDeliveryNote')}
              </Button>
              <input
                ref={deliveryProofInputRef}
                type="file"
                hidden
                accept=".pdf,.png,.jpg,.jpeg,.gif,.webp"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) void handleUploadSigned(file);
                  e.target.value = '';
                }}
              />
            </>
          ) : null}

          {isShipmentCompleted(shipment.status) ? (
            <Typography variant="body2" color="success.main" sx={{ alignSelf: 'center' }}>
              {t('completedMessage')}
            </Typography>
          ) : null}
        </Stack>
      </Paper>

      <Dialog open={editDialogOpen} onClose={() => !editSubmitting && setEditDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{tOrder('edit')}</DialogTitle>
        <DialogContent>
          <Autocomplete
            freeSolo
            options={courierOptions}
            value={courierDraft}
            onChange={(_e, value) => setCourierDraft(typeof value === 'string' ? value : value ?? '')}
            onInputChange={(_e, value) => setCourierDraft(value)}
            renderInput={(params) => (
              <TextField {...params} label={tOrder('courier')} margin="normal" size="small" fullWidth />
            )}
          />
          <TextField
            label={tOrder('trackingNumber')}
            value={trackingDraft}
            onChange={(e) => setTrackingDraft(e.target.value)}
            fullWidth
            margin="normal"
            size="small"
          />
          <TextField
            label={tOrder('deliveryDate')}
            type="date"
            value={deliveryDateDraft}
            onChange={(e) => setDeliveryDateDraft(e.target.value)}
            fullWidth
            margin="normal"
            size="small"
            InputLabelProps={{ shrink: true }}
            inputProps={{ max: '9999-12-31' }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditDialogOpen(false)} disabled={editSubmitting}>
            {tOrder('cancel')}
          </Button>
          <Button variant="contained" onClick={handleSaveEdit} disabled={editSubmitting}>
            {editSubmitting ? tOrder('saving') : tOrder('save')}
          </Button>
        </DialogActions>
      </Dialog>

      <DeliveryProofCourierWarningDialog
        open={courierPickupWarnOpen}
        onClose={() => setCourierPickupWarnOpen(false)}
        onConfirm={proceedDeliveryProofUpload}
        t={tOrder}
      />
    </Box>
  );
}
