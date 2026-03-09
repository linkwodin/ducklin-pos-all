import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Box,
  Paper,
  Popover,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  Button,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Autocomplete,
} from '@mui/material';
import { ArrowBack as BackIcon, Add as AddIcon } from '@mui/icons-material';
import { wholesaleOrdersAPI, wholesaleClientsAPI, storesAPI, productsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { WholesaleClient, Store, Product } from '../types';
import { useTranslation } from 'react-i18next';
import { productDisplayName } from '../utils/productDisplay';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import ProductAutocomplete from '../components/ProductAutocomplete';

const ORDER_CHANNEL_OPTIONS: { value: string; label: string }[] = [
  { value: 'po', label: 'Client PO' },
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'email', label: 'Email' },
];

type LineDiscountType = 'amount' | 'rate';

type CreateRow = {
  product_id: number;
  quantity: number;
  line_discount_type: LineDiscountType;
  line_discount_value: number; // £ if type is 'amount', % if type is 'rate'
};

function getUnitPrice(product: Product | undefined, sectorId?: number): number {
  if (!product?.current_cost) return 0;
  const c = product.current_cost;
  let price = c.wholesale_cost_gbp > 0 ? c.wholesale_cost_gbp : (c.direct_retail_online_store_price_gbp ?? 0);
  if (sectorId && product.discounts?.length) {
    const disc = product.discounts.find((d) => d.sector_id === sectorId);
    if (disc) {
      if (disc.sector_price_gbp > 0) {
        return disc.sector_price_gbp;
      }
      if (disc.discount_percent > 0 && price > 0) {
        price = Math.round(price * (1 - disc.discount_percent / 100) * 100) / 100;
      }
    }
  }
  return price;
}

export default function WholesaleOrderCreatePage() {
  const navigate = useNavigate();
  const { i18n } = useTranslation();
  const lang = i18n.language || 'en';
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [clients, setClients] = useState<WholesaleClient[]>([]);
  const [loading, setLoading] = useState(true);
  const [actioning, setActioning] = useState(false);
  const [clientId, setClientId] = useState<number | ''>('');
  const [shippingStoreId, setShippingStoreId] = useState<number | ''>('');
  const [poNumber, setPONumber] = useState('');
  const [orderChannel, setOrderChannel] = useState<string>('po');
  const [recentOrderChannels, setRecentOrderChannels] = useState<string[]>([]);
  const [poDate, setPODate] = useState(new Date().toISOString().substring(0, 10));
  const [paymentTerms, setPaymentTerms] = useState('');
  const [shippingFee, setShippingFee] = useState('');
  const [notes, setNotes] = useState('');
  const [orderDiscountType, setOrderDiscountType] = useState<LineDiscountType>('rate');
  const [orderDiscountValue, setOrderDiscountValue] = useState(0);
  const [rows, setRows] = useState<CreateRow[]>([
    { product_id: 0, quantity: 1, line_discount_type: 'rate', line_discount_value: 0 },
  ]);
  const [discountPopover, setDiscountPopover] = useState<{
    anchorEl: HTMLElement;
    rowIdx: number;
    step: 'choice' | 'amount' | 'rate';
  } | null>(null);
  const [discountInputValue, setDiscountInputValue] = useState('');
  const [orderDiscountPopover, setOrderDiscountPopover] = useState<{
    anchorEl: HTMLElement;
    step: 'choice' | 'amount' | 'rate';
  } | null>(null);
  const [orderDiscountInputValue, setOrderDiscountInputValue] = useState('');
  const { enqueueSnackbar } = useSnackbar();

  // Re-fetch products when poDate changes so prices reflect the selected date
  useEffect(() => {
    if (!poDate) return;
    productsAPI.list(undefined, poDate, poDate).then(setProducts).catch(() => {});
  }, [poDate]);

  useEffect(() => {
    const load = async () => {
      try {
        setLoading(true);
        const [sList, pList, cList, channels] = await Promise.all([
          storesAPI.list(),
          productsAPI.list(undefined, poDate, poDate),
          wholesaleClientsAPI.list({ active_only: true }),
          wholesaleOrdersAPI.getRecentOrderChannels().catch(() => []),
        ]);
        setStores(sList);
        setProducts(pList);
        setClients(cList);
        setRecentOrderChannels(channels);
        if (cList.length) {
          setClientId(cList[0].id);
          setShippingStoreId('');
          setPaymentTerms(cList[0].terms ?? '');
        }
      } catch {
        enqueueSnackbar('Failed to load data', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [enqueueSnackbar]);

  const selectedClient = clients.find((c) => c.id === clientId);
  const clientSectorId = selectedClient?.sector_id;

  // Order channel options: recent user input first, then standard (Client PO, WhatsApp, Email) if not already in recent
  const orderChannelOptions = useMemo(() => {
    const seen = new Set(recentOrderChannels.map((c) => c.toLowerCase()));
    const standard = ORDER_CHANNEL_OPTIONS.map((o) => o.value).filter((v) => !seen.has(v.toLowerCase()));
    return [...recentOrderChannels, ...standard];
  }, [recentOrderChannels]);

  const addRow = () =>
    setRows((prev) => [...prev, { product_id: 0, quantity: 1, line_discount_type: 'rate', line_discount_value: 0 }]);

  const updateRow = (idx: number, patch: Partial<CreateRow>) => {
    setRows((prev) => prev.map((r, i) => (i === idx ? { ...r, ...patch } : r)));
  };

  const removeRow = (idx: number) => {
    setRows((prev) => (prev.length > 1 ? prev.filter((_, i) => i !== idx) : prev));
  };

  const beforeDiscountByLine = (row: CreateRow) => {
    const product = products.find((p) => p.id === row.product_id);
    return getUnitPrice(product, clientSectorId) * (row.quantity || 0);
  };

  const lineDiscountAmount = (row: CreateRow) => {
    const before = beforeDiscountByLine(row);
    if (row.line_discount_type === 'amount') {
      return Math.max(0, Math.min(before, row.line_discount_value ?? 0));
    }
    const rate = Math.max(0, Math.min(100, row.line_discount_value ?? 0));
    return (before * rate) / 100;
  };

  const lineDiscountRate = (row: CreateRow) => {
    const before = beforeDiscountByLine(row);
    if (before <= 0) return 0;
    if (row.line_discount_type === 'rate') return row.line_discount_value ?? 0;
    return ((row.line_discount_value ?? 0) / before) * 100;
  };

  const subtotalByLine = (row: CreateRow) => {
    const before = beforeDiscountByLine(row);
    return Math.max(0, before - lineDiscountAmount(row));
  };

  const setLineDiscountFromRate = (idx: number, rate: number) => {
    updateRow(idx, { line_discount_type: 'rate', line_discount_value: Math.max(0, Math.min(100, rate)) });
  };

  const totalSubtotal = rows.reduce((sum, r) => sum + subtotalByLine(r), 0);
  const orderDiscountAmount =
    orderDiscountType === 'amount'
      ? Math.max(0, Math.min(totalSubtotal, orderDiscountValue ?? 0))
      : totalSubtotal * (Math.max(0, Math.min(100, orderDiscountValue ?? 0)) / 100);
  const orderDiscountRateDisplay =
    totalSubtotal > 0 ? (orderDiscountAmount / totalSubtotal) * 100 : 0;
  const totalAfterOrderDiscount = Math.max(0, totalSubtotal - orderDiscountAmount);

  const handleSubmit = async () => {
    if (!clientId || !stores.length) {
      enqueueSnackbar('Client and at least one store are required', { variant: 'warning' });
      return;
    }
    const validRows = rows.filter((r) => r.product_id && r.quantity > 0);
    if (!validRows.length) {
      enqueueSnackbar('Add at least one product with quantity', { variant: 'warning' });
      return;
    }
    try {
      setActioning(true);
      const order = await wholesaleOrdersAPI.create({
        wholesale_client_id: clientId as number,
        wholesale_client_store_id: shippingStoreId || undefined,
        store_id: stores[0].id,
        po_number: orderChannel === 'po' ? (poNumber.trim() || undefined) : undefined,
        order_channel: orderChannel,
        po_date: poDate || undefined,
        payment_terms: paymentTerms.trim() || undefined,
        notes: notes.trim() || undefined,
        total_discount: orderDiscountAmount,
        shipping_fee: (() => {
          const f = parseFloat(shippingFee);
          return Number.isFinite(f) && f >= 0 ? f : undefined;
        })(),
        items: validRows.map((r) => ({
          product_id: r.product_id,
          quantity: r.quantity,
          line_discount_amount: lineDiscountAmount(r),
        })),
      });
      enqueueSnackbar('Wholesale order created (pending approval)', { variant: 'success' });
      navigate(`/wholesale-orders/${order.id}`);
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to create order', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  if (loading) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box sx={{ p: 3 }}>
      <Button startIcon={<BackIcon />} onClick={() => navigate('/wholesale-orders')} sx={{ mb: 2 }}>
        Back to list
      </Button>

      <Typography variant="h5" sx={{ mb: 3 }}>
        Create wholesale order
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <FormControl fullWidth sx={{ mb: 2 }}>
          <InputLabel>Wholesale client</InputLabel>
          <Select
            value={clientId}
            onChange={(e) => {
              const id = e.target.value === '' ? '' : Number(e.target.value);
              setClientId(id);
              setShippingStoreId('');
              const client = clients.find((c) => c.id === id);
              setPaymentTerms(client?.terms ?? '');
            }}
            label="Wholesale client"
          >
            {clients.map((c) => (
              <MenuItem key={c.id} value={c.id}>
                {c.name}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        {selectedClient?.stores && selectedClient.stores.length > 0 && (
          <FormControl fullWidth sx={{ mb: 2 }}>
            <InputLabel>Shipping address</InputLabel>
            <Select
              value={shippingStoreId}
              onChange={(e) => setShippingStoreId(e.target.value === '' ? '' : Number(e.target.value))}
              label="Shipping address"
            >
              <MenuItem value="">
                <em>Company address</em>
              </MenuItem>
              {selectedClient.stores.map((s) => (
                <MenuItem key={s.id} value={s.id}>
                  {s.name}
                  {s.address_line1 ? ` — ${s.address_line1}${s.postcode ? `, ${s.postcode}` : ''}` : ''}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        )}
        {selectedClient?.sector && (
          <Typography variant="caption" color="text.secondary" sx={{ mb: 2, display: 'block' }}>
            Sector pricing: <strong>{selectedClient.sector.name}</strong> — unit prices reflect sector discount
          </Typography>
        )}
        <Autocomplete
          freeSolo
          options={orderChannelOptions}
          getOptionLabel={(v) => ORDER_CHANNEL_OPTIONS.find((o) => o.value === v)?.label ?? v}
          value={orderChannel}
          onInputChange={(_, inputValue, reason) => {
            if (reason === 'input') setOrderChannel(inputValue);
          }}
          onChange={(_, newValue) => {
            if (newValue != null) setOrderChannel(String(newValue));
          }}
          renderInput={(params) => (
            <TextField {...params} label="Order channel" placeholder="e.g. WhatsApp, Email, or type your own" />
          )}
          sx={{ mb: 2 }}
        />
        {orderChannel === 'po' && (
          <TextField
            fullWidth
            label="PO Number (optional)"
            value={poNumber}
            onChange={(e) => setPONumber(e.target.value)}
            sx={{ mb: 2 }}
          />
        )}
        <TextField
          fullWidth
          label="PO Date (optional)"
          type="date"
          value={poDate}
          onChange={(e) => setPODate(e.target.value)}
          InputLabelProps={{ shrink: true }}
          sx={{ mb: 2 }}
        />
        <TextField
          fullWidth
          label="Payment terms"
          value={paymentTerms}
          onChange={(e) => setPaymentTerms(e.target.value)}
          placeholder="e.g. Net 30, 7 days on invoice"
          sx={{ mb: 2 }}
        />
        <TextField
          fullWidth
          label="Shipping fee (£) (optional)"
          type="number"
          value={shippingFee}
          onChange={(e) => setShippingFee(e.target.value)}
          inputProps={{ min: 0, step: 0.01 }}
          placeholder="0"
          sx={{ mb: 2 }}
        />
        <TextField
          fullWidth
          label="Notes (optional)"
          multiline
          rows={2}
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          sx={{ mb: 2 }}
        />
      </Paper>

      <Paper sx={{ p: 2, mb: 3, overflow: 'hidden' }}>
        <Typography variant="subtitle1" sx={{ mb: 2 }}>
          Items — unit price is fixed; adjust line discount to change subtotal
        </Typography>
        <TableContainer sx={{ overflowX: 'auto' }}>
        <Table size="small" sx={{ tableLayout: 'auto', width: '100%' }}>
          <TableHead>
            <TableRow>
              <TableCell sx={{ width: 52 }} />
              <TableCell sx={{ minWidth: 300 }}>Product</TableCell>
              <TableCell align="right" sx={{ minWidth: 150, width: 150 }}>
                Qty
              </TableCell>
              <TableCell align="right" sx={{ width: 100 }}>
                Unit price (£)
              </TableCell>
              <TableCell sx={{ width: 140 }}>
                Discount
              </TableCell>
              <TableCell align="right" sx={{ width: 100 }}>
                Subtotal (£)
              </TableCell>
              <TableCell sx={{ width: 44 }} />
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row, idx) => {
              const product = products.find((p) => p.id === row.product_id);
              const unitPrice = getUnitPrice(product, clientSectorId);
              const subtotal = subtotalByLine(row);
              return (
                <TableRow key={idx}>
                  <TableCell sx={{ verticalAlign: 'middle', width: 52 }}>
                    <ProductImageWithPopover
                      imageUrl={product?.image_url}
                      productName={product ? productDisplayName(product, lang) : ''}
                      size={40}
                    />
                  </TableCell>
                  <TableCell>
                    <ProductAutocomplete
                      products={products}
                      value={row.product_id || null}
                      onChange={(id) => updateRow(idx, { product_id: id ?? 0 })}
                    />
                  </TableCell>
                  <TableCell align="right" sx={{ minWidth: 150, width: 150 }}>
                    <TextField
                      type="number"
                      size="small"
                      fullWidth
                      value={row.quantity}
                      onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })}
                      inputProps={{ min: 1, step: 1 }}
                    />
                  </TableCell>
                  <TableCell align="right" sx={{ width: 100, color: 'text.secondary' }}>
                    £{unitPrice.toFixed(2)}
                  </TableCell>
                  <TableCell sx={{ width: 140, position: 'relative', verticalAlign: 'middle' }}>
                    <Box
                      sx={{
                        display: 'inline-block',
                        maxWidth: '100%',
                        minHeight: 32,
                      }}
                      component="span"
                    >
                      {discountPopover?.rowIdx === idx ? (
                        <Box sx={{ width: 120, height: 32 }} />
                      ) : (
                        <Button
                          size="small"
                          variant="outlined"
                          onClick={(e) => {
                            setDiscountInputValue('');
                            setDiscountPopover({
                              anchorEl: (e.currentTarget.parentElement ?? e.currentTarget) as HTMLElement,
                              rowIdx: idx,
                              step: 'choice',
                            });
                          }}
                        >
                          {(row.line_discount_value ?? 0) > 0 || lineDiscountAmount(row) > 0
                            ? row.line_discount_type === 'amount'
                              ? `£${lineDiscountAmount(row).toFixed(2)}`
                              : `£${lineDiscountAmount(row).toFixed(2)} (${lineDiscountRate(row).toFixed(0)}%)`
                            : 'Add discount'}
                        </Button>
                      )}
                    </Box>
                  </TableCell>
                  <TableCell align="right" sx={{ width: '12%', overflow: 'hidden' }}>£{subtotal.toFixed(2)}</TableCell>
                  <TableCell sx={{ width: '6%', overflow: 'hidden' }}>
                    <Button size="small" color="error" onClick={() => removeRow(idx)}>
                      ×
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
        </TableContainer>
        <Button startIcon={<AddIcon />} size="small" onClick={addRow} sx={{ mt: 1 }}>
          Add line
        </Button>
        <Popover
          open={!!discountPopover}
          anchorEl={discountPopover?.anchorEl}
          onClose={() => {
            setDiscountPopover(null);
            setDiscountInputValue('');
          }}
          anchorOrigin={{ vertical: 'top', horizontal: 'left' }}
          transformOrigin={{ vertical: 'top', horizontal: 'left' }}
          PaperProps={{ sx: { mt: -0.5 } }}
        >
          <Paper sx={{ p: 1.5, minWidth: 160 }} elevation={8}>
            {discountPopover != null && (() => {
              const row = rows[discountPopover.rowIdx];
              const idx = discountPopover.rowIdx;
              const step = discountPopover.step;

              const handleConfirm = () => {
                const num = Number(discountInputValue) || 0;
                if (step === 'amount') {
                  updateRow(idx, { line_discount_type: 'amount', line_discount_value: Math.max(0, num) });
                } else if (step === 'rate') {
                  setLineDiscountFromRate(idx, num);
                }
                setDiscountPopover(null);
                setDiscountInputValue('');
              };

              if (step === 'choice') {
                return (
                  <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                    <Button
                      size="small"
                      fullWidth
                      variant="outlined"
                      onClick={() => {
                        setDiscountInputValue(String(lineDiscountAmount(row).toFixed(2)));
                        setDiscountPopover((p) => (p ? { ...p, step: 'amount' } : null));
                      }}
                    >
                      amount
                    </Button>
                    <Button
                      size="small"
                      fullWidth
                      variant="outlined"
                      onClick={() => {
                        setDiscountInputValue(
                          String(lineDiscountRate(row).toFixed(1))
                        );
                        setDiscountPopover((p) => (p ? { ...p, step: 'rate' } : null));
                      }}
                    >
                      rate
                    </Button>
                  </Box>
                );
              }

              if (step === 'amount') {
                return (
                  <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                    <TextField
                      type="number"
                      size="small"
                      placeholder="0"
                      value={discountInputValue}
                      onChange={(e) => setDiscountInputValue(e.target.value)}
                      inputProps={{ min: 0, step: 0.01 }}
                      sx={{ width: '100%' }}
                      autoFocus
                    />
                    <Button size="small" variant="contained" onClick={handleConfirm}>
                      confirm
                    </Button>
                  </Box>
                );
              }

              // step === 'rate'
              return (
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                    <TextField
                      type="number"
                      size="small"
                      placeholder="0"
                      value={discountInputValue}
                      onChange={(e) => setDiscountInputValue(e.target.value)}
                      inputProps={{ min: 0, max: 100, step: 0.1 }}
                      sx={{ flex: 1 }}
                      autoFocus
                    />
                    <Typography variant="body2">%</Typography>
                  </Box>
                  <Button size="small" variant="contained" onClick={handleConfirm}>
                    confirm
                  </Button>
                </Box>
              );
            })()}
          </Paper>
        </Popover>
        <Box sx={{ mt: 3, display: 'flex', justifyContent: 'flex-end' }}>
          <Box sx={{ textAlign: 'right', minWidth: 200 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 3, py: 0.5 }}>
              <Typography variant="body2" color="text.secondary">
                Line total
              </Typography>
              <Typography variant="body2">£{totalSubtotal.toFixed(2)}</Typography>
            </Box>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 3, py: 0.5 }}>
              <Typography variant="body2" color="text.secondary">
                Order discount
              </Typography>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                <Button
                  size="small"
                  variant="outlined"
                  onClick={(e) => {
                    setOrderDiscountInputValue('');
                    setOrderDiscountPopover({
                      anchorEl: e.currentTarget,
                      step: 'choice',
                    });
                  }}
                >
                  {(orderDiscountValue ?? 0) > 0 || orderDiscountAmount > 0
                    ? orderDiscountType === 'amount'
                      ? `£${orderDiscountAmount.toFixed(2)}`
                      : `£${orderDiscountAmount.toFixed(2)} (${orderDiscountRateDisplay.toFixed(0)}%)`
                    : 'Add discount'}
                </Button>
              </Box>
            </Box>
            <Popover
              open={!!orderDiscountPopover}
              anchorEl={orderDiscountPopover?.anchorEl}
              onClose={() => {
                setOrderDiscountPopover(null);
                setOrderDiscountInputValue('');
              }}
              anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
              transformOrigin={{ vertical: 'top', horizontal: 'right' }}
            >
              <Paper sx={{ p: 1.5, minWidth: 160 }} elevation={8}>
                {orderDiscountPopover != null && (() => {
                  const step = orderDiscountPopover.step;
                  const handleOrderDiscountConfirm = () => {
                    const num = Number(orderDiscountInputValue) || 0;
                    if (step === 'amount') {
                      setOrderDiscountType('amount');
                      setOrderDiscountValue(Math.max(0, num));
                    } else if (step === 'rate') {
                      setOrderDiscountType('rate');
                      setOrderDiscountValue(Math.max(0, Math.min(100, num)));
                    }
                    setOrderDiscountPopover(null);
                    setOrderDiscountInputValue('');
                  };
                  if (step === 'choice') {
                    return (
                      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                        <Button
                          size="small"
                          fullWidth
                          variant="outlined"
                          onClick={() => {
                            setOrderDiscountInputValue(String(orderDiscountAmount.toFixed(2)));
                            setOrderDiscountPopover((p) => (p ? { ...p, step: 'amount' } : null));
                          }}
                        >
                          amount
                        </Button>
                        <Button
                          size="small"
                          fullWidth
                          variant="outlined"
                          onClick={() => {
                            setOrderDiscountInputValue(String(orderDiscountRateDisplay.toFixed(1)));
                            setOrderDiscountPopover((p) => (p ? { ...p, step: 'rate' } : null));
                          }}
                        >
                          rate
                        </Button>
                      </Box>
                    );
                  }
                  if (step === 'amount') {
                    return (
                      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                        <TextField
                          type="number"
                          size="small"
                          placeholder="0"
                          value={orderDiscountInputValue}
                          onChange={(e) => setOrderDiscountInputValue(e.target.value)}
                          inputProps={{ min: 0, step: 0.01 }}
                          sx={{ width: '100%' }}
                          autoFocus
                        />
                        <Button size="small" variant="contained" onClick={handleOrderDiscountConfirm}>
                          confirm
                        </Button>
                      </Box>
                    );
                  }
                  return (
                    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                        <TextField
                          type="number"
                          size="small"
                          placeholder="0"
                          value={orderDiscountInputValue}
                          onChange={(e) => setOrderDiscountInputValue(e.target.value)}
                          inputProps={{ min: 0, max: 100, step: 0.1 }}
                          sx={{ flex: 1 }}
                          autoFocus
                        />
                        <Typography variant="body2">%</Typography>
                      </Box>
                      <Button size="small" variant="contained" onClick={handleOrderDiscountConfirm}>
                        confirm
                      </Button>
                    </Box>
                  );
                })()}
              </Paper>
            </Popover>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 3, py: 0.5, borderTop: 1, borderColor: 'divider', mt: 0.5, pt: 1 }}>
              <Typography variant="body2" fontWeight="bold">
                Total
              </Typography>
              <Typography variant="body2" fontWeight="bold">
                £{totalAfterOrderDiscount.toFixed(2)}
              </Typography>
            </Box>
          </Box>
        </Box>
      </Paper>

      <Box sx={{ display: 'flex', gap: 2 }}>
        <Button variant="outlined" onClick={() => navigate('/wholesale-orders')}>
          Cancel
        </Button>
        <Button
          variant="contained"
          disabled={actioning || !clientId || rows.every((r) => !r.product_id || r.quantity <= 0)}
          onClick={handleSubmit}
        >
          {actioning ? 'Creating…' : 'Create order'}
        </Button>
      </Box>
    </Box>
  );
}
