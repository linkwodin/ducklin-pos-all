import { useEffect, useState } from 'react';
import {
  Alert,
  Autocomplete,
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  FormControl,
  FormControlLabel,
  FormLabel,
  InputAdornment,
  Radio,
  RadioGroup,
  TextField,
  Typography,
} from '@mui/material';
import { useTranslation } from 'react-i18next';
import { productLinesAPI } from '../services/api';
import type { Product, ProductLine } from '../types';
import {
  appendProductFormToFormData,
  buildProductPayload,
  isSaleTypeSelected,
  lineHasWeightVariant,
  productToFormData,
  resolveLineWithVariants,
  resolveSelectedLine,
  validateProductForm,
  type ProductFormData,
} from '../utils/productForm';

type ProductVariantDialogProps = {
  open: boolean;
  onClose: () => void;
  onSave: (data: Partial<Product> | FormData) => void;
  product: Product | null;
  existingCategories: string[];
  initialLineId?: number;
  initialLineName?: string;
  /** When set, adds a variant to this line only (hides line picker). */
  fixedLine?: ProductLine | null;
};

export default function ProductVariantDialog({
  open,
  onClose,
  onSave,
  product,
  existingCategories,
  initialLineId,
  initialLineName,
  fixedLine,
}: ProductVariantDialogProps) {
  const { t } = useTranslation();
  const [productLines, setProductLines] = useState<ProductLine[]>([]);
  const [selectedLine, setSelectedLine] = useState<ProductLine | null>(null);
  const [formData, setFormData] = useState<ProductFormData>({
    lineName: '',
    name_chinese: '',
    barcode: '',
    sku: '',
    category: '',
    unit_type: '' as ProductFormData['unit_type'],
    variant_label: '',
    units_per_pack: '',
    wholesale_units_per_box: '',
    selling_weight_g: '',
  });
  const [saleModeError, setSaleModeError] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);

  const lineLocked = Boolean(fixedLine && !product);

  useEffect(() => {
    if (open && !lineLocked) {
      productLinesAPI.list().then(setProductLines).catch(() => {});
    }
  }, [open, lineLocked]);

  useEffect(() => {
    if (!open || !product) return;
    setSelectedLine(resolveSelectedLine(product, productLines));
  }, [open, product, productLines]);

  useEffect(() => {
    if (!open) return;
    if (product) {
      setFormData(productToFormData(product));
      setImagePreview(product.image_url ?? null);
      setImageFile(null);
      return;
    }

    const line = fixedLine
      ?? (initialLineId && initialLineName
        ? ({ id: initialLineId, name: initialLineName, is_active: true } as ProductLine)
        : null);

    setSelectedLine(line);
    setFormData({
      lineName: line?.name || initialLineName || '',
      name_chinese: line?.name_chinese || '',
      barcode: '',
      sku: '',
      category: line?.category || '',
      unit_type: '' as ProductFormData['unit_type'],
      variant_label: '',
      units_per_pack: '',
      wholesale_units_per_box: '',
      selling_weight_g: '',
    });
    setImagePreview(null);
    setImageFile(null);
    setSaleModeError('');
  }, [product, open, initialLineId, initialLineName, fixedLine]);

  const validateAndSetImage = (file: File) => {
    const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
    if (!validTypes.includes(file.type)) {
      alert('Invalid file type. Please upload a JPEG, PNG, GIF, or WebP image.');
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
    const handlePasteGlobal = (e: ClipboardEvent) => {
      if (!open) return;
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
    if (open) {
      document.addEventListener('paste', handlePasteGlobal);
      return () => document.removeEventListener('paste', handlePasteGlobal);
    }
  }, [open]);

  const handleSubmit = () => {
    const line = lineLocked ? fixedLine! : selectedLine;
    const validation = validateProductForm(formData, line);
    if (validation === 'lineNameRequired') {
      setSaleModeError(t('productLines.lineNameRequired'));
      return;
    }
    if (validation === 'saleTypeRequired') {
      setSaleModeError(t('productLines.selectSaleTypeFirst'));
      return;
    }
    if (validation === 'barcodeRequired') {
      setSaleModeError(t('productsPage.barcodeRequired'));
      return;
    }
    setSaleModeError('');

    const lineForCheck = resolveLineWithVariants(line, productLines);
    if (
      formData.unit_type === 'weight' &&
      lineHasWeightVariant(lineForCheck, product?.id)
    ) {
      setSaleModeError(t('productLines.weightVariantAlreadyExists'));
      return;
    }

    if (imageFile) {
      const formDataToSend = new FormData();
      formDataToSend.append('name_chinese', formData.name_chinese);
      formDataToSend.append('sku', formData.sku);
      formDataToSend.append('category', formData.category);
      appendProductFormToFormData(formDataToSend, formData, line);
      formDataToSend.append('image', imageFile);
      onSave(formDataToSend as Partial<Product> | FormData);
    } else {
      onSave(buildProductPayload(formData, line));
    }
  };

  const dialogTitle = product
    ? t('products.editProduct')
    : lineLocked
      ? t('productLines.addVariant')
      : t('products.addProduct');

  const activeLine = resolveLineWithVariants(
    lineLocked ? fixedLine : selectedLine,
    productLines,
  );
  const weightVariantTaken = lineHasWeightVariant(activeLine, product?.id);
  const saleTypeSelected = isSaleTypeSelected(formData.unit_type);
  const showVariantFields = Boolean(product) || saleTypeSelected;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>{dialogTitle}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          {!lineLocked && (
            <>
              <Typography variant="subtitle2" color="text.secondary">
                {t('productLines.title')}
              </Typography>
              <Autocomplete
                options={productLines}
                getOptionLabel={(o) => o.name}
                value={selectedLine}
                onChange={(_, v) => {
                  setSelectedLine(v);
                  if (v) {
                    setFormData((f) => ({
                      ...f,
                      lineName: v.name,
                      category: v.category || f.category,
                      name_chinese: v.name_chinese || f.name_chinese,
                    }));
                  }
                }}
                renderInput={(params) => (
                  <TextField
                    {...params}
                    label={t('productLines.existingLine')}
                    helperText={t('productLines.existingLineHint')}
                  />
                )}
              />
              {!selectedLine && (
                <TextField
                  label={t('productLines.lineName')}
                  required
                  fullWidth
                  value={formData.lineName}
                  onChange={(e) => setFormData({ ...formData, lineName: e.target.value })}
                  helperText={t('productLines.lineNameHint')}
                />
              )}
              <Divider />
            </>
          )}
          {lineLocked && fixedLine && (
            <Box>
              <Typography variant="subtitle2" color="text.secondary">
                {t('productLines.title')}
              </Typography>
              <Typography variant="body1" sx={{ mt: 0.5 }}>
                {fixedLine.name}
                {fixedLine.name_chinese ? ` (${fixedLine.name_chinese})` : ''}
              </Typography>
              <Divider sx={{ mt: 2 }} />
            </Box>
          )}

          <FormControl required={!product}>
            <FormLabel>{t('productLines.saleType')}</FormLabel>
            <RadioGroup
              row
              value={formData.unit_type}
              onChange={(e) => {
                const unit_type = e.target.value as 'quantity' | 'weight';
                if (unit_type === 'weight' && weightVariantTaken) return;
                setFormData({
                  ...formData,
                  unit_type,
                  ...(unit_type === 'weight'
                    ? {
                        units_per_pack: '',
                        wholesale_units_per_box: '',
                        variant_label: formData.variant_label.replace(/[^\d.]/g, ''),
                      }
                    : { selling_weight_g: '' }),
                });
                setSaleModeError('');
              }}
            >
              <FormControlLabel value="quantity" control={<Radio />} label={t('productLines.byQty')} />
              <FormControlLabel
                value="weight"
                control={<Radio />}
                label={t('productLines.byWeight')}
                disabled={weightVariantTaken && formData.unit_type !== 'weight'}
              />
            </RadioGroup>
            {weightVariantTaken && formData.unit_type !== 'weight' ? (
              <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                {t('productLines.weightVariantAlreadyExists')}
              </Typography>
            ) : !showVariantFields ? (
              <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                {t('productLines.selectSaleTypeFirst')}
              </Typography>
            ) : null}
          </FormControl>

          {showVariantFields && (
            <>
              <Divider />
              <Typography variant="subtitle2" color="text.secondary">
                {t('productsPage.sectionVariant')}
              </Typography>
              {formData.unit_type === 'quantity' ? (
                <TextField
                  label={t('productLines.variantLabel')}
                  fullWidth
                  value={formData.variant_label}
                  onChange={(e) => setFormData({ ...formData, variant_label: e.target.value })}
                  placeholder={t('productLines.variantLabelPlaceholder')}
                  helperText={t('productLines.variantLabelHint')}
                />
              ) : (
                <TextField
                  label={t('productLines.weightVariantLabel')}
                  fullWidth
                  value={formData.variant_label}
                  onChange={(e) =>
                    setFormData({
                      ...formData,
                      variant_label: e.target.value.replace(/[^\d.]/g, ''),
                    })
                  }
                  placeholder="1000"
                  helperText={t('productLines.weightVariantHint')}
                  inputProps={{ inputMode: 'decimal', min: 0 }}
                  sx={{ '& .MuiInputBase-root': { flexWrap: 'nowrap' } }}
                  InputProps={{
                    startAdornment: (
                      <InputAdornment position="start" sx={{ mr: 0.25, flexShrink: 0 }}>
                        <Typography
                          component="span"
                          sx={{ color: 'text.secondary', whiteSpace: 'nowrap' }}
                        >
                          per
                        </Typography>
                      </InputAdornment>
                    ),
                    endAdornment: (
                      <InputAdornment position="end" sx={{ ml: 0.25, flexShrink: 0 }}>
                        <Typography component="span" sx={{ color: 'text.secondary', whiteSpace: 'nowrap' }}>
                          g
                        </Typography>
                      </InputAdornment>
                    ),
                  }}
                />
              )}
              {formData.unit_type === 'quantity' && (
                <>
                  <TextField
                    label={t('productLines.unitsPerPack')}
                    fullWidth
                    value={formData.units_per_pack}
                    onChange={(e) => {
                      const val = e.target.value.replace(/[^\d.]/g, '');
                      setFormData({ ...formData, units_per_pack: val });
                    }}
                    helperText={t('productLines.unitsPerPackHint')}
                    inputProps={{ inputMode: 'decimal', min: 0 }}
                  />
                  <TextField
                    label={t('productDetail.wholesaleUnitsPerBox')}
                    fullWidth
                    value={formData.wholesale_units_per_box}
                    onChange={(e) => {
                      const val = e.target.value.replace(/[^\d.]/g, '');
                      setFormData({ ...formData, wholesale_units_per_box: val });
                    }}
                    helperText={t('productDetail.wholesaleUnitsPerBoxHelper')}
                    inputProps={{ inputMode: 'decimal', min: 0 }}
                  />
                </>
              )}

              <Divider />
              <Typography variant="subtitle2" color="text.secondary">
                {t('productsPage.barcode')}
              </Typography>
              {saleModeError ? <Alert severity="error">{saleModeError}</Alert> : null}
              <TextField
                label={t('productsPage.barcode')}
                fullWidth
                required
                value={formData.barcode}
                onChange={(e) => setFormData({ ...formData, barcode: e.target.value })}
                helperText={t('productsPage.barcodeHint')}
              />
              <Divider />
              <Typography variant="subtitle2" color="text.secondary">
                {t('productsPage.sectionDetails')}
              </Typography>
              <TextField
                label={t('products.productNameChinese')}
                fullWidth
                value={formData.name_chinese}
                onChange={(e) => setFormData({ ...formData, name_chinese: e.target.value })}
              />
              <TextField
                label={t('productsPage.sku')}
                fullWidth
                value={formData.sku}
                onChange={(e) => setFormData({ ...formData, sku: e.target.value })}
              />
              <Autocomplete
                freeSolo
                options={existingCategories}
                value={formData.category || null}
                onChange={(_, newValue) => {
                  const categoryValue = typeof newValue === 'string' ? newValue : newValue || '';
                  setFormData({ ...formData, category: categoryValue });
                }}
                onInputChange={(_, newInputValue) => {
                  setFormData({ ...formData, category: newInputValue });
                }}
                renderInput={(params) => (
                  <TextField
                    {...params}
                    label={t('productsPage.category')}
                    placeholder={t('productsPage.categoryPlaceholder')}
                  />
                )}
              />
              <Box>
                <Typography variant="body2" sx={{ mb: 1 }}>
                  {t('productsPage.productImage')}
                </Typography>
                <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
                  {t('productsPage.uploadOrPaste')}
                </Typography>
                <input
                  accept="image/*"
                  style={{ display: 'none' }}
                  id="product-variant-dialog-image"
                  type="file"
                  onChange={handleImageChange}
                />
                <label htmlFor="product-variant-dialog-image">
                  <Button variant="outlined" component="span" fullWidth sx={{ mb: 1 }}>
                    {imageFile ? t('productsPage.changeImage') : t('products.uploadImage')}
                  </Button>
                </label>
                {imagePreview && (
                  <Box
                    component="img"
                    src={imagePreview}
                    alt="Preview"
                    sx={{
                      width: '100%',
                      maxHeight: 200,
                      objectFit: 'contain',
                      borderRadius: 1,
                      mb: 1,
                      border: '1px solid #e0e0e0',
                    }}
                  />
                )}
              </Box>
            </>
          )}
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('common.cancel')}</Button>
        <Button
          onClick={handleSubmit}
          variant="contained"
          disabled={!product && !saleTypeSelected}
        >
          {t('common.save')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
