import { useMemo, useState } from 'react';
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  List,
  ListItemButton,
  ListItemText,
  TextField,
  Typography,
} from '@mui/material';
import { Search as SearchIcon } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import type { Product } from '../types';
import { normalizeCategory } from '../utils/category';
import {
  displayVariantLabel,
  productDisplayBarcode,
  productLineName,
  stockProductLabel,
  variantSearchHaystack,
} from '../utils/productInventory';
import ProductImageWithPopover from './ProductImageWithPopover';

function productImageUrl(product: Product): string | undefined {
  return product.image_url?.trim() || product.product_line?.image_url?.trim() || undefined;
}

type Props = {
  open: boolean;
  onClose: () => void;
  products: Product[];
  onSelect: (productId: number) => void;
};

export default function ProductSearchDialog({ open, onClose, products, onSelect }: Props) {
  const { t } = useTranslation(['stock', 'productLines', 'common']);
  const [query, setQuery] = useState('');
  const [searched, setSearched] = useState(false);

  const results = useMemo(() => {
    if (!searched || !query.trim()) return [];
    const q = query.trim().toLowerCase();
    return products
      .filter((p) => variantSearchHaystack(p, t).includes(q))
      .sort((a, b) => {
        const lineCmp = productLineName(a).localeCompare(productLineName(b));
        if (lineCmp !== 0) return lineCmp;
        return displayVariantLabel(a).localeCompare(displayVariantLabel(b)) || a.id - b.id;
      });
  }, [products, query, searched, t]);

  const handleSearch = () => {
    setSearched(true);
  };

  const handleClose = () => {
    setQuery('');
    setSearched(false);
    onClose();
  };

  const handlePick = (productId: number) => {
    onSelect(productId);
    setQuery('');
    setSearched(false);
    onClose();
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>{t('stock:searchByTitle')}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start', mt: 0.5, mb: 2 }}>
          <TextField
            label={t('stock:searchModeName', 'Name / category')}
            placeholder={t('stock:variantSearchPlaceholderName', 'Search product name or category')}
            size="small"
            fullWidth
            autoFocus
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setSearched(false);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                handleSearch();
              }
            }}
          />
          <Button
            variant="contained"
            onClick={handleSearch}
            startIcon={<SearchIcon />}
            sx={{ mt: '3px', minWidth: 100, flexShrink: 0 }}
          >
            {t('stock:search', 'Search')}
          </Button>
        </Box>

        {!searched ? (
          <Typography variant="body2" color="text.secondary">
            {t('stock:searchProductsHint', 'Enter a product name or category, then search.')}
          </Typography>
        ) : results.length === 0 ? (
          <Typography variant="body2" color="text.secondary">
            {t('stock:noMatchingVariant', 'No matching variant')}
          </Typography>
        ) : (
          <List dense disablePadding sx={{ maxHeight: 360, overflow: 'auto' }}>
            {results.map((product) => {
              const variantName = displayVariantLabel(product, { t });
              const lineName = productLineName(product);
              const category = normalizeCategory(product.category || product.product_line?.category || '');
              const barcode = productDisplayBarcode(product);
              const secondary = [
                lineName && lineName !== variantName ? lineName : '',
                category,
                barcode ? t('stock:barcodeLabel', { code: barcode }) : '',
              ]
                .filter(Boolean)
                .join(' · ');

              return (
                <ListItemButton key={product.id} onClick={() => handlePick(product.id)} sx={{ gap: 1.5 }}>
                  <ProductImageWithPopover
                    imageUrl={productImageUrl(product)}
                    productName={variantName}
                    size={48}
                  />
                  <ListItemText
                    primary={variantName}
                    secondary={secondary || undefined}
                    primaryTypographyProps={{ fontWeight: 600 }}
                  />
                </ListItemButton>
              );
            })}
          </List>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={handleClose}>{t('common:cancel')}</Button>
      </DialogActions>
    </Dialog>
  );
}
