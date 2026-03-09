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
  CircularProgress,
  Checkbox,
  Button,
} from '@mui/material';
import { stockAPI, storesAPI, productsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Store, Product } from '../types';
import { useTranslation } from 'react-i18next';
import { productDisplayName } from '../utils/productDisplay';
import ProductImageWithPopover from '../components/ProductImageWithPopover';

// productIdsByStore[storeId] = Set of product IDs assigned to that store (server state)
type ProductIdsByStore = Record<number, Set<number>>;
// pendingChanges: key = `${productId}-${storeId}`, value = desired checked state (true = assign, false = unassign)
type PendingChanges = Record<string, boolean>;

function isInStore(productIdsByStore: ProductIdsByStore, storeId: number, productId: number): boolean {
  return productIdsByStore[storeId]?.has(productId) ?? false;
}

function pendingKey(productId: number, storeId: number): string {
  return `${productId}-${storeId}`;
}

export default function AssignProductToStorePage() {
  const { i18n } = useTranslation();
  const lang = i18n.language || 'en';
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [productIdsByStore, setProductIdsByStore] = useState<ProductIdsByStore>({});
  const [pendingChanges, setPendingChanges] = useState<PendingChanges>({});
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  const displayedChecked = (productId: number, storeId: number) =>
    pendingKey(productId, storeId) in pendingChanges
      ? pendingChanges[pendingKey(productId, storeId)]
      : isInStore(productIdsByStore, storeId, productId);

  const isChanged = (productId: number, storeId: number) => pendingKey(productId, storeId) in pendingChanges;

  useEffect(() => {
    const load = async () => {
      try {
        setLoading(true);
        const [sList, pList] = await Promise.all([storesAPI.list(), productsAPI.list()]);
        setStores(sList);
        setProducts(pList);
        const byStore: ProductIdsByStore = {};
        await Promise.all(
          sList.map(async (s) => {
            const stock = await stockAPI.getStoreStock(s.id);
            byStore[s.id] = new Set(stock.map((x) => x.product_id));
          })
        );
        setProductIdsByStore(byStore);
      } catch {
        enqueueSnackbar('Failed to load stores/products', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [enqueueSnackbar]);

  const toggle = (productId: number, storeId: number) => {
    const key = pendingKey(productId, storeId);
    const currentDisplayed = displayedChecked(productId, storeId);
    const serverState = isInStore(productIdsByStore, storeId, productId);
    const nextChecked = !currentDisplayed;
    setPendingChanges((prev) => {
      const next = { ...prev };
      if (nextChecked === serverState) delete next[key];
      else next[key] = nextChecked;
      return next;
    });
  };

  const pendingCount = Object.keys(pendingChanges).length;

  const handleSubmit = async () => {
    if (pendingCount === 0) return;
    try {
      setSubmitting(true);
      const byStoreAssign: Record<number, number[]> = {};
      const byStoreUnassign: Record<number, number[]> = {};
      for (const [key, checked] of Object.entries(pendingChanges)) {
        const [productIdStr, storeIdStr] = key.split('-');
        const productId = Number(productIdStr);
        const storeId = Number(storeIdStr);
        if (checked) {
          if (!byStoreAssign[storeId]) byStoreAssign[storeId] = [];
          byStoreAssign[storeId].push(productId);
        } else {
          if (!byStoreUnassign[storeId]) byStoreUnassign[storeId] = [];
          byStoreUnassign[storeId].push(productId);
        }
      }
      await Promise.all([
        ...Object.entries(byStoreAssign).map(([storeId, ids]) =>
          stockAPI.assignProductsToStore(Number(storeId), ids)
        ),
        ...Object.entries(byStoreUnassign).map(([storeId, ids]) =>
          stockAPI.unassignProductsFromStore(Number(storeId), ids)
        ),
      ]);
      enqueueSnackbar('Changes saved', { variant: 'success' });
      setPendingChanges({});
      const byStore: ProductIdsByStore = {};
      await Promise.all(
        stores.map(async (s) => {
          const stock = await stockAPI.getStoreStock(s.id);
          byStore[s.id] = new Set(stock.map((x) => x.product_id));
        })
      );
      setProductIdsByStore(byStore);
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to save changes', { variant: 'error' });
    } finally {
      setSubmitting(false);
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
      <Typography variant="h5" sx={{ mb: 3 }}>
        Assign product to store
      </Typography>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Click a product image to enlarge. Check or uncheck stores, then click Submit to save. Changed cells are
        highlighted in yellow.
      </Typography>

      <Box sx={{ mb: 2 }}>
        <Button
          variant="contained"
          onClick={handleSubmit}
          disabled={submitting || pendingCount === 0}
        >
          {submitting ? 'Saving…' : `Submit ${pendingCount} change${pendingCount === 1 ? '' : 's'}`}
        </Button>
      </Box>

      <Paper sx={{ p: 2, mb: 2, overflow: 'auto' }}>
        <TableContainer>
          <Table size="small" stickyHeader>
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 52, minWidth: 52 }} />
                <TableCell sx={{ minWidth: 160 }}>Product</TableCell>
                {stores.map((s) => (
                  <TableCell key={s.id} align="center" sx={{ minWidth: 80 }}>
                    {s.name}
                  </TableCell>
                ))}
              </TableRow>
            </TableHead>
            <TableBody>
              {products.map((p) => (
                <TableRow key={p.id} hover>
                  <TableCell onClick={(e) => e.stopPropagation()} sx={{ width: 52 }}>
                    <ProductImageWithPopover
                      imageUrl={p.image_url}
                      productName={productDisplayName(p, lang)}
                      size={40}
                    />
                  </TableCell>
                  <TableCell>{productDisplayName(p, lang)}</TableCell>
                  {stores.map((store) => {
                    const checked = displayedChecked(p.id, store.id);
                    const changed = isChanged(p.id, store.id);
                    return (
                      <TableCell
                        key={store.id}
                        align="center"
                        onClick={() => toggle(p.id, store.id)}
                        sx={{
                          cursor: 'pointer',
                          bgcolor: changed ? 'warning.light' : undefined,
                          '&:hover': { bgcolor: changed ? 'warning.main' : 'action.hover' },
                        }}
                      >
                        <Checkbox
                          checked={checked}
                          size="small"
                          onClick={(e) => {
                            e.stopPropagation();
                            toggle(p.id, store.id);
                          }}
                        />
                      </TableCell>
                    );
                  })}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </Box>
  );
}
