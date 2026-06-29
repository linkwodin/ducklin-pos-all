import { useEffect, useMemo, useState } from 'react';
import { useNavigate, Link as RouterLink } from 'react-router-dom';
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
  Link,
  IconButton,
  List,
  ListItem,
  ListItemText,
  ListItemSecondaryAction,
  Checkbox,
  FormControlLabel,
  Stack,
  useMediaQuery,
} from '@mui/material';
import { useTheme } from '@mui/material/styles';
import { Add as AddIcon, ChevronRight as ChevronRightIcon, AttachFile as AttachFileIcon, Delete as DeleteIcon } from '@mui/icons-material';
import { wholesaleOrdersAPI, wholesaleClientsAPI, storesAPI, productsAPI, usersAPI } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { useSnackbar } from 'notistack';
import type { WholesaleClient, Store, Product } from '../types';
import { useTranslation } from 'react-i18next';
import { productDisplayName } from '../utils/productDisplay';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import ProductAutocomplete from '../components/ProductAutocomplete';

const ORDER_CHANNEL_OPTIONS: { value: string; label: string }[] = [
  { value: 'po', label: 'Client PO' },
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'wechat', label: 'WeChat' },
  { value: 'email', label: 'Email' },
  { value: 'na', label: 'N/A' },
];

type LineDiscountType = 'order_entry' | 'order_entry_unit';

type CreateRow = {
  product_id: number;
  quantity: number;
  line_discount_type: LineDiscountType;
  line_discount_value: number; // £ per line (order_entry) or £ per unit (order_entry_unit)
};

function getUnitPrice(product: Product | undefined, sectorId?: number): number {
  if (!product?.current_cost) return 0;
  const c = product.current_cost;
  // Wholesale order creation base "product price" is the retail price field.
  // If retail isn't set for that PO-date season, we fall back to wholesale.
  const directRetail = c.direct_retail_online_store_price_gbp ?? 0;
  const wholesale = c.wholesale_cost_gbp ?? 0;
  let price = directRetail > 0 ? directRetail : wholesale;
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
  const { user: authUser } = useAuth();
  const { t, i18n } = useTranslation();
  const lang = i18n.language || 'en';
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [clients, setClients] = useState<WholesaleClient[]>([]);
  const [loading, setLoading] = useState(true);
  const [actioning, setActioning] = useState(false);
  const [clientId, setClientId] = useState<number | ''>('');
  const [shippingStoreId, setShippingStoreId] = useState<number | ''>('');
  const [useCustomShipping, setUseCustomShipping] = useState(false);
  const [customShippingName, setCustomShippingName] = useState('');
  const [customShippingAddress1, setCustomShippingAddress1] = useState('');
  const [customShippingCity, setCustomShippingCity] = useState('');
  const [customShippingPostcode, setCustomShippingPostcode] = useState('');
  const [saveCustomAsStore, setSaveCustomAsStore] = useState(true);
  const [poNumber, setPONumber] = useState('');
  const [orderChannel, setOrderChannel] = useState<string>('po');
  const [recentOrderChannels, setRecentOrderChannels] = useState<string[]>([]);
  const [poDate, setPODate] = useState(new Date().toISOString().substring(0, 10));
  const [paymentTerms, setPaymentTerms] = useState('');
  const [shippingFee, setShippingFee] = useState('');
  const [notes, setNotes] = useState('');
  const [orderDiscountValue, setOrderDiscountValue] = useState(0);
  const [rows, setRows] = useState<CreateRow[]>([
    { product_id: 0, quantity: 1, line_discount_type: 'order_entry', line_discount_value: 0 },
  ]);
  const [discountPopover, setDiscountPopover] = useState<{
    anchorEl: HTMLElement;
    rowIdx: number;
    step: 'choice' | 'order_entry' | 'order_entry_unit';
  } | null>(null);
  const [discountInputValue, setDiscountInputValue] = useState('');
  const [orderDiscountPopover, setOrderDiscountPopover] = useState<{
    anchorEl: HTMLElement;
    step: 'order_discount';
  } | null>(null);
  const [orderDiscountInputValue, setOrderDiscountInputValue] = useState('');
  const [poAttachmentFiles, setPoAttachmentFiles] = useState<File[]>([]);
  const [poDropActive, setPoDropActive] = useState(false);
  const [defaultStoreId, setDefaultStoreId] = useState<number | undefined>();
  const { enqueueSnackbar } = useSnackbar();
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));

  const acceptPoFile = (file: File) =>
    file.type === 'application/pdf' || file.type.startsWith('image/');
  const addPoFiles = (files: FileList | null) => {
    if (!files?.length) return;
    const valid = Array.from(files).filter(acceptPoFile);
    if (valid.length) setPoAttachmentFiles((prev) => [...prev, ...valid]);
  };

  // Re-fetch products when poDate changes so prices reflect the selected date
  useEffect(() => {
    if (!poDate) return;
    productsAPI.list(undefined, poDate, poDate).then(setProducts).catch(() => {});
  }, [poDate]);

  useEffect(() => {
    const load = async () => {
      try {
        setLoading(true);
        const [sList, pList, cList, channels, workUser] = await Promise.all([
          storesAPI.list(),
          productsAPI.list(undefined, poDate, poDate),
          wholesaleClientsAPI.list({ active_only: true }),
          wholesaleOrdersAPI.getRecentOrderChannels().catch(() => []),
          authUser?.id ? usersAPI.get(authUser.id).catch(() => null) : Promise.resolve(null),
        ]);
        const allowedClientIds = workUser?.wholesale_clients?.map((c) => c.id) ?? [];
        const filteredClients =
          allowedClientIds.length > 0 ? cList.filter((c) => allowedClientIds.includes(c.id)) : [];
        const allowedStoreIds = workUser?.stores?.map((s) => s.id) ?? [];
        const filteredStores =
          allowedStoreIds.length > 0 ? sList.filter((s) => allowedStoreIds.includes(s.id)) : sList;
        setStores(filteredStores.length > 0 ? filteredStores : sList);
        setProducts(pList);
        setClients(filteredClients);
        setRecentOrderChannels(channels);
        const initialClientId =
          workUser?.default_wholesale_client_id &&
          filteredClients.some((c) => c.id === workUser.default_wholesale_client_id)
            ? workUser.default_wholesale_client_id
            : filteredClients[0]?.id;
        if (initialClientId) {
          const initialClient = filteredClients.find((c) => c.id === initialClientId);
          setClientId(initialClientId);
          setShippingStoreId('');
          setPaymentTerms(initialClient?.terms ?? '');
        }
        const storeId =
          workUser?.default_store_id &&
          (filteredStores.length > 0 ? filteredStores : sList).some(
            (s) => s.id === workUser.default_store_id,
          )
            ? workUser.default_store_id
            : (filteredStores.length > 0 ? filteredStores : sList)[0]?.id;
        setDefaultStoreId(storeId);
      } catch {
        enqueueSnackbar('Failed to load data', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [enqueueSnackbar, authUser?.id]);

  const selectedClient = clients.find((c) => c.id === clientId);
  const clientSectorId = selectedClient?.sector_id;

  // Order channel options: recent user input first, then standard (Client PO, WhatsApp, Email) if not already in recent
  const orderChannelOptions = useMemo(() => {
    const seen = new Set(recentOrderChannels.map((c) => c.toLowerCase()));
    const standard = ORDER_CHANNEL_OPTIONS.map((o) => o.value).filter((v) => !seen.has(v.toLowerCase()));
    return [...recentOrderChannels, ...standard];
  }, [recentOrderChannels]);

  const addRow = () =>
    setRows((prev) => [...prev, { product_id: 0, quantity: 1, line_discount_type: 'order_entry', line_discount_value: 0 }]);

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
    if (row.line_discount_type === 'order_entry') {
      return Math.max(0, Math.min(before, row.line_discount_value ?? 0));
    }
    const perUnit = Math.max(0, row.line_discount_value ?? 0);
    return Math.max(0, Math.min(before, perUnit * (row.quantity || 0)));
  };

  const subtotalByLine = (row: CreateRow) => {
    const before = beforeDiscountByLine(row);
    return Math.max(0, before - lineDiscountAmount(row));
  };

  const totalSubtotal = rows.reduce((sum, r) => sum + subtotalByLine(r), 0);
  const orderDiscountAmount = Math.max(0, Math.min(totalSubtotal, orderDiscountValue ?? 0));
  const totalAfterOrderDiscount = Math.max(0, totalSubtotal - orderDiscountAmount);

  const handleSubmit = async () => {
    if (!clientId || !stores.length) {
      enqueueSnackbar('Client and at least one store are required', { variant: 'warning' });
      return;
    }
    if (useCustomShipping) {
      if (!customShippingName.trim() || !customShippingAddress1.trim()) {
        enqueueSnackbar('Enter at least location name and address line 1 for the new shipping address', {
          variant: 'warning',
        });
        return;
      }
    }
    const validRows = rows.filter((r) => r.product_id && r.quantity > 0);
    if (!validRows.length) {
      enqueueSnackbar('Add at least one product with quantity', { variant: 'warning' });
      return;
    }
    try {
      setActioning(true);
      let shippingStoreIdToUse: number | '' = shippingStoreId;
      if (useCustomShipping && clientId && saveCustomAsStore) {
        try {
          const createdStore = await wholesaleClientsAPI.createStore(clientId as number, {
            name: customShippingName.trim(),
            address_line1: customShippingAddress1.trim(),
            city: customShippingCity.trim() || undefined,
            postcode: customShippingPostcode.trim() || undefined,
          } as any);
          shippingStoreIdToUse = createdStore.id;
        } catch (e: any) {
          enqueueSnackbar(e.response?.data?.error || 'Failed to save new shipping address', { variant: 'error' });
          setActioning(false);
          return;
        }
      }
      const order = await wholesaleOrdersAPI.create({
        wholesale_client_id: clientId as number,
        wholesale_client_store_id: shippingStoreIdToUse || undefined,
        store_id: defaultStoreId ?? stores[0]?.id,
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
          line_discount_type: r.line_discount_type,
          line_discount_unit: r.line_discount_type === 'order_entry_unit' ? Math.max(0, r.line_discount_value ?? 0) : 0,
          line_discount_amount: lineDiscountAmount(r),
        })),
      });
      // If channel is Client PO but no PO number was entered, default PO number to order_number
      if (orderChannel === 'po' && !poNumber.trim()) {
        try {
          await wholesaleOrdersAPI.update(order.id, { po_number: order.order_number });
        } catch {
          // Non-critical; ignore if this defaulting fails
        }
      }
      if (poAttachmentFiles.length > 0) {
        await wholesaleOrdersAPI.uploadPoAttachments(order.id, poAttachmentFiles);
      }
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
      <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2 }}>
        <Link component={RouterLink} to="/" color="primary" underline="none">Home</Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <Link component={RouterLink} to="/wholesale-orders" color="primary" underline="none">
          {t('layout.wholesaleOrders')}
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <span>{t('wholesaleOrdersPage.createTitle')}</span>
      </Typography>

      <Typography variant="h5" sx={{ mb: 3 }}>
        {t('wholesaleOrdersPage.createTitle')}
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
              setUseCustomShipping(false);
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
        {selectedClient && (
          <>
            <FormControl fullWidth sx={{ mb: 2 }}>
              <InputLabel>Shipping address</InputLabel>
              <Select
                value={useCustomShipping ? 'custom' : shippingStoreId}
                onChange={(e) => {
                  const v = e.target.value;
                  if (v === 'custom') {
                    setUseCustomShipping(true);
                    setShippingStoreId('');
                  } else {
                    setUseCustomShipping(false);
                    setShippingStoreId(v === '' ? '' : Number(v));
                  }
                }}
                label="Shipping address"
              >
                <MenuItem value="">
                  <em>Company address</em>
                </MenuItem>
                {(selectedClient.stores || []).map((s) => (
                  <MenuItem key={s.id} value={s.id}>
                    {s.name}
                    {s.address_line1 ? ` — ${s.address_line1}${s.postcode ? `, ${s.postcode}` : ''}` : ''}
                  </MenuItem>
                ))}
                <MenuItem value="custom">
                  + New shipping address…
                </MenuItem>
              </Select>
            </FormControl>
            {useCustomShipping && (
              <Box sx={{ mb: 2, mt: 1, p: 2, borderRadius: 1, border: '1px solid', borderColor: 'divider' }}>
                <Typography variant="subtitle2" sx={{ mb: 1 }}>
                  New shipping address
                </Typography>
                <TextField
                  fullWidth
                  label="Location name"
                  value={customShippingName}
                  onChange={(e) => setCustomShippingName(e.target.value)}
                  sx={{ mb: 1.5 }}
                />
                <TextField
                  fullWidth
                  label="Address line 1"
                  value={customShippingAddress1}
                  onChange={(e) => setCustomShippingAddress1(e.target.value)}
                  sx={{ mb: 1.5 }}
                />
                <TextField
                  fullWidth
                  label="City"
                  value={customShippingCity}
                  onChange={(e) => setCustomShippingCity(e.target.value)}
                  sx={{ mb: 1.5 }}
                />
                <TextField
                  fullWidth
                  label="Postcode"
                  value={customShippingPostcode}
                  onChange={(e) => setCustomShippingPostcode(e.target.value)}
                  sx={{ mb: 1.5 }}
                />
                <FormControlLabel
                  control={
                    <Checkbox
                      checked={saveCustomAsStore}
                      onChange={(e) => setSaveCustomAsStore(e.target.checked)}
                    />
                  }
                  label="Save to frequent addresses"
                />
              </Box>
            )}
          </>
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
        <Box
          onDragOver={(e) => {
            e.preventDefault();
            e.stopPropagation();
            setPoDropActive(true);
          }}
          onDragLeave={(e) => {
            e.preventDefault();
            e.stopPropagation();
            setPoDropActive(false);
          }}
          onDrop={(e) => {
            e.preventDefault();
            e.stopPropagation();
            setPoDropActive(false);
            addPoFiles(e.dataTransfer.files);
          }}
          sx={{
            border: '2px dashed',
            borderColor: poDropActive ? 'primary.main' : 'divider',
            borderRadius: 2,
            bgcolor: poDropActive ? 'action.hover' : 'transparent',
            p: 2,
            mb: 2,
            transition: 'border-color 0.15s ease, background-color 0.15s ease',
          }}
        >
          <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 1 }}>
            PO attachment (optional)
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
            Upload PDF or images of the purchase order. Drag and drop anywhere in this box to add files.
          </Typography>
          <Box sx={{ py: 2, textAlign: 'center' }}>
            <input
              accept=".pdf,image/*"
              id="po-attachment-input"
              type="file"
              multiple
              style={{ display: 'none' }}
              onChange={(e) => {
                addPoFiles(e.target.files);
                e.target.value = '';
              }}
            />
            <label htmlFor="po-attachment-input" style={{ cursor: 'pointer' }}>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                {poDropActive ? 'Drop files here' : 'Drag and drop PDF or images here, or'}
              </Typography>
              <Button variant="outlined" component="span" startIcon={<AttachFileIcon />} size="small">
                Choose files
              </Button>
            </label>
          </Box>
          {poAttachmentFiles.length > 0 && (
            <List dense sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, maxWidth: 400 }}>
              {poAttachmentFiles.map((file, i) => (
                <ListItem key={i}>
                  <ListItemText primary={file.name} secondary={`${(file.size / 1024).toFixed(1)} KB`} />
                  <ListItemSecondaryAction>
                    <IconButton
                      edge="end"
                      size="small"
                      onClick={() => setPoAttachmentFiles((prev) => prev.filter((_, j) => j !== i))}
                      aria-label="Remove"
                    >
                      <DeleteIcon fontSize="small" />
                    </IconButton>
                  </ListItemSecondaryAction>
                </ListItem>
              ))}
            </List>
          )}
        </Box>
      </Paper>

      <Paper sx={{ p: 2, mb: 3, overflow: 'hidden' }}>
        <Typography variant="subtitle1" sx={{ mb: 2 }}>
          Items — unit price is fixed; adjust line discount to change subtotal
        </Typography>
        {isMobile ? (
          <Stack spacing={1.5}>
            {rows.map((row, idx) => {
              const product = products.find((p) => p.id === row.product_id);
              const unitPrice = getUnitPrice(product, clientSectorId);
              const subtotal = subtotalByLine(row);
              const beforeDiscount = beforeDiscountByLine(row);
              const lineDiscount = lineDiscountAmount(row);
              return (
                <Paper key={idx} variant="outlined" sx={{ p: 1.5 }}>
                  <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'flex-start', mb: 1.5 }}>
                    <ProductImageWithPopover
                      imageUrl={product?.image_url}
                      productName={product ? productDisplayName(product, lang) : ''}
                      size={48}
                    />
                    <Box sx={{ flex: 1, minWidth: 0 }}>
                      <ProductAutocomplete
                        products={products}
                        value={row.product_id || null}
                        onChange={(id) => updateRow(idx, { product_id: id ?? 0 })}
                        label="Product"
                      />
                    </Box>
                  </Box>
                  <Stack spacing={1.25}>
                    <TextField
                      label="Qty"
                      type="number"
                      size="small"
                      fullWidth
                      value={row.quantity}
                      onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })}
                      inputProps={{ min: 1, step: 1 }}
                    />
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2 }}>
                      <Typography variant="body2" color="text.secondary">
                        Unit price (£)
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        £{unitPrice.toFixed(2)}
                      </Typography>
                    </Box>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 2 }}>
                      <Typography variant="body2" color="text.secondary">
                        Discount
                      </Typography>
                      <Box component="span">
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
                              ? row.line_discount_type === 'order_entry'
                                ? `£${lineDiscountAmount(row).toFixed(2)}`
                                : `£${lineDiscountAmount(row).toFixed(2)} (unit £${(row.line_discount_value ?? 0).toFixed(2)})`
                              : 'Add discount'}
                          </Button>
                        )}
                      </Box>
                    </Box>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 2 }}>
                      <Box>
                        <Typography variant="body2" fontWeight={600}>
                          Subtotal (£{subtotal.toFixed(2)})
                        </Typography>
                        {row.line_discount_type === 'order_entry' && lineDiscount > 0 && (
                          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', lineHeight: 1.2 }}>
                            -£{lineDiscount.toFixed(2)} (from £{beforeDiscount.toFixed(2)})
                          </Typography>
                        )}
                      </Box>
                      <Button size="small" color="error" onClick={() => removeRow(idx)}>
                        Remove
                      </Button>
                    </Box>
                  </Stack>
                </Paper>
              );
            })}
          </Stack>
        ) : (
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
              const beforeDiscount = beforeDiscountByLine(row);
              const lineDiscount = lineDiscountAmount(row);
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
                            ? row.line_discount_type === 'order_entry'
                              ? `£${lineDiscountAmount(row).toFixed(2)}`
                              : `£${lineDiscountAmount(row).toFixed(2)} (unit £${(row.line_discount_value ?? 0).toFixed(2)})`
                            : 'Add discount'}
                        </Button>
                      )}
                    </Box>
                  </TableCell>
                  <TableCell align="right" sx={{ width: '12%', overflow: 'hidden' }}>
                    <Typography variant="body2">£{subtotal.toFixed(2)}</Typography>
                    {row.line_discount_type === 'order_entry' && lineDiscount > 0 && (
                      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', lineHeight: 1.2 }}>
                        -£{lineDiscount.toFixed(2)} (from £{beforeDiscount.toFixed(2)})
                      </Typography>
                    )}
                  </TableCell>
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
        )}
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
                if (step === 'order_entry') {
                  updateRow(idx, { line_discount_type: 'order_entry', line_discount_value: Math.max(0, num) });
                } else if (step === 'order_entry_unit') {
                  updateRow(idx, { line_discount_type: 'order_entry_unit', line_discount_value: Math.max(0, num) });
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
                        setDiscountPopover((p) => (p ? { ...p, step: 'order_entry' } : null));
                      }}
                    >
                      order entry
                    </Button>
                    <Button
                      size="small"
                      fullWidth
                      variant="outlined"
                      onClick={() => {
                        const perUnitCurrent =
                          row.quantity > 0 ? lineDiscountAmount(row) / row.quantity : (row.line_discount_value ?? 0);
                        setDiscountInputValue(String(perUnitCurrent.toFixed(2)));
                        setDiscountPopover((p) => (p ? { ...p, step: 'order_entry_unit' } : null));
                      }}
                    >
                      order entry unit
                    </Button>
                  </Box>
                );
              }

              if (step === 'order_entry') {
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

              // step === 'order_entry_unit'
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
                      step: 'order_discount',
                    });
                  }}
                >
                  {(orderDiscountValue ?? 0) > 0 || orderDiscountAmount > 0
                    ? `£${orderDiscountAmount.toFixed(2)}`
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
                    if (step === 'order_discount') {
                      setOrderDiscountValue(Math.max(0, num));
                    }
                    setOrderDiscountPopover(null);
                    setOrderDiscountInputValue('');
                  };
                  if (step === 'order_discount') {
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
                  return null;
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
