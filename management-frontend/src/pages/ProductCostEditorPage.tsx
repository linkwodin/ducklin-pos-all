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
  TextField,
  Button,
  IconButton,
  Tooltip,
  MenuItem,
  Select,
  FormControl,
  InputLabel,
  Chip,
  Alert,
} from '@mui/material';
import {
  Save as SaveIcon,
  Refresh as RefreshIcon,
  CheckCircle as CheckCircleIcon,
} from '@mui/icons-material';
import { productsAPI, sectorsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Product, ProductCost, Sector } from '../types';
import { useTranslation } from 'react-i18next';

interface EditableProductRow {
  id: number;
  productName: string;
  productNameChinese: string;
  barcode: string;
  currentCost?: ProductCost;
  editedCost?: number; // WholesaleCostGBP
  editedPrice?: number; // DirectRetailOnlineStorePriceGBP
  discounts: Map<number, number>; // sector_id -> discount_percent
  originalDiscounts: Map<number, number>; // sector_id -> discount_percent (original values)
  hasChanges: boolean;
}

export default function ProductCostEditorPage() {
  const { t } = useTranslation();
  const [products, setProducts] = useState<Product[]>([]);
  const [sectors, setSectors] = useState<Sector[]>([]);
  const [rows, setRows] = useState<EditableProductRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState<string>('');
  const [categories, setCategories] = useState<string[]>([]);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchData();
  }, [selectedCategory]);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [productsData, sectorsData] = await Promise.all([
        productsAPI.list(selectedCategory || undefined),
        sectorsAPI.list(),
      ]);

      // Get categories from products
      const uniqueCategories = Array.from(new Set(productsData.map(p => p.category).filter(Boolean))) as string[];
      setCategories(uniqueCategories);

      setProducts(productsData);
      setSectors(sectorsData);

      // Initialize rows with current data
      const initialRows: EditableProductRow[] = productsData.map(product => {
        const cost = product.current_cost;
        const discounts = new Map<number, number>();
        const originalDiscounts = new Map<number, number>();
        
        // Load existing discounts
        if (product.discounts) {
          product.discounts.forEach(d => {
            discounts.set(d.sector_id, d.discount_percent);
            originalDiscounts.set(d.sector_id, d.discount_percent);
          });
        }

        return {
          id: product.id,
          productName: product.name,
          productNameChinese: product.name_chinese || '',
          barcode: product.barcode || '',
          currentCost: cost,
          editedCost: cost?.wholesale_cost_gbp,
          editedPrice: cost?.direct_retail_online_store_price_gbp,
          discounts,
          originalDiscounts,
          hasChanges: false,
        };
      });

      setRows(initialRows);
    } catch (error) {
      enqueueSnackbar(t('costEditor.failedToLoad'), { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleCostChange = (productId: number, value: string) => {
    setRows(prevRows =>
      prevRows.map(row => {
        if (row.id === productId) {
          const numValue = parseFloat(value) || 0;
          return {
            ...row,
            editedCost: numValue,
            hasChanges: numValue !== (row.currentCost?.wholesale_cost_gbp || 0),
          };
        }
        return row;
      })
    );
  };

  const handlePriceChange = (productId: number, value: string) => {
    setRows(prevRows =>
      prevRows.map(row => {
        if (row.id === productId) {
          const numValue = parseFloat(value) || 0;
          return {
            ...row,
            editedPrice: numValue,
            hasChanges: numValue !== (row.currentCost?.direct_retail_online_store_price_gbp || 0),
          };
        }
        return row;
      })
    );
  };

  const handleDiscountChange = (productId: number, sectorId: number, value: string) => {
    setRows(prevRows =>
      prevRows.map(row => {
        if (row.id === productId) {
          const numValue = parseFloat(value) || 0;
          const newDiscounts = new Map(row.discounts);
          newDiscounts.set(sectorId, numValue);
          
          const oldDiscount = row.originalDiscounts.get(sectorId) || 0;
          const costChanged = row.editedCost !== undefined && row.editedCost !== (row.currentCost?.wholesale_cost_gbp || 0);
          const priceChanged = row.editedPrice !== undefined && row.editedPrice !== (row.currentCost?.direct_retail_online_store_price_gbp || 0);
          const discountChanged = numValue !== oldDiscount;
          
          // Check if any discount changed
          let anyDiscountChanged = discountChanged;
          if (!anyDiscountChanged) {
            for (const [sid, disc] of newDiscounts.entries()) {
              if ((row.originalDiscounts.get(sid) || 0) !== disc) {
                anyDiscountChanged = true;
                break;
              }
            }
          }
          
          return {
            ...row,
            discounts: newDiscounts,
            hasChanges: costChanged || priceChanged || anyDiscountChanged,
          };
        }
        return row;
      })
    );
  };

  const handleSave = async () => {
    const rowsToSave = rows.filter(row => row.hasChanges);
    if (rowsToSave.length === 0) {
      enqueueSnackbar(t('costEditor.noChanges'), { variant: 'info' });
      return;
    }

    setSaving(true);
    let successCount = 0;
    let errorCount = 0;

    try {
      for (const row of rowsToSave) {
        try {
          // Update cost/price if changed
          const costUpdate: any = {};
          const currentCostValue = row.currentCost?.wholesale_cost_gbp;
          const currentPriceValue = row.currentCost?.direct_retail_online_store_price_gbp;
          
          // Check if cost was changed
          // If there's no currentCost, any value entered should be saved
          // If there is a currentCost, only save if the value changed
          if (row.editedCost !== undefined && row.editedCost !== null && 
              (currentCostValue === undefined || row.editedCost !== currentCostValue)) {
            costUpdate.wholesale_cost_gbp = row.editedCost;
          }
          
          // Check if price was changed
          if (row.editedPrice !== undefined && row.editedPrice !== null && 
              (currentPriceValue === undefined || row.editedPrice !== currentPriceValue)) {
            costUpdate.direct_retail_online_store_price_gbp = row.editedPrice;
          }
          
          if (Object.keys(costUpdate).length > 0) {
            await productsAPI.updateCostSimple(row.id, costUpdate);
          }

          // Update discounts
          for (const [sectorId, discountPercent] of row.discounts.entries()) {
            const oldDiscount = row.originalDiscounts.get(sectorId) || 0;
            
            if (discountPercent !== oldDiscount) {
              await productsAPI.setDiscount(row.id, sectorId, discountPercent);
            }
          }

          successCount++;
        } catch (error: any) {
          console.error(`Failed to save product ${row.id}:`, error);
          errorCount++;
        }
      }

      if (successCount > 0) {
        enqueueSnackbar(t('costEditor.savedSuccess', { count: successCount }), { variant: 'success' });
      }
      if (errorCount > 0) {
        enqueueSnackbar(t('costEditor.savedErrors', { count: errorCount }), { variant: 'warning' });
      }

      // Refresh data
      await fetchData();
    } catch (error) {
      enqueueSnackbar(t('costEditor.saveFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

  const changedCount = rows.filter(r => r.hasChanges).length;

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4">{t('costEditor.title')}</Typography>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <FormControl sx={{ minWidth: 200 }}>
            <InputLabel>{t('costEditor.filterByCategory')}</InputLabel>
            <Select
              value={selectedCategory}
              onChange={(e) => setSelectedCategory(e.target.value)}
              label={t('costEditor.filterByCategory')}
            >
              <MenuItem value="">{t('costEditor.allCategories')}</MenuItem>
              {categories.map((cat) => (
                <MenuItem key={cat} value={cat}>
                  {cat}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          <Tooltip title={t('costEditor.refresh')}>
            <IconButton onClick={fetchData} disabled={loading || saving}>
              <RefreshIcon />
            </IconButton>
          </Tooltip>
          <Button
            variant="contained"
            startIcon={<SaveIcon />}
            onClick={handleSave}
            disabled={saving || changedCount === 0}
            color="primary"
          >
            {t('costEditor.saveChanges')} {changedCount > 0 && `(${changedCount})`}
          </Button>
        </Box>
      </Box>

      {changedCount > 0 && (
        <Alert severity="info" sx={{ mb: 2 }}>
          {t('costEditor.unsavedChanges', { count: changedCount })}
        </Alert>
      )}

      <TableContainer component={Paper} sx={{ maxHeight: 'calc(100vh - 300px)' }}>
        <Table stickyHeader size="small">
          <TableHead>
            <TableRow>
              <TableCell sx={{ minWidth: 200, position: 'sticky', left: 0, zIndex: 3, backgroundColor: 'white' }}>
                {t('costEditor.productName')}
              </TableCell>
              <TableCell sx={{ minWidth: 150 }}>{t('costEditor.barcode')}</TableCell>
              <TableCell sx={{ minWidth: 120 }}>{t('costEditor.currentCost')}</TableCell>
              <TableCell sx={{ minWidth: 120, backgroundColor: '#e3f2fd' }}>
                {t('costEditor.wholesaleCost')} (£)
              </TableCell>
              <TableCell sx={{ minWidth: 120, backgroundColor: '#fff3e0' }}>
                {t('costEditor.retailPrice')} (£)
              </TableCell>
              {sectors.map((sector) => (
                <TableCell key={sector.id} sx={{ minWidth: 100, backgroundColor: '#f3e5f5' }}>
                  {sector.name} {t('costEditor.discount')} (%)
                </TableCell>
              ))}
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={5 + sectors.length} align="center">
                  {t('common.loading')}
                </TableCell>
              </TableRow>
            ) : rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5 + sectors.length} align="center">
                  {t('costEditor.noProducts')}
                </TableCell>
              </TableRow>
            ) : (
              rows.map((row) => (
                <TableRow key={row.id} sx={{ backgroundColor: row.hasChanges ? '#fff9c4' : 'inherit' }}>
                  <TableCell sx={{ position: 'sticky', left: 0, zIndex: 2, backgroundColor: row.hasChanges ? '#fff9c4' : 'white' }}>
                    <Box>
                      <Typography variant="body2" fontWeight="bold">
                        {row.productName}
                      </Typography>
                      {row.productNameChinese && (
                        <Typography variant="caption" color="text.secondary">
                          {row.productNameChinese}
                        </Typography>
                      )}
                    </Box>
                  </TableCell>
                  <TableCell>{row.barcode || '-'}</TableCell>
                  <TableCell>
                    {row.currentCost?.wholesale_cost_gbp ? `£${row.currentCost.wholesale_cost_gbp.toFixed(2)}` : '-'}
                  </TableCell>
                  <TableCell>
                    <TextField
                      type="number"
                      size="small"
                      value={row.editedCost ?? ''}
                      onChange={(e) => handleCostChange(row.id, e.target.value)}
                      inputProps={{ step: '0.01', min: '0' }}
                      sx={{ width: '100%' }}
                    />
                  </TableCell>
                  <TableCell>
                    <TextField
                      type="number"
                      size="small"
                      value={row.editedPrice ?? ''}
                      onChange={(e) => handlePriceChange(row.id, e.target.value)}
                      inputProps={{ step: '0.01', min: '0' }}
                      sx={{ width: '100%' }}
                    />
                  </TableCell>
                  {sectors.map((sector) => (
                    <TableCell key={sector.id}>
                      <TextField
                        type="number"
                        size="small"
                        value={row.discounts.get(sector.id) ?? ''}
                        onChange={(e) => handleDiscountChange(row.id, sector.id, e.target.value)}
                        inputProps={{ step: '0.1', min: '0', max: '100' }}
                        sx={{ width: '100%' }}
                      />
                    </TableCell>
                  ))}
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>
    </Box>
  );
}

