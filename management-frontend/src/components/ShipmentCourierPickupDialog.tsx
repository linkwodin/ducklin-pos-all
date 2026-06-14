import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  Checkbox,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  List,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Paper,
  Step,
  StepLabel,
  Stepper,
  TextField,
  Typography,
} from '@mui/material';
import { Close as CloseIcon, QrCodeScanner as ScanIcon } from '@mui/icons-material';
import { format } from 'date-fns';
import { useSnackbar } from 'notistack';
import type { Shipment } from '../types';
import {
  shipmentMatchesCouriers,
  shipmentMatchesDeliveryNoteScan,
} from '../utils/shipmentDeliveryNoteScan';
import { shipmentTotalBoxes } from '../utils/shipmentExpectedBoxes';
import { sortShipmentsByOrderTimeAsc } from '../utils/shipmentOrderTime';
import { shipmentsAPI } from '../services/api';

type PickupStep = 'courier' | 'orders' | 'confirm';

type ShipmentCourierPickupDialogProps = {
  open: boolean;
  queue: Shipment[];
  courierOptions: string[];
  t: (key: string, opts?: Record<string, unknown>) => string;
  onClose: () => void;
  onShipmentShipped: (updated: Shipment) => void;
};

const STEPS: PickupStep[] = ['courier', 'orders', 'confirm'];

function orderNumber(shipment: Shipment): string {
  return shipment.wholesale_order?.order_number ?? `#${shipment.wholesale_order_id}`;
}

function orderRef(shipment: Shipment): string {
  return (shipment.wholesale_order?.ref_no ?? '').trim();
}

function shipmentSecondary(shipment: Shipment, t: (key: string, opts?: Record<string, unknown>) => string): string {
  const parts = [
    shipment.wholesale_order?.wholesale_client?.name,
    shipment.store?.name,
    shipment.delivery_date
      ? format(new Date(String(shipment.delivery_date).substring(0, 10)), 'yyyy-MM-dd')
      : null,
    shipment.wholesale_order?.po_number ? `PO ${shipment.wholesale_order.po_number}` : null,
  ].filter(Boolean);
  return parts.join(' · ');
}

function formatBoxCount(count: number, t: (key: string, opts?: Record<string, unknown>) => string): string {
  return t('courierPickupBoxes', { count });
}

export default function ShipmentCourierPickupDialog({
  open,
  queue,
  courierOptions,
  t,
  onClose,
  onShipmentShipped,
}: ShipmentCourierPickupDialogProps) {
  const { enqueueSnackbar } = useSnackbar();
  const scanRef = useRef<HTMLInputElement>(null);
  const [step, setStep] = useState<PickupStep>('courier');
  const [selectedCourier, setSelectedCourier] = useState<string | null>(null);
  const [selectedOrderIds, setSelectedOrderIds] = useState<Set<number>>(() => new Set());
  const [scan, setScan] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const sortedQueue = useMemo(() => [...queue].sort(sortShipmentsByOrderTimeAsc), [queue]);

  const ordersByCourier = useMemo(() => {
    const map = new Map<string, number>();
    for (const courier of courierOptions) {
      map.set(courier, sortedQueue.filter((s) => shipmentMatchesCouriers(s, [courier])).length);
    }
    return map;
  }, [courierOptions, sortedQueue]);

  const eligibleOrders = useMemo(() => {
    if (!selectedCourier) return [];
    return sortedQueue.filter((s) => shipmentMatchesCouriers(s, [selectedCourier]));
  }, [selectedCourier, sortedQueue]);

  const selectedShipments = useMemo(
    () => eligibleOrders.filter((s) => selectedOrderIds.has(s.id)),
    [eligibleOrders, selectedOrderIds],
  );

  const selectedTotalBoxes = useMemo(
    () => selectedShipments.reduce((sum, s) => sum + shipmentTotalBoxes(s), 0),
    [selectedShipments],
  );

  useEffect(() => {
    if (!open) {
      setStep('courier');
      setSelectedCourier(null);
      setSelectedOrderIds(new Set());
      setScan('');
      setSubmitting(false);
    }
  }, [open]);

  useEffect(() => {
    if (open && step === 'orders') {
      window.setTimeout(() => scanRef.current?.focus(), 150);
    }
  }, [open, step]);

  const stepIndex = STEPS.indexOf(step);

  const toggleOrder = (shipmentId: number) => {
    setSelectedOrderIds((prev) => {
      const next = new Set(prev);
      if (next.has(shipmentId)) next.delete(shipmentId);
      else next.add(shipmentId);
      return next;
    });
  };

  const handleScanSubmit = () => {
    const code = scan.trim();
    if (!code) return;

    const match = eligibleOrders.find((s) => shipmentMatchesDeliveryNoteScan(s, code));
    if (!match) {
      enqueueSnackbar(t('courierPickupNotFound', { code }), { variant: 'warning' });
      setScan('');
      scanRef.current?.focus();
      return;
    }

    toggleOrder(match.id);
    setScan('');
    scanRef.current?.focus();
  };

  const handleConfirmBatch = async () => {
    if (submitting || selectedShipments.length === 0 || !selectedCourier) return;
    setSubmitting(true);
    let successCount = 0;
    try {
      for (const shipment of selectedShipments) {
        if (!shipment.courier?.trim()) {
          await shipmentsAPI.update(shipment.id, { courier: selectedCourier });
        }
        const updated = await shipmentsAPI.updateStatus(shipment.id, 'shipped');
        onShipmentShipped(updated);
        successCount += 1;
      }
      enqueueSnackbar(
        t('courierPickupBatchConfirmed', { count: successCount, courier: selectedCourier }),
        { variant: 'success' },
      );
      onClose();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } } };
      enqueueSnackbar(err.response?.data?.error || t('courierPickupFailed'), { variant: 'error' });
    } finally {
      setSubmitting(false);
    }
  };

  const goNext = () => {
    if (step === 'courier') {
      if (!selectedCourier) {
        enqueueSnackbar(t('courierPickupSelectCourier'), { variant: 'warning' });
        return;
      }
      setStep('orders');
      return;
    }
    if (step === 'orders') {
      if (selectedOrderIds.size === 0) {
        enqueueSnackbar(t('courierPickupSelectOrders'), { variant: 'warning' });
        return;
      }
      setStep('confirm');
    }
  };

  const goBack = () => {
    if (step === 'confirm') setStep('orders');
    else if (step === 'orders') {
      setSelectedOrderIds(new Set());
      setStep('courier');
    }
  };

  const orderPrimaryLine = (shipment: Shipment) => {
    const ref = orderRef(shipment);
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap', pr: 1 }}>
        <Typography component="span" sx={{ fontWeight: 700 }}>
          {orderNumber(shipment)}
        </Typography>
        {ref ? (
          <Typography component="span" variant="body2" color="text.secondary">
            {t('courierPickupOrderRef', { ref })}
          </Typography>
        ) : null}
      </Box>
    );
  };

  return (
    <Dialog open={open} onClose={onClose} fullScreen disableEnforceFocus disableRestoreFocus>
      <DialogTitle
        sx={{
          display: 'flex',
          alignItems: 'center',
          gap: 1,
          pr: 1,
          borderBottom: 1,
          borderColor: 'divider',
        }}
      >
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Typography variant="h6" component="span" sx={{ fontWeight: 700 }}>
            {t('courierPickupTitle')}
          </Typography>
        </Box>
        <IconButton onClick={onClose} aria-label={t('packingQueueClose')}>
          <CloseIcon />
        </IconButton>
      </DialogTitle>

      <DialogContent sx={{ bgcolor: 'grey.50', p: { xs: 2, md: 3 } }}>
        <Box sx={{ maxWidth: 900, mx: 'auto', display: 'flex', flexDirection: 'column', gap: 3 }}>
          <Stepper activeStep={stepIndex} alternativeLabel>
            <Step>
              <StepLabel>{t('courierPickupStepCourier')}</StepLabel>
            </Step>
            <Step>
              <StepLabel>{t('courierPickupStepOrders')}</StepLabel>
            </Step>
            <Step>
              <StepLabel>{t('courierPickupStepConfirm')}</StepLabel>
            </Step>
          </Stepper>

          {step === 'courier' ? (
            <Paper sx={{ p: 3 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>
                {t('courierPickupStepCourier')}
              </Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('courierPickupSelectOneCourier')}
              </Typography>
              {courierOptions.length === 0 ? (
                <Typography variant="body2" color="warning.main">
                  {t('courierPickupNoCouriersConfigured')}
                </Typography>
              ) : (
                <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                  {courierOptions.map((courier) => {
                    const orderCount = ordersByCourier.get(courier) ?? 0;
                    return (
                      <Button
                        key={courier}
                        variant={selectedCourier === courier ? 'contained' : 'outlined'}
                        onClick={() => setSelectedCourier(courier)}
                        sx={{ minHeight: 48, px: 2.5, textTransform: 'none', gap: 1 }}
                      >
                        <span>{courier}</span>
                        <Chip
                          size="small"
                          label={orderCount}
                          color={selectedCourier === courier ? 'default' : 'primary'}
                          variant={selectedCourier === courier ? 'filled' : 'outlined'}
                          sx={{ height: 24, fontWeight: 700 }}
                        />
                      </Button>
                    );
                  })}
                </Box>
              )}
            </Paper>
          ) : null}

          {step === 'orders' ? (
            <Paper sx={{ overflow: 'hidden' }}>
              <Box sx={{ px: 2, py: 2, borderBottom: 1, borderColor: 'divider' }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2, flexWrap: 'wrap' }}>
                  <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                    {t('courierPickupStepOrders')}
                  </Typography>
                  <Chip size="small" label={selectedCourier ?? ''} color="primary" />
                  <Chip
                    size="small"
                    label={t('courierPickupSelectedCount', { count: selectedOrderIds.size })}
                    color={selectedOrderIds.size > 0 ? 'success' : 'default'}
                  />
                </Box>
                <TextField
                  inputRef={scanRef}
                  fullWidth
                  size="small"
                  label={t('courierPickupScanLabel')}
                  placeholder={t('courierPickupScanPlaceholder')}
                  value={scan}
                  onChange={(e) => setScan(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      handleScanSubmit();
                    }
                  }}
                  InputProps={{
                    startAdornment: <ScanIcon sx={{ mr: 1, color: 'action.active' }} />,
                  }}
                  autoComplete="off"
                  helperText={t('courierPickupScanSelectHint')}
                />
              </Box>

              {eligibleOrders.length === 0 ? (
                <Box sx={{ p: 4, textAlign: 'center' }}>
                  <Typography color="text.secondary">{t('courierPickupAllDone')}</Typography>
                </Box>
              ) : (
                <List disablePadding>
                  {eligibleOrders.map((shipment) => {
                    const checked = selectedOrderIds.has(shipment.id);
                    const boxes = shipmentTotalBoxes(shipment);
                    return (
                      <ListItem key={shipment.id} disablePadding divider>
                        <ListItemButton onClick={() => toggleOrder(shipment.id)} sx={{ py: 1.5, alignItems: 'flex-start' }}>
                          <ListItemIcon sx={{ minWidth: 42, mt: 0.25 }}>
                            <Checkbox edge="start" checked={checked} tabIndex={-1} disableRipple />
                          </ListItemIcon>
                          <ListItemText
                            primary={orderPrimaryLine(shipment)}
                            secondary={shipmentSecondary(shipment, t)}
                            sx={{ pr: 1 }}
                          />
                          <Chip
                            size="small"
                            label={formatBoxCount(boxes, t)}
                            variant="outlined"
                            sx={{ flexShrink: 0, mt: 0.5, fontWeight: 600 }}
                          />
                        </ListItemButton>
                      </ListItem>
                    );
                  })}
                </List>
              )}
            </Paper>
          ) : null}

          {step === 'confirm' ? (
            <Paper sx={{ p: 3 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>
                {t('courierPickupStepConfirm')}
              </Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('courierPickupConfirmBatchMessage', {
                  count: selectedShipments.length,
                  courier: selectedCourier ?? '',
                })}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  gap: 1,
                  flexWrap: 'wrap',
                  mb: 2,
                  p: 1.5,
                  bgcolor: 'primary.50',
                  borderRadius: 1,
                  border: 1,
                  borderColor: 'primary.light',
                }}
              >
                <Chip
                  label={t('courierPickupSelectedCount', { count: selectedShipments.length })}
                  color="primary"
                  size="small"
                />
                <Chip
                  label={t('courierPickupTotalBoxes', { count: selectedTotalBoxes })}
                  color="primary"
                  variant="outlined"
                  size="small"
                  sx={{ fontWeight: 700 }}
                />
              </Box>
              <List disablePadding>
                {selectedShipments.map((shipment) => {
                  const boxes = shipmentTotalBoxes(shipment);
                  return (
                    <ListItem
                      key={shipment.id}
                      disablePadding
                      sx={{
                        py: 1,
                        borderBottom: 1,
                        borderColor: 'divider',
                        alignItems: 'flex-start',
                        '&:last-child': { borderBottom: 0 },
                      }}
                    >
                      <ListItemText
                        primary={orderPrimaryLine(shipment)}
                        secondary={shipmentSecondary(shipment, t)}
                        sx={{ pr: 1 }}
                      />
                      <Chip
                        size="small"
                        label={formatBoxCount(boxes, t)}
                        variant="outlined"
                        sx={{ flexShrink: 0, fontWeight: 600 }}
                      />
                    </ListItem>
                  );
                })}
              </List>
            </Paper>
          ) : null}
        </Box>
      </DialogContent>

      <DialogActions sx={{ px: 3, py: 2, borderTop: 1, borderColor: 'divider' }}>
        {step !== 'courier' ? (
          <Button onClick={goBack} disabled={submitting}>
            {t('courierPickupBack')}
          </Button>
        ) : (
          <Box sx={{ flex: 1 }} />
        )}
        <Button onClick={onClose} disabled={submitting}>
          {t('packingQueueClose')}
        </Button>
        {step === 'confirm' ? (
          <Button
            variant="contained"
            disabled={submitting || selectedShipments.length === 0}
            onClick={() => void handleConfirmBatch()}
            startIcon={submitting ? <CircularProgress size={18} color="inherit" /> : undefined}
          >
            {t('courierPickupConfirm')}
          </Button>
        ) : (
          <Button
            variant="contained"
            onClick={goNext}
            disabled={
              (step === 'courier' && !selectedCourier) ||
              (step === 'orders' && selectedOrderIds.size === 0)
            }
          >
            {t('courierPickupNext')}
          </Button>
        )}
      </DialogActions>
    </Dialog>
  );
}
