import { useEffect, useState, useRef, useMemo } from 'react';
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
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Checkbox,
  FormControlLabel,
  Autocomplete,
} from '@mui/material';
import {
  Save as SaveIcon,
  Refresh as RefreshIcon,
  UploadFile as UploadFileIcon,
  Warning as WarningIcon,
} from '@mui/icons-material';
import { productsAPI, sectorsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Product, ProductCost, Sector } from '../types';
import { useTranslation } from 'react-i18next';
import * as XLSX from 'xlsx';
import DateRangeSelector from '../components/DateRangeSelector';
import { normalizeCategory } from '../utils/category';

interface EditableProductRow {
  id: number;
  productName: string;
  productNameChinese: string;
  category: string;
  barcode: string;
  currentCost?: ProductCost;
  editedCost?: number; // WholesaleCostGBP
  editedPrice?: number; // DirectRetailOnlineStorePriceGBP
  discounts: Map<number, number>; // sector_id -> discount_percent
  sectorPrices: Map<number, number>; // sector_id -> sector_price_gbp
  originalDiscounts: Map<number, number>; // sector_id -> discount_percent (original values)
  originalSectorPrices: Map<number, number>; // sector_id -> sector_price_gbp (original values)
  hasChanges: boolean;
}

interface ExcelSection {
  label: string;
  rowIndex: number;
  priceRowIndex: number;
  prices: Map<number, number>; // excel col index -> price
}

interface ExcelData {
  sheetName: string;
  products: { colIndex: number; name: string }[];
  wholesaleCostRow?: { rowIndex: number; values: Map<number, number> };
  retailPriceRow?: { rowIndex: number; values: Map<number, number> };
  sections: ExcelSection[];
}

interface ImportMatch {
  excelColIndex: number;
  excelName: string;
  systemProductId: number | null;
  systemProductName: string;
}

function parseExcelFile(file: File): Promise<ExcelData> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const data = new Uint8Array(e.target?.result as ArrayBuffer);
        const workbook = XLSX.read(data, { type: 'array' });
        const sheetName = workbook.SheetNames[0];
        const sheet = workbook.Sheets[sheetName];

        // Use raw cell access to handle merged cells properly
        const range = XLSX.utils.decode_range(sheet['!ref'] || 'A1');
        const maxRow = range.e.r;
        const maxCol = range.e.c;

        // Build a 2D array from raw cells
        const rawData: any[][] = [];
        for (let r = 0; r <= maxRow; r++) {
          const row: any[] = [];
          for (let c = 0; c <= maxCol; c++) {
            const addr = XLSX.utils.encode_cell({ r, c });
            const cell = sheet[addr];
            row.push(cell ? cell.v : null);
          }
          rawData.push(row);
        }

        const products: { colIndex: number; name: string }[] = [];
        let wholesaleCostRow: ExcelData['wholesaleCostRow'];
        let retailPriceRow: ExcelData['retailPriceRow'];
        const sections: ExcelSection[] = [];

        // Dynamically find the product name row:
        // It's the row with the most unique string values starting from col 2
        let productRowIdx = -1;
        let maxStringCount = 0;
        for (let row = 0; row <= Math.min(10, maxRow); row++) {
          let stringCount = 0;
          for (let col = 2; col < rawData[row].length; col++) {
            const val = rawData[row][col];
            if (val && typeof val === 'string' && val.trim().length > 2) {
              stringCount++;
            }
          }
          if (stringCount > maxStringCount) {
            maxStringCount = stringCount;
            productRowIdx = row;
          }
        }

        if (productRowIdx >= 0) {
          const productRow = rawData[productRowIdx];
          for (let col = 2; col < productRow.length; col++) {
            const val = productRow[col];
            if (val && typeof val === 'string' && val.trim()) {
              products.push({ colIndex: col, name: val.trim() });
            }
          }
        }

        console.log(`[Excel Import] Sheet "${sheetName}": ${maxRow + 1} rows, ${maxCol + 1} cols`);
        console.log(`[Excel Import] Product name row: ${productRowIdx + 1} (${products.length} products found)`);
        if (products.length > 0) {
          console.log(`[Excel Import] First product: "${products[0].name}" at col ${products[0].colIndex}`);
        }

        // Scan column A and B to find sections and key rows
        for (let row = 0; row < rawData.length; row++) {
          const cellA = rawData[row]?.[0];
          const cellB = rawData[row]?.[1];

          // Find "Wholesale cost" row (column B label)
          if (cellB && typeof cellB === 'string' && cellB.toLowerCase().includes('wholesale cost')) {
            const values = new Map<number, number>();
            for (let col = 2; col < rawData[row].length; col++) {
              const v = rawData[row][col];
              if (typeof v === 'number') values.set(col, Math.round(v * 100) / 100);
            }
            wholesaleCostRow = { rowIndex: row + 1, values };
            console.log(`[Excel Import] Wholesale cost row: ${row + 1} (${values.size} values)`);
          }

          // Find "Direct retail price" row
          if (cellB && typeof cellB === 'string' && cellB.toLowerCase().includes('direct retail price')) {
            const values = new Map<number, number>();
            for (let col = 2; col < rawData[row].length; col++) {
              const v = rawData[row][col];
              if (typeof v === 'number') values.set(col, Math.round(v * 100) / 100);
            }
            retailPriceRow = { rowIndex: row + 1, values };
            console.log(`[Excel Import] Retail price row: ${row + 1} (${values.size} values)`);
          }

          // Find sections in column A (skip rows before product names)
          if (cellA && typeof cellA === 'string' && cellA.trim() && row > productRowIdx) {
            const label = cellA.replace(/[\u2028\u2029\n\r]/g, ' ').trim();
            if (label.toLowerCase() === 'cost' || label.toLowerCase().includes('dashboard')) continue;

            // Find the price row for this section
            let priceRowIdx = -1;
            for (let r = row; r < Math.min(row + 4, rawData.length); r++) {
              const b = rawData[r]?.[1];
              if (b && typeof b === 'string' && b.toLowerCase().includes('price') && !b.toLowerCase().includes('profit')) {
                priceRowIdx = r;
                break;
              }
            }

            if (priceRowIdx >= 0) {
              const prices = new Map<number, number>();
              for (let col = 2; col < rawData[priceRowIdx].length; col++) {
                const v = rawData[priceRowIdx][col];
                if (typeof v === 'number') prices.set(col, Math.round(v * 100) / 100);
              }
              sections.push({ label, rowIndex: row + 1, priceRowIndex: priceRowIdx + 1, prices });
              console.log(`[Excel Import] Section: "${label}" price row: ${priceRowIdx + 1} (${prices.size} values)`);
            }
          }
        }

        resolve({ sheetName, products, wholesaleCostRow, retailPriceRow, sections });
      } catch (err) {
        reject(err);
      }
    };
    reader.onerror = () => reject(new Error('Failed to read file'));
    reader.readAsArrayBuffer(file);
  });
}

function normalize(s: string): string {
  return s
    .replace(/[\s\u3000]/g, '')    // remove all whitespace (including CJK space)
    .replace(/[^\p{L}\p{N}]/gu, '') // remove non-letter, non-number characters
    .toLowerCase();
}

function matchProducts(
  excelProducts: { colIndex: number; name: string }[],
  systemRows: EditableProductRow[]
): ImportMatch[] {
  const usedIds = new Set<number>();

  const results = excelProducts.map((ep) => {
    const exNorm = normalize(ep.name);
    const exLower = ep.name.toLowerCase();

    type Candidate = { row: EditableProductRow; score: number };
    let best: Candidate | null = null;

    for (const r of systemRows) {
      if (usedIds.has(r.id)) continue;
      let score = 0;

      // Chinese name matching
      if (r.productNameChinese) {
        const cnNorm = normalize(r.productNameChinese);
        if (cnNorm === exNorm) {
          score = 100;
        } else if (cnNorm.includes(exNorm) || exNorm.includes(cnNorm)) {
          const overlap = Math.min(cnNorm.length, exNorm.length) / Math.max(cnNorm.length, exNorm.length);
          score = Math.max(score, 60 + overlap * 30);
        }
      }

      // English name matching
      const enNorm = normalize(r.productName);
      if (enNorm === exNorm) {
        score = Math.max(score, 95);
      } else if (enNorm.includes(exNorm) || exNorm.includes(enNorm)) {
        const overlap = Math.min(enNorm.length, exNorm.length) / Math.max(enNorm.length, exNorm.length);
        score = Math.max(score, 50 + overlap * 30);
      }

      // Cross-language partial matching (excel Chinese vs system English and vice versa)
      const enLower = r.productName.toLowerCase();
      if (r.productNameChinese) {
        if (exLower.includes(r.productNameChinese) || r.productNameChinese.includes(ep.name)) {
          score = Math.max(score, 70);
        }
      }
      if (enLower.includes(exLower) || exLower.includes(enLower)) {
        const overlap = Math.min(enLower.length, exLower.length) / Math.max(enLower.length, exLower.length);
        score = Math.max(score, 40 + overlap * 30);
      }

      if (score > (best?.score ?? 0) && score >= 40) {
        best = { row: r, score };
      }
    }

    const matched = best?.row ?? null;
    if (matched) usedIds.add(matched.id);

    return {
      excelColIndex: ep.colIndex,
      excelName: ep.name,
      systemProductId: matched?.id ?? null,
      systemProductName: matched
        ? `${matched.productName}${matched.productNameChinese ? ` (${matched.productNameChinese})` : ''}`
        : '',
    };
  });

  // Sort: unmatched first, then matched
  results.sort((a, b) => {
    if (a.systemProductId === null && b.systemProductId !== null) return -1;
    if (a.systemProductId !== null && b.systemProductId === null) return 1;
    return 0;
  });

  return results;
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
  const [dateRange, setDateRange] = useState<import('../components/DateRangeSelector').DateRangeValue>({ effectiveFrom: '', effectiveTo: '', mode: 'current' });
  const { enqueueSnackbar } = useSnackbar();
  const [importDialogOpen, setImportDialogOpen] = useState(false);
  const [excelData, setExcelData] = useState<ExcelData | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    fetchData();
  }, [selectedCategory, dateRange]);

  const fetchData = async () => {
    try {
      setLoading(true);
      const efFrom = dateRange.mode !== 'current' && dateRange.effectiveFrom ? dateRange.effectiveFrom : undefined;
      const efTo = dateRange.mode !== 'current' && dateRange.effectiveTo ? dateRange.effectiveTo : undefined;
      const [productsData, sectorsData] = await Promise.all([
        productsAPI.list(selectedCategory || undefined, efFrom, efTo),
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
        const sectorPrices = new Map<number, number>();
        const originalDiscounts = new Map<number, number>();
        const originalSectorPrices = new Map<number, number>();
        
        if (product.discounts) {
          product.discounts.forEach(d => {
            discounts.set(d.sector_id, d.discount_percent);
            originalDiscounts.set(d.sector_id, d.discount_percent);
            sectorPrices.set(d.sector_id, d.sector_price_gbp ?? 0);
            originalSectorPrices.set(d.sector_id, d.sector_price_gbp ?? 0);
          });
        }

        return {
          id: product.id,
          productName: product.name,
          productNameChinese: product.name_chinese || '',
          category: product.category || '',
          barcode: product.barcode || '',
          currentCost: cost,
          editedCost: cost?.wholesale_cost_gbp,
          editedPrice: cost?.direct_retail_online_store_price_gbp,
          discounts,
          sectorPrices,
          originalDiscounts,
          originalSectorPrices,
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

  const checkRowHasChanges = (row: EditableProductRow) => {
    const costChanged = row.editedCost !== undefined && row.editedCost !== (row.currentCost?.wholesale_cost_gbp || 0);
    const priceChanged = row.editedPrice !== undefined && row.editedPrice !== (row.currentCost?.direct_retail_online_store_price_gbp || 0);
    let anySectorPriceChanged = false;
    for (const [sid, sp] of row.sectorPrices.entries()) {
      if ((row.originalSectorPrices.get(sid) || 0) !== sp) { anySectorPriceChanged = true; break; }
    }
    return costChanged || priceChanged || anySectorPriceChanged;
  };

  const handleSectorPriceChange = (productId: number, sectorId: number, value: string) => {
    setRows(prevRows =>
      prevRows.map(row => {
        if (row.id === productId) {
          const numValue = parseFloat(value) || 0;
          const newPrices = new Map(row.sectorPrices);
          newPrices.set(sectorId, numValue);
          const updated = { ...row, sectorPrices: newPrices };
          return { ...updated, hasChanges: checkRowHasChanges(updated) };
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
            if (dateRange.mode !== 'current' && dateRange.effectiveFrom && dateRange.effectiveTo) {
              costUpdate.effective_from = dateRange.effectiveFrom;
              costUpdate.effective_to = dateRange.effectiveTo;
            }
            await productsAPI.updateCostSimple(row.id, costUpdate);
          }

          const efFrom = dateRange.mode !== 'current' && dateRange.effectiveFrom ? dateRange.effectiveFrom : undefined;
          const efTo = dateRange.mode !== 'current' && dateRange.effectiveTo ? dateRange.effectiveTo : undefined;
          for (const [sectorId, sectorPrice] of row.sectorPrices.entries()) {
            const oldSectorPrice = row.originalSectorPrices.get(sectorId) || 0;
            if (sectorPrice !== oldSectorPrice) {
              const discountPercent = row.discounts.get(sectorId) || 0;
              await productsAPI.setDiscount(row.id, sectorId, discountPercent, sectorPrice, efFrom, efTo);
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

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const parsed = await parseExcelFile(file);
      setExcelData(parsed);
      setImportDialogOpen(true);
    } catch (err) {
      enqueueSnackbar('Failed to parse Excel file', { variant: 'error' });
    }
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const handleImportApply = (updates: {
    productId: number;
    cost?: number;
    price?: number;
    sectorPrices?: Map<number, number>;
  }[]) => {
    setRows(prevRows =>
      prevRows.map(row => {
        const update = updates.find(u => u.productId === row.id);
        if (!update) return row;

        const newRow = { ...row };
        if (update.cost !== undefined) newRow.editedCost = update.cost;
        if (update.price !== undefined) newRow.editedPrice = update.price;
        if (update.sectorPrices) {
          const newPrices = new Map(row.sectorPrices);
          for (const [sid, sp] of update.sectorPrices.entries()) {
            newPrices.set(sid, sp);
          }
          newRow.sectorPrices = newPrices;
        }
        newRow.hasChanges = checkRowHasChanges(newRow);
        return newRow;
      })
    );
    setImportDialogOpen(false);
    setExcelData(null);
  };

  const changedCount = rows.filter(r => r.hasChanges).length;

  return (
    <Box sx={{ p: 3 }}>
      <input
        type="file"
        accept=".xlsx,.xls"
        ref={fileInputRef}
        style={{ display: 'none' }}
        onChange={handleFileUpload}
      />
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
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
          <Button
            variant="outlined"
            startIcon={<UploadFileIcon />}
            onClick={() => fileInputRef.current?.click()}
            disabled={loading || saving || rows.length === 0}
          >
            Import Excel
          </Button>
          <DateRangeSelector value={dateRange} onChange={setDateRange} />
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

      <TableContainer component={Paper} sx={{ maxHeight: 'calc(100vh - 360px)' }}>
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
                <TableCell key={`price-${sector.id}`} sx={{ minWidth: 100, backgroundColor: '#e8f5e9' }}>
                  {sector.name} Price (£)
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
                    <TableCell key={`price-${sector.id}`}>
                      <TextField
                        type="number"
                        size="small"
                        value={row.sectorPrices.get(sector.id) ?? ''}
                        onChange={(e) => handleSectorPriceChange(row.id, sector.id, e.target.value)}
                        inputProps={{ step: '0.01', min: '0' }}
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

      {excelData && (
        <ImportDialog
          open={importDialogOpen}
          onClose={() => { setImportDialogOpen(false); setExcelData(null); }}
          excelData={excelData}
          systemRows={rows}
          systemSectors={sectors}
          onApply={handleImportApply}
        />
      )}
    </Box>
  );
}

function ImportDialog({
  open,
  onClose,
  excelData,
  systemRows,
  systemSectors,
  onApply,
}: {
  open: boolean;
  onClose: () => void;
  excelData: ExcelData;
  systemRows: EditableProductRow[];
  systemSectors: Sector[];
  onApply: (updates: { productId: number; cost?: number; price?: number; sectorPrices?: Map<number, number> }[]) => void;
}) {
  const [matches, setMatches] = useState<ImportMatch[]>([]);
  const [importCost, setImportCost] = useState(true);
  const [importRetailPrice, setImportRetailPrice] = useState(true);
  const [sectorMapping, setSectorMapping] = useState<Map<string, number>>(new Map());

  useEffect(() => {
    const m = matchProducts(excelData.products, systemRows);
    setMatches(m);

    // Auto-map sections to sectors by name similarity
    const autoMap = new Map<string, number>();
    for (const section of excelData.sections) {
      const lower = section.label.toLowerCase();
      for (const sector of systemSectors) {
        const sectorLower = sector.name.toLowerCase();
        if (lower.includes(sectorLower) || sectorLower.includes('wholesale') && lower.includes('wholesale') && lower.includes('restaurant')) {
          // Only auto-map specific known patterns
        }
      }
    }
    setSectorMapping(autoMap);
  }, [excelData, systemRows, systemSectors]);

  const handleMatchChange = (excelColIndex: number, productId: number | null) => {
    setMatches(prev =>
      prev.map(m => m.excelColIndex === excelColIndex ? { ...m, systemProductId: productId, systemProductName: productId ? (systemRows.find(r => r.id === productId)?.productName || '') : '' } : m)
    );
  };

  const handleSectorMapChange = (sectionLabel: string, sectorId: number | 0) => {
    setSectorMapping(prev => {
      const next = new Map(prev);
      if (sectorId === 0) {
        next.delete(sectionLabel);
      } else {
        next.set(sectionLabel, sectorId);
      }
      return next;
    });
  };

  const matchedCount = matches.filter(m => m.systemProductId !== null).length;
  const unmatchedCount = matches.length - matchedCount;

  const productOptions = useMemo(() => {
    return [...systemRows].sort(
      (a, b) =>
        normalizeCategory(a.category || '').localeCompare(normalizeCategory(b.category || '')) ||
        a.productName.localeCompare(b.productName)
    );
  }, [systemRows]);

  const handleApply = () => {
    const updates: { productId: number; cost?: number; price?: number; sectorPrices?: Map<number, number> }[] = [];

    for (const match of matches) {
      if (!match.systemProductId) continue;
      const update: { productId: number; cost?: number; price?: number; sectorPrices?: Map<number, number> } = {
        productId: match.systemProductId,
      };

      if (importCost && excelData.wholesaleCostRow) {
        const v = excelData.wholesaleCostRow.values.get(match.excelColIndex);
        if (v !== undefined) update.cost = v;
      }

      if (importRetailPrice && excelData.retailPriceRow) {
        const v = excelData.retailPriceRow.values.get(match.excelColIndex);
        if (v !== undefined) update.price = v;
      }

      const sp = new Map<number, number>();
      for (const section of excelData.sections) {
        const sectorId = sectorMapping.get(section.label);
        if (!sectorId) continue;
        const v = section.prices.get(match.excelColIndex);
        if (v !== undefined) sp.set(sectorId, v);
      }
      if (sp.size > 0) update.sectorPrices = sp;

      if (update.cost !== undefined || update.price !== undefined || update.sectorPrices) {
        updates.push(update);
      }
    }

    onApply(updates);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="lg" fullWidth>
      <DialogTitle>Import from Excel</DialogTitle>
      <DialogContent dividers>
        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 2 }}>
          Sheet: {excelData.sheetName} &mdash; {excelData.products.length} products found
        </Typography>

        {/* Import options */}
        <Paper variant="outlined" sx={{ p: 2, mb: 3 }}>
          <Typography variant="subtitle1" fontWeight="bold" gutterBottom>
            What to import
          </Typography>
          <Box sx={{ display: 'flex', gap: 3, flexWrap: 'wrap', alignItems: 'flex-start' }}>
            <Box>
              <FormControlLabel
                control={<Checkbox checked={importCost} onChange={(e) => setImportCost(e.target.checked)} />}
                label={`Wholesale Cost${excelData.wholesaleCostRow ? ` (Row ${excelData.wholesaleCostRow.rowIndex})` : ' (not found)'}`}
                disabled={!excelData.wholesaleCostRow}
              />
              <br />
              <FormControlLabel
                control={<Checkbox checked={importRetailPrice} onChange={(e) => setImportRetailPrice(e.target.checked)} />}
                label={`Retail Price${excelData.retailPriceRow ? ` (Row ${excelData.retailPriceRow.rowIndex})` : ' (not found)'}`}
                disabled={!excelData.retailPriceRow}
              />
            </Box>
          </Box>

          {/* Sector mapping */}
          {systemSectors.length > 0 && excelData.sections.length > 0 && (
            <Box sx={{ mt: 2 }}>
              <Typography variant="subtitle2" fontWeight="bold" gutterBottom>
                Map Excel sections to system sectors (for sector prices)
              </Typography>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Excel Section</TableCell>
                    <TableCell>Price Row</TableCell>
                    <TableCell>Map to Sector</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {excelData.sections.map((section) => (
                    <TableRow key={section.label}>
                      <TableCell>
                        <Typography variant="body2">{section.label}</Typography>
                      </TableCell>
                      <TableCell>
                        <Typography variant="body2" color="text.secondary">Row {section.priceRowIndex}</Typography>
                      </TableCell>
                      <TableCell>
                        <FormControl size="small" sx={{ minWidth: 180 }}>
                          <Select
                            value={sectorMapping.get(section.label) || 0}
                            onChange={(e) => handleSectorMapChange(section.label, Number(e.target.value))}
                            displayEmpty
                          >
                            <MenuItem value={0}><em>Skip</em></MenuItem>
                            {systemSectors.map((s) => (
                              <MenuItem key={s.id} value={s.id}>{s.name}</MenuItem>
                            ))}
                          </Select>
                        </FormControl>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </Box>
          )}
        </Paper>

        {/* Product matching */}
        <Paper variant="outlined" sx={{ p: 2 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
            <Typography variant="subtitle1" fontWeight="bold">
              Product matching ({matchedCount}/{matches.length} matched)
            </Typography>
            {unmatchedCount > 0 && (
              <Alert severity="warning" sx={{ py: 0, flex: 1 }} icon={<WarningIcon fontSize="small" />}>
                {unmatchedCount} product{unmatchedCount > 1 ? 's' : ''} not matched — please assign manually
              </Alert>
            )}
          </Box>
          <TableContainer sx={{ maxHeight: 400 }}>
            <Table size="small" stickyHeader>
              <TableHead>
                <TableRow>
                  <TableCell sx={{ minWidth: 30 }}>#</TableCell>
                  <TableCell sx={{ minWidth: 250 }}>Excel Product Name</TableCell>
                  <TableCell sx={{ minWidth: 280 }}>System Product</TableCell>
                  {importCost && excelData.wholesaleCostRow && <TableCell>Cost (£)</TableCell>}
                  {importRetailPrice && excelData.retailPriceRow && <TableCell>Retail (£)</TableCell>}
                  {excelData.sections.filter(s => sectorMapping.has(s.label)).map(s => (
                    <TableCell key={s.label}>
                      {systemSectors.find(sec => sec.id === sectorMapping.get(s.label))?.name || ''} (£)
                    </TableCell>
                  ))}
                </TableRow>
              </TableHead>
              <TableBody>
                {matches.map((match, idx) => {
                  const isUnmatched = match.systemProductId === null;
                  return (
                    <TableRow
                      key={match.excelColIndex}
                      sx={{
                        backgroundColor: isUnmatched ? '#ffebee' : '#e8f5e9',
                        '&:hover': { backgroundColor: isUnmatched ? '#ffcdd2' : '#c8e6c9' },
                      }}
                    >
                      <TableCell>
                        {isUnmatched && <WarningIcon fontSize="small" color="error" sx={{ verticalAlign: 'middle', mr: 0.5 }} />}
                        {idx + 1}
                      </TableCell>
                      <TableCell>
                        <Typography variant="body2" fontWeight={isUnmatched ? 'bold' : 'normal'}>
                          {match.excelName}
                        </Typography>
                      </TableCell>
                      <TableCell sx={{ minWidth: 320 }}>
                        <Autocomplete
                          size="small"
                          options={productOptions}
                          groupBy={(option) => normalizeCategory(option.category || '') || 'Uncategorized'}
                          getOptionLabel={(option) =>
                            `${option.productName}${option.productNameChinese ? ` (${option.productNameChinese})` : ''}`
                          }
                          value={productOptions.find(r => r.id === match.systemProductId) || null}
                          onChange={(_, newVal) => handleMatchChange(match.excelColIndex, newVal?.id ?? null)}
                          filterOptions={(options, { inputValue }) => {
                            const q = inputValue.toLowerCase();
                            return options.filter(o =>
                              o.productName.toLowerCase().includes(q) ||
                              o.productNameChinese.includes(inputValue) ||
                              (o.barcode && o.barcode.includes(inputValue))
                            );
                          }}
                          renderInput={(params) => (
                            <TextField
                              {...params}
                              placeholder="Search product..."
                              error={isUnmatched}
                              sx={isUnmatched ? { '& .MuiOutlinedInput-root': { borderColor: 'error.main', borderWidth: 2 } } : {}}
                            />
                          )}
                          renderOption={(props, option) => (
                            <li {...props} key={option.id}>
                              <Box>
                                <Typography variant="body2">{option.productName}</Typography>
                                {option.productNameChinese && (
                                  <Typography variant="caption" color="text.secondary">{option.productNameChinese}</Typography>
                                )}
                              </Box>
                            </li>
                          )}
                          isOptionEqualToValue={(option, value) => option.id === value.id}
                          clearOnBlur
                          blurOnSelect
                          noOptionsText="No products found"
                        />
                      </TableCell>
                      {importCost && excelData.wholesaleCostRow && (
                        <TableCell>
                          {excelData.wholesaleCostRow.values.get(match.excelColIndex)?.toFixed(2) ?? '-'}
                        </TableCell>
                      )}
                      {importRetailPrice && excelData.retailPriceRow && (
                        <TableCell>
                          {excelData.retailPriceRow.values.get(match.excelColIndex)?.toFixed(2) ?? '-'}
                        </TableCell>
                      )}
                      {excelData.sections.filter(s => sectorMapping.has(s.label)).map(s => (
                        <TableCell key={s.label}>
                          {s.prices.get(match.excelColIndex)?.toFixed(2) ?? '-'}
                        </TableCell>
                      ))}
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
        </Paper>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          variant="contained"
          onClick={handleApply}
          disabled={matchedCount === 0}
        >
          Apply {matchedCount} products
        </Button>
      </DialogActions>
    </Dialog>
  );
}

