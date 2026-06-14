import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { useSnackbar } from 'notistack';
import {
  Alert,
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
  IconButton,
  Paper,
  Step,
  StepLabel,
  Stepper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
  useMediaQuery,
} from '@mui/material';
import { useTheme } from '@mui/material/styles';
import {
  ArrowBack as ArrowBackIcon,
  ArrowForward as ArrowForwardIcon,
  CheckCircle as CheckCircleIcon,
  LocalShipping as ShipIcon,
  QrCodeScanner as ScanIcon,
  Refresh as RefreshIcon,
} from '@mui/icons-material';
import { format } from 'date-fns';
import type { Product, Shipment, Stock } from '../types';
import { productDisplayName } from '../utils/productDisplay';
import {
  normalizeBarcodeScanInput,
  packingScanDelta,
  resolveProductScanForPacking,
} from '../utils/productBarcode';
import {
  availableStockForProduct,
  buildShipmentPackingLines,
  effectiveShipmentItemsForPacking,
  formatPackingQty,
  hasNoStock,
  packingLineSubtitle,
  packingScanCatalog,
  stockByProductId,
  type ShipmentPackingLine,
} from '../utils/shipmentPacking';
import { shipmentExpectedBoxes } from '../utils/shipmentExpectedBoxes';
import { effectiveShipmentItemQty, formatAssignmentQty } from '../utils/wholesaleOrderAssignment';
import ProductImageWithPopover from './ProductImageWithPopover';

export type ShipmentPackingFinishPayload = {
  case_qty: { wholesale_order_item_id: number; case_qty: number }[];
  delivery_date?: string;
  courier?: string;
  tracking_number?: string;
};

type PackingStep = 'scan' | 'boxes' | 'courier';

type ShipmentPackingScanPanelProps = {
  shipment: Shipment;
  products: Product[];
  storeStock: Stock[];
  courierOptions: string[];
  lang: string;
  submitting: boolean;
  onFinish: (payload: ShipmentPackingFinishPayload) => void;
  t: (key: string, opts?: Record<string, unknown>) => string;
  tOrder: (key: string, opts?: Record<string, unknown>) => string;
};

function initialCaseQtyFromShipment(shipment: Shipment): Record<number, string> {
  const out: Record<number, string> = {};
  for (const si of effectiveShipmentItemsForPacking(shipment)) {
    const expected = shipmentExpectedBoxes(si);
    const saved = si.case_qty != null && si.case_qty > 0 ? si.case_qty : expected;
    out[si.wholesale_order_item_id] = String(saved);
  }
  return out;
}

function PackingLabelValueRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 2 }}>
      <Typography variant="body2" color="text.secondary" sx={{ flexShrink: 0 }}>
        {label}
      </Typography>
      <Box sx={{ minWidth: 0, textAlign: 'right' }}>{children}</Box>
    </Box>
  );
}

const STEPS: PackingStep[] = ['scan', 'boxes', 'courier'];

export default function ShipmentPackingScanPanel({
  shipment,
  products,
  storeStock,
  courierOptions,
  lang,
  submitting,
  onFinish,
  t,
  tOrder,
}: ShipmentPackingScanPanelProps) {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  const { enqueueSnackbar } = useSnackbar();
  const barcodeRef = useRef<HTMLInputElement>(null);
  const scanDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [step, setStep] = useState<PackingStep>('scan');
  const [barcodeDisplay, setBarcodeDisplay] = useState('');
  const [scannedQty, setScannedQty] = useState<Record<number, number>>({});
  const [caseQtyByOrderItemId, setCaseQtyByOrderItemId] = useState<Record<number, string>>(() =>
    initialCaseQtyFromShipment(shipment),
  );
  const [courierDraft, setCourierDraft] = useState(shipment.courier ?? '');
  const [trackingDraft, setTrackingDraft] = useState(shipment.tracking_number ?? '');
  const [deliveryDateDraft, setDeliveryDateDraft] = useState(
    shipment.delivery_date
      ? String(shipment.delivery_date).substring(0, 10)
      : format(new Date(), 'yyyy-MM-dd'),
  );
  const [ackedNoStockProductIds, setAckedNoStockProductIds] = useState<Set<number>>(() => new Set());
  const [noStockAdvanceConfirmOpen, setNoStockAdvanceConfirmOpen] = useState(false);
  const [exceedConfirm, setExceedConfirm] = useState<{
    line: ShipmentPackingLine;
    productId: number;
    scanDelta: number;
    alreadyScanned: number;
    applied: number;
    mode: 'full' | 'capped';
  } | null>(null);

  const packingLines = useMemo(() => buildShipmentPackingLines(shipment), [shipment]);
  const packingItems = useMemo(() => effectiveShipmentItemsForPacking(shipment), [shipment]);
  const scanCatalog = useMemo(() => packingScanCatalog(products, shipment), [products, shipment]);
  const stockMap = useMemo(() => stockByProductId(storeStock), [storeStock]);
  const stepIndex = STEPS.indexOf(step);

  const focusBarcode = useCallback(() => {
    if (step !== 'scan') return;
    window.setTimeout(() => {
      barcodeRef.current?.focus();
      barcodeRef.current?.select();
    }, 0);
  }, [step]);

  useEffect(() => {
    focusBarcode();
  }, [focusBarcode, step, shipment.id]);

  useEffect(() => {
    setStep('scan');
    setBarcodeDisplay('');
    setScannedQty({});
    setCaseQtyByOrderItemId(initialCaseQtyFromShipment(shipment));
    setAckedNoStockProductIds(new Set());
  }, [shipment.id]);

  const allScanned = useMemo(
    () =>
      packingLines.length > 0 &&
      packingLines.every((line) => (scannedQty[line.productId] ?? 0) >= line.expectedQty - 0.0001),
    [packingLines, scannedQty],
  );

  const noStockLines = useMemo(() => {
    return packingLines.filter((line) => {
      const stock = stockMap.get(line.productId);
      return hasNoStock(availableStockForProduct(stock, line.product));
    });
  }, [packingLines, stockMap]);

  const lineHasNoStock = (line: ShipmentPackingLine) => {
    const stock = stockMap.get(line.productId);
    return hasNoStock(availableStockForProduct(stock, line.product));
  };

  const clearBarcodeInput = useCallback(() => {
    setBarcodeDisplay('');
    if (barcodeRef.current) barcodeRef.current.value = '';
  }, []);

  const readBarcodeInput = () =>
    normalizeBarcodeScanInput(barcodeRef.current?.value ?? barcodeDisplay);

  /** Stock warning is shown on the line; do not block scanning (per packing policy). */
  const confirmNoStockScanIfNeeded = (line: ShipmentPackingLine, onConfirm: () => void) => {
    if (lineHasNoStock(line)) {
      setAckedNoStockProductIds((prev) => new Set(prev).add(line.productId));
    }
    onConfirm();
  };

  const applyScanDelta = (productId: number, line: ShipmentPackingLine, delta: number) => {
    const alreadyScanned = scannedQty[productId] ?? 0;
    const remaining = line.expectedQty - alreadyScanned;
    if (remaining <= 0.0001) {
      return { ok: false as const, reason: 'full' as const };
    }
    const applied = Math.min(delta, remaining);
    const afterScan = alreadyScanned + applied;
    setScannedQty((prev) => ({ ...prev, [productId]: afterScan }));
    if (delta > remaining) {
      return { ok: true as const, capped: true as const, applied };
    }
    return { ok: true as const, capped: false as const, applied };
  };

  const finishScan = useCallback(
    (productId: number, line: ShipmentPackingLine, scanDelta: number, alreadyScanned: number) => {
      const result = applyScanDelta(productId, line, scanDelta);
      if (result.ok) {
        const newQty = alreadyScanned + (result.applied ?? scanDelta);
        enqueueSnackbar(
          t('scanRecorded', {
            name: productDisplayName(line.product, lang),
            qty: formatPackingQty(newQty),
            expected: formatPackingQty(line.expectedQty),
          }),
          { variant: 'success' },
        );
      }
      focusBarcode();
    },
    [enqueueSnackbar, focusBarcode, lang, scannedQty, t],
  );

  const handleBarcodeSubmit = useCallback(
    (rawCode?: string) => {
      const code = normalizeBarcodeScanInput(rawCode ?? readBarcodeInput());
      if (!code) return;

      const scanned = resolveProductScanForPacking(code, packingLines, scanCatalog);
      if (!scanned) {
        enqueueSnackbar(t('barcodeNotFound', { code }), { variant: 'error' });
        clearBarcodeInput();
        focusBarcode();
        return;
      }

      const line = packingLines.find((l) => l.productId === scanned.id);
      if (!line) {
        enqueueSnackbar(t('productNotInShipment'), { variant: 'error' });
        clearBarcodeInput();
        focusBarcode();
        return;
      }

      const alreadyScanned = scannedQty[scanned.id] ?? 0;
      const remaining = line.expectedQty - alreadyScanned;
      const scanDelta = packingScanDelta(line.product, scanned);

      clearBarcodeInput();

      if (remaining <= 0.0001) {
        setExceedConfirm({
          line,
          productId: scanned.id,
          scanDelta,
          alreadyScanned,
          applied: 0,
          mode: 'full',
        });
        return;
      }

      if (alreadyScanned + scanDelta > line.expectedQty + 0.0001) {
        setExceedConfirm({
          line,
          productId: scanned.id,
          scanDelta,
          alreadyScanned,
          applied: Math.min(scanDelta, remaining),
          mode: 'capped',
        });
        return;
      }

      confirmNoStockScanIfNeeded(line, () => {
        finishScan(scanned.id, line, scanDelta, alreadyScanned);
      });
    },
    [clearBarcodeInput, finishScan, focusBarcode, lang, packingLines, scanCatalog, scannedQty, t],
  );

  const handleBarcodeSubmitRef = useRef(handleBarcodeSubmit);
  handleBarcodeSubmitRef.current = handleBarcodeSubmit;

  const handleBarcodeChange = (value: string) => {
    setBarcodeDisplay(value);
    if (scanDebounceRef.current) clearTimeout(scanDebounceRef.current);
    const trimmed = normalizeBarcodeScanInput(value);
    // Only auto-submit complete barcode lengths — never at 8+ while a 13-digit EAN is still arriving
    // (otherwise the first 8 digits match a weight prefix and wrongly open the weight dialog).
    const completeLengths = new Set([8, 12, 13, 14]);
    if (completeLengths.has(trimmed.length) && /^\d+$/.test(trimmed)) {
      scanDebounceRef.current = setTimeout(() => {
        handleBarcodeSubmitRef.current(trimmed);
      }, 300);
    }
  };

  const handleScanFormSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (scanDebounceRef.current) clearTimeout(scanDebounceRef.current);
    handleBarcodeSubmit();
  };

  useEffect(
    () => () => {
      if (scanDebounceRef.current) clearTimeout(scanDebounceRef.current);
    },
    [],
  );

  const advanceFromScan = () => {
    if (!allScanned) return;
    if (noStockLines.length > 0) {
      setNoStockAdvanceConfirmOpen(true);
      return;
    }
    setStep('boxes');
  };

  const buildFinishPayload = (): ShipmentPackingFinishPayload => ({
    case_qty: packingItems.map((si) => ({
      wholesale_order_item_id: si.wholesale_order_item_id,
      case_qty: Math.max(
        0,
        parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0,
      ),
    })),
    delivery_date: deliveryDateDraft.trim() || undefined,
    courier: courierDraft.trim() || undefined,
    tracking_number: trackingDraft.trim() || undefined,
  });

  const noStockWarning = (line: ShipmentPackingLine) => {
    if (!lineHasNoStock(line)) return null;
    return (
      <Chip size="small" color="warning" label={t('noStockWarning')} sx={{ mt: 0.5 }} />
    );
  };

  const stepLabel = (s: PackingStep) => {
    switch (s) {
      case 'scan':
        return t('stepScan');
      case 'boxes':
        return t('stepBoxes');
      case 'courier':
        return t('stepCourier');
    }
  };

  return (
    <Paper sx={{ p: { xs: 2, md: 3 }, mb: 2 }}>
      <Stepper activeStep={stepIndex} alternativeLabel sx={{ mb: 3 }}>
        {STEPS.map((s) => (
          <Step key={s} completed={STEPS.indexOf(s) < stepIndex}>
            <StepLabel>{stepLabel(s)}</StepLabel>
          </Step>
        ))}
      </Stepper>

      {step === 'scan' ? (
        <>
          <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>
            {t('scanPackingTitle')}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {t('scanPackingHint')}
          </Typography>

          {noStockLines.length > 0 ? (
            <Alert severity="warning" sx={{ mb: 2 }}>
              {t('noStockBanner', { count: noStockLines.length })}
            </Alert>
          ) : null}

          {packingLines.length === 0 ? (
            <Alert severity="error" sx={{ mb: 2 }}>
              {t('noPackingLines')}
            </Alert>
          ) : null}

          <Box
            component="form"
            onSubmit={handleScanFormSubmit}
            sx={{ display: 'flex', gap: 1, mb: 2, alignItems: 'flex-start' }}
          >
            <TextField
              inputRef={barcodeRef}
              fullWidth
              autoFocus
              defaultValue=""
              key={`barcode-${shipment.id}`}
              onChange={(e) => handleBarcodeChange(e.target.value)}
              placeholder={t('scanBarcodePlaceholder')}
              disabled={packingLines.length === 0}
              inputProps={{ autoComplete: 'off', inputMode: 'numeric' }}
              InputProps={{
                startAdornment: <ScanIcon sx={{ mr: 1, color: 'action.active' }} />,
              }}
            />
            <Button
              type="submit"
              variant="contained"
              disabled={packingLines.length === 0}
              sx={{ minWidth: 88, height: 56 }}
            >
              {t('scanAdd')}
            </Button>
          </Box>

          <Stack spacing={1}>
            {packingLines.map((line) => {
              const scanned = scannedQty[line.productId] ?? 0;
              const satisfied = scanned >= line.expectedQty - 0.0001;
              const name = productDisplayName(line.product, lang);
              return (
                <Paper
                  key={line.productId}
                  variant="outlined"
                  sx={{
                    p: 1.5,
                    borderColor: satisfied ? 'success.light' : 'divider',
                    bgcolor: satisfied ? 'success.50' : 'background.paper',
                  }}
                >
                  <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'flex-start' }}>
                    <ProductImageWithPopover
                      imageUrl={line.product.image_url}
                      productName={name}
                      size={44}
                    />
                    <Box sx={{ flex: 1, minWidth: 0 }}>
                      <Typography variant="subtitle2" sx={{ wordBreak: 'break-word', mb: 0.5 }}>
                        {name}
                      </Typography>
                      <Typography variant="body2" color="text.secondary" sx={{ wordBreak: 'break-word' }}>
                        {packingLineSubtitle(line)}
                      </Typography>
                      {noStockWarning(line)}
                    </Box>
                  </Box>
                  <Box
                    sx={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      gap: 1,
                      mt: 1.5,
                      pt: 1.25,
                      borderTop: 1,
                      borderColor: 'divider',
                    }}
                  >
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, minWidth: 0 }}>
                      <Typography
                        variant="body2"
                        sx={{ fontWeight: 700, color: satisfied ? 'success.main' : 'warning.main' }}
                      >
                        {t('scannedQty', { qty: formatPackingQty(scanned) })}
                      </Typography>
                      {satisfied ? <CheckCircleIcon color="success" fontSize="small" /> : null}
                    </Box>
                    <IconButton
                      size="small"
                      aria-label={t('resetScanned')}
                      onClick={() =>
                        setScannedQty((prev) => {
                          const next = { ...prev };
                          delete next[line.productId];
                          return next;
                        })
                      }
                    >
                      <RefreshIcon fontSize="small" />
                    </IconButton>
                  </Box>
                </Paper>
              );
            })}
          </Stack>

          <Box sx={{ mt: 2, display: 'flex', justifyContent: 'flex-end' }}>
            <Button
              variant="contained"
              size="large"
              disabled={!allScanned}
              endIcon={<ArrowForwardIcon />}
              onClick={advanceFromScan}
            >
              {t('nextConfirmBoxes')}
            </Button>
          </Box>
          {!allScanned ? (
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1, textAlign: 'right' }}>
              {t('scanAllItemsFirst')}
            </Typography>
          ) : null}
        </>
      ) : null}

      {step === 'boxes' ? (
        <>
          <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>
            {t('confirmBoxesTitle')}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {t('confirmBoxesHint')}
          </Typography>
          {isMobile ? (
            <Stack spacing={1.5} sx={{ mb: 2 }}>
              {packingItems.map((si) => {
                const product = si.wholesale_order_item?.product;
                const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                const lineQty = formatAssignmentQty(effectiveShipmentItemQty(si));
                const expected = shipmentExpectedBoxes(si);
                const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                const actual = parseFloat(value) || 0;
                const delta = actual - expected;
                const deltaText = delta > 0 ? `+${delta}` : delta < 0 ? String(delta) : '—';
                return (
                  <Paper key={si.id} variant="outlined" sx={{ p: 1.5 }}>
                    <Typography variant="subtitle2" sx={{ mb: 1.5, wordBreak: 'break-word' }}>
                      {name}
                    </Typography>
                    <Stack spacing={1}>
                      <PackingLabelValueRow label={tOrder('qty')}>
                        <Typography variant="body2">{lineQty}</Typography>
                      </PackingLabelValueRow>
                      <PackingLabelValueRow label={tOrder('expectedBoxes')}>
                        <Typography variant="body2" color="text.secondary">
                          {expected}
                        </Typography>
                      </PackingLabelValueRow>
                      <PackingLabelValueRow label={tOrder('box')}>
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
                          sx={{ width: 96 }}
                        />
                      </PackingLabelValueRow>
                      <PackingLabelValueRow label={tOrder('addedOrReduced')}>
                        <Typography
                          variant="body2"
                          sx={{
                            fontWeight: 500,
                            color: delta > 0 ? 'success.main' : delta < 0 ? 'error.main' : 'text.secondary',
                          }}
                        >
                          {deltaText}
                        </Typography>
                      </PackingLabelValueRow>
                    </Stack>
                  </Paper>
                );
              })}
            </Stack>
          ) : (
          <TableContainer sx={{ mb: 2, overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
          <Table size="small" sx={{ minWidth: 520 }}>
            <TableHead>
              <TableRow>
                <TableCell>{tOrder('product')}</TableCell>
                <TableCell align="right">{tOrder('qty')}</TableCell>
                <TableCell align="right">{tOrder('expectedBoxes')}</TableCell>
                <TableCell align="right">{tOrder('box')}</TableCell>
                <TableCell align="right">{tOrder('addedOrReduced')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {packingItems.map((si) => {
                const product = si.wholesale_order_item?.product;
                const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                const lineQty = formatAssignmentQty(effectiveShipmentItemQty(si));
                const expected = shipmentExpectedBoxes(si);
                const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                const actual = parseFloat(value) || 0;
                const delta = actual - expected;
                const deltaText = delta > 0 ? `+${delta}` : delta < 0 ? String(delta) : '—';
                return (
                  <TableRow key={si.id}>
                    <TableCell sx={{ wordBreak: 'break-word' }}>{name}</TableCell>
                    <TableCell align="right">{lineQty}</TableCell>
                    <TableCell align="right" sx={{ color: 'text.secondary' }}>
                      {expected}
                    </TableCell>
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
                        sx={{ width: 88 }}
                      />
                    </TableCell>
                    <TableCell
                      align="right"
                      sx={{
                        fontWeight: 500,
                        color: delta > 0 ? 'success.main' : delta < 0 ? 'error.main' : 'text.secondary',
                      }}
                    >
                      {deltaText}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
          </TableContainer>
          )}
          <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 1 }}>
            <Button startIcon={<ArrowBackIcon />} onClick={() => setStep('scan')}>
              {t('back')}
            </Button>
            <Button variant="contained" endIcon={<ArrowForwardIcon />} onClick={() => setStep('courier')}>
              {t('nextConfirmCourier')}
            </Button>
          </Box>
        </>
      ) : null}

      {step === 'courier' ? (
        <>
          <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>
            {t('confirmCourierTitle')}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {tOrder('startShipmentHint')}
          </Typography>
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
            placeholder={tOrder('trackingNumberOptional')}
            fullWidth
            margin="normal"
            size="small"
            helperText={tOrder('trackingNumberHint')}
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
            sx={{ mb: 2 }}
          />
          <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 1 }}>
            <Button startIcon={<ArrowBackIcon />} onClick={() => setStep('boxes')} disabled={submitting}>
              {t('back')}
            </Button>
            <Button
              variant="contained"
              color="primary"
              disabled={submitting}
              startIcon={submitting ? <CircularProgress size={18} color="inherit" /> : <ShipIcon />}
              onClick={() => onFinish(buildFinishPayload())}
            >
              {submitting ? t('processing') : t('finishPacking')}
            </Button>
          </Box>
        </>
      ) : null}

      <Dialog
        open={!!exceedConfirm}
        onClose={() => {
          setExceedConfirm(null);
          focusBarcode();
        }}
        maxWidth="sm"
        fullWidth
        sx={{ zIndex: 1600 }}
      >
        <DialogTitle>{t('scanExceedsOrderTitle')}</DialogTitle>
        <DialogContent>
          <DialogContentText>
            {exceedConfirm?.mode === 'full'
              ? t('scanExceedsOrderFullMessage', {
                  name: productDisplayName(exceedConfirm.line.product, lang),
                  expected: formatPackingQty(exceedConfirm.line.expectedQty),
                  scanned: formatPackingQty(exceedConfirm.alreadyScanned),
                })
              : exceedConfirm
                ? t('scanExceedsOrderCappedMessage', {
                    name: productDisplayName(exceedConfirm.line.product, lang),
                    expected: formatPackingQty(exceedConfirm.line.expectedQty),
                    scanned: formatPackingQty(exceedConfirm.alreadyScanned),
                    attempted: formatPackingQty(exceedConfirm.scanDelta),
                    applied: formatPackingQty(exceedConfirm.applied),
                  })
                : ''}
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          {exceedConfirm?.mode === 'capped' ? (
            <>
              <Button
                onClick={() => {
                  setExceedConfirm(null);
                  focusBarcode();
                }}
              >
                {tOrder('cancel')}
              </Button>
              <Button
                variant="contained"
                color="warning"
                onClick={() => {
                  if (!exceedConfirm) return;
                  const { line, productId, applied, alreadyScanned } = exceedConfirm;
                  setExceedConfirm(null);
                  confirmNoStockScanIfNeeded(line, () => {
                    finishScan(productId, line, applied, alreadyScanned);
                  });
                }}
              >
                {t('scanExceedsOrderCountRemaining')}
              </Button>
            </>
          ) : (
            <Button
              variant="contained"
              onClick={() => {
                setExceedConfirm(null);
                focusBarcode();
              }}
            >
              {t('scanExceedsOrderDismiss')}
            </Button>
          )}
        </DialogActions>
      </Dialog>

      <Dialog
        open={noStockAdvanceConfirmOpen}
        onClose={() => setNoStockAdvanceConfirmOpen(false)}
        maxWidth="sm"
        fullWidth
        sx={{ zIndex: 1600 }}
      >
        <DialogTitle>{t('noStockCompleteConfirmTitle')}</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>{t('noStockCompleteConfirmMessage')}</DialogContentText>
          <Box component="ul" sx={{ m: 0, pl: 2.5 }}>
            {noStockLines.map((line) => (
              <Typography component="li" variant="body2" key={line.productId}>
                {productDisplayName(line.product, lang)}
              </Typography>
            ))}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setNoStockAdvanceConfirmOpen(false)}>{tOrder('cancel')}</Button>
          <Button
            variant="contained"
            color="warning"
            onClick={() => {
              setNoStockAdvanceConfirmOpen(false);
              setStep('boxes');
            }}
          >
            {t('continuePacking')}
          </Button>
        </DialogActions>
      </Dialog>

    </Paper>
  );
}
