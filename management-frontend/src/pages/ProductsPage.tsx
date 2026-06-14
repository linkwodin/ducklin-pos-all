import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Box,
  Button,
  Paper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  IconButton,
  Chip,
  TextField,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  MenuItem,
  CircularProgress,
  useMediaQuery,
  Tooltip,
} from '@mui/material';
import { useTheme } from '@mui/material/styles';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
  Visibility as VisibilityIcon,
  EditNote as EditNoteIcon,
} from '@mui/icons-material';
import { productsAPI, categoriesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { Product } from '../types';
import { productDisplayBarcode, productIsWeight } from '../utils/productInventory';
import ProductVariantDialog from '../components/ProductVariantDialog';

export default function ProductsPage() {
  const { t } = useTranslation();
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [categoryFilter, setCategoryFilter] = useState('');
  const [importDialogOpen, setImportDialogOpen] = useState(false);
  const [importFile, setImportFile] = useState<File | null>(null);
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const theme = useTheme();
  const isListMobile = useMediaQuery(theme.breakpoints.down('md'));

  useEffect(() => {
    fetchProducts();
    fetchCategories();
  }, [categoryFilter]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const data = await productsAPI.list(categoryFilter || undefined);
      setProducts(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch products', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const fetchCategories = async () => {
    try {
      const data = await categoriesAPI.list();
      setCategories(data);
    } catch (error) {
      // Silently fail - categories are optional
      console.error('Failed to fetch categories:', error);
    }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm(t('productsPage.confirmDeactivate'))) {
      return;
    }
    try {
      await productsAPI.delete(id);
      enqueueSnackbar('Product deactivated', { variant: 'success' });
      fetchProducts();
    } catch (error) {
      enqueueSnackbar('Failed to deactivate product', { variant: 'error' });
    }
  };

  const handleSave = async (productData: Partial<Product> | FormData) => {
    try {
      if (editingProduct) {
        await productsAPI.update(editingProduct.id, productData);
        enqueueSnackbar('Product updated', { variant: 'success' });
      } else {
        await productsAPI.create(productData);
        enqueueSnackbar('Product created', { variant: 'success' });
      }
      setOpen(false);
      setEditingProduct(null);
      fetchProducts();
      fetchCategories(); // Refresh categories after adding/updating product
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to save product', {
        variant: 'error',
      });
    }
  };

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          mb: 3,
          flexWrap: 'wrap',
          gap: 1.5,
        }}
      >
        <Typography variant="h4" sx={{ typography: { xs: 'h5', md: 'h4' } }}>
          {t('products.title')}
        </Typography>
        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', justifyContent: { xs: 'flex-start', sm: 'flex-end' } }}>
          <Button
            variant="outlined"
            onClick={() => setImportDialogOpen(true)}
          >
            {t('productsPage.importFromExcel')}
          </Button>
          <Button
            variant="outlined"
            startIcon={<EditNoteIcon />}
            onClick={() => navigate('/product-cost-editor')}
          >
            {t('productsPage.costPriceEditor')}
          </Button>
          <Button
            variant="outlined"
            onClick={() => navigate('/product-lines')}
          >
            {t('productLines.title')}
          </Button>
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={() => {
              setEditingProduct(null);
              setOpen(true);
            }}
          >
            {t('products.addProduct')}
          </Button>
        </Box>
      </Box>

      <Box sx={{ mb: 2 }}>
        <TextField
          select
          label={t('productsPage.filterByCategory')}
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          sx={{ minWidth: { xs: 0, sm: 200 }, width: { xs: '100%', sm: 'auto' } }}
          size="small"
        >
          <MenuItem value="">{t('productsPage.allCategories')}</MenuItem>
          {categories.map((cat) => (
            <MenuItem key={cat} value={cat}>
              {cat}
            </MenuItem>
          ))}
        </TextField>
      </Box>

      {isListMobile ? (
        <Stack spacing={1.5} component={Paper} sx={{ p: 1.5 }}>
          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress size={28} />
            </Box>
          ) : products.length === 0 ? (
            <Typography align="center" color="text.secondary" sx={{ py: 4 }}>
              {t('productsPage.noProductsFound')}
            </Typography>
          ) : (
            products.map((product) => (
              <Paper key={product.id} variant="outlined" sx={{ p: 1.5, borderRadius: 2 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, wordBreak: 'break-word', lineHeight: 1.35, mb: 1 }}>
                  {product.name}
                </Typography>
                <Stack spacing={0.5} sx={{ mb: 1.5 }}>
                  <Typography variant="body2" color="text.secondary">
                    {t('productsPage.sku')}: {product.sku || '—'}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {t('productsPage.barcode')}: {productDisplayBarcode(product) || '—'}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {t('productsPage.category')}: {product.category || '—'}
                  </Typography>
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.75, alignItems: 'center' }}>
                    <Chip
                      size="small"
                      variant="outlined"
                      color={productIsWeight(product) ? 'secondary' : 'primary'}
                      label={productIsWeight(product) ? t('productLines.byWeight') : t('productLines.byQty')}
                    />
                    <Chip
                      label={product.is_active ? t('productsPage.active') : t('productsPage.inactive')}
                      size="small"
                      color={product.is_active ? 'success' : 'default'}
                    />
                  </Box>
                  <Typography variant="body2">
                    <Box component="span" sx={{ color: 'text.secondary' }}>
                      {t('productsPage.priceGbp')}{' '}
                    </Box>
                    £{product.current_cost?.wholesale_cost_gbp?.toFixed(2) || '—'}
                  </Typography>
                </Stack>
                <Button
                  variant="contained"
                  fullWidth
                  size="medium"
                  startIcon={<VisibilityIcon />}
                  onClick={() => navigate(`/products/${product.id}`)}
                  sx={{ mb: 1 }}
                >
                  {t('productsPage.viewProduct')}
                </Button>
                <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, alignItems: 'center' }}>
                  <Tooltip title={t('products.editProduct')}>
                    <IconButton
                      size="small"
                      onClick={() => {
                        setEditingProduct(product);
                        setOpen(true);
                      }}
                    >
                      <EditIcon />
                    </IconButton>
                  </Tooltip>
                  <Tooltip title={t('common.delete')}>
                    <IconButton size="small" onClick={() => handleDelete(product.id)} color="error">
                      <DeleteIcon />
                    </IconButton>
                  </Tooltip>
                </Box>
              </Paper>
            ))
          )}
        </Stack>
      ) : (
        <TableContainer component={Paper}>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>{t('productsPage.name')}</TableCell>
                <TableCell>{t('productsPage.sku')}</TableCell>
                <TableCell>{t('productsPage.barcodes')}</TableCell>
                <TableCell>{t('productsPage.category')}</TableCell>
                <TableCell>{t('productLines.saleType')}</TableCell>
                <TableCell>{t('productsPage.status')}</TableCell>
                <TableCell>{t('productsPage.priceGbp')}</TableCell>
                <TableCell>{t('productsPage.actions')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell colSpan={8} align="center">
                    {t('productsPage.loading')}
                  </TableCell>
                </TableRow>
              ) : products.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={8} align="center">
                    {t('productsPage.noProductsFound')}
                  </TableCell>
                </TableRow>
              ) : (
                products.map((product) => (
                  <TableRow key={product.id}>
                    <TableCell>{product.name}</TableCell>
                    <TableCell>{product.sku || '-'}</TableCell>
                    <TableCell>{productDisplayBarcode(product) || '-'}</TableCell>
                    <TableCell>{product.category || '-'}</TableCell>
                    <TableCell>
                      <Chip
                        size="small"
                        variant="outlined"
                        color={productIsWeight(product) ? 'secondary' : 'primary'}
                        label={productIsWeight(product) ? t('productLines.byWeight') : t('productLines.byQty')}
                      />
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={product.is_active ? t('productsPage.active') : t('productsPage.inactive')}
                        size="small"
                        color={product.is_active ? 'success' : 'default'}
                      />
                    </TableCell>
                    <TableCell>£{product.current_cost?.wholesale_cost_gbp?.toFixed(2) || '-'}</TableCell>
                    <TableCell>
                      <IconButton size="small" onClick={() => navigate(`/products/${product.id}`)}>
                        <VisibilityIcon />
                      </IconButton>
                      <IconButton
                        size="small"
                        onClick={() => {
                          setEditingProduct(product);
                          setOpen(true);
                        }}
                      >
                        <EditIcon />
                      </IconButton>
                      <IconButton size="small" onClick={() => handleDelete(product.id)} color="error">
                        <DeleteIcon />
                      </IconButton>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      <ProductVariantDialog
        open={open}
        onClose={() => {
          setOpen(false);
          setEditingProduct(null);
        }}
        onSave={handleSave}
        product={editingProduct}
        existingCategories={categories}
      />

      <Dialog
        open={importDialogOpen}
        onClose={() => {
          setImportDialogOpen(false);
          setImportFile(null);
        }}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>{t('productsPage.importDialogTitle')}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" sx={{ mb: 2 }}>
            {t('productsPage.importDialogIntro')}
          </Typography>
          <Box sx={{ mb: 2, pl: 2 }}>
            <Typography variant="body2">• {t('productsPage.importHeaderChineseName')}</Typography>
            <Typography variant="body2">• {t('productsPage.importHeaderEnglishName')}</Typography>
            <Typography variant="body2">• {t('productsPage.importHeaderUnit')}</Typography>
            <Typography variant="body2">• {t('productsPage.importHeaderBarcode')}</Typography>
            <Typography variant="body2">• {t('productsPage.importHeaderRetailPrice')}</Typography>
            <Typography variant="body2">• {t('productsPage.importHeaderCategory')}</Typography>
            <Typography variant="body2">• {t('productsPage.importHeaderSector')}</Typography>
          </Box>
          <Button
            variant="outlined"
            component="label"
            sx={{ mt: 1 }}
          >
            {t('productsPage.chooseExcelFile')}
            <input
              type="file"
              accept=".xlsx"
              hidden
              onChange={(e) => {
                const file = e.target.files?.[0] || null;
                setImportFile(file);
              }}
            />
          </Button>
          <Typography variant="body2" sx={{ mt: 1 }}>
            {importFile ? importFile.name : t('productsPage.noFileSelected')}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button
            onClick={() => {
              setImportDialogOpen(false);
              setImportFile(null);
            }}
          >
            {t('common.cancel')}
          </Button>
          <Button
            variant="contained"
            disabled={!importFile}
            onClick={async () => {
              if (!importFile) return;
              try {
                const result = await productsAPI.importExcel(importFile);
                enqueueSnackbar(
                  `Imported: ${result.imported}, Updated: ${result.updated}`,
                  { variant: 'success' }
                );
                if (result.errors && result.errors.length > 0) {
                  console.error('Import errors:', result.errors);
                  enqueueSnackbar(
                    `${result.errors.length} errors occurred. Check console for details.`,
                    { variant: 'warning' }
                  );
                }
                setImportDialogOpen(false);
                setImportFile(null);
                fetchProducts();
              } catch (error: any) {
                enqueueSnackbar(
                  error.response?.data?.error || 'Failed to import products',
                  { variant: 'error' }
                );
              }
            }}
          >
            {t('productsPage.import')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

