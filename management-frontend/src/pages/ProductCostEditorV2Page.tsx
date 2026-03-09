import { useEffect, useState, useMemo, useCallback, useRef } from 'react';
import {
  Box,
  Paper,
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
} from '@mui/material';
import {
  Save as SaveIcon,
  Refresh as RefreshIcon,
} from '@mui/icons-material';
import { productsAPI, sectorsAPI, currencyRatesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Product, ProductCost, Sector } from '../types';
import { useTranslation } from 'react-i18next';
import DateRangeSelector from '../components/DateRangeSelector';
import type { DateRangeValue } from '../components/DateRangeSelector';
import { normalizeCategory } from '../utils/category';

// ── Types ────────────────────────────────────────────────────────────

interface CostInputs {
  exchange_rate: number;
  purchasing_cost_hkd: number;
  unit_weight_g: number;
  purchasing_cost_buffer_percent: number;
  weight_g: number;
  weight_buffer_percent: number;
  freight_rate_hkd_per_kg: number;
  import_duty_percent: number;
  packaging_gbp: number;
  direct_retail_online_store_price_gbp: number;
}

interface CostCalc extends CostInputs {
  purchasing_cost_gbp: number;
  cost_buffer_gbp: number;
  adjusted_purchasing_cost_gbp: number;
  freight_buffer_hkd: number;
  freight_hkd: number;
  freight_gbp: number;
  import_duty_gbp: number;
  wholesale_cost_gbp: number;
  retail_profit_gbp: number;
  retail_profit_margin: number;
}

interface ProductColumn {
  product: Product;
  inputs: CostInputs;
  originalInputs: CostInputs;
  calc: CostCalc;
  sectorPrices: Map<number, number>;
  originalSectorPrices: Map<number, number>;
  hasChanges: boolean;
}

type RowDef = {
  key: string;
  label: string;
  section?: string;
  field?: keyof CostInputs;
  calcField?: keyof CostCalc;
  sectorId?: number;
  type: 'input' | 'calculated' | 'header' | 'sector_input';
  format?: 'number' | 'percent' | 'currency' | 'weight';
  step?: string;
};

// ── Calculations ─────────────────────────────────────────────────────

function calculate(i: CostInputs): CostCalc {
  const purchasing_cost_gbp = i.exchange_rate > 0 ? i.purchasing_cost_hkd / i.exchange_rate : 0;
  const cost_buffer_gbp = purchasing_cost_gbp * i.purchasing_cost_buffer_percent;
  const adjusted_purchasing_cost_gbp = purchasing_cost_gbp + cost_buffer_gbp;
  const freight_buffer_hkd = (i.weight_g * i.weight_buffer_percent * i.freight_rate_hkd_per_kg) / 1000;
  const freight_hkd = (i.weight_g * (1 + i.weight_buffer_percent) * i.freight_rate_hkd_per_kg) / 1000;
  const freight_gbp = i.exchange_rate > 0 ? freight_hkd / i.exchange_rate : 0;
  const import_duty_gbp = (adjusted_purchasing_cost_gbp + freight_gbp) * i.import_duty_percent;
  const wholesale_cost_gbp = adjusted_purchasing_cost_gbp + freight_gbp + import_duty_gbp + i.packaging_gbp;
  const retail_profit_gbp = i.direct_retail_online_store_price_gbp - wholesale_cost_gbp;
  const retail_profit_margin = i.direct_retail_online_store_price_gbp > 0
    ? retail_profit_gbp / i.direct_retail_online_store_price_gbp
    : 0;

  return {
    ...i,
    purchasing_cost_gbp: r2(purchasing_cost_gbp),
    cost_buffer_gbp: r2(cost_buffer_gbp),
    adjusted_purchasing_cost_gbp: r2(adjusted_purchasing_cost_gbp),
    freight_buffer_hkd: r2(freight_buffer_hkd),
    freight_hkd: r2(freight_hkd),
    freight_gbp: r2(freight_gbp),
    import_duty_gbp: r2(import_duty_gbp),
    wholesale_cost_gbp: r2(wholesale_cost_gbp),
    retail_profit_gbp: r2(retail_profit_gbp),
    retail_profit_margin: r4(retail_profit_margin),
  };
}

function r2(n: number) { return Math.round(n * 100) / 100; }
function r4(n: number) { return Math.round(n * 10000) / 10000; }

function extractInputs(cost?: ProductCost): CostInputs {
  if (!cost) return defaultInputs();
  return {
    exchange_rate: cost.exchange_rate || 0,
    purchasing_cost_hkd: cost.purchasing_cost_hkd || 0,
    unit_weight_g: cost.unit_weight_g || 0,
    purchasing_cost_buffer_percent: cost.purchasing_cost_buffer_percent || 0,
    weight_g: cost.weight_g || 0,
    weight_buffer_percent: cost.weight_buffer_percent || 0,
    freight_rate_hkd_per_kg: cost.freight_rate_hkd_per_kg || 0,
    import_duty_percent: cost.import_duty_percent || 0,
    packaging_gbp: cost.packaging_gbp || 0,
    direct_retail_online_store_price_gbp: cost.direct_retail_online_store_price_gbp || 0,
  };
}

function defaultInputs(): CostInputs {
  return {
    exchange_rate: 0, purchasing_cost_hkd: 0, unit_weight_g: 0,
    purchasing_cost_buffer_percent: 0, weight_g: 0, weight_buffer_percent: 0,
    freight_rate_hkd_per_kg: 0, import_duty_percent: 0, packaging_gbp: 0,
    direct_retail_online_store_price_gbp: 0,
  };
}

function inputsEqual(a: CostInputs, b: CostInputs): boolean {
  return (Object.keys(a) as (keyof CostInputs)[]).every(k => a[k] === b[k]);
}

// ── Styles ───────────────────────────────────────────────────────────

const LABEL_WIDTH = 220;
const COL_WIDTH = 120;
const HEADER_BG = '#1565c0';
const HEADER_TEXT = '#fff';
const SECTION_BG = '#e3f2fd';
const CALC_BG = '#f5f5f5';
const INPUT_BG = '#fff';
const CHANGED_BG = '#fff9c4';
const WHOLESALE_BG = '#c8e6c9';

const numberInputStyle: React.CSSProperties = {
  width: '100%',
  border: 'none',
  outline: 'none',
  textAlign: 'right',
  fontSize: 12,
  padding: '2px 2px',
  backgroundColor: 'transparent',
  boxSizing: 'border-box',
  MozAppearance: 'textfield',
  WebkitAppearance: 'none',
  appearance: 'textfield',
} as React.CSSProperties;

const cellStyle = (bg: string, bold = false): React.CSSProperties => ({
  width: COL_WIDTH,
  minWidth: COL_WIDTH,
  maxWidth: COL_WIDTH,
  padding: '2px 4px',
  textAlign: 'right',
  fontSize: 12,
  fontWeight: bold ? 700 : 400,
  backgroundColor: bg,
  borderRight: '1px solid #e0e0e0',
  borderBottom: '1px solid #e0e0e0',
  whiteSpace: 'nowrap',
  overflow: 'hidden',
});

const labelStyle: React.CSSProperties = {
  width: LABEL_WIDTH,
  minWidth: LABEL_WIDTH,
  maxWidth: LABEL_WIDTH,
  padding: '4px 8px',
  fontSize: 12,
  fontWeight: 500,
  backgroundColor: '#fafafa',
  borderRight: '2px solid #bdbdbd',
  borderBottom: '1px solid #e0e0e0',
  position: 'sticky',
  left: 0,
  zIndex: 2,
};

// ── Component ────────────────────────────────────────────────────────

export default function ProductCostEditorV2Page() {
  const { t } = useTranslation();
  const { enqueueSnackbar } = useSnackbar();
  const [columns, setColumns] = useState<ProductColumn[]>([]);
  const [sectors, setSectors] = useState<Sector[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState<string>('');
  const [categories, setCategories] = useState<string[]>([]);
  const [dateRange, setDateRange] = useState<DateRangeValue>({ effectiveFrom: '', effectiveTo: '', mode: 'current' });
  const scrollRef = useRef<HTMLDivElement>(null);

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      const efFrom = dateRange.mode !== 'current' && dateRange.effectiveFrom ? dateRange.effectiveFrom : undefined;
      const efTo = dateRange.mode !== 'current' && dateRange.effectiveTo ? dateRange.effectiveTo : undefined;
      const [productsData, sectorsData, hkdRate] = await Promise.all([
        productsAPI.list(selectedCategory || undefined, efFrom, efTo),
        sectorsAPI.list(),
        currencyRatesAPI.get('HKD').catch(() => null),
      ]);
      const dbExchangeRate = hkdRate ? hkdRate.rate_to_gbp : 0;
      const cats = Array.from(new Set(productsData.map(p => p.category).filter(Boolean))) as string[];
      setCategories(cats);
      setSectors(sectorsData);

      const cols: ProductColumn[] = productsData.map(product => {
        const inputs = extractInputs(product.current_cost);
        if (!inputs.exchange_rate && dbExchangeRate > 0) {
          inputs.exchange_rate = dbExchangeRate;
        }
        const originalInputs = { ...inputs };
        const sectorPrices = new Map<number, number>();
        const originalSectorPrices = new Map<number, number>();
        if (product.discounts) {
          product.discounts.forEach(d => {
            sectorPrices.set(d.sector_id, d.sector_price_gbp ?? 0);
            originalSectorPrices.set(d.sector_id, d.sector_price_gbp ?? 0);
          });
        }
        return {
          product,
          inputs,
          originalInputs,
          calc: calculate(inputs),
          sectorPrices,
          originalSectorPrices,
          hasChanges: false,
        };
      });

      // Sort by normalized category (trim + NFC) then name so duplicate-looking categories merge
      cols.sort((a, b) =>
        normalizeCategory(a.product.category || '').localeCompare(normalizeCategory(b.product.category || '')) ||
        a.product.name.localeCompare(b.product.name)
      );

      setColumns(cols);
    } catch {
      enqueueSnackbar('Failed to load data', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  }, [selectedCategory, dateRange, enqueueSnackbar]);

  useEffect(() => { fetchData(); }, [fetchData]);

  // ── Row definitions ─────────────────────────────────────────────

  const rowDefs = useMemo((): RowDef[] => {
    const rows: RowDef[] = [
      { key: 'sec_cost', label: 'COST CALCULATION', type: 'header', section: 'cost' },
      { key: 'exchange_rate', label: 'Exchange Rate', field: 'exchange_rate', type: 'input', format: 'number', step: '0.01' },
      { key: 'purchasing_cost_hkd', label: 'Purchasing Cost (HKD)', field: 'purchasing_cost_hkd', type: 'input', format: 'number', step: '0.01' },
      { key: 'unit_weight_g', label: 'Unit Weight (g)', field: 'unit_weight_g', type: 'input', format: 'weight', step: '1' },
      { key: 'purchasing_cost_gbp', label: 'Purchasing Cost (GBP)', calcField: 'purchasing_cost_gbp', type: 'calculated', format: 'currency' },
      { key: 'purchasing_cost_buffer_percent', label: 'Cost Buffer %', field: 'purchasing_cost_buffer_percent', type: 'input', format: 'percent', step: '0.01' },
      { key: 'cost_buffer_gbp', label: 'Cost Buffer (GBP)', calcField: 'cost_buffer_gbp', type: 'calculated', format: 'currency' },
      { key: 'adjusted_purchasing_cost_gbp', label: 'Adjusted Cost (GBP)', calcField: 'adjusted_purchasing_cost_gbp', type: 'calculated', format: 'currency' },
      { key: 'weight_g', label: 'Weight (g)', field: 'weight_g', type: 'input', format: 'weight', step: '1' },
      { key: 'weight_buffer_percent', label: 'Weight Buffer %', field: 'weight_buffer_percent', type: 'input', format: 'percent', step: '0.01' },
      { key: 'freight_rate_hkd_per_kg', label: 'Freight Rate (HKD/KG)', field: 'freight_rate_hkd_per_kg', type: 'input', format: 'number', step: '0.01' },
      { key: 'freight_buffer_hkd', label: 'Freight Buffer (HKD)', calcField: 'freight_buffer_hkd', type: 'calculated', format: 'number' },
      { key: 'freight_hkd', label: 'Freight (HKD)', calcField: 'freight_hkd', type: 'calculated', format: 'number' },
      { key: 'freight_gbp', label: 'Freight (GBP)', calcField: 'freight_gbp', type: 'calculated', format: 'currency' },
      { key: 'import_duty_percent', label: 'Import Duty %', field: 'import_duty_percent', type: 'input', format: 'percent', step: '0.01' },
      { key: 'import_duty_gbp', label: 'Import Duty (GBP)', calcField: 'import_duty_gbp', type: 'calculated', format: 'currency' },
      { key: 'packaging_gbp', label: 'Packaging (GBP)', field: 'packaging_gbp', type: 'input', format: 'currency', step: '0.01' },
      { key: 'wholesale_cost_gbp', label: 'Wholesale Cost (GBP)', calcField: 'wholesale_cost_gbp', type: 'calculated', format: 'currency' },
      { key: 'sec_retail', label: 'RETAIL PRICING', type: 'header', section: 'retail' },
      { key: 'direct_retail_online_store_price_gbp', label: 'Retail Price (GBP)', field: 'direct_retail_online_store_price_gbp', type: 'input', format: 'currency', step: '0.01' },
      { key: 'retail_profit_gbp', label: 'Retail Profit (GBP)', calcField: 'retail_profit_gbp', type: 'calculated', format: 'currency' },
      { key: 'retail_profit_margin', label: 'Retail Profit Margin', calcField: 'retail_profit_margin', type: 'calculated', format: 'percent' },
    ];

    if (sectors.length > 0) {
      rows.push({ key: 'sec_sectors', label: 'SECTOR PRICES', type: 'header', section: 'sectors' });
      sectors.forEach(s => {
        rows.push({
          key: `sector_${s.id}`,
          label: `${s.name} Price (£)`,
          type: 'sector_input',
          sectorId: s.id,
          format: 'currency',
          step: '0.01',
        });
      });
    }

    return rows;
  }, [sectors]);

  // ── Category grouping for column headers ───────────────────────

  const categoryGroups = useMemo(() => {
    const groups: { category: string; count: number }[] = [];
    let cur = '';
    let count = 0;
    for (const col of columns) {
      const cat = normalizeCategory(col.product.category || '') || 'Uncategorized';
      if (cat !== cur) {
        if (count > 0) groups.push({ category: cur, count });
        cur = cat;
        count = 1;
      } else {
        count++;
      }
    }
    if (count > 0) groups.push({ category: cur, count });
    return groups;
  }, [columns]);

  // ── Handlers ───────────────────────────────────────────────────

  const handleInputChange = (colIdx: number, field: keyof CostInputs, value: string) => {
    setColumns(prev => {
      const next = [...prev];
      const col = { ...next[colIdx] };
      const inputs = { ...col.inputs, [field]: parseFloat(value) || 0 };
      col.inputs = inputs;
      col.calc = calculate(inputs);
      col.hasChanges = !inputsEqual(inputs, col.originalInputs) ||
        sectorPricesChanged(col.sectorPrices, col.originalSectorPrices);
      next[colIdx] = col;
      return next;
    });
  };

  const handleSectorPriceChange = (colIdx: number, sectorId: number, value: string) => {
    setColumns(prev => {
      const next = [...prev];
      const col = { ...next[colIdx] };
      const sp = new Map(col.sectorPrices);
      sp.set(sectorId, parseFloat(value) || 0);
      col.sectorPrices = sp;
      col.hasChanges = !inputsEqual(col.inputs, col.originalInputs) ||
        sectorPricesChanged(sp, col.originalSectorPrices);
      next[colIdx] = col;
      return next;
    });
  };

  function sectorPricesChanged(a: Map<number, number>, b: Map<number, number>) {
    for (const [k, v] of a.entries()) {
      if ((b.get(k) || 0) !== v) return true;
    }
    return false;
  }

  const changedCount = columns.filter(c => c.hasChanges).length;

  const handleSave = async () => {
    const toSave = columns.filter(c => c.hasChanges);
    if (toSave.length === 0) return;

    setSaving(true);
    let ok = 0;
    let fail = 0;
    for (const col of toSave) {
      try {
        if (!inputsEqual(col.inputs, col.originalInputs)) {
          const costPayload: any = {
            exchange_rate: col.inputs.exchange_rate,
            purchasing_cost_hkd: col.inputs.purchasing_cost_hkd,
            unit_weight_g: col.inputs.unit_weight_g,
            purchasing_cost_buffer_percent: col.inputs.purchasing_cost_buffer_percent,
            weight_g: col.inputs.weight_g,
            weight_buffer_percent: col.inputs.weight_buffer_percent,
            freight_rate_hkd_per_kg: col.inputs.freight_rate_hkd_per_kg,
            import_duty_percent: col.inputs.import_duty_percent,
            packaging_gbp: col.inputs.packaging_gbp,
            direct_retail_online_store_price_gbp: col.inputs.direct_retail_online_store_price_gbp,
          };
          if (dateRange.mode !== 'current' && dateRange.effectiveFrom && dateRange.effectiveTo) {
            costPayload.effective_from = dateRange.effectiveFrom;
            costPayload.effective_to = dateRange.effectiveTo;
          }
          await productsAPI.setCost(col.product.id, costPayload);
        }
        const efFrom = dateRange.mode !== 'current' && dateRange.effectiveFrom ? dateRange.effectiveFrom : undefined;
        const efTo = dateRange.mode !== 'current' && dateRange.effectiveTo ? dateRange.effectiveTo : undefined;
        for (const [sid, price] of col.sectorPrices.entries()) {
          if ((col.originalSectorPrices.get(sid) || 0) !== price) {
            await productsAPI.setDiscount(col.product.id, sid, 0, price, efFrom, efTo);
          }
        }
        ok++;
      } catch {
        fail++;
      }
    }
    if (ok > 0) enqueueSnackbar(`Saved ${ok} product(s)`, { variant: 'success' });
    if (fail > 0) enqueueSnackbar(`Failed to save ${fail} product(s)`, { variant: 'warning' });
    await fetchData();
    setSaving(false);
  };

  // ── Format helpers ─────────────────────────────────────────────

  const fmt = (val: number, format?: string) => {
    if (format === 'currency') return val ? `£${val.toFixed(2)}` : '-';
    if (format === 'percent') return val ? `${(val * 100).toFixed(1)}%` : '-';
    if (format === 'weight') return val ? `${val}` : '-';
    return val ? val.toFixed(2) : '-';
  };

  // ── Render ─────────────────────────────────────────────────────

  if (loading) return <Box sx={{ p: 3 }}><Typography>Loading...</Typography></Box>;

  return (
    <>
      <style>{`
        .v2-num-input::-webkit-outer-spin-button,
        .v2-num-input::-webkit-inner-spin-button { -webkit-appearance: none; margin: 0; }
        .v2-num-input { -moz-appearance: textfield; }
      `}</style>
      {/* Toolbar */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
        <Typography variant="h5">Cost & Price Editor v2</Typography>
        <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center' }}>
          <FormControl size="small" sx={{ minWidth: 160 }}>
            <InputLabel>{t('costEditor.filterByCategory')}</InputLabel>
            <Select
              value={selectedCategory}
              onChange={(e) => setSelectedCategory(e.target.value)}
              label={t('costEditor.filterByCategory')}
            >
              <MenuItem value="">All</MenuItem>
              {categories.map(c => <MenuItem key={c} value={c}>{c}</MenuItem>)}
            </Select>
          </FormControl>
          <DateRangeSelector value={dateRange} onChange={setDateRange} />
          <Tooltip title="Refresh">
            <IconButton onClick={fetchData} disabled={saving} size="small"><RefreshIcon /></IconButton>
          </Tooltip>
          <Button
            variant="contained"
            size="small"
            startIcon={<SaveIcon />}
            onClick={handleSave}
            disabled={saving || changedCount === 0}
            sx={{ whiteSpace: 'nowrap' }}
          >
            Save {changedCount > 0 && `(${changedCount})`}
          </Button>
        </Box>
      </Box>

      {changedCount > 0 && (
        <Alert severity="info" sx={{ mb: 1, py: 0 }}>
          {changedCount} product(s) with unsaved changes
        </Alert>
      )}

      {/* Table - scrolls independently */}
      <Paper
        ref={scrollRef}
        variant="outlined"
        sx={{
          overflow: 'auto',
          height: 'calc(100vh - 180px)',
        }}
      >
        <table style={{ borderCollapse: 'collapse', tableLayout: 'fixed' }}>
          {/* Category header row */}
          <thead style={{ position: 'sticky', top: 0, zIndex: 4 }}>
            <tr>
              <th style={{ ...labelStyle, backgroundColor: HEADER_BG, color: HEADER_TEXT, zIndex: 5, top: 0, position: 'sticky', borderBottom: 'none' }}>
                Category
              </th>
              {categoryGroups.map((g, gi) => (
                <th
                  key={gi}
                  colSpan={g.count}
                  style={{
                    padding: '6px 4px',
                    fontSize: 11,
                    fontWeight: 700,
                    backgroundColor: HEADER_BG,
                    color: HEADER_TEXT,
                    textAlign: 'center',
                    borderRight: '2px solid #0d47a1',
                    borderBottom: 'none',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {g.category}
                </th>
              ))}
            </tr>
            {/* Product name row */}
            <tr>
              <th style={{
                ...labelStyle,
                backgroundColor: HEADER_BG,
                color: HEADER_TEXT,
                zIndex: 5,
                top: 28,
                position: 'sticky',
                fontWeight: 700,
              }}>
                Product
              </th>
              {columns.map((col, ci) => (
                <th
                  key={col.product.id}
                  style={{
                    width: COL_WIDTH,
                    minWidth: COL_WIDTH,
                    maxWidth: COL_WIDTH,
                    padding: '4px 4px',
                    fontSize: 10,
                    fontWeight: 600,
                    backgroundColor: col.hasChanges ? CHANGED_BG : '#e8eaf6',
                    textAlign: 'center',
                    borderRight: '1px solid #c5cae9',
                    borderBottom: '2px solid #3f51b5',
                    lineHeight: 1.2,
                    position: 'sticky',
                    top: 28,
                    zIndex: 3,
                    // Thick border at category boundary (normalized so duplicate-looking categories merge)
                    ...(ci > 0 && normalizeCategory(columns[ci - 1].product.category || '') !== normalizeCategory(col.product.category || '')
                      ? { borderLeft: '2px solid #0d47a1' }
                      : {}),
                  }}
                  title={col.product.name}
                >
                  {col.product.name_chinese || col.product.name}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rowDefs.map((row) => {
              if (row.type === 'header') {
                return (
                  <tr key={row.key}>
                    <td
                      style={{
                        ...labelStyle,
                        padding: '8px 8px',
                        fontSize: 12,
                        fontWeight: 700,
                        backgroundColor: SECTION_BG,
                        color: '#1565c0',
                        borderBottom: '2px solid #1565c0',
                        zIndex: 3,
                      }}
                    >
                      {row.label}
                    </td>
                    {columns.map((col) => (
                      <td
                        key={col.product.id}
                        style={{
                          backgroundColor: SECTION_BG,
                          borderBottom: '2px solid #1565c0',
                        }}
                      />
                    ))}
                  </tr>
                );
              }

              const isWholesale = row.key === 'wholesale_cost_gbp';

              return (
                <tr key={row.key}>
                  <td style={{
                    ...labelStyle,
                    fontWeight: isWholesale ? 700 : 500,
                    backgroundColor: isWholesale ? WHOLESALE_BG : labelStyle.backgroundColor,
                  }}>
                    {row.label}
                  </td>
                  {columns.map((col, ci) => {
                    const bg = col.hasChanges
                      ? CHANGED_BG
                      : isWholesale ? WHOLESALE_BG
                      : row.type === 'calculated' ? CALC_BG : INPUT_BG;

                    if (row.type === 'input' && row.field) {
                      return (
                        <td key={col.product.id} style={cellStyle(bg)}>
                          <input
                            type="number"
                            value={col.inputs[row.field] || ''}
                            onChange={(e) => handleInputChange(ci, row.field!, e.target.value)}
                            step={row.step}
                            className="v2-num-input"
                            style={numberInputStyle}
                          />
                        </td>
                      );
                    }

                    if (row.type === 'calculated' && row.calcField) {
                      const val = col.calc[row.calcField] as number;
                      return (
                        <td
                          key={col.product.id}
                          style={{ ...cellStyle(bg, isWholesale), color: isWholesale ? '#1b5e20' : undefined }}
                        >
                          {fmt(val, row.format)}
                        </td>
                      );
                    }

                    if (row.type === 'sector_input' && row.sectorId) {
                      return (
                        <td key={col.product.id} style={cellStyle(bg)}>
                          <input
                            type="number"
                            value={col.sectorPrices.get(row.sectorId!) || ''}
                            onChange={(e) => handleSectorPriceChange(ci, row.sectorId!, e.target.value)}
                            step="0.01"
                            className="v2-num-input"
                            style={numberInputStyle}
                          />
                        </td>
                      );
                    }

                    return <td key={col.product.id} style={cellStyle(bg)}>-</td>;
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
      </Paper>
    </>
  );
}
