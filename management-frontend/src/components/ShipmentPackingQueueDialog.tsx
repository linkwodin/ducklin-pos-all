import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogContent,
  DialogTitle,
  IconButton,
  LinearProgress,
  Typography,
} from '@mui/material';
import { Close as CloseIcon, SkipNext as SkipNextIcon } from '@mui/icons-material';
import { useSnackbar } from 'notistack';
import ShipmentPackingScanPanel, {
  type ShipmentPackingFinishPayload,
} from './ShipmentPackingScanPanel';
import { productsAPI, shipmentsAPI, stockAPI, wholesaleOrdersAPI } from '../services/api';
import type { Product, Shipment, Stock } from '../types';
import { sortShipmentsByOrderTimeAsc } from '../utils/shipmentOrderTime';

type ShipmentPackingQueueDialogProps = {
  open: boolean;
  queue: Shipment[];
  lang: string;
  courierOptions: string[];
  t: (key: string, opts?: Record<string, unknown>) => string;
  tOrder: (key: string, opts?: Record<string, unknown>) => string;
  onClose: () => void;
  onShipmentPacked: (updated: Shipment) => void;
};

export default function ShipmentPackingQueueDialog({
  open,
  queue,
  lang,
  courierOptions,
  t,
  tOrder,
  onClose,
  onShipmentPacked,
}: ShipmentPackingQueueDialogProps) {
  const { enqueueSnackbar } = useSnackbar();
  const [initialTotal, setInitialTotal] = useState(0);
  const [skippedIds, setSkippedIds] = useState<Set<number>>(() => new Set());
  const [submitting, setSubmitting] = useState(false);
  const [products, setProducts] = useState<Product[]>([]);
  const [storeStock, setStoreStock] = useState<Stock[]>([]);
  const [dataLoading, setDataLoading] = useState(false);
  const [currentShipment, setCurrentShipment] = useState<Shipment | null>(null);

  const sortedQueue = useMemo(() => [...queue].sort(sortShipmentsByOrderTimeAsc), [queue]);
  const activeQueue = useMemo(
    () => sortedQueue.filter((s) => !skippedIds.has(s.id)),
    [skippedIds, sortedQueue],
  );
  const current = activeQueue[0] ?? null;
  const doneCount = Math.max(0, initialTotal - activeQueue.length);

  useEffect(() => {
    if (open) {
      setInitialTotal(queue.length);
      setSkippedIds(new Set());
    }
  }, [open, queue.length]);

  useEffect(() => {
    if (open && activeQueue.length === 0 && initialTotal > 0) {
      enqueueSnackbar(t('packingQueueDone'), { variant: 'success' });
      onClose();
    }
  }, [activeQueue.length, enqueueSnackbar, initialTotal, onClose, open, t]);

  const loadPackingData = useCallback(
    async (shipment: Shipment) => {
      setDataLoading(true);
      setCurrentShipment(null);
      try {
        const [fullShipment, catalog, stock] = await Promise.all([
          shipmentsAPI.get(shipment.id),
          productsAPI.list(),
          stockAPI.getStoreStock(shipment.store_id),
        ]);
        setCurrentShipment(fullShipment);
        setProducts(catalog);
        setStoreStock(stock);
      } catch {
        enqueueSnackbar(t('packingDataLoadFailed'), { variant: 'error' });
      } finally {
        setDataLoading(false);
      }
    },
    [enqueueSnackbar, t],
  );

  useEffect(() => {
    if (!open || !current) {
      setCurrentShipment(null);
      return;
    }
    void loadPackingData(current);
  }, [current?.id, loadPackingData, open]);

  const completeAssignmentIfNeeded = async (orderId: number) => {
    const order = await wholesaleOrdersAPI.get(orderId);
    if (order.status === 'assign_shipment') {
      await wholesaleOrdersAPI.completeAssignment(orderId);
    }
  };

  const handleFinish = async (payload: ShipmentPackingFinishPayload) => {
    const packingTarget = currentShipment ?? current;
    if (!packingTarget) return;
    setSubmitting(true);
    try {
      await completeAssignmentIfNeeded(packingTarget.wholesale_order_id);
      const updated = await shipmentsAPI.startShipment(packingTarget.id, payload);
      onShipmentPacked(updated);
      enqueueSnackbar(t('shipmentPacked'), { variant: 'success' });
      onClose();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } } };
      enqueueSnackbar(err.response?.data?.error || t('startFailed'), { variant: 'error' });
    } finally {
      setSubmitting(false);
    }
  };

  const handleSkip = () => {
    if (!current) return;
    setSkippedIds((prev) => new Set([...prev, current.id]));
  };

  const orderLabel = current?.wholesale_order?.order_number ?? (current ? `#${current.wholesale_order_id}` : '');
  const progressPct = initialTotal > 0 ? Math.min(100, (doneCount / initialTotal) * 100) : 0;

  return (
    <Dialog open={open} onClose={onClose} fullScreen disableEnforceFocus disableRestoreFocus>
      <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1, pr: 1 }}>
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Typography variant="h6" component="span" sx={{ fontWeight: 700 }}>
            {t('packingQueueTitle')}
          </Typography>
          {current ? (
            <Typography variant="body2" color="text.secondary" noWrap>
              {t('packingQueueProgress', {
                current: doneCount + 1,
                total: initialTotal,
                order: orderLabel,
              })}
            </Typography>
          ) : null}
        </Box>
        {current && activeQueue.length > 1 ? (
          <Button size="small" startIcon={<SkipNextIcon />} onClick={handleSkip} disabled={submitting}>
            {t('packingQueueSkip')}
          </Button>
        ) : null}
        <IconButton onClick={onClose} aria-label={t('packingQueueClose')}>
          <CloseIcon />
        </IconButton>
      </DialogTitle>
      {initialTotal > 0 ? <LinearProgress variant="determinate" value={progressPct} sx={{ height: 4 }} /> : null}
      <DialogContent sx={{ bgcolor: 'grey.50' }}>
        {!current ? (
          <Box sx={{ py: 8, textAlign: 'center' }}>
            <Typography color="text.secondary">{t('packingQueueEmpty')}</Typography>
            <Button sx={{ mt: 2 }} onClick={onClose}>
              {t('packingQueueClose')}
            </Button>
          </Box>
        ) : dataLoading || !currentShipment ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
            <CircularProgress />
          </Box>
        ) : (
          <Box sx={{ maxWidth: 960, mx: 'auto' }}>
            <ShipmentPackingScanPanel
              key={currentShipment.id}
              shipment={currentShipment}
              products={products}
              storeStock={storeStock}
              courierOptions={courierOptions}
              lang={lang}
              submitting={submitting}
              onFinish={handleFinish}
              t={t}
              tOrder={tOrder}
            />
          </Box>
        )}
      </DialogContent>
    </Dialog>
  );
}
