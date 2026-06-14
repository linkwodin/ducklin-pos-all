import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Box,
  Button,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  IconButton,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Autocomplete,
  CircularProgress,
  Collapse,
  Stack,
  MenuItem,
  InputAdornment,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
  ExpandMore as ExpandMoreIcon,
  ExpandLess as ExpandLessIcon,
  Search as SearchIcon,
} from '@mui/icons-material';
import { productLinesAPI, productsAPI, categoriesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import type { Product, ProductLine } from '../types';
import { displayVariantLabel } from '../utils/productInventory';
import {
  productLineVariantActionsCellSx,
  productLineVariantCellSx,
  productLineVariantTableSx,
  VARIANT_TABLE_COLS_LIST,
} from '../utils/productLineVariantTable';

export default function ProductLinesPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const [lines, setLines] = useState<ProductLine[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState<Record<number, boolean>>({});
  const [lineDialogOpen, setLineDialogOpen] = useState(false);
  const [editingLine, setEditingLine] = useState<ProductLine | null>(null);
  const [lineForm, setLineForm] = useState({ name: '', name_chinese: '', category: '' });
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');

  const categoryOptions = useMemo(() => {
    const fromLines = lines.map((line) => line.category).filter(Boolean) as string[];
    return Array.from(new Set([...categories, ...fromLines])).sort((a, b) => a.localeCompare(b));
  }, [categories, lines]);

  const filteredLines = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return lines.filter((line) => {
      if (categoryFilter && (line.category ?? '') !== categoryFilter) return false;
      if (!q) return true;
      const parts = [
        line.name,
        line.name_chinese,
        line.category,
        ...(line.variants ?? []).flatMap((v) => [
          v.variant_label,
          v.barcode,
          v.weight_barcode,
          v.sku,
        ]),
      ];
      const haystack = parts
        .filter((v) => v != null && String(v).trim() !== '')
        .join(' ')
        .toLowerCase();
      return haystack.includes(q);
    });
  }, [lines, searchQuery, categoryFilter]);

  useEffect(() => {
    fetchLines();
    categoriesAPI.list().then(setCategories).catch(() => {});
  }, []);

  const fetchLines = async () => {
    try {
      setLoading(true);
      const data = await productLinesAPI.list();
      setLines(data);
      setExpanded((prev) => {
        const next = { ...prev };
        for (const line of data) {
          if (next[line.id] === undefined) next[line.id] = true;
        }
        return next;
      });
    } catch {
      enqueueSnackbar(t('productLines.loadFailed'), { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const openLineDialog = (line?: ProductLine) => {
    setEditingLine(line ?? null);
    setLineForm({
      name: line?.name ?? '',
      name_chinese: line?.name_chinese ?? '',
      category: line?.category ?? '',
    });
    setLineDialogOpen(true);
  };

  const saveLine = async () => {
    if (!lineForm.name.trim()) return;
    try {
      if (editingLine) {
        await productLinesAPI.update(editingLine.id, lineForm);
        enqueueSnackbar(t('productLines.updated'), { variant: 'success' });
      } else {
        await productLinesAPI.create(lineForm);
        enqueueSnackbar(t('productLines.created'), { variant: 'success' });
      }
      setLineDialogOpen(false);
      fetchLines();
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('productLines.saveFailed'), { variant: 'error' });
    }
  };

  const deactivateVariant = async (variant: Product) => {
    if (!window.confirm(t('productsPage.confirmDeactivate'))) return;
    try {
      await productsAPI.delete(variant.id);
      enqueueSnackbar(t('productLines.variantDeactivated'), { variant: 'success' });
      fetchLines();
    } catch {
      enqueueSnackbar(t('productLines.deactivateFailed'), { variant: 'error' });
    }
  };

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3, flexWrap: 'wrap', gap: 1.5 }}>
        <Box>
          <Typography variant="h4" sx={{ typography: { xs: 'h5', md: 'h4' } }}>
            {t('productLines.title')}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {t('productLines.subtitle')}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => openLineDialog()}>
          {t('productLines.addLine')}
        </Button>
      </Box>

      <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 2, mb: 2 }}>
        <TextField
          size="small"
          label={t('common.search')}
          placeholder={t('productLines.searchPlaceholder')}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          sx={{ minWidth: { xs: 0, sm: 260 }, flex: { xs: '1 1 100%', sm: '1 1 280px' } }}
          InputProps={{
            startAdornment: (
              <InputAdornment position="start">
                <SearchIcon fontSize="small" color="action" />
              </InputAdornment>
            ),
          }}
        />
        <TextField
          select
          size="small"
          label={t('productsPage.filterByCategory')}
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          sx={{ minWidth: { xs: 0, sm: 200 }, width: { xs: '100%', sm: 'auto' } }}
        >
          <MenuItem value="">{t('productsPage.allCategories')}</MenuItem>
          {categoryOptions.map((cat) => (
            <MenuItem key={cat} value={cat}>
              {cat}
            </MenuItem>
          ))}
        </TextField>
      </Box>

      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      ) : lines.length === 0 ? (
        <Paper sx={{ p: 4, textAlign: 'center' }}>
          <Typography color="text.secondary">{t('productLines.empty')}</Typography>
        </Paper>
      ) : filteredLines.length === 0 ? (
        <Paper sx={{ p: 4, textAlign: 'center' }}>
          <Typography color="text.secondary">{t('productLines.noLinesMatchFilter')}</Typography>
        </Paper>
      ) : (
        <Stack spacing={2}>
          {filteredLines.map((line) => (
            <Paper key={line.id} variant="outlined">
              <Box
                sx={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 1,
                  p: 2,
                  cursor: 'pointer',
                }}
                onClick={() => setExpanded((e) => ({ ...e, [line.id]: !e[line.id] }))}
              >
                <IconButton size="small" aria-label="expand">
                  {expanded[line.id] ? <ExpandLessIcon /> : <ExpandMoreIcon />}
                </IconButton>
                <Box
                  sx={{ flex: 1, minWidth: 0, cursor: 'pointer' }}
                  onClick={(e) => {
                    e.stopPropagation();
                    navigate(`/product-lines/${line.id}`);
                  }}
                >
                  <Typography
                    variant="h6"
                    sx={{ wordBreak: 'break-word', '&:hover': { color: 'primary.main' } }}
                  >
                    {line.name}
                    {line.name_chinese ? ` (${line.name_chinese})` : ''}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {line.category || t('productLines.noCategory')} · {(line.variants?.length ?? 0)}{' '}
                    {t('productLines.variants')}
                  </Typography>
                </Box>
                <Button
                  size="small"
                  variant="outlined"
                  onClick={(e) => {
                    e.stopPropagation();
                    navigate(`/product-lines/${line.id}`);
                  }}
                >
                  {t('productLines.details')}
                </Button>
              </Box>
              <Collapse in={expanded[line.id]}>
                <TableContainer sx={{ width: '100%' }}>
                  <Table size="small" sx={productLineVariantTableSx}>
                    <colgroup>
                      {VARIANT_TABLE_COLS_LIST.map((width, i) => (
                        <col key={i} style={{ width }} />
                      ))}
                    </colgroup>
                    <TableHead>
                      <TableRow>
                        <TableCell sx={productLineVariantCellSx}>{t('productLines.variant')}</TableCell>
                        <TableCell sx={productLineVariantCellSx}>{t('productLines.saleType')}</TableCell>
                        <TableCell sx={productLineVariantCellSx}>{t('productsPage.barcode')}</TableCell>
                        <TableCell sx={productLineVariantCellSx}>{t('productsPage.sku')}</TableCell>
                        <TableCell align="right" sx={productLineVariantActionsCellSx}>
                          {t('productsPage.actions')}
                        </TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {(line.variants ?? []).length === 0 ? (
                        <TableRow>
                          <TableCell colSpan={5} align="center" sx={{ color: 'text.secondary' }}>
                            {t('productLines.noVariants')}
                          </TableCell>
                        </TableRow>
                      ) : (
                        (line.variants ?? []).map((variant) => (
                          <TableRow key={variant.id} hover>
                            <TableCell sx={productLineVariantCellSx}>
                              {displayVariantLabel(variant, {
                                siblingCount: line.variants?.length ?? 1,
                                t,
                              })}
                            </TableCell>
                            <TableCell sx={productLineVariantCellSx}>
                              <Chip
                                size="small"
                                label={
                                  variant.unit_type === 'weight'
                                    ? t('productLines.byWeight')
                                    : t('productLines.byQty')
                                }
                                color={variant.unit_type === 'weight' ? 'secondary' : 'primary'}
                                variant="outlined"
                              />
                            </TableCell>
                            <TableCell sx={productLineVariantCellSx}>
                              {variant.unit_type === 'weight'
                                ? variant.weight_barcode || variant.barcode || '—'
                                : variant.barcode || '—'}
                            </TableCell>
                            <TableCell sx={productLineVariantCellSx}>{variant.sku || '—'}</TableCell>
                            <TableCell align="right" sx={productLineVariantActionsCellSx}>
                              <IconButton size="small" onClick={() => navigate(`/products/${variant.id}`)}>
                                <EditIcon fontSize="small" />
                              </IconButton>
                              <IconButton size="small" color="error" onClick={() => deactivateVariant(variant)}>
                                <DeleteIcon fontSize="small" />
                              </IconButton>
                            </TableCell>
                          </TableRow>
                        ))
                      )}
                    </TableBody>
                  </Table>
                </TableContainer>
              </Collapse>
            </Paper>
          ))}
        </Stack>
      )}

      <Dialog open={lineDialogOpen} onClose={() => setLineDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{editingLine ? t('productLines.editLine') : t('productLines.addLine')}</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField
              label={t('productsPage.name')}
              required
              fullWidth
              value={lineForm.name}
              onChange={(e) => setLineForm({ ...lineForm, name: e.target.value })}
            />
            <TextField
              label={t('products.productNameChinese')}
              fullWidth
              value={lineForm.name_chinese}
              onChange={(e) => setLineForm({ ...lineForm, name_chinese: e.target.value })}
            />
            <Autocomplete
              freeSolo
              options={categories}
              value={lineForm.category}
              onChange={(_, v) => setLineForm({ ...lineForm, category: typeof v === 'string' ? v : v ?? '' })}
              onInputChange={(_, v) => setLineForm({ ...lineForm, category: v })}
              renderInput={(params) => <TextField {...params} label={t('productsPage.category')} />}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setLineDialogOpen(false)}>{t('common.cancel')}</Button>
          <Button variant="contained" onClick={saveLine} disabled={!lineForm.name.trim()}>
            {t('common.save')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
