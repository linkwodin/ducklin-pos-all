import { useEffect, useState } from 'react';
import {
  Alert,
  Autocomplete,
  Box,
  Button,
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
import { categoriesAPI, productLinesAPI, productsAPI } from '../services/api';
import type { Product, ProductLine } from '../types';
import {
  buildProductPayload,
  isSaleTypeSelected,
  lineHasWeightVariant,
  productToFormData,
  resolveLineWithVariants,
  resolveSelectedLine,
  validateProductForm,
  type ProductFormData,
} from '../utils/productForm';

type ProductVariantFormProps = {
  product: Product;
  onSaved: (product: Product) => void;
};

export default function ProductVariantForm({ product, onSaved }: ProductVariantFormProps) {
  const { t } = useTranslation();
  const [productLines, setProductLines] = useState<ProductLine[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [selectedLine, setSelectedLine] = useState<ProductLine | null>(null);
  const [formData, setFormData] = useState<ProductFormData>(() => productToFormData(product));
  const [errorKey, setErrorKey] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    productLinesAPI.list().then(setProductLines).catch(() => {});
    categoriesAPI.list().then(setCategories).catch(() => {});
  }, []);

  useEffect(() => {
    setFormData(productToFormData(product));
    setErrorKey(null);
  }, [product]);

  useEffect(() => {
    if (productLines.length === 0) return;
    setSelectedLine(resolveSelectedLine(product, productLines));
  }, [product, productLines]);

  const handleSave = async () => {
    const validation = validateProductForm(formData, selectedLine);
    if (validation === 'lineNameRequired') {
      setErrorKey(t('productLines.lineNameRequired'));
      return;
    }
    if (validation === 'saleTypeRequired') {
      setErrorKey(t('productLines.selectSaleTypeFirst'));
      return;
    }
    if (validation === 'barcodeRequired') {
      setErrorKey(t('productsPage.barcodeRequired'));
      return;
    }
    const lineForCheck = resolveLineWithVariants(selectedLine, productLines);
    if (formData.unit_type === 'weight' && lineHasWeightVariant(lineForCheck, product.id)) {
      setErrorKey(t('productLines.weightVariantAlreadyExists'));
      return;
    }
    setErrorKey(null);
    setSaving(true);
    try {
      const updated = await productsAPI.update(product.id, buildProductPayload(formData, selectedLine));
      onSaved(updated);
    } catch (e: unknown) {
      const msg = (e as { response?: { data?: { error?: string } } })?.response?.data?.error;
      setErrorKey(msg || t('productDetail.saveFailed', 'Failed to save product'));
    } finally {
      setSaving(false);
    }
  };

  const activeLine = resolveLineWithVariants(selectedLine, productLines);
  const weightVariantTaken = lineHasWeightVariant(activeLine, product.id);
  const saleTypeSelected = isSaleTypeSelected(formData.unit_type);

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
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
      <FormControl>
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
        ) : null}
      </FormControl>

      {saleTypeSelected && (
        <>
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
                    <Typography component="span" sx={{ color: 'text.secondary', whiteSpace: 'nowrap' }}>
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
          {errorKey ? <Alert severity="error">{errorKey}</Alert> : null}
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
            options={categories}
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
        </>
      )}

      <Box sx={{ display: 'flex', justifyContent: 'flex-end', pt: 1 }}>
        <Button variant="contained" onClick={handleSave} disabled={saving || !saleTypeSelected}>
          {saving ? t('productDetail.saving', 'Saving…') : t('productDetail.saveSettings', 'Save settings')}
        </Button>
      </Box>
    </Box>
  );
}
