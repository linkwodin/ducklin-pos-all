import { useEffect, useState } from 'react';
import { Link as RouterLink, useParams } from 'react-router-dom';
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
  CircularProgress,
  Checkbox,
  Tooltip,
  Link,
  Chip,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  IconButton,
} from '@mui/material';
import {
  ChevronRight as ChevronRightIcon,
  LocalShipping as LocalShippingIcon,
  Add as AddIcon,
  Save as SaveIcon,
} from '@mui/icons-material';
import { useTheme, alpha } from '@mui/material/styles';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import { productsAPI, stockAPI, storesAPI } from '../services/api';
import type { Product, Stock, Store } from '../types';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import VariantProductPicker from '../components/VariantProductPicker';
import {
  assignmentFlagsForVariant,
  productIsWeight,
  stockLevelInputLabel,
  stockLevelValue,
  stockProductLabel,
} from '../utils/productInventory';

export default function StoreDetailPage() {
  const { id } = useParams<{ id: string }>();
  const storeId = Number(id);
  const { t, i18n } = useTranslation(['storeDetail', 'assignProductToStore', 'storesPage', 'stores', 'stock', 'common']);
  const theme = useTheme();
  const lang = i18n.language || 'en';
  const { enqueueSnackbar } = useSnackbar();
  const [store, setStore] = useState<Store | null>(null);
  const [stockRows, setStockRows] = useState<Stock[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [stockDrafts, setStockDrafts] = useState<Record<number, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingProductId, setSavingProductId] = useState<number | null>(null);
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [addProductId, setAddProductId] = useState<number | null>(null);
  const [addLevel, setAddLevel] = useState('0');
  const [addingProduct, setAddingProduct] = useState(false);
  const shipCheckboxSx = {
    color: theme.palette.success.dark,
    '&.Mui-checked': { color: theme.palette.success.dark },
  };
  const shipHeaderBg = alpha(theme.palette.success.main, 0.16);

  const load = async () => {
    if (!id || Number.isNaN(storeId)) {
      setLoading(false);
      return;
    }
    try {
      setLoading(true);
      const [stores, stock, productList] = await Promise.all([
        storesAPI.list(),
        stockAPI.getStoreStock(storeId),
        productsAPI.list(),
      ]);
      const found = stores.find((s) => s.id === storeId) ?? null;
      const rows = stock.filter((row) => row.track_prepacked !== false || row.track_weight);
      setStore(found);
      setProducts(productList);
      setStockRows(rows);
      setStockDrafts(
        Object.fromEntries(rows.map((row) => [row.product_id, String(stockLevelValue(row, row.product))])),
      );
    } catch {
      enqueueSnackbar(t('storeDetail:loadFailed'), { variant: 'error' });
      setStore(null);
      setStockRows([]);
      setStockDrafts({});
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, [id, storeId]);

  const assignedProductIds = new Set(stockRows.map((row) => row.product_id));
  const addableProducts = products.filter((p) => !assignedProductIds.has(p.id));

  const toggleShipFrom = async (row: Stock) => {
    const enabling = !row.wholesale_ship_from;
    try {
      setSavingProductId(row.product_id);
      await stockAPI.setAssignments(storeId, [
        {
          product_id: row.product_id,
          ...assignmentFlagsForVariant(row.product),
          wholesale_ship_from: enabling,
        },
      ]);
      await load();
      enqueueSnackbar(t('storeDetail:shipFromSaved'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:shipFromSaveFailed'), { variant: 'error' });
    } finally {
      setSavingProductId(null);
    }
  };

  const saveStock = async (row: Stock) => {
    const draft = stockDrafts[row.product_id];
    if (draft == null) return;
    const product = row.product;
    const level = parseFloat(draft);
    if (Number.isNaN(level) || level < 0) {
      enqueueSnackbar(t('storeDetail:invalidQuantity'), { variant: 'warning' });
      return;
    }
    try {
      setSavingProductId(row.product_id);
      await stockAPI.update(row.product_id, storeId, {
        quantity: productIsWeight(product) ? 0 : level,
        weight_quantity_g: productIsWeight(product) ? level : undefined,
        low_stock_threshold: row.low_stock_threshold,
        reason: 'manual adjustment',
      });
      await load();
      enqueueSnackbar(t('storeDetail:stockSaved'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:stockSaveFailed'), { variant: 'error' });
    } finally {
      setSavingProductId(null);
    }
  };

  const handleAddProduct = async () => {
    if (!addProductId) return;
    const product = products.find((p) => p.id === addProductId);
    if (!product) return;
    const level = parseFloat(addLevel);
    if (Number.isNaN(level) || level < 0) {
      enqueueSnackbar(t('storeDetail:invalidQuantity'), { variant: 'warning' });
      return;
    }
    try {
      setAddingProduct(true);
      await stockAPI.setAssignments(storeId, [
        {
          product_id: addProductId,
          ...assignmentFlagsForVariant(product),
          wholesale_ship_from: false,
        },
      ]);
      await stockAPI.update(addProductId, storeId, {
        quantity: productIsWeight(product) ? 0 : level,
        weight_quantity_g: productIsWeight(product) ? level : undefined,
        low_stock_threshold: 0,
        reason: 'manual adjustment',
      });
      setAddDialogOpen(false);
      setAddProductId(null);
      setAddLevel('0');
      await load();
      enqueueSnackbar(t('storeDetail:productAdded'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:productAddFailed'), { variant: 'error' });
    } finally {
      setAddingProduct(false);
    }
  };

  if (loading) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!store) {
    return (
      <Box sx={{ p: 3 }}>
        <Typography color="text.secondary">{t('storeDetail:notFound')}</Typography>
      </Box>
    );
  }

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2, flexWrap: 'wrap' }}>
        <Link component={RouterLink} to="/" color="primary" underline="none">
          Home
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <Link component={RouterLink} to="/stores" color="primary" underline="none">
          {t('storesPage:title')}
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <span>{store.name}</span>
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h4" sx={{ mb: 2, typography: { xs: 'h5', md: 'h4' } }}>
          {store.name}
        </Typography>
        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 1 }}>
          <Chip
            size="small"
            label={store.is_active ? t('storesPage:active') : t('storesPage:inactive')}
            color={store.is_active ? 'success' : 'default'}
            variant="outlined"
          />
          {store.is_warehouse_only ? (
            <Chip size="small" label={t('stores:warehouseOnly')} variant="outlined" />
          ) : null}
        </Box>
        <Typography variant="body2" color="text.secondary">
          {store.address || '—'}
        </Typography>
      </Paper>

      <Paper sx={{ p: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 2, flexWrap: 'wrap', mb: 2 }}>
          <Box>
            <Typography variant="h6">{t('storeDetail:productsSection')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {t('storeDetail:productsHint')}
            </Typography>
          </Box>
          <Button variant="contained" startIcon={<AddIcon />} onClick={() => setAddDialogOpen(true)}>
            {t('storeDetail:addProduct')}
          </Button>
        </Box>
        <TableContainer>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 52 }} />
                <TableCell>{t('assignProductToStore:product')}</TableCell>
                <TableCell align="right" sx={{ minWidth: 120 }}>
                  {t('stock:stockLevel')}
                </TableCell>
                <TableCell align="center" sx={{ bgcolor: shipHeaderBg, color: 'success.dark', fontWeight: 600 }}>
                  {t('assignProductToStore:shipFromShort')}
                </TableCell>
                <TableCell align="center" sx={{ width: 72 }}>
                  {t('common:actions')}
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {stockRows.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={5} align="center" sx={{ color: 'text.secondary' }}>
                    {t('storeDetail:noProducts')}
                  </TableCell>
                </TableRow>
              ) : (
                stockRows.map((row) => {
                  const product = row.product;
                  return (
                    <TableRow key={row.id} hover>
                      <TableCell>
                        <ProductImageWithPopover
                          imageUrl={product?.image_url}
                          productName={stockProductLabel(product, lang, t)}
                          size={40}
                        />
                      </TableCell>
                      <TableCell>{stockProductLabel(product, lang, t)}</TableCell>
                      <TableCell align="right">
                        <TextField
                          size="small"
                          type="number"
                          value={stockDrafts[row.product_id] ?? '0'}
                          onChange={(e) =>
                            setStockDrafts((prev) => ({ ...prev, [row.product_id]: e.target.value }))
                          }
                          inputProps={{ min: 0, step: 0.001 }}
                          sx={{ width: 112 }}
                        />
                      </TableCell>
                      <TableCell align="center">
                        <Tooltip title={t('assignProductToStore:shipFrom')}>
                          <span>
                            <Checkbox
                              checked={!!row.wholesale_ship_from}
                              size="small"
                              disabled={savingProductId === row.product_id}
                              sx={shipCheckboxSx}
                              icon={<LocalShippingIcon fontSize="small" />}
                              checkedIcon={<LocalShippingIcon fontSize="small" />}
                              onChange={() => toggleShipFrom(row)}
                            />
                          </span>
                        </Tooltip>
                      </TableCell>
                      <TableCell align="center">
                        <Tooltip title={t('storeDetail:saveStock')}>
                          <span>
                            <IconButton
                              size="small"
                              color="primary"
                              disabled={savingProductId === row.product_id}
                              onClick={() => saveStock(row)}
                            >
                              {savingProductId === row.product_id ? (
                                <CircularProgress size={18} />
                              ) : (
                                <SaveIcon fontSize="small" />
                              )}
                            </IconButton>
                          </span>
                        </Tooltip>
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>

      <Dialog open={addDialogOpen} onClose={() => !addingProduct && setAddDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{t('storeDetail:addProduct')}</DialogTitle>
        <DialogContent>
          <Box sx={{ mt: 1, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <VariantProductPicker
              products={addableProducts}
              productId={addProductId}
              onProductIdChange={setAddProductId}
              disabled={addingProduct}
            />
            <TextField
              label={stockLevelInputLabel(products.find((p) => p.id === addProductId), t)}
              type="number"
              size="small"
              fullWidth
              value={addLevel}
              onChange={(e) => setAddLevel(e.target.value)}
              inputProps={{ min: 0, step: 0.001 }}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAddDialogOpen(false)} disabled={addingProduct}>
            {t('common:cancel')}
          </Button>
          <Button variant="contained" onClick={handleAddProduct} disabled={addingProduct || !addProductId}>
            {addingProduct ? t('storeDetail:addingProduct') : t('storeDetail:addProduct')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
