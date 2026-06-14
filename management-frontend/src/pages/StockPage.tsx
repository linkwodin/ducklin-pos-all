import { useEffect, useState } from 'react';
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
  TextField,
  MenuItem,
  Alert,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  IconButton,
  Tooltip,
  Checkbox,
  FormControlLabel,
} from '@mui/material';
import {
  Warning as WarningIcon,
  Add as AddIcon,
  Delete as DeleteIcon,
  History as HistoryIcon,
  LocalShipping as LocalShippingIcon,
  Edit as EditIcon,
  Save as SaveIcon,
} from '@mui/icons-material';
import { stockAPI, storesAPI, restockAPI, productsAPI, auditAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Stock, Store, Product, AuditLog } from '../types';
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import { useTheme, alpha } from '@mui/material/styles';
import UserDisplay from '../components/UserDisplay';
import ProductAutocomplete from '../components/ProductAutocomplete';
import VariantProductPicker from '../components/VariantProductPicker';
import {
  assignmentFlagsForVariant,
  formatStockLevelAtStore,
  productIsWeight,
  stockLevelInputLabel,
  stockLevelValue,
  stockProductLabel,
} from '../utils/productInventory';

function formatPendingPackAmount(
  qty: number | undefined,
  product?: Product | null,
): string {
  if (qty == null || qty <= 0) return '—';
  if (productIsWeight(product)) return `${qty} g`;
  return Number.isInteger(qty) ? String(qty) : String(qty);
}

export default function StockPage() {
  const { t, i18n } = useTranslation(['stock', 'common', 'stores', 'assignProductToStore']);
  const theme = useTheme();
  const lang = i18n.language || 'en';
  const shipHeaderBg = alpha(theme.palette.success.main, 0.16);
  const [stock, setStock] = useState<Stock[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [lowStock, setLowStock] = useState<Stock[]>([]);
  const [selectedStore, setSelectedStore] = useState<number | ''>('');
  const [loading, setLoading] = useState(true);
  const [restockDialogOpen, setRestockDialogOpen] = useState(false);
  const [auditDialogOpen, setAuditDialogOpen] = useState(false);
  const [selectedStockItem, setSelectedStockItem] = useState<Stock | null>(null);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [loadingAuditLogs, setLoadingAuditLogs] = useState(false);
  const [addInventoryOpen, setAddInventoryOpen] = useState(false);
  const [adjustDialogOpen, setAdjustDialogOpen] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchStores();
    fetchLowStock();
  }, []);

  useEffect(() => {
    fetchStock();
  }, [selectedStore]);

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list();
      setStores(data);
    } catch (error) {
      enqueueSnackbar(t('stock:fetchStoresFailed', 'Failed to fetch stores'), { variant: 'error' });
    }
  };

  const fetchStock = async () => {
    try {
      setLoading(true);
      const data = await stockAPI.list(
        selectedStore ? Number(selectedStore) : undefined
      );
      setStock(data);
    } catch (error) {
      enqueueSnackbar(t('stock:fetchStockFailed', 'Failed to fetch stock'), { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const fetchLowStock = async () => {
    try {
      const data = await stockAPI.getLowStock();
      setLowStock(data);
    } catch (error) {
      console.error('Failed to fetch low stock:', error);
    }
  };

  const handleViewAuditLogs = async (item: Stock) => {
    setSelectedStockItem(item);
    setAuditDialogOpen(true);
    setLoadingAuditLogs(true);

    try {
      const logs = await auditAPI.getStockAuditLogs({
        entity_id: item.id,
        product_id: item.product_id,
        store_id: item.store_id,
      });
      setAuditLogs(logs);
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('stock:fetchAuditLogsFailed', 'Failed to fetch audit logs'), {
        variant: 'error',
      });
      setAuditLogs([]);
    } finally {
      setLoadingAuditLogs(false);
    }
  };

  const handleInitiateRestock = (item: Stock) => {
    setSelectedStockItem(item);
    setRestockDialogOpen(true);
  };

  const handleCreateRestock = async (orderData: {
    store_id: number;
    items: { product_id: number; quantity: number }[];
    notes?: string;
  }) => {
    try {
      await restockAPI.create(orderData);
      enqueueSnackbar(t('stock:shipmentCreated', 'Shipment created successfully'), { variant: 'success' });
      setRestockDialogOpen(false);
      setSelectedStockItem(null);
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('stock:shipmentCreateFailed', 'Failed to create shipment'), {
        variant: 'error',
      });
    }
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        {t('stock:title')}
      </Typography>

      {lowStock.length > 0 && (
        <Alert severity="warning" icon={<WarningIcon />} sx={{ mb: 3 }}>
          <Typography variant="h6" gutterBottom>
            {t('stock:lowStockAlert', { count: lowStock.length })}
          </Typography>
          <Box component="ul" sx={{ pl: 2 }}>
            {lowStock.slice(0, 5).map((item) => (
              <li key={item.id}>
                {stockProductLabel(item.product, lang, t)} — {formatStockLevelAtStore(item, item.product)} ({t('stock:store')}:{' '}
                {item.store?.name})
              </li>
            ))}
            {lowStock.length > 5 && (
              <li>{t('stock:lowStockMore', { count: lowStock.length - 5, defaultValue: '…and {{count}} more' })}</li>
            )}
          </Box>
        </Alert>
      )}

      <Box sx={{ mb: 2, display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
        <TextField
          select
          label={t('stock:filterByStore')}
          value={selectedStore}
          onChange={(e) => setSelectedStore(e.target.value ? Number(e.target.value) : '')}
          sx={{ minWidth: 200 }}
          size="small"
        >
          <MenuItem value="">{t('stock:allStores')}</MenuItem>
          {stores.map((store) => (
            <MenuItem key={store.id} value={store.id}>
              {store.name}
              {store.is_warehouse_only ? ` (${t('stores:warehouseOnly')})` : ''}
            </MenuItem>
          ))}
        </TextField>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setAddInventoryOpen(true)}>
          {t('stock:addInventory')}
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>{t('stock:product')}</TableCell>
              <TableCell>{t('stock:store')}</TableCell>
              <TableCell align="right">{t('stock:stockLevel')}</TableCell>
              <TableCell align="right">{t('stock:pendingPack')}</TableCell>
              <TableCell>{t('stock:lowStockThreshold')}</TableCell>
              <TableCell align="center" sx={{ bgcolor: shipHeaderBg, color: 'success.dark', fontWeight: 600 }}>
                {t('assignProductToStore:shipFromShort')}
              </TableCell>
              <TableCell>{t('common:status')}</TableCell>
              <TableCell>{t('stock:lastUpdated')}</TableCell>
              <TableCell>{t('common:actions')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={9} align="center">
                  {t('common:loading')}
                </TableCell>
              </TableRow>
            ) : stock.length === 0 ? (
              <TableRow>
                <TableCell colSpan={9} align="center">
                  {t('common:noData')}
                </TableCell>
              </TableRow>
            ) : (
              stock.map((item) => {
                const product = item.product;
                const level = stockLevelValue(item, product);
                const isLowStock = level <= item.low_stock_threshold;
                return (
                  <TableRow key={item.id} hover>
                    <TableCell>{stockProductLabel(product, lang, t)}</TableCell>
                    <TableCell>{item.store?.name || '-'}</TableCell>
                    <TableCell align="right">
                      {formatStockLevelAtStore(item, product)}
                      {item.incoming_quantity && item.incoming_quantity > 0 ? (
                        <span style={{ color: '#1976d2', marginLeft: '4px' }}>
                          (+{item.incoming_quantity}
                          {productIsWeight(product) ? ' g' : ''})
                        </span>
                      ) : null}
                    </TableCell>
                    <TableCell align="right">
                      {formatPendingPackAmount(item.pending_pack_quantity, product)}
                    </TableCell>
                    <TableCell>
                      {item.low_stock_threshold}{' '}
                      {productIsWeight(product) ? 'g' : t('stock:units')}
                    </TableCell>
                    <TableCell align="center">
                      {item.wholesale_ship_from ? (
                        <Tooltip title={t('stock:defaultShipFromStore')}>
                          <LocalShippingIcon fontSize="small" sx={{ color: 'success.dark' }} />
                        </Tooltip>
                      ) : (
                        '—'
                      )}
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={isLowStock ? t('stock:lowStock') : t('stock:inStock')}
                        size="small"
                        color={isLowStock ? 'error' : 'success'}
                      />
                    </TableCell>
                    <TableCell>
                      {new Date(item.last_updated).toLocaleDateString()}
                    </TableCell>
                    <TableCell>
                      <Box sx={{ display: 'flex', gap: 0.5 }}>
                        <Tooltip title={t('stock:adjustInventory')}>
                          <IconButton
                            size="small"
                            onClick={() => {
                              setSelectedStockItem(item);
                              setAdjustDialogOpen(true);
                            }}
                            color="primary"
                          >
                            <EditIcon />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title={t('stock:viewAmendmentRecord')}>
                          <IconButton
                            size="small"
                            onClick={() => handleViewAuditLogs(item)}
                            color="primary"
                          >
                            <HistoryIcon />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title={t('stock:initiateRestock')}>
                          <IconButton
                            size="small"
                            onClick={() => handleInitiateRestock(item)}
                            color="secondary"
                          >
                            <LocalShippingIcon />
                          </IconButton>
                        </Tooltip>
                      </Box>
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </TableContainer>

      {selectedStockItem && (
        <>
          <RestockDialog
            open={restockDialogOpen}
            onClose={() => {
              setRestockDialogOpen(false);
              setSelectedStockItem(null);
            }}
            onSave={handleCreateRestock}
            stockItem={selectedStockItem}
            stores={stores}
          />
          <AuditLogDialog
            open={auditDialogOpen}
            onClose={() => {
              setAuditDialogOpen(false);
              setSelectedStockItem(null);
              setAuditLogs([]);
            }}
            stockItem={selectedStockItem}
            auditLogs={auditLogs}
            loading={loadingAuditLogs}
          />
        </>
      )}

      <AddInventoryDialog
        open={addInventoryOpen}
        onClose={() => setAddInventoryOpen(false)}
        stores={stores}
        initialStoreId={selectedStore === '' ? null : Number(selectedStore)}
        existingStock={stock}
        onSaved={() => {
          setAddInventoryOpen(false);
          fetchStock();
          fetchLowStock();
        }}
      />

      {selectedStockItem && (
        <AdjustStockDialog
          open={adjustDialogOpen}
          onClose={() => {
            setAdjustDialogOpen(false);
            setSelectedStockItem(null);
          }}
          stockItem={selectedStockItem}
          onSaved={() => {
            setAdjustDialogOpen(false);
            setSelectedStockItem(null);
            fetchStock();
            fetchLowStock();
          }}
        />
      )}
    </Box>
  );
}

function AddInventoryDialog({
  open,
  onClose,
  stores,
  initialStoreId,
  existingStock,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  stores: Store[];
  initialStoreId: number | null;
  existingStock: Stock[];
  onSaved: () => void;
}) {
  const { t } = useTranslation(['stock', 'common', 'stores']);
  const { enqueueSnackbar } = useSnackbar();
  const [products, setProducts] = useState<Product[]>([]);
  const [storeId, setStoreId] = useState<number | ''>('');
  const [productId, setProductId] = useState<number | null>(null);
  const [level, setLevel] = useState('0');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setStoreId(initialStoreId ?? '');
    setProductId(null);
    setLevel('0');
    productsAPI.list().then(setProducts).catch(() => {});
  }, [open, initialStoreId]);

  const assignedAtStore = new Set(
    existingStock.filter((row) => row.store_id === storeId).map((row) => row.product_id),
  );
  const addableProducts = products.filter((p) => !assignedAtStore.has(p.id));
  const selectedProduct = products.find((p) => p.id === productId);

  const handleSave = async () => {
    if (storeId === '' || !productId || !selectedProduct) return;
    const levelNum = parseFloat(level);
    if (Number.isNaN(levelNum) || levelNum < 0) {
      enqueueSnackbar(t('stock:invalidQuantity'), { variant: 'warning' });
      return;
    }
    try {
      setSaving(true);
      await stockAPI.setAssignments(Number(storeId), [
        {
          product_id: productId,
          ...assignmentFlagsForVariant(selectedProduct),
          wholesale_ship_from: false,
        },
      ]);
      await stockAPI.update(productId, Number(storeId), {
        quantity: productIsWeight(selectedProduct) ? 0 : levelNum,
        weight_quantity_g: productIsWeight(selectedProduct) ? levelNum : undefined,
        low_stock_threshold: 0,
        reason: 'manual adjustment',
      });
      enqueueSnackbar(t('stock:inventorySaved'), { variant: 'success' });
      onSaved();
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('stock:inventorySaveFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onClose={() => !saving && onClose()} maxWidth="sm" fullWidth>
      <DialogTitle>{t('stock:addInventory')}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            select
            label={t('stock:store')}
            required
            fullWidth
            size="small"
            value={storeId}
            onChange={(e) => {
              setStoreId(e.target.value === '' ? '' : Number(e.target.value));
              setProductId(null);
            }}
          >
            {stores.map((store) => (
              <MenuItem key={store.id} value={store.id}>
                {store.name}
                {store.is_warehouse_only ? ` (${t('stores:warehouseOnly')})` : ''}
              </MenuItem>
            ))}
          </TextField>
          {storeId === '' ? (
            <Alert severity="info" sx={{ py: 0.5 }}>
              {t('stock:selectStoreForVariant')}
            </Alert>
          ) : null}
          <VariantProductPicker
            products={addableProducts}
            productId={productId}
            onProductIdChange={setProductId}
            disabled={saving || storeId === ''}
            resetKey={storeId}
            autoFocus={storeId !== ''}
          />
          <TextField
            label={stockLevelInputLabel(selectedProduct, t)}
            type="number"
            size="small"
            fullWidth
            value={level}
            onChange={(e) => setLevel(e.target.value)}
            inputProps={{ min: 0, step: 0.001 }}
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={saving}>
          {t('common:cancel')}
        </Button>
        <Button
          variant="contained"
          startIcon={<SaveIcon />}
          onClick={() => void handleSave()}
          disabled={saving || storeId === '' || !productId}
        >
          {saving ? t('common:loading') : t('stock:saveInventory')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function AdjustStockDialog({
  open,
  onClose,
  stockItem,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  stockItem: Stock;
  onSaved: () => void;
}) {
  const { t, i18n } = useTranslation(['stock', 'common', 'assignProductToStore']);
  const lang = i18n.language || 'en';
  const { enqueueSnackbar } = useSnackbar();
  const [level, setLevel] = useState('0');
  const [lowStockThreshold, setLowStockThreshold] = useState('0');
  const [wholesaleShipFrom, setWholesaleShipFrom] = useState(false);
  const [saving, setSaving] = useState(false);

  const product = stockItem.product;

  useEffect(() => {
    if (!open) return;
    setLevel(String(stockLevelValue(stockItem, product)));
    setLowStockThreshold(String(stockItem.low_stock_threshold ?? 0));
    setWholesaleShipFrom(!!stockItem.wholesale_ship_from);
  }, [open, stockItem, product]);

  const handleSave = async () => {
    const levelNum = parseFloat(level);
    const threshold = parseFloat(lowStockThreshold);
    if (Number.isNaN(levelNum) || levelNum < 0) {
      enqueueSnackbar(t('stock:invalidQuantity'), { variant: 'warning' });
      return;
    }
    if (Number.isNaN(threshold) || threshold < 0) {
      enqueueSnackbar(t('stock:invalidThreshold'), { variant: 'warning' });
      return;
    }
    try {
      setSaving(true);
      await stockAPI.setAssignments(stockItem.store_id, [
        {
          product_id: stockItem.product_id,
          ...assignmentFlagsForVariant(product),
          wholesale_ship_from: wholesaleShipFrom,
        },
      ]);
      await stockAPI.update(stockItem.product_id, stockItem.store_id, {
        quantity: productIsWeight(product) ? 0 : levelNum,
        weight_quantity_g: productIsWeight(product) ? levelNum : undefined,
        low_stock_threshold: threshold,
        reason: 'manual adjustment',
      });
      enqueueSnackbar(t('stock:inventorySaved'), { variant: 'success' });
      onSaved();
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('stock:inventorySaveFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onClose={() => !saving && onClose()} maxWidth="sm" fullWidth>
      <DialogTitle>{t('stock:adjustInventory')}</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          {stockProductLabel(product, lang, t)} · {stockItem.store?.name}
        </Typography>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <TextField
            label={stockLevelInputLabel(product, t)}
            type="number"
            size="small"
            fullWidth
            value={level}
            onChange={(e) => setLevel(e.target.value)}
            inputProps={{ min: 0, step: 0.001 }}
          />
          <TextField
            label={t('stock:lowStockThreshold')}
            type="number"
            size="small"
            fullWidth
            value={lowStockThreshold}
            onChange={(e) => setLowStockThreshold(e.target.value)}
            inputProps={{ min: 0, step: 0.001 }}
          />
          <FormControlLabel
            control={
              <Checkbox
                checked={wholesaleShipFrom}
                onChange={(e) => setWholesaleShipFrom(e.target.checked)}
                icon={<LocalShippingIcon fontSize="small" />}
                checkedIcon={<LocalShippingIcon fontSize="small" />}
              />
            }
            label={t('assignProductToStore:shipFrom')}
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={saving}>
          {t('common:cancel')}
        </Button>
        <Button
          variant="contained"
          startIcon={<SaveIcon />}
          onClick={() => void handleSave()}
          disabled={saving}
        >
          {saving ? t('common:loading') : t('stock:saveInventory')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function RestockDialog({
  open,
  onClose,
  onSave,
  stockItem,
  stores,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: {
    store_id: number;
    items: { product_id: number; quantity: number }[];
    notes?: string;
  }) => void;
  stockItem: Stock;
  stores: Store[];
}) {
  const { t } = useTranslation(['stock', 'common', 'stores']);
  const [formData, setFormData] = useState({
    store_id: 0,
    items: [] as { product_id: number; quantity: number }[],
    notes: '',
  });
  const [products, setProducts] = useState<Product[]>([]);

  useEffect(() => {
    if (open && stockItem) {
      // Pre-fill with selected stock item
      setFormData({
        store_id: stockItem.store_id,
        items: stockItem.product_id
          ? [{ product_id: stockItem.product_id, quantity: 0 }]
          : [],
        notes: `Restock for ${stockItem.product?.name || 'product'}`,
      });
      fetchProducts();
    }
  }, [open, stockItem]);

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
    // Validate all items have product and quantity
    const validItems = formData.items.filter(
      (item) => item.product_id > 0 && item.quantity > 0
    );
    if (validItems.length === 0) {
      return;
    }
    onSave({
      ...formData,
      items: validItems,
    });
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>{t('stock:createShipment')}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            select
            label={t('stock:store')}
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
                {store.is_warehouse_only ? ` (${t('stores:warehouseOnly')})` : ''}
              </MenuItem>
            ))}
          </TextField>
          <TextField
            label={t('common:notes')}
            fullWidth
            multiline
            rows={3}
            value={formData.notes}
            onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
          />
          <Box>
            <Button onClick={handleAddItem} startIcon={<AddIcon />}>
              {t('stock:addItem')}
            </Button>
            {formData.items.map((item, index) => (
                <Box key={index} sx={{ display: 'flex', gap: 1, mt: 1, alignItems: 'center' }}>
                  <Box sx={{ flex: 2 }}>
                    <ProductAutocomplete
                      products={products}
                      value={item.product_id || null}
                      onChange={(id) => handleItemChange(index, 'product_id', id ?? 0)}
                      label={t('stock:productSelect')}
                    />
                  </Box>
                  <TextField
                    label={t('stock:quantityInput')}
                    type="number"
                    required
                    sx={{ flex: 1 }}
                    size="small"
                    value={item.quantity}
                    onChange={(e) =>
                      handleItemChange(index, 'quantity', parseFloat(e.target.value) || 0)
                    }
                    inputProps={{ min: 0, step: 0.01 }}
                  />
                  {formData.items.length > 1 && (
                    <IconButton onClick={() => handleRemoveItem(index)} color="error">
                      <DeleteIcon />
                    </IconButton>
                    )}
                  </Box>
                )
            )}
          </Box>
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('common:cancel')}</Button>
        <Button onClick={handleSubmit} variant="contained">
          {t('stock:createShipment')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function AuditLogDialog({
  open,
  onClose,
  stockItem,
  auditLogs,
  loading,
}: {
  open: boolean;
  onClose: () => void;
  stockItem: Stock | null;
  auditLogs: AuditLog[];
  loading: boolean;
}) {
  const { t } = useTranslation(['stock', 'common']);
  const parseChanges = (changesJson: string) => {
    try {
      return JSON.parse(changesJson);
    } catch {
      return {};
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>
        {t('stock:stockAmendmentRecord')}
        {stockItem && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
            {stockItem.product?.name} - {t('stock:store')}: {stockItem.store?.name}
          </Typography>
        )}
      </DialogTitle>
      <DialogContent>
        {loading ? (
          <Box sx={{ textAlign: 'center', py: 4 }}>
            <Typography>{t('common:loading')}</Typography>
          </Box>
        ) : auditLogs.length === 0 ? (
          <Box sx={{ textAlign: 'center', py: 4 }}>
            <Typography color="text.secondary">{t('stock:noAuditLogs')}</Typography>
          </Box>
        ) : (
          <TableContainer>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>{t('common:date')} & {t('common:time')}</TableCell>
                  <TableCell>{t('common:user')}</TableCell>
                  <TableCell>{t('stock:oldQuantity')}</TableCell>
                  <TableCell>{t('stock:newQuantity')}</TableCell>
                  <TableCell>{t('stock:change')}</TableCell>
                  <TableCell>{t('common:reason')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {auditLogs.map((log) => {
                  const changes = parseChanges(log.changes);
                  const oldQty = changes.old_quantity || 0;
                  const newQty = changes.new_quantity || 0;
                  const change = newQty - oldQty;
                  const reason = changes.reason || 'N/A';

                  return (
                    <TableRow key={log.id}>
                      <TableCell>
                        {format(new Date(log.created_at), 'yyyy-MM-dd HH:mm:ss')}
                      </TableCell>
                      <TableCell>
                        <UserDisplay user={log.user} showName={true} size="small" />
                      </TableCell>
                      <TableCell>{oldQty.toFixed(2)}</TableCell>
                      <TableCell>{newQty.toFixed(2)}</TableCell>
                      <TableCell>
                        <Chip
                          label={change >= 0 ? `+${change.toFixed(2)}` : change.toFixed(2)}
                          size="small"
                          color={change >= 0 ? 'success' : 'error'}
                        />
                      </TableCell>
                      <TableCell>{reason}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('common:close')}</Button>
      </DialogActions>
    </Dialog>
  );
}

