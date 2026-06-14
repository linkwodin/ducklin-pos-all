import { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Checkbox,
  CircularProgress,
  FormControl,
  InputLabel,
  MenuItem,
  OutlinedInput,
  Paper,
  Select,
  SelectChangeEvent,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
  ListItemText,
} from '@mui/material';
import DownloadIcon from '@mui/icons-material/Download';
import SearchIcon from '@mui/icons-material/Search';
import { useTranslation } from 'react-i18next';
import { ordersAPI, reportsAPI, storesAPI } from '../services/api';
import type { Store } from '../types';

type ProductSalesRow = {
  product_id: number;
  product_name: string;
  product_name_chinese: string;
  quantity: number;
  revenue: number;
};

type ClientSalesRow = {
  client_id: number;
  client_name: string;
  revenue: number;
};

function toISODate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function formatGBP(n: number): string {
  if (!Number.isFinite(n)) return '£0.00';
  return `£${n.toFixed(2)}`;
}

function formatQty(n: unknown): string {
  const v = typeof n === 'number' ? n : Number(n);
  if (!Number.isFinite(v)) return '0.000';
  return v.toFixed(3);
}

function csvEscape(value: unknown): string {
  const s = String(value ?? '');
  // Escape double quotes by doubling them.
  return `"${s.replace(/"/g, '""')}"`;
}

export default function ReportsPage() {
  const { t } = useTranslation();

  const [stores, setStores] = useState<Store[]>([]);
  const [selectedStoreIds, setSelectedStoreIds] = useState<number[]>([]);

  const defaultEnd = useMemo(() => new Date(), []);
  const defaultStart = useMemo(() => {
    const d = new Date();
    d.setMonth(d.getMonth() - 1);
    return d;
  }, []);

  const [startDate, setStartDate] = useState<string>(() => toISODate(defaultStart));
  const [endDate, setEndDate] = useState<string>(() => toISODate(defaultEnd));

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasSearched, setHasSearched] = useState(false);

  const [posTotalRevenue, setPosTotalRevenue] = useState(0);
  const [posProductsSales, setPosProductsSales] = useState<ProductSalesRow[]>([]);

  const [wholesaleTotalRevenue, setWholesaleTotalRevenue] = useState(0);
  const [wholesaleProductsSales, setWholesaleProductsSales] = useState<ProductSalesRow[]>([]);
  const [wholesaleClientsSales, setWholesaleClientsSales] = useState<ClientSalesRow[]>([]);

  const posProductsTotalRevenue = useMemo(
    () => posProductsSales.reduce((sum, r) => sum + (r.revenue ?? 0), 0),
    [posProductsSales],
  );
  const wholesaleProductsTotalRevenue = useMemo(
    () => wholesaleProductsSales.reduce((sum, r) => sum + (r.revenue ?? 0), 0),
    [wholesaleProductsSales],
  );

  const selectedStoresLabel = useMemo(() => {
    if (stores.length === 0) return '';
    if (selectedStoreIds.length === stores.length) return t('dashboard.allStores');
    const names = stores.filter((s) => selectedStoreIds.includes(s.id)).map((s) => s.name);
    return names.join(', ');
  }, [stores, selectedStoreIds, t]);

  const fetchStores = async () => {
    const data = await storesAPI.list({ exclude_warehouse_only: true });
    setStores(data);
    // default: no store selected => no store filter
    setSelectedStoreIds([]);
  };

  useEffect(() => {
    fetchStores().catch((e) => {
      console.error('Failed to fetch stores:', e);
      setError('Failed to load stores');
    });
  }, []);

  const handleStoreChange = (e: SelectChangeEvent<unknown>) => {
    const value = e.target.value;
    setSelectedStoreIds(
      typeof value === 'string' ? value.split(',').map((v) => Number(v)) : (value as number[]),
    );
  };

  const runReport = async () => {
    setLoading(true);
    setError(null);
    setHasSearched(true);

    try {
      // ---- POS totals ----
      const posFilter = selectedStoreIds.length > 0 ? { store_ids: selectedStoreIds } : undefined;
      const [revRows, prodRows] = await Promise.all([
        ordersAPI.getDailyRevenueStats({ start_date: startDate, end_date: endDate, ...posFilter }),
        ordersAPI.getDailyProductSalesStats({ start_date: startDate, end_date: endDate, ...posFilter }),
      ]);

      setPosTotalRevenue(revRows.reduce((sum, r) => sum + (r.revenue ?? 0), 0));
      const byProduct = new Map<number, ProductSalesRow>();
      prodRows.forEach((r) => {
        const existing = byProduct.get(r.product_id);
        if (!existing) {
          byProduct.set(r.product_id, { ...r, quantity: r.quantity ?? 0, revenue: r.revenue ?? 0 });
          return;
        }
        existing.quantity += r.quantity ?? 0;
        existing.revenue += r.revenue ?? 0;
      });
      setPosProductsSales(Array.from(byProduct.values()).sort((a, b) => b.revenue - a.revenue));

      // ---- Wholesale totals ----
      // We compute total wholesale revenue from the client breakdown (it includes shipping fees).
      const wholesaleFilter = selectedStoreIds.length > 0 ? { store_ids: selectedStoreIds } : undefined;
      const [whProdRows, whClientRows] = await Promise.all([
        reportsAPI.getWholesaleProductSales({ start_date: startDate, end_date: endDate, ...(wholesaleFilter ?? {}) }),
        reportsAPI.getWholesaleClientSales({ start_date: startDate, end_date: endDate, ...(wholesaleFilter ?? {}) }),
      ]);

      setWholesaleProductsSales(whProdRows);
      setWholesaleClientsSales(whClientRows);
      setWholesaleTotalRevenue(whClientRows.reduce((sum, r) => sum + (r.revenue ?? 0), 0));
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || 'Failed to load report');
    } finally {
      setLoading(false);
    }
  };

  const exportTableCSV = (type: 'posProducts' | 'wholesaleProducts' | 'wholesaleClients') => {
    const dateLabel = `${startDate}..${endDate}`;
    const storeLabel = selectedStoresLabel || 'All stores';

    const lines: string[] = [];

    if (type === 'posProducts') {
      lines.push(['Type', 'Product ID', 'Product Name', 'Product Name (Chinese)', 'Quantity', 'Revenue'].map(csvEscape).join(','));
      posProductsSales.forEach((r) => {
        lines.push(['POS', r.product_id, r.product_name, r.product_name_chinese, r.quantity, r.revenue].map(csvEscape).join(','));
      });
    } else if (type === 'wholesaleProducts') {
      lines.push(['Type', 'Product ID', 'Product Name', 'Product Name (Chinese)', 'Quantity', 'Revenue'].map(csvEscape).join(','));
      wholesaleProductsSales.forEach((r) => {
        lines.push(['Wholesale', r.product_id, r.product_name, r.product_name_chinese, r.quantity, r.revenue].map(csvEscape).join(','));
      });
    } else {
      lines.push(['Type', 'Client ID', 'Client Name', 'Revenue'].map(csvEscape).join(','));
      wholesaleClientsSales.forEach((r) => {
        lines.push(['Wholesale', r.client_id, r.client_name, r.revenue].map(csvEscape).join(','));
      });
    }

    const csv = lines.join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `report_${type}_${startDate}_to_${endDate}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  };

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 2 }}>
        {t('report.title')}
      </Typography>

      <Paper sx={{ p: 2, mb: 2 }}>
        <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
          <TextField
            label={t('dashboard.dateFrom')}
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            InputLabelProps={{ shrink: true }}
            size="small"
          />
          <TextField
            label={t('dashboard.dateTo')}
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            InputLabelProps={{ shrink: true }}
            size="small"
          />

          <FormControl size="small" sx={{ minWidth: 260 }}>
            <InputLabel>{t('dashboard.filterByStore')}</InputLabel>
            <Select
              multiple
              value={selectedStoreIds}
              onChange={handleStoreChange}
              input={<OutlinedInput label={t('dashboard.filterByStore')} />}
              renderValue={() => selectedStoresLabel || t('dashboard.allStores')}
            >
              {stores.map((s) => (
                <MenuItem key={s.id} value={s.id}>
                  <Checkbox checked={selectedStoreIds.indexOf(s.id) > -1} />
                  <ListItemText primary={s.name} />
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <Box sx={{ flexGrow: 1 }} />

          <Button
            variant="contained"
            startIcon={<SearchIcon />}
            onClick={runReport}
            disabled={loading || stores.length === 0}
          >
            {t('common.search')}
          </Button>
        </Box>
      </Paper>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {loading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', my: 3 }}>
          <CircularProgress />
        </Box>
      )}

      {!loading && hasSearched && (
        <>
          <Paper sx={{ p: 2, mb: 2 }}>
            <Typography variant="subtitle1" sx={{ mb: 1 }}>
              {t('report.totals')}
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {`POS: ${formatGBP(posTotalRevenue)} • POS products: ${formatGBP(posProductsTotalRevenue)}`}
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {`Wholesale: ${formatGBP(wholesaleTotalRevenue)} • Wholesale products: ${formatGBP(wholesaleProductsTotalRevenue)} • Wholesale clients: ${formatGBP(wholesaleTotalRevenue)}`}
            </Typography>
          </Paper>

          <TableContainer component={Paper} sx={{ mb: 2 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', px: 2, py: 1 }}>
              <Typography variant="h6">
                {t('report.posSalesByProducts')}
              </Typography>
              <Button
                variant="outlined"
                size="small"
                startIcon={<DownloadIcon />}
                onClick={() => exportTableCSV('posProducts')}
                disabled={loading || posProductsSales.length === 0}
              >
                {t('common.export')}
              </Button>
            </Box>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>{t('products.productName')}</TableCell>
                  <TableCell>{t('products.productNameChinese')}</TableCell>
                  <TableCell align="right">{t('common.quantity')}</TableCell>
                  <TableCell align="right">{t('dashboard.revenue')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {posProductsSales.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4}>{t('common.noData')}</TableCell>
                  </TableRow>
                ) : (
                  posProductsSales.map((r) => (
                    <TableRow key={`pos-${r.product_id}`}>
                      <TableCell>{r.product_name}</TableCell>
                      <TableCell>{r.product_name_chinese}</TableCell>
                      <TableCell align="right">{formatQty(r.quantity)}</TableCell>
                      <TableCell align="right">{formatGBP(r.revenue)}</TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </TableContainer>

          <TableContainer component={Paper} sx={{ mb: 2 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', px: 2, py: 1 }}>
              <Typography variant="h6">
                {t('report.wholesaleSalesByProducts')}
              </Typography>
              <Button
                variant="outlined"
                size="small"
                startIcon={<DownloadIcon />}
                onClick={() => exportTableCSV('wholesaleProducts')}
                disabled={loading || wholesaleProductsSales.length === 0}
              >
                {t('common.export')}
              </Button>
            </Box>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>{t('products.productName')}</TableCell>
                  <TableCell>{t('products.productNameChinese')}</TableCell>
                  <TableCell align="right">{t('common.quantity')}</TableCell>
                  <TableCell align="right">{t('dashboard.revenue')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {wholesaleProductsSales.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4}>{t('common.noData')}</TableCell>
                  </TableRow>
                ) : (
                  wholesaleProductsSales.map((r) => (
                    <TableRow key={`wh-${r.product_id}`}>
                      <TableCell>{r.product_name}</TableCell>
                      <TableCell>{r.product_name_chinese}</TableCell>
                      <TableCell align="right">{formatQty(r.quantity)}</TableCell>
                      <TableCell align="right">{formatGBP(r.revenue)}</TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </TableContainer>

          <TableContainer component={Paper}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', px: 2, py: 1 }}>
              <Typography variant="h6">
                {t('report.wholesaleSalesByClient')}
              </Typography>
              <Button
                variant="outlined"
                size="small"
                startIcon={<DownloadIcon />}
                onClick={() => exportTableCSV('wholesaleClients')}
                disabled={loading || wholesaleClientsSales.length === 0}
              >
                {t('common.export')}
              </Button>
            </Box>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>{t('common.name')}</TableCell>
                  <TableCell align="right">{t('dashboard.revenue')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {wholesaleClientsSales.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={2}>{t('common.noData')}</TableCell>
                  </TableRow>
                ) : (
                  wholesaleClientsSales.map((r) => (
                    <TableRow key={`client-${r.client_id}`}>
                      <TableCell>{r.client_name}</TableCell>
                      <TableCell align="right">{formatGBP(r.revenue)}</TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </TableContainer>
        </>
      )}
    </Box>
  );
}

