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
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Alert,
  Button,
} from '@mui/material';
import PrintIcon from '@mui/icons-material/Print';
import { stockAPI, storesAPI } from '../services/api';
import type { StockReportRow, Store } from '../types';

function formatQty(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(3);
}

export default function StockReportPage() {
  const [rows, setRows] = useState<StockReportRow[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [storeId, setStoreId] = useState<number | ''>('');
  const [printing, setPrinting] = useState(false);

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list();
      setStores(data);
    } catch (_) {}
  };

  const fetchReport = async () => {
    if (!date) return;
    setLoading(true);
    setError(null);
    try {
      const data = await stockAPI.getStockReport({
        date,
        store_id: storeId === '' ? undefined : storeId,
      });
      setRows(data);
    } catch (e: any) {
      setError(e?.response?.data?.error || 'Failed to load stock report');
      setRows([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStores();
  }, []);

  useEffect(() => {
    fetchReport();
  }, [date, storeId]);

  const handlePrint = () => {
    setPrinting(true);
    const storeLabel = storeId === '' ? 'All stores' : stores.find((s) => s.id === storeId)?.name ?? `Store ${storeId}`;
    const tableRows =
      rows.length === 0
        ? '<tr><td colspan="4">No data for this date</td></tr>'
        : rows
            .map(
              (r) =>
                `<tr><td>${r.product_name}</td><td>${r.store_name}</td><td>${formatQty(r.day_start_quantity)}</td><td>${formatQty(r.day_end_quantity)}</td></tr>`
            )
            .join('');
    const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Stock report ${date}</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 16px; color: #111; }
    h1 { font-size: 1.25rem; margin-bottom: 4px; }
    .meta { color: #666; font-size: 0.875rem; margin-bottom: 16px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
    th { background: #f5f5f5; font-weight: 600; }
  </style>
</head>
<body>
  <h1>Stock report</h1>
  <p class="meta">Date: ${date} · ${storeLabel} · Printed ${new Date().toLocaleString()}</p>
  <table>
    <thead><tr><th>Product</th><th>Store</th><th>Day start</th><th>Day end</th></tr></thead>
    <tbody>${tableRows}</tbody>
  </table>
  <p style="margin-top: 24px;"><button onclick="window.print()">Print</button> <button onclick="window.close()">Close</button></p>
</body>
</html>`;
    const win = window.open('', '_blank');
    if (!win) {
      alert('Pop-up was blocked. Please allow pop-ups and try again.');
      setPrinting(false);
      return;
    }
    win.document.write(html);
    win.document.close();
    win.focus();
    setTimeout(() => {
      win.print();
      setPrinting(false);
    }, 250);
  };

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 2 }}>
        Stock report
      </Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Day start and day end quantities per product from stocktake audit (select date and optional store).
      </Typography>

      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center', mb: 2 }}>
        <TextField
          label="Date"
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          InputLabelProps={{ shrink: true }}
          size="small"
        />
        <FormControl size="small" sx={{ minWidth: 200 }}>
          <InputLabel>Store</InputLabel>
          <Select
            value={storeId}
            label="Store"
            onChange={(e) => setStoreId(e.target.value === '' ? '' : Number(e.target.value))}
          >
            <MenuItem value="">All stores</MenuItem>
            {stores.map((s) => (
              <MenuItem key={s.id} value={s.id}>
                {s.name}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        <Button
          variant="outlined"
          startIcon={<PrintIcon />}
          onClick={handlePrint}
          disabled={loading || printing}
        >
          {printing ? 'Preparing…' : 'Print'}
        </Button>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
          <CircularProgress />
        </Box>
      ) : (
        <TableContainer component={Paper}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Product</TableCell>
                <TableCell>Store</TableCell>
                <TableCell>Day start</TableCell>
                <TableCell>Day end</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {rows.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={4} align="center" sx={{ py: 3 }}>
                    No stocktake data for this date. Day start / day end come from completed stocktakes.
                  </TableCell>
                </TableRow>
              ) : (
                rows.map((r, idx) => (
                  <TableRow key={`${r.product_id}-${r.store_id}-${idx}`}>
                    <TableCell>{r.product_name}</TableCell>
                    <TableCell>{r.store_name}</TableCell>
                    <TableCell>{formatQty(r.day_start_quantity)}</TableCell>
                    <TableCell>{formatQty(r.day_end_quantity)}</TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Box>
  );
}
