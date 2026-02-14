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
  Chip,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Alert,
  Checkbox,
  ListItemText,
  OutlinedInput,
  Button,
} from '@mui/material';
import PrintIcon from '@mui/icons-material/Print';
import { stocktakeAPI, userActivityAPI, usersAPI, storesAPI } from '../services/api';
import type { StocktakeDayStartRecord, User, Store } from '../types';

function safeFormatDate(d: string | undefined): string {
  if (!d || typeof d !== 'string' || d.length < 10) return '—';
  const parsed = new Date(d + 'T12:00:00');
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed.toLocaleDateString(undefined, {
    weekday: 'short',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function formatTime(iso: string): string {
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed.toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

export default function StocktakeTimetablePage() {
  const [records, setRecords] = useState<StocktakeDayStartRecord[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [from, setFrom] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() - 13);
    return d.toISOString().slice(0, 10);
  });
  const [to, setTo] = useState(() => new Date().toISOString().slice(0, 10));
  const [userId, setUserId] = useState<number | ''>('');
  const [storeIds, setStoreIds] = useState<number[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [printing, setPrinting] = useState(false);

  const fetchUsers = async () => {
    try {
      const data = await usersAPI.list();
      setUsers(data);
    } catch (_) {}
  };

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list();
      setStores(data);
    } catch (_) {}
  };

  const fetchRecords = async () => {
    try {
      setLoading(true);
      setError(null);
      const params: { from?: string; to?: string; user_id?: number; store_ids?: number[] } = { from, to };
      if (userId !== '') params.user_id = userId;
      if (storeIds.length > 0) params.store_ids = storeIds;
      const data = await stocktakeAPI.listDayStart(params);
      setRecords(data);
    } catch (e: any) {
      setError(e?.response?.data?.error || 'Failed to load stocktake');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchUsers();
    fetchStores();
  }, []);

  useEffect(() => {
    fetchRecords();
  }, [from, to, userId, storeIds]);

  const handlePrint = async () => {
    setPrinting(true);
    try {
      const params: { from: string; to: string; user_id?: number; store_ids?: number[] } = { from, to };
      if (userId !== '') params.user_id = userId;
      if (storeIds.length > 0) params.store_ids = storeIds;
      const activityEvents = await userActivityAPI.list({
        ...params,
        event_type: ['logout', 'stocktake_day_end_skipped'],
      });
      const dayEndEvents = activityEvents.sort(
        (a, b) => a.occurred_at.localeCompare(b.occurred_at)
      );

      const formatDateOnly = (iso: string) => {
        const d = iso.slice(0, 10);
        const parsed = new Date(d + 'T12:00:00');
        return Number.isNaN(parsed.getTime()) ? d : parsed.toLocaleDateString();
      };
      const formatDateTime = (iso: string) => {
        const parsed = new Date(iso);
        return Number.isNaN(parsed.getTime())
          ? iso
          : parsed.toLocaleString(undefined, {
              dateStyle: 'short',
              timeStyle: 'medium',
            });
      };

      const dayStartRows = records
        .map(
          (r) =>
            `<tr><td>${safeFormatDate(r.date)}</td><td>${r.store?.name ?? '—'}</td><td>${r.user ? `${r.user.first_name} ${r.user.last_name}` : `User #${r.user_id}`}</td><td>${formatTime(r.first_login_at)}</td><td>${r.status === 'done' && r.done_at ? `Done at ${formatTime(r.done_at)}` : r.status === 'skipped' ? (r.skip_reason ? `Skipped: ${r.skip_reason}` : 'Skipped') : 'Pending'}</td></tr>`
        )
        .join('');
      const dayEndRows = dayEndEvents
        .map(
          (e) =>
            `<tr><td>${formatDateTime(e.occurred_at)}</td><td>${e.user ? `${e.user.first_name} ${e.user.last_name}` : `User #${e.user_id}`}</td><td>${e.store?.name ?? '—'}</td><td>${e.event_type === 'logout' ? 'Logout' : 'Day-end stocktake skipped'}</td><td>${e.event_type === 'stocktake_day_end_skipped' && e.skip_reason ? e.skip_reason : '—'}</td></tr>`
        )
        .join('');

      const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Stocktake Records ${from} to ${to}</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 16px; color: #111; }
    h1 { font-size: 1.25rem; margin-bottom: 4px; }
    .meta { color: #666; font-size: 0.875rem; margin-bottom: 16px; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
    th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
    th { background: #f5f5f5; font-weight: 600; }
    h2 { font-size: 1rem; margin: 16px 0 8px; }
  </style>
</head>
<body>
  <h1>Stocktake Records</h1>
  <p class="meta">Date range: ${safeFormatDate(from)} to ${safeFormatDate(to)} · Printed ${new Date().toLocaleString()}</p>
  <h2>Day-start stocktake</h2>
  <table>
    <thead><tr><th>Date</th><th>Store</th><th>User</th><th>First login</th><th>Result</th></tr></thead>
    <tbody>${dayStartRows || '<tr><td colspan="5">No records</td></tr>'}</tbody>
  </table>
  <h2>Day-end / Logout</h2>
  <table>
    <thead><tr><th>Date & time</th><th>User</th><th>Store</th><th>Event</th><th>Remark</th></tr></thead>
    <tbody>${dayEndRows || '<tr><td colspan="5">No events</td></tr>'}</tbody>
  </table>
  <p style="margin-top: 24px;"><button onclick="window.print()">Print</button> <button onclick="window.close()">Close</button></p>
</body>
</html>`;
      const win = window.open('', '_blank');
      if (!win) {
        alert('Pop-up was blocked. Please allow pop-ups for this site and try again.');
        return;
      }
      win.document.write(html);
      win.document.close();
      win.focus();
      // Delay print so the document is rendered (avoids blank page); leave window open so user can print/save PDF
      setTimeout(() => {
        win.print();
      }, 250);
    } catch (e) {
      console.error('Print failed', e);
    } finally {
      setPrinting(false);
    }
  };

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 2 }}>
        Stocktake
      </Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Day-start stocktake records (first login and result per user per store).
      </Typography>

      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center', mb: 2 }}>
        <TextField
          label="From"
          type="date"
          value={from}
          onChange={(e) => setFrom(e.target.value)}
          InputLabelProps={{ shrink: true }}
          size="small"
        />
        <TextField
          label="To"
          type="date"
          value={to}
          onChange={(e) => setTo(e.target.value)}
          InputLabelProps={{ shrink: true }}
          size="small"
        />
        <FormControl size="small" sx={{ minWidth: 180 }}>
          <InputLabel>User</InputLabel>
          <Select
            value={userId}
            label="User"
            onChange={(e) => setUserId(e.target.value === '' ? '' : Number(e.target.value))}
          >
            <MenuItem value="">All users</MenuItem>
            {users.map((u) => (
              <MenuItem key={u.id} value={u.id}>
                {u.first_name} {u.last_name} ({u.username})
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        <FormControl size="small" sx={{ minWidth: 220 }}>
          <InputLabel>Stores</InputLabel>
          <Select
            multiple
            value={storeIds}
            label="Stores"
            onChange={(e) => setStoreIds(Array.isArray(e.target.value) ? e.target.value : [])}
            input={<OutlinedInput label="Stores" />}
            renderValue={(selected) =>
              selected.length === 0
                ? 'All stores'
                : selected
                    .map((id) => stores.find((s) => s.id === id)?.name ?? id)
                    .join(', ')
            }
          >
            {stores.map((store) => (
              <MenuItem key={store.id} value={store.id}>
                <Checkbox checked={storeIds.indexOf(store.id) > -1} size="small" sx={{ mr: 1 }} />
                <ListItemText primary={store.name} />
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
          {printing ? 'Preparing…' : 'Print date start / date end stock record'}
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
                <TableCell>Date</TableCell>
                <TableCell>Store</TableCell>
                <TableCell>User</TableCell>
                <TableCell>First login</TableCell>
                <TableCell>Result</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {records.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={5} align="center" sx={{ py: 3 }}>
                    No records in this range.
                  </TableCell>
                </TableRow>
              ) : (
                records.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell>{safeFormatDate(r.date)}</TableCell>
                    <TableCell>{r.store?.name ?? '—'}</TableCell>
                    <TableCell>
                      {r.user
                        ? `${r.user.first_name} ${r.user.last_name} (${r.user.username})`
                        : `User #${r.user_id}`}
                    </TableCell>
                    <TableCell>{formatTime(r.first_login_at)}</TableCell>
                    <TableCell>
                      {r.status === 'done' && r.done_at && (
                        <Chip size="small" color="success" label={`Done at ${formatTime(r.done_at)}`} />
                      )}
                      {r.status === 'skipped' && (
                        <Chip
                          size="small"
                          color="warning"
                          label={r.skip_reason ? `Skipped: ${r.skip_reason}` : 'Skipped'}
                        />
                      )}
                      {r.status === 'pending' && <Chip size="small" label="Pending" />}
                    </TableCell>
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
