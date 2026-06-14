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
  Tooltip,
} from '@mui/material';
import { LocalShipping as LocalShippingIcon } from '@mui/icons-material';
import { useTheme, alpha } from '@mui/material/styles';
import { stockAPI, storesAPI, productsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Store, Product, Stock } from '../types';
import { useTranslation } from 'react-i18next';
import { productDisplayName } from '../utils/productDisplay';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import { productSupportsDualInventory, assignmentFlagsForVariant } from '../utils/productInventory';

type AssignmentState = {
  track_prepacked: boolean;
  track_weight: boolean;
  wholesale_ship_from: boolean;
};

type AssignmentByStore = Record<number, Record<number, AssignmentState>>;

type PendingChanges = Record<string, AssignmentState>;

function pendingKey(productId: number, storeId: number): string {
  return `${productId}-${storeId}`;
}

function serverAssignment(
  assignmentByStore: AssignmentByStore,
  productId: number,
  storeId: number,
): AssignmentState {
  return assignmentByStore[storeId]?.[productId] ?? {
    track_prepacked: false,
    track_weight: false,
    wholesale_ship_from: false,
  };
}

function displayedAssignment(
  assignmentByStore: AssignmentByStore,
  pendingChanges: PendingChanges,
  productId: number,
  storeId: number,
): AssignmentState {
  const key = pendingKey(productId, storeId);
  if (key in pendingChanges) return pendingChanges[key];
  return serverAssignment(assignmentByStore, productId, storeId);
}

function assignmentMatchesServer(server: AssignmentState, next: AssignmentState): boolean {
  return (
    next.track_prepacked === server.track_prepacked &&
    next.track_weight === server.track_weight &&
    next.wholesale_ship_from === server.wholesale_ship_from
  );
}

function isChanged(pendingChanges: PendingChanges, productId: number, storeId: number): boolean {
  return pendingKey(productId, storeId) in pendingChanges;
}

function isAssigned(state: AssignmentState): boolean {
  return state.track_prepacked || state.track_weight;
}

function stockToAssignment(stock: Stock, product: Product): AssignmentState {
  return {
    ...assignmentFlagsForVariant(product),
    wholesale_ship_from: !!stock.wholesale_ship_from,
  };
}

export default function AssignProductToStorePage() {
  const { t, i18n } = useTranslation(['assignProductToStore', 'common']);
  const theme = useTheme();
  const lang = i18n.language || 'en';
  const prepackHeaderBg = alpha(theme.palette.primary.main, 0.14);
  const weightHeaderBg = alpha(theme.palette.warning.main, 0.22);
  const shipHeaderBg = alpha(theme.palette.success.main, 0.16);
  const prepackCheckboxSx = {
    color: theme.palette.primary.main,
    '&.Mui-checked': { color: theme.palette.primary.main },
  };
  const weightCheckboxSx = {
    color: theme.palette.warning.dark,
    '&.Mui-checked': { color: theme.palette.warning.dark },
  };
  const shipCheckboxSx = {
    color: theme.palette.success.dark,
    '&.Mui-checked': { color: theme.palette.success.dark },
  };
  const changedCellBg = '#fff9c4';
  const changedCellHoverBg = '#fff59d';
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [assignmentByStore, setAssignmentByStore] = useState<AssignmentByStore>({});
  const [pendingChanges, setPendingChanges] = useState<PendingChanges>({});
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  const loadAssignments = async (storeList: Store[], productList: Product[]) => {
    const byStore: AssignmentByStore = {};
    await Promise.all(
      storeList.map(async (s) => {
        const stock = await stockAPI.getStoreStock(s.id);
        const byProduct: Record<number, AssignmentState> = {};
        for (const row of stock) {
          const product = productList.find((p) => p.id === row.product_id) ?? row.product;
          if (!product) continue;
          byProduct[row.product_id] = stockToAssignment(row, product);
        }
        byStore[s.id] = byProduct;
      }),
    );
    setAssignmentByStore(byStore);
  };

  useEffect(() => {
    const load = async () => {
      try {
        setLoading(true);
        const [sList, pList] = await Promise.all([storesAPI.list(), productsAPI.list()]);
        setStores(sList);
        setProducts(pList);
        await loadAssignments(sList, pList);
      } catch {
        enqueueSnackbar('Failed to load stores/products', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [enqueueSnackbar]);

  const setPendingForCell = (productId: number, storeId: number, next: AssignmentState) => {
    const key = pendingKey(productId, storeId);
    const server = serverAssignment(assignmentByStore, productId, storeId);
    setPendingChanges((prev) => {
      const updated = { ...prev };
      if (assignmentMatchesServer(server, next)) {
        delete updated[key];
      } else {
        updated[key] = next;
      }
      return updated;
    });
  };

  const toggleSimple = (productId: number, storeId: number) => {
    const product = products.find((p) => p.id === productId);
    const current = displayedAssignment(assignmentByStore, pendingChanges, productId, storeId);
    if (isAssigned(current)) {
      setPendingForCell(productId, storeId, {
        track_prepacked: false,
        track_weight: false,
        wholesale_ship_from: false,
      });
      return;
    }
    setPendingForCell(productId, storeId, {
      ...assignmentFlagsForVariant(product),
      wholesale_ship_from: false,
    });
  };

  const toggleDual = (
    productId: number,
    storeId: number,
    field: 'track_prepacked' | 'track_weight',
  ) => {
    const current = displayedAssignment(assignmentByStore, pendingChanges, productId, storeId);
    const next = {
      ...current,
      [field]: !current[field],
    };
    if (!next.track_prepacked && !next.track_weight) {
      next.wholesale_ship_from = false;
    }
    setPendingForCell(productId, storeId, next);
  };

  const toggleShipFrom = (productId: number, storeId: number) => {
    const current = displayedAssignment(assignmentByStore, pendingChanges, productId, storeId);
    if (!isAssigned(current)) {
      enqueueSnackbar(t('assignProductToStore:shipFromRequiresAssignment'), { variant: 'warning' });
      return;
    }
    const enabling = !current.wholesale_ship_from;
    setPendingChanges((prev) => {
      const updated = { ...prev };
      for (const store of stores) {
        const key = pendingKey(productId, store.id);
        const base = key in updated
          ? updated[key]
          : serverAssignment(assignmentByStore, productId, store.id);
        const next = {
          ...base,
          wholesale_ship_from: enabling && store.id === storeId,
        };
        const server = serverAssignment(assignmentByStore, productId, store.id);
        if (assignmentMatchesServer(server, next)) {
          delete updated[key];
        } else {
          updated[key] = next;
        }
      }
      return updated;
    });
  };

  const renderShipCell = (productId: number, storeId: number, cellSx: object) => {
    const state = displayedAssignment(assignmentByStore, pendingChanges, productId, storeId);
    return (
      <TableCell key={`${storeId}-ship`} align="center" sx={cellSx}>
        <Tooltip title={t('assignProductToStore:shipFrom')}>
          <span>
            <Checkbox
              checked={state.wholesale_ship_from}
              size="small"
              disabled={!isAssigned(state)}
              sx={shipCheckboxSx}
              icon={<LocalShippingIcon fontSize="small" />}
              checkedIcon={<LocalShippingIcon fontSize="small" />}
              onChange={() => toggleShipFrom(productId, storeId)}
            />
          </span>
        </Tooltip>
      </TableCell>
    );
  };

  const pendingCount = Object.keys(pendingChanges).length;

  const handleSubmit = async () => {
    if (pendingCount === 0) return;
    try {
      setSubmitting(true);
      const byStore: Record<
        number,
        { product_id: number; track_prepacked: boolean; track_weight: boolean; wholesale_ship_from: boolean }[]
      > = {};
      for (const [key, state] of Object.entries(pendingChanges)) {
        const [productIdStr, storeIdStr] = key.split('-');
        const storeId = Number(storeIdStr);
        if (!byStore[storeId]) byStore[storeId] = [];
        byStore[storeId].push({
          product_id: Number(productIdStr),
          track_prepacked: state.track_prepacked,
          track_weight: state.track_weight,
          wholesale_ship_from: state.wholesale_ship_from,
        });
      }
      await Promise.all(
        Object.entries(byStore).map(([storeId, assignments]) =>
          stockAPI.setAssignments(Number(storeId), assignments),
        ),
      );
      enqueueSnackbar(t('assignProductToStore:saved'), { variant: 'success' });
      setPendingChanges({});
      await loadAssignments(stores, products);
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('assignProductToStore:saveFailed'), { variant: 'error' });
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

  const hasDualProducts = products.some((p) => productSupportsDualInventory(p));

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h5" sx={{ mb: 3 }}>
        {t('assignProductToStore:title')}
      </Typography>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {t('assignProductToStore:subtitle')}
      </Typography>

      <Box sx={{ mb: 2 }}>
        <Button
          variant="contained"
          onClick={handleSubmit}
          disabled={submitting || pendingCount === 0}
        >
          {submitting ? t('assignProductToStore:saving') : t('assignProductToStore:submitChanges', { count: pendingCount })}
        </Button>
      </Box>

      <Paper sx={{ p: 2, mb: 2, overflow: 'auto' }}>
        <TableContainer>
          <Table size="small" stickyHeader>
            <TableHead>
              {hasDualProducts ? (
                <>
                  <TableRow>
                    <TableCell
                      rowSpan={2}
                      sx={{ width: 52, minWidth: 52, verticalAlign: 'bottom', bgcolor: 'background.paper' }}
                    />
                    <TableCell
                      rowSpan={2}
                      sx={{ minWidth: 160, verticalAlign: 'bottom', bgcolor: 'background.paper' }}
                    >
                      {t('assignProductToStore:product')}
                    </TableCell>
                    {stores.map((s) => (
                      <TableCell
                        key={s.id}
                        align="center"
                        colSpan={3}
                        sx={{
                          minWidth: 140,
                          borderBottom: 'none',
                          bgcolor: 'grey.100',
                        }}
                      >
                        <Typography variant="body2" fontWeight={600}>
                          {s.name}
                        </Typography>
                      </TableCell>
                    ))}
                  </TableRow>
                  <TableRow>
                    {stores.flatMap((s) => [
                      <TableCell
                        key={`${s.id}-pre`}
                        align="center"
                        sx={{
                          minWidth: 56,
                          py: 0.75,
                          bgcolor: prepackHeaderBg,
                          borderTop: `2px solid ${theme.palette.primary.main}`,
                          fontWeight: 600,
                          fontSize: '0.75rem',
                          color: 'primary.dark',
                        }}
                      >
                        {t('assignProductToStore:prepackedShort')}
                      </TableCell>,
                      <TableCell
                        key={`${s.id}-wt`}
                        align="center"
                        sx={{
                          minWidth: 56,
                          py: 0.75,
                          bgcolor: weightHeaderBg,
                          borderTop: `2px solid ${theme.palette.warning.dark}`,
                          fontWeight: 600,
                          fontSize: '0.75rem',
                          color: 'warning.dark',
                        }}
                      >
                        {t('assignProductToStore:weightShort')}
                      </TableCell>,
                      <TableCell
                        key={`${s.id}-ship`}
                        align="center"
                        sx={{
                          minWidth: 56,
                          py: 0.75,
                          bgcolor: shipHeaderBg,
                          borderTop: `2px solid ${theme.palette.success.dark}`,
                          fontWeight: 600,
                          fontSize: '0.75rem',
                          color: 'success.dark',
                        }}
                      >
                        {t('assignProductToStore:shipFromShort')}
                      </TableCell>,
                    ])}
                  </TableRow>
                </>
              ) : (
                <>
                  <TableRow>
                    <TableCell sx={{ width: 52, minWidth: 52 }} rowSpan={2} />
                    <TableCell sx={{ minWidth: 160 }} rowSpan={2}>
                      {t('assignProductToStore:product')}
                    </TableCell>
                    {stores.map((s) => (
                      <TableCell key={s.id} align="center" colSpan={2} sx={{ bgcolor: 'grey.100' }}>
                        <Typography variant="body2" fontWeight={600}>
                          {s.name}
                        </Typography>
                      </TableCell>
                    ))}
                  </TableRow>
                  <TableRow>
                    {stores.flatMap((s) => [
                      <TableCell key={`${s.id}-inv`} align="center" sx={{ fontSize: '0.75rem', fontWeight: 600 }}>
                        {t('assignProductToStore:assignedShort')}
                      </TableCell>,
                      <TableCell
                        key={`${s.id}-ship-h`}
                        align="center"
                        sx={{ fontSize: '0.75rem', fontWeight: 600, color: 'success.dark', bgcolor: shipHeaderBg }}
                      >
                        {t('assignProductToStore:shipFromShort')}
                      </TableCell>,
                    ])}
                  </TableRow>
                </>
              )}
            </TableHead>
            <TableBody>
              {products.map((p) => {
                const dual = productSupportsDualInventory(p);
                return (
                  <TableRow key={p.id} hover>
                    <TableCell onClick={(e) => e.stopPropagation()} sx={{ width: 52 }}>
                      <ProductImageWithPopover
                        imageUrl={p.image_url}
                        productName={productDisplayName(p, lang)}
                        size={40}
                      />
                    </TableCell>
                    <TableCell>{productDisplayName(p, lang)}</TableCell>
                    {stores.flatMap((store) => {
                      const state = displayedAssignment(assignmentByStore, pendingChanges, p.id, store.id);
                      const changed = isChanged(pendingChanges, p.id, store.id);
                      const cellSx = {
                        bgcolor: changed ? changedCellBg : undefined,
                        verticalAlign: 'middle' as const,
                      };
                      if (hasDualProducts && dual) {
                        return [
                          <TableCell
                            key={`${store.id}-pre`}
                            align="center"
                            sx={cellSx}
                          >
                            <Tooltip title={t('assignProductToStore:prepacked')}>
                              <Checkbox
                                checked={state.track_prepacked}
                                size="small"
                                sx={prepackCheckboxSx}
                                onChange={() => toggleDual(p.id, store.id, 'track_prepacked')}
                              />
                            </Tooltip>
                          </TableCell>,
                          <TableCell
                            key={`${store.id}-wt`}
                            align="center"
                            sx={cellSx}
                          >
                            <Tooltip title={t('assignProductToStore:weight')}>
                              <Checkbox
                                checked={state.track_weight}
                                size="small"
                                sx={weightCheckboxSx}
                                onChange={() => toggleDual(p.id, store.id, 'track_weight')}
                              />
                            </Tooltip>
                          </TableCell>,
                          renderShipCell(p.id, store.id, cellSx),
                        ];
                      }
                      if (hasDualProducts && !dual) {
                        return [
                          <TableCell
                            key={`${store.id}-pre`}
                            align="center"
                            onClick={() => toggleSimple(p.id, store.id)}
                            sx={{
                              ...cellSx,
                              cursor: 'pointer',
                              '&:hover': { bgcolor: changed ? changedCellHoverBg : 'action.hover' },
                            }}
                          >
                            <Checkbox
                              checked={state.track_prepacked}
                              size="small"
                              sx={prepackCheckboxSx}
                              onClick={(e) => {
                                e.stopPropagation();
                                toggleSimple(p.id, store.id);
                              }}
                            />
                          </TableCell>,
                          <TableCell key={`${store.id}-wt`} align="center" sx={{ verticalAlign: 'middle' }} />,
                          renderShipCell(p.id, store.id, cellSx),
                        ];
                      }
                      return [
                        <TableCell
                          key={`${store.id}-inv`}
                          align="center"
                          onClick={() => toggleSimple(p.id, store.id)}
                          sx={{ ...cellSx, cursor: 'pointer', '&:hover': { bgcolor: changed ? changedCellHoverBg : 'action.hover' } }}
                        >
                          <Checkbox
                            checked={state.track_prepacked}
                            size="small"
                            onClick={(e) => {
                              e.stopPropagation();
                              toggleSimple(p.id, store.id);
                            }}
                          />
                        </TableCell>,
                        renderShipCell(p.id, store.id, cellSx),
                      ];
                    })}
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </Box>
  );
}
