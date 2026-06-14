import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  FormHelperText,
  Paper,
  TextField,
  Typography,
} from '@mui/material';
import { Search as SearchIcon } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import type { Product } from '../types';
import { normalizeCategory } from '../utils/category';
import { resolveProductScanFromList } from '../utils/productBarcode';
import {
  displayVariantLabel,
  productDisplayBarcode,
  productLineName,
  stockProductLabel,
} from '../utils/productInventory';
import ProductSearchDialog from './ProductSearchDialog';
import ProductImageWithPopover from './ProductImageWithPopover';

function productImageUrl(product: Product): string | undefined {
  return product.image_url?.trim() || product.product_line?.image_url?.trim() || undefined;
}

type Props = {
  products: Product[];
  productId: number | null;
  onProductIdChange: (productId: number | null) => void;
  disabled?: boolean;
  resetKey?: string | number;
  autoFocus?: boolean;
};

function ProductDetailsPanel({
  product,
  t,
  lang,
}: {
  product: Product | null;
  t: (key: string, options?: Record<string, unknown>) => string;
  lang: string;
}) {
  if (!product) {
    return (
      <Typography variant="body2" color="text.secondary">
        {t('stock:noProductSelected')}
      </Typography>
    );
  }

  const lineName = productLineName(product);
  const variantName = displayVariantLabel(product, { t });
  const category = normalizeCategory(product.category || product.product_line?.category || '');
  const barcode = productDisplayBarcode(product);
  const label = stockProductLabel(product, lang, t);

  return (
    <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-start' }}>
      <ProductImageWithPopover imageUrl={productImageUrl(product)} productName={label} size={72} />
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.75, minWidth: 0, flex: 1 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
          {label}
        </Typography>
        {lineName && variantName && lineName !== variantName ? (
          <DetailRow label={t('stock:variantSelect')} value={variantName} />
        ) : null}
        {category ? <DetailRow label={t('stock:category')} value={category} /> : null}
        {barcode ? <DetailRow label={t('stock:barcode')} value={barcode} /> : null}
        {product.sku?.trim() ? <DetailRow label={t('stock:sku')} value={product.sku.trim()} /> : null}
      </Box>
    </Box>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <Typography variant="body2" color="text.secondary">
      <Box component="span" sx={{ fontWeight: 500, color: 'text.primary', mr: 0.75 }}>
        {label}:
      </Box>
      {value}
    </Typography>
  );
}

export default function VariantProductPicker({
  products,
  productId,
  onProductIdChange,
  disabled,
  resetKey,
  autoFocus = false,
}: Props) {
  const { t, i18n } = useTranslation(['stock', 'productLines', 'common']);
  const lang = i18n.language || 'en';
  const [barcodeInput, setBarcodeInput] = useState('');
  const [barcodeError, setBarcodeError] = useState('');
  const [searchOpen, setSearchOpen] = useState(false);

  const pickerDisabled = disabled || products.length === 0;
  const selectedProduct = products.find((p) => p.id === productId) ?? null;

  useEffect(() => {
    setBarcodeInput('');
    setBarcodeError('');
    setSearchOpen(false);
  }, [resetKey]);

  useEffect(() => {
    if (productId == null) {
      setBarcodeInput('');
      return;
    }
    if (!products.some((p) => p.id === productId)) {
      onProductIdChange(null);
      return;
    }
    const product = products.find((p) => p.id === productId);
    if (product) {
      const barcode = productDisplayBarcode(product);
      if (barcode) setBarcodeInput(barcode);
    }
  }, [productId, products, onProductIdChange]);

  const lookupBarcode = () => {
    setBarcodeError('');
    const raw = barcodeInput.trim();
    if (!raw) {
      setBarcodeError(t('stock:enterBarcode'));
      return;
    }
    const hit = resolveProductScanFromList(raw, products);
    if (!hit) {
      onProductIdChange(null);
      setBarcodeError(t('stock:barcodeNotFound'));
      return;
    }
    onProductIdChange(hit.id);
  };

  const handleSearchDialogSelect = (id: number) => {
    setBarcodeError('');
    onProductIdChange(id);
  };

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
        <TextField
          label={t('stock:barcode')}
          placeholder={t('stock:variantSearchPlaceholderBarcode')}
          size="small"
          fullWidth
          disabled={pickerDisabled}
          autoFocus={autoFocus && !pickerDisabled}
          value={barcodeInput}
          onChange={(e) => {
            setBarcodeInput(e.target.value);
            setBarcodeError('');
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              lookupBarcode();
            }
          }}
        />
        <Button
          variant="contained"
          disabled={pickerDisabled}
          onClick={() => setSearchOpen(true)}
          startIcon={<SearchIcon />}
          sx={{ mt: '3px', minWidth: 100, flexShrink: 0 }}
        >
          {t('stock:searchBy')}
        </Button>
      </Box>

      {barcodeError ? <FormHelperText error>{barcodeError}</FormHelperText> : null}

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 1.5 }}>
          {t('stock:productDetails')}
        </Typography>
        <ProductDetailsPanel product={selectedProduct} t={t} lang={lang} />
      </Paper>

      {products.length === 0 && !disabled ? (
        <FormHelperText>{t('stock:noProductsToAdd')}</FormHelperText>
      ) : null}

      <ProductSearchDialog
        open={searchOpen}
        onClose={() => setSearchOpen(false)}
        products={products}
        onSelect={handleSearchDialogSelect}
      />
    </Box>
  );
}
