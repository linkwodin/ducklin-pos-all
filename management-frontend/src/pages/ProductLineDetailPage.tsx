import { useEffect, useState } from 'react';
import { useNavigate, useParams, Link as RouterLink } from 'react-router-dom';
import {
  Box,
  Paper,
  Typography,
  Button,
  Grid,
  TextField,
  Autocomplete,
  Stack,
  CircularProgress,
  Link,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Chip,
  IconButton,
  Tooltip,
  Divider,
  FormControl,
  InputAdornment,
  MenuItem,
  Select,
} from '@mui/material';
import {
  Add as AddIcon,
  Check as CheckIcon,
  Close as CloseIcon,
  Delete as DeleteIcon,
  Edit as EditIcon,
  ChevronRight as ChevronRightIcon,
  Save as SaveIcon,
} from '@mui/icons-material';
import { categoriesAPI, productLinesAPI, productsAPI, storesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { Product, ProductLine, Stock, Store } from '../types';
import {
  buildProductPayload,
  emptyNewVariantDraft,
  isSaleTypeSelected,
  lineHasWeightVariant,
  productToFormData,
  variantRowsFromProducts,
  formatPerWeightVariantLabel,
  sanitizeWeightVariantGramsInput,
  weightVariantGramsFromProduct,
  type NewVariantDraft,
  type VariantRowEdit,
} from '../utils/productForm';
import {
  displayVariantLabel,
  formatVariantStockLevel,
} from '../utils/productInventory';
import {
  productLineVariantActionsCellSx,
  productLineVariantCellSx,
  productLineVariantEditLabelCellSx,
  productLineVariantLabelCellSx,
  productLineVariantTableSx,
  VARIANT_TABLE_COLS_WITH_PRICE,
} from '../utils/productLineVariantTable';
import WholesaleShipFromSelect from '../components/WholesaleShipFromSelect';
import { fetchProductStockAssignments, setProductWholesaleShipStore } from '../utils/wholesaleShipFrom';

function applyLineToEdits(data: ProductLine) {
  return {
    form: {
      name: data.name ?? '',
      name_chinese: data.name_chinese ?? '',
      category: data.category ?? '',
    },
    imagePreview: data.image_url ?? null,
    variantEdits: variantRowsFromProducts(data.variants ?? []),
  };
}

function shipStoreFromAssignments(assignments: Stock[]): number | '' {
  return assignments.find((row) => row.wholesale_ship_from)?.store_id ?? '';
}

export default function ProductLineDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation();
  const { enqueueSnackbar } = useSnackbar();
  const [line, setLine] = useState<ProductLine | null>(null);
  const [categories, setCategories] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({ name: '', name_chinese: '', category: '' });
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [variantEdits, setVariantEdits] = useState<Record<number, VariantRowEdit>>({});
  const [savingVariantId, setSavingVariantId] = useState<number | null>(null);
  const [isEditing, setIsEditing] = useState(false);
  const [newVariantDraft, setNewVariantDraft] = useState<NewVariantDraft | null>(null);
  const [savingNewVariant, setSavingNewVariant] = useState(false);
  const [stores, setStores] = useState<Store[]>([]);
  const [shipAssignmentsByProductId, setShipAssignmentsByProductId] = useState<Record<number, Stock[]>>({});
  const [shipStoreDraftByProductId, setShipStoreDraftByProductId] = useState<Record<number, number | ''>>({});

  const lineId = Number(id);

  useEffect(() => {
    categoriesAPI.list().then(setCategories).catch(() => {});
    storesAPI.list().then(setStores).catch(() => {});
  }, []);

  useEffect(() => {
    if (!id || Number.isNaN(lineId)) {
      setLoading(false);
      return;
    }
    fetchLine();
  }, [id]);

  const fetchLine = async () => {
    try {
      setLoading(true);
      const data = await productLinesAPI.get(lineId);
      setLine(data);
      const edits = applyLineToEdits(data);
      setForm(edits.form);
      setImagePreview(edits.imagePreview);
      setImageFile(null);
      setVariantEdits(edits.variantEdits);
      setIsEditing(false);
      setNewVariantDraft(null);
      const variants = data.variants ?? [];
      if (variants.length === 0) {
        setShipAssignmentsByProductId({});
        setShipStoreDraftByProductId({});
      } else {
        const pairs = await Promise.all(
          variants.map(async (variant) => [variant.id, await fetchProductStockAssignments(variant.id)] as const),
        );
        const byProductId = Object.fromEntries(pairs) as Record<number, Stock[]>;
        setShipAssignmentsByProductId(byProductId);
        setShipStoreDraftByProductId(
          Object.fromEntries(
            pairs.map(([productId, assignments]) => [productId, shipStoreFromAssignments(assignments)]),
          ),
        );
      }
    } catch {
      enqueueSnackbar(t('productLineDetail.loadFailed'), { variant: 'error' });
      setLine(null);
    } finally {
      setLoading(false);
    }
  };

  const validateAndSetImage = (file: File) => {
    const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
    if (!validTypes.includes(file.type)) {
      enqueueSnackbar(t('productLineDetail.invalidImageType'), { variant: 'warning' });
      return false;
    }
    setImageFile(file);
    const reader = new FileReader();
    reader.onloadend = () => setImagePreview(reader.result as string);
    reader.readAsDataURL(file);
    return true;
  };

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) validateAndSetImage(file);
  };

  useEffect(() => {
    if (!isEditing) return;
    const handlePaste = (e: ClipboardEvent) => {
      const items = e.clipboardData?.items;
      if (!items) return;
      for (let i = 0; i < items.length; i++) {
        if (items[i].type.indexOf('image') !== -1) {
          const blob = items[i].getAsFile();
          if (blob) {
            const file = new File([blob], `pasted-image-${Date.now()}.png`, {
              type: blob.type || 'image/png',
            });
            if (validateAndSetImage(file)) e.preventDefault();
            break;
          }
        }
      }
    };
    document.addEventListener('paste', handlePaste);
    return () => document.removeEventListener('paste', handlePaste);
  }, [isEditing]);

  const cancelEdit = () => {
    if (!line) return;
    const edits = applyLineToEdits(line);
    setForm(edits.form);
    setImagePreview(edits.imagePreview);
    setImageFile(null);
    setVariantEdits(edits.variantEdits);
    setIsEditing(false);
    setNewVariantDraft(null);
    setShipStoreDraftByProductId(
      Object.fromEntries(
        Object.entries(shipAssignmentsByProductId).map(([productId, assignments]) => [
          Number(productId),
          shipStoreFromAssignments(assignments),
        ]),
      ),
    );
  };

  const saveVariant = async (variant: Product, edit: VariantRowEdit) => {
    if (!line) return;
    if (!edit.barcode.trim()) {
      enqueueSnackbar(t('productsPage.barcodeRequired'), { variant: 'error' });
      throw new Error('barcode required');
    }
    const formData = {
      ...productToFormData(variant),
      unit_type: edit.unit_type,
      variant_label:
        edit.unit_type === 'weight'
          ? sanitizeWeightVariantGramsInput(edit.variant_label)
          : edit.variant_label,
      barcode: edit.barcode,
      sku: edit.sku,
    };
    if (
      edit.unit_type === 'weight' &&
      lineHasWeightVariant(line, variant.id)
    ) {
      enqueueSnackbar(t('productLines.weightVariantAlreadyExists'), { variant: 'error' });
      throw new Error('weight variant exists');
    }
    await productsAPI.update(variant.id, buildProductPayload(formData, line));

    const prevPrice = variant.current_cost?.direct_retail_online_store_price_gbp ?? 0;
    const newPrice = edit.retail_price.trim() ? parseFloat(edit.retail_price) : NaN;
    if (edit.retail_price.trim() && !Number.isNaN(newPrice) && newPrice !== prevPrice) {
      await productsAPI.updateCostSimple(variant.id, {
        direct_retail_online_store_price_gbp: newPrice,
      });
    }
  };

  const handleSave = async () => {
    if (!line || !form.name.trim()) return;
    try {
      setSaving(true);
      let updated: ProductLine;
      if (imageFile) {
        const formData = new FormData();
        formData.append('name', form.name.trim());
        formData.append('name_chinese', form.name_chinese);
        formData.append('category', form.category);
        formData.append('image', imageFile);
        updated = await productLinesAPI.update(line.id, formData);
      } else {
        updated = await productLinesAPI.update(line.id, {
          name: form.name.trim(),
          name_chinese: form.name_chinese,
          category: form.category,
        });
      }

      const variantsToSave = updated.variants ?? line.variants ?? [];
      for (const variant of variantsToSave) {
        const edit = variantEdits[variant.id];
        if (edit) {
          setSavingVariantId(variant.id);
          await saveVariant(variant, edit);
        }
        const assignments = shipAssignmentsByProductId[variant.id] ?? [];
        const serverStore = shipStoreFromAssignments(assignments);
        const draftStore = shipStoreDraftByProductId[variant.id] ?? serverStore;
        if (draftStore !== serverStore) {
          setSavingVariantId(variant.id);
          await setProductWholesaleShipStore(variant.id, draftStore, assignments);
        }
      }

      enqueueSnackbar(t('productLineDetail.settingsSaved'), { variant: 'success' });
      setIsEditing(false);
      await fetchLine();
    } catch (error: unknown) {
      if ((error as Error).message === 'barcode required') return;
      if ((error as Error).message === 'weight variant exists') return;
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('productLines.saveFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
      setSavingVariantId(null);
    }
  };

  const deactivateLine = async () => {
    if (!line) return;
    if (!window.confirm(t('productLines.confirmDeactivate'))) return;
    try {
      await productLinesAPI.delete(line.id);
      enqueueSnackbar(t('productLines.deactivated'), { variant: 'success' });
      navigate('/product-lines');
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('productLines.deactivateFailed'), { variant: 'error' });
    }
  };

  const deactivateVariant = async (variant: Product) => {
    if (!window.confirm(t('productsPage.confirmDeactivate'))) return;
    try {
      await productsAPI.delete(variant.id);
      enqueueSnackbar(t('productLines.variantDeactivated'), { variant: 'success' });
      fetchLine();
    } catch {
      enqueueSnackbar(t('productLines.deactivateFailed'), { variant: 'error' });
    }
  };

  const saveNewVariant = async () => {
    if (!line || !newVariantDraft) return;
    if (!isSaleTypeSelected(newVariantDraft.unit_type)) {
      enqueueSnackbar(t('productLines.selectSaleTypeFirst'), { variant: 'warning' });
      return;
    }
    if (!newVariantDraft.barcode.trim()) {
      enqueueSnackbar(t('productsPage.barcodeRequired'), { variant: 'error' });
      return;
    }
    if (newVariantDraft.unit_type === 'weight' && lineHasWeightVariant(line)) {
      enqueueSnackbar(t('productLines.weightVariantAlreadyExists'), { variant: 'error' });
      return;
    }
    try {
      setSavingNewVariant(true);
      const created = await productsAPI.create(
        buildProductPayload(
          {
            lineName: line.name,
            name_chinese: line.name_chinese || '',
            barcode: newVariantDraft.barcode,
            sku: newVariantDraft.sku,
            category: line.category || '',
            unit_type: newVariantDraft.unit_type,
            variant_label:
              newVariantDraft.unit_type === 'weight'
                ? sanitizeWeightVariantGramsInput(newVariantDraft.variant_label)
                : newVariantDraft.variant_label,
            units_per_pack: '',
            wholesale_units_per_box: '',
            selling_weight_g: '',
          },
          line,
        ),
      );
      const price = newVariantDraft.retail_price.trim() ? parseFloat(newVariantDraft.retail_price) : NaN;
      if (newVariantDraft.retail_price.trim() && !Number.isNaN(price)) {
        await productsAPI.updateCostSimple(created.id, {
          direct_retail_online_store_price_gbp: price,
        });
      }
      enqueueSnackbar(t('productLines.variantCreated'), { variant: 'success' });
      setNewVariantDraft(null);
      await fetchLine();
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('productLines.variantCreateFailed'), { variant: 'error' });
    } finally {
      setSavingNewVariant(false);
    }
  };

  const updateNewVariantDraft = (patch: Partial<NewVariantDraft>) => {
    setNewVariantDraft((prev) => (prev ? { ...prev, ...patch } : prev));
  };

  const updateVariantEdit = (variantId: number, patch: Partial<VariantRowEdit>) => {
    setVariantEdits((prev) => ({
      ...prev,
      [variantId]: { ...prev[variantId], ...patch },
    }));
  };

  const formatRetailPrice = (variant: Product, edit?: VariantRowEdit) => {
    const raw = edit?.retail_price?.trim()
      ? parseFloat(edit.retail_price)
      : variant.current_cost?.direct_retail_online_store_price_gbp;
    if (raw == null || Number.isNaN(raw)) return '—';
    return `£${raw.toFixed(2)}`;
  };

  const variantBarcode = (variant: Product, edit?: VariantRowEdit) => {
    if (edit?.barcode) return edit.barcode;
    return variant.unit_type === 'weight'
      ? variant.weight_barcode || variant.barcode || '—'
      : variant.barcode || '—';
  };

  if (loading) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!line) {
    return (
      <Box sx={{ p: 3 }}>
        <Typography color="text.secondary">{t('productLineDetail.notFound')}</Typography>
        <Button sx={{ mt: 2 }} onClick={() => navigate('/product-lines')}>
          {t('productLineDetail.backToList')}
        </Button>
      </Box>
    );
  }

  const variants = line.variants ?? [];
  const newWeightTaken = lineHasWeightVariant(line);
  const newSaleTypeSelected = newVariantDraft ? isSaleTypeSelected(newVariantDraft.unit_type) : false;

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2, flexWrap: 'wrap' }}>
        <Link component={RouterLink} to="/" color="primary" underline="none">
          {t('common.home')}
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <Link component={RouterLink} to="/product-lines" color="primary" underline="none">
          {t('productLines.title')}
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <span>{line.name}</span>
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 2, mb: 3 }}>
          <Typography variant="h4" sx={{ typography: { xs: 'h5', md: 'h4' } }}>
            {t('productLineDetail.title')}
          </Typography>
          <Stack direction="row" spacing={1}>
            {isEditing ? (
              <>
                <Button
                  variant="contained"
                  startIcon={<SaveIcon />}
                  onClick={handleSave}
                  disabled={saving || !form.name.trim()}
                >
                  {saving ? t('productLineDetail.saving') : t('productLineDetail.save')}
                </Button>
                <Button variant="outlined" onClick={cancelEdit} disabled={saving}>
                  {t('common.cancel')}
                </Button>
              </>
            ) : (
              <Button variant="contained" startIcon={<EditIcon />} onClick={() => setIsEditing(true)}>
                {t('productLineDetail.edit')}
              </Button>
            )}
            <Button
              variant="outlined"
              color="error"
              startIcon={<DeleteIcon />}
              onClick={deactivateLine}
              disabled={isEditing && saving}
            >
              {t('productLineDetail.deactivate')}
            </Button>
          </Stack>
        </Box>

        <Grid container spacing={3}>
          <Grid item xs={12} md={8}>
            {isEditing ? (
              <Stack spacing={2}>
                <TextField
                  label={t('productsPage.name')}
                  required
                  fullWidth
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                />
                <TextField
                  label={t('products.productNameChinese')}
                  fullWidth
                  value={form.name_chinese}
                  onChange={(e) => setForm({ ...form, name_chinese: e.target.value })}
                />
                <Autocomplete
                  freeSolo
                  options={categories}
                  value={form.category}
                  onChange={(_, v) => setForm({ ...form, category: typeof v === 'string' ? v : v ?? '' })}
                  onInputChange={(_, v) => setForm({ ...form, category: v })}
                  renderInput={(params) => <TextField {...params} label={t('productsPage.category')} />}
                />
                <Box>
                  <input
                    accept="image/*"
                    style={{ display: 'none' }}
                    id="product-line-image-upload"
                    type="file"
                    onChange={handleImageChange}
                  />
                  <label htmlFor="product-line-image-upload">
                    <Button variant="outlined" component="span" size="small">
                      {imageFile ? t('productsPage.changeImage') : t('products.uploadImage')}
                    </Button>
                  </label>
                  <Typography variant="caption" display="block" color="text.secondary" sx={{ mt: 0.5 }}>
                    {t('productLineDetail.imageHint')}
                  </Typography>
                </Box>
              </Stack>
            ) : (
              <Stack spacing={1.5}>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    {t('productsPage.name')}
                  </Typography>
                  <Typography variant="body1">{form.name || '—'}</Typography>
                </Box>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    {t('products.productNameChinese')}
                  </Typography>
                  <Typography variant="body1">{form.name_chinese || '—'}</Typography>
                </Box>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    {t('productsPage.category')}
                  </Typography>
                  <Typography variant="body1">{form.category || t('productLines.noCategory')}</Typography>
                </Box>
              </Stack>
            )}
          </Grid>
          <Grid item xs={12} md={4}>
            {imagePreview ? (
              <Box
                component="img"
                src={imagePreview}
                alt={line.name}
                sx={{ maxWidth: '100%', maxHeight: 320, borderRadius: 2, display: 'block', mx: 'auto' }}
              />
            ) : (
              <Typography variant="body2" color="text.secondary" align="center">
                {t('productDetail.noImage', 'No image')}
              </Typography>
            )}
          </Grid>
        </Grid>
      </Paper>

      <Paper sx={{ p: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 1.5 }}>
          <Typography variant="h6">{t('productLineDetail.variantsSection')}</Typography>
          {isEditing && (
            <Button
              variant="outlined"
              startIcon={<AddIcon />}
              onClick={() => setNewVariantDraft(emptyNewVariantDraft())}
              disabled={newVariantDraft != null || savingNewVariant}
            >
              {t('productLines.addVariant')}
            </Button>
          )}
        </Box>
        <Divider sx={{ mb: 2 }} />
        {isEditing && (
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {t('productLineDetail.variantsEditHint')}
          </Typography>
        )}
        <TableContainer sx={{ width: '100%' }}>
          <Table size="small" sx={productLineVariantTableSx}>
            <colgroup>
              {VARIANT_TABLE_COLS_WITH_PRICE.map((width, i) => (
                <col key={i} style={{ width }} />
              ))}
            </colgroup>
            <TableHead>
              <TableRow>
                <TableCell sx={productLineVariantLabelCellSx}>{t('productLines.variant')}</TableCell>
                <TableCell sx={productLineVariantCellSx}>{t('productLines.saleType')}</TableCell>
                <TableCell sx={productLineVariantCellSx}>{t('productLineDetail.qty')}</TableCell>
                <TableCell sx={productLineVariantCellSx}>{t('productsPage.barcode')}</TableCell>
                <TableCell sx={productLineVariantCellSx}>{t('productsPage.sku')}</TableCell>
                <TableCell sx={productLineVariantCellSx}>{t('productLineDetail.retailPriceGbp')}</TableCell>
                <TableCell sx={productLineVariantCellSx}>{t('productLineDetail.wholesaleShipStore', 'Wholesale ship from')}</TableCell>
                <TableCell align="right" sx={productLineVariantActionsCellSx}>
                  {t('productsPage.actions')}
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {variants.length === 0 && !newVariantDraft && (
                <TableRow>
                  <TableCell colSpan={8} align="center" sx={{ color: 'text.secondary' }}>
                    {t('productLines.noVariants')}
                  </TableCell>
                </TableRow>
              )}
              {variants.map((variant) => {
                  const edit = variantEdits[variant.id] ?? variantRowsFromProducts([variant])[variant.id];
                  const unitType = isEditing ? edit.unit_type : variant.unit_type;
                  const weightTaken = lineHasWeightVariant(line, variant.id);
                  return (
                  <TableRow key={variant.id} hover>
                    <TableCell sx={isEditing ? productLineVariantEditLabelCellSx : productLineVariantLabelCellSx}>
                      {unitType === 'weight' ? (
                        isEditing ? (
                          <TextField
                            size="small"
                            fullWidth
                            value={edit.variant_label}
                            onChange={(e) =>
                              updateVariantEdit(variant.id, {
                                variant_label: sanitizeWeightVariantGramsInput(e.target.value),
                              })
                            }
                            placeholder="1000"
                            inputProps={{ inputMode: 'decimal', min: 0 }}
                            sx={{ '& .MuiInputBase-root': { flexWrap: 'nowrap' } }}
                            InputProps={{
                              startAdornment: (
                                <InputAdornment position="start" sx={{ mr: 0.25, flexShrink: 0 }}>
                                  <Typography
                                    component="span"
                                    sx={{ color: 'text.secondary', fontSize: '0.8125rem', whiteSpace: 'nowrap' }}
                                  >
                                    per
                                  </Typography>
                                </InputAdornment>
                              ),
                              endAdornment: (
                                <InputAdornment position="end" sx={{ ml: 0.25, flexShrink: 0 }}>
                                  <Typography
                                    component="span"
                                    sx={{ color: 'text.secondary', fontSize: '0.8125rem', whiteSpace: 'nowrap' }}
                                  >
                                    g
                                  </Typography>
                                </InputAdornment>
                              ),
                            }}
                          />
                        ) : (
                          formatPerWeightVariantLabel(
                            edit.variant_label || weightVariantGramsFromProduct(variant),
                          ) || t('productLines.looseWeight')
                        )
                      ) : isEditing ? (
                        <TextField
                          size="small"
                          fullWidth
                          value={edit.variant_label}
                          onChange={(e) => updateVariantEdit(variant.id, { variant_label: e.target.value })}
                          placeholder={t('productLines.variantLabelPlaceholder')}
                        />
                      ) : (
                        displayVariantLabel(variant, { siblingCount: variants.length, t })
                      )}
                    </TableCell>
                    <TableCell sx={productLineVariantCellSx}>
                      {isEditing ? (
                        <FormControl size="small" fullWidth>
                          <Select
                            value={edit.unit_type}
                            onChange={(e) => {
                              const next = e.target.value as VariantRowEdit['unit_type'];
                              if (next === 'weight' && weightTaken) return;
                              updateVariantEdit(variant.id, {
                                unit_type: next,
                                ...(next === 'weight'
                                  ? {
                                      variant_label: sanitizeWeightVariantGramsInput(edit.variant_label),
                                    }
                                  : {}),
                              });
                            }}
                          >
                            <MenuItem value="quantity">{t('productLines.byQty')}</MenuItem>
                            <MenuItem value="weight" disabled={weightTaken && edit.unit_type !== 'weight'}>
                              {t('productLines.byWeight')}
                            </MenuItem>
                          </Select>
                        </FormControl>
                      ) : (
                        <Chip
                          size="small"
                          label={variant.unit_type === 'weight' ? t('productLines.byWeight') : t('productLines.byQty')}
                          color={variant.unit_type === 'weight' ? 'secondary' : 'primary'}
                          variant="outlined"
                        />
                      )}
                    </TableCell>
                    <TableCell sx={productLineVariantCellSx}>
                      {formatVariantStockLevel(variant)}
                    </TableCell>
                    <TableCell sx={productLineVariantCellSx}>
                      {isEditing ? (
                        <TextField
                          size="small"
                          fullWidth
                          required
                          value={edit.barcode}
                          onChange={(e) => updateVariantEdit(variant.id, { barcode: e.target.value })}
                        />
                      ) : (
                        variantBarcode(variant, edit)
                      )}
                    </TableCell>
                    <TableCell sx={productLineVariantCellSx}>
                      {isEditing ? (
                        <TextField
                          size="small"
                          fullWidth
                          value={edit.sku}
                          onChange={(e) => updateVariantEdit(variant.id, { sku: e.target.value })}
                        />
                      ) : (
                        edit.sku || variant.sku || '—'
                      )}
                    </TableCell>
                    <TableCell sx={productLineVariantCellSx}>
                      {isEditing ? (
                        <TextField
                          size="small"
                          fullWidth
                          value={edit.retail_price}
                          onChange={(e) => {
                            const val = e.target.value.replace(/[^\d.]/g, '');
                            updateVariantEdit(variant.id, { retail_price: val });
                          }}
                          inputProps={{ inputMode: 'decimal', min: 0, step: 0.01 }}
                          InputProps={{
                            startAdornment: <Typography sx={{ mr: 0.5, color: 'text.secondary' }}>£</Typography>,
                          }}
                        />
                      ) : (
                        formatRetailPrice(variant, edit)
                      )}
                    </TableCell>
                    <TableCell sx={productLineVariantCellSx}>
                      <WholesaleShipFromSelect
                        assignments={shipAssignmentsByProductId[variant.id] ?? []}
                        stores={stores}
                        value={shipStoreDraftByProductId[variant.id] ?? shipStoreFromAssignments(shipAssignmentsByProductId[variant.id] ?? [])}
                        readOnly={!isEditing}
                        onChange={(storeId) =>
                          setShipStoreDraftByProductId((prev) => ({ ...prev, [variant.id]: storeId }))
                        }
                      />
                    </TableCell>
                    <TableCell align="right" sx={productLineVariantActionsCellSx}>
                      {isEditing && savingVariantId === variant.id && (
                        <CircularProgress size={18} sx={{ mr: 1, verticalAlign: 'middle' }} />
                      )}
                      <Tooltip title={t('products.editProduct')}>
                        <IconButton size="small" onClick={() => navigate(`/products/${variant.id}`)}>
                          <EditIcon fontSize="small" />
                        </IconButton>
                      </Tooltip>
                      <Tooltip title={t('common.delete')}>
                        <IconButton
                          size="small"
                          color="error"
                          onClick={() => deactivateVariant(variant)}
                          disabled={isEditing && saving}
                        >
                          <DeleteIcon fontSize="small" />
                        </IconButton>
                      </Tooltip>
                    </TableCell>
                  </TableRow>
                  );
                })}
              {newVariantDraft && isEditing && !newSaleTypeSelected && (
                <TableRow sx={{ bgcolor: 'action.hover' }}>
                  <TableCell colSpan={7} align="center" sx={{ py: 2 }}>
                    <Stack direction="row" spacing={1.5} justifyContent="center" alignItems="center" flexWrap="wrap">
                      <Button
                        variant="contained"
                        size="small"
                        onClick={() =>
                          updateNewVariantDraft({
                            unit_type: 'quantity',
                          })
                        }
                      >
                        {t('productLines.byQty')}
                      </Button>
                      <Tooltip
                        title={newWeightTaken ? t('productLines.weightVariantAlreadyExists') : ''}
                        disableHoverListener={!newWeightTaken}
                      >
                        <span>
                          <Button
                            variant="contained"
                            size="small"
                            color="secondary"
                            disabled={newWeightTaken}
                            onClick={() =>
                              updateNewVariantDraft({
                                unit_type: 'weight',
                                variant_label: sanitizeWeightVariantGramsInput(newVariantDraft.variant_label),
                              })
                            }
                          >
                            {t('productLines.byWeight')}
                          </Button>
                        </span>
                      </Tooltip>
                    </Stack>
                  </TableCell>
                  <TableCell align="right" sx={productLineVariantActionsCellSx}>
                    <Tooltip title={t('common.cancel')}>
                      <IconButton
                        size="small"
                        onClick={() => setNewVariantDraft(null)}
                        disabled={savingNewVariant}
                      >
                        <CloseIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </TableCell>
                </TableRow>
              )}
              {newVariantDraft && isEditing && newSaleTypeSelected && (
                <TableRow sx={{ bgcolor: 'action.hover' }}>
                  <TableCell sx={productLineVariantEditLabelCellSx}>
                    {newVariantDraft.unit_type === 'weight' ? (
                      <TextField
                        size="small"
                        fullWidth
                        value={newVariantDraft.variant_label}
                        onChange={(e) =>
                          updateNewVariantDraft({
                            variant_label: sanitizeWeightVariantGramsInput(e.target.value),
                          })
                        }
                        placeholder="1000"
                        inputProps={{ inputMode: 'decimal', min: 0 }}
                        sx={{ '& .MuiInputBase-root': { flexWrap: 'nowrap' } }}
                        InputProps={{
                          startAdornment: (
                            <InputAdornment position="start" sx={{ mr: 0.25, flexShrink: 0 }}>
                              <Typography
                                component="span"
                                sx={{ color: 'text.secondary', fontSize: '0.8125rem', whiteSpace: 'nowrap' }}
                              >
                                per
                              </Typography>
                            </InputAdornment>
                          ),
                          endAdornment: (
                            <InputAdornment position="end" sx={{ ml: 0.25, flexShrink: 0 }}>
                              <Typography
                                component="span"
                                sx={{ color: 'text.secondary', fontSize: '0.8125rem', whiteSpace: 'nowrap' }}
                              >
                                g
                              </Typography>
                            </InputAdornment>
                          ),
                        }}
                      />
                    ) : (
                      <TextField
                        size="small"
                        fullWidth
                        value={newVariantDraft.variant_label}
                        onChange={(e) => updateNewVariantDraft({ variant_label: e.target.value })}
                        placeholder={t('productLines.variantLabelPlaceholder')}
                      />
                    )}
                  </TableCell>
                  <TableCell sx={productLineVariantCellSx}>
                    <Chip
                      size="small"
                      label={
                        newVariantDraft.unit_type === 'weight'
                          ? t('productLines.byWeight')
                          : t('productLines.byQty')
                      }
                      color={newVariantDraft.unit_type === 'weight' ? 'secondary' : 'primary'}
                      variant="outlined"
                    />
                  </TableCell>
                  <TableCell sx={productLineVariantCellSx}>—</TableCell>
                  <TableCell sx={productLineVariantCellSx}>
                    <TextField
                      size="small"
                      fullWidth
                      required
                      value={newVariantDraft.barcode}
                      onChange={(e) => updateNewVariantDraft({ barcode: e.target.value })}
                    />
                  </TableCell>
                  <TableCell sx={productLineVariantCellSx}>
                    <TextField
                      size="small"
                      fullWidth
                      value={newVariantDraft.sku}
                      onChange={(e) => updateNewVariantDraft({ sku: e.target.value })}
                    />
                  </TableCell>
                  <TableCell sx={productLineVariantCellSx}>
                    <TextField
                      size="small"
                      fullWidth
                      value={newVariantDraft.retail_price}
                      onChange={(e) => {
                        const val = e.target.value.replace(/[^\d.]/g, '');
                        updateNewVariantDraft({ retail_price: val });
                      }}
                      inputProps={{ inputMode: 'decimal', min: 0, step: 0.01 }}
                      InputProps={{
                        startAdornment: <Typography sx={{ mr: 0.5, color: 'text.secondary' }}>£</Typography>,
                      }}
                    />
                  </TableCell>
                  <TableCell sx={productLineVariantCellSx}>—</TableCell>
                  <TableCell align="right" sx={productLineVariantActionsCellSx}>
                    {savingNewVariant && <CircularProgress size={18} sx={{ mr: 1, verticalAlign: 'middle' }} />}
                    <Tooltip title={t('common.save')}>
                      <span>
                        <IconButton
                          size="small"
                          color="primary"
                          onClick={saveNewVariant}
                          disabled={savingNewVariant}
                        >
                          <CheckIcon fontSize="small" />
                        </IconButton>
                      </span>
                    </Tooltip>
                    <Tooltip title={t('common.cancel')}>
                      <IconButton
                        size="small"
                        onClick={() => setNewVariantDraft(null)}
                        disabled={savingNewVariant}
                      >
                        <CloseIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </Box>
  );
}
