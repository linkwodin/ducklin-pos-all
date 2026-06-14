import { useEffect, useMemo, useState } from 'react';
import {
  Box,
  Button,
  CircularProgress,
  FormControl,
  InputLabel,
  MenuItem,
  Paper,
  Select,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from '@mui/material';
import { Print as PrintIcon } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import BarcodeSvg from '../components/BarcodeSvg';
import { productsAPI } from '../services/api';
import type { Product } from '../types';
import {
  categorySortKey,
  productBarcodeEntries,
  renderBarcodeSvg,
} from '../utils/barcodeImage';

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function sortProducts(a: Product, b: Product): number {
  const catCmp = categorySortKey(a.category).localeCompare(categorySortKey(b.category));
  if (catCmp !== 0) return catCmp;
  const en = (a.name || a.name_chinese || '').localeCompare(b.name || b.name_chinese || '');
  if (en !== 0) return en;
  return (a.name_chinese || '').localeCompare(b.name_chinese || '');
}

function categoryLabel(category: string | undefined, uncategorizedLabel: string): string {
  const trimmed = category?.trim();
  return trimmed || uncategorizedLabel;
}

const PRINT_CJK_FONT_LINKS = `
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;700&family=Noto+Sans+TC:wght@400;700&display=swap" rel="stylesheet">
`;

const PRINT_FONT_FAMILY =
  '"Noto Sans SC", "Noto Sans TC", "PingFang SC", "PingFang TC", "Heiti SC", "Microsoft YaHei", "SimHei", sans-serif';

const BARCODE_RENDER_OPTS = { uniformCode128: true, height: 42, fontSize: 11, width: 1.4 } as const;
const BARCODE_PRINT_OPTS = { uniformCode128: true, height: 36, fontSize: 10, width: 1.2 } as const;

async function printDocumentWhenReady(win: Window): Promise<void> {
  try {
    if (win.document.fonts) {
      await Promise.all([
        win.document.fonts.load('400 10pt "Noto Sans SC"'),
        win.document.fonts.load('400 10pt "Noto Sans TC"'),
      ]).catch(() => undefined);
      await win.document.fonts.ready;
    }
  } catch {
    // Fall back to system fonts if Font Loading API is unavailable.
  }
  await new Promise((resolve) => setTimeout(resolve, 400));
  win.print();
}

export default function ProductBarcodeReferencePage() {
  const { t } = useTranslation('productBarcodeReference');
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [printing, setPrinting] = useState(false);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const list = await productsAPI.list();
        if (!cancelled) setProducts(list.filter((p) => p.is_active !== false));
      } catch {
        if (!cancelled) setProducts([]);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const categories = useMemo(() => {
    const set = new Set<string>();
    for (const p of products) {
      const c = p.category?.trim();
      if (c) set.add(c);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [products]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return products
      .filter((p) => {
        if (category && (p.category ?? '') !== category) return false;
        if (!q) return true;
        const hay = [
          p.name,
          p.name_chinese,
          p.barcode,
          p.weight_barcode,
          p.sku,
          p.category,
        ]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();
        return hay.includes(q);
      })
      .sort(sortProducts);
  }, [products, search, category]);

  const barcodeKindLabel = (kind: 'qty' | 'weight') =>
    kind === 'qty' ? t('qtyBarcode') : t('weightBarcode');

  const renderBarcodeCellHtml = (product: Product): string => {
    const entries = productBarcodeEntries(product);
    if (!entries.length) return '—';
    return entries
      .map((entry) => {
        const svg = renderBarcodeSvg(entry.code, BARCODE_PRINT_OPTS);
        const label = escapeHtml(barcodeKindLabel(entry.kind));
        if (svg) {
          return `<div class="barcode-block"><div class="barcode-label">${label}</div>${svg}</div>`;
        }
        return `<div class="barcode-block"><div class="barcode-label">${label}</div><span class="mono">${escapeHtml(entry.code)}</span></div>`;
      })
      .join('');
  };

  const handlePrint = () => {
    setPrinting(true);
    const uncategorized = t('uncategorized');
    const rowsHtml =
      filtered.length === 0
        ? `<tr><td colspan="4">${escapeHtml(t('noProducts'))}</td></tr>`
        : filtered
            .map((p) => {
              return `<tr>
  <td>${escapeHtml(categoryLabel(p.category, uncategorized))}</td>
  <td>${escapeHtml(p.name || '—')}</td>
  <td>${escapeHtml(p.name_chinese || '—')}</td>
  <td class="barcode-cell">${renderBarcodeCellHtml(p)}</td>
</tr>`;
            })
            .join('');

    const html = `<!DOCTYPE html>
<html lang="zh-Hans">
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>${escapeHtml(t('printTitle'))}</title>
  ${PRINT_CJK_FONT_LINKS}
  <style>
    @page { margin: 10mm; }
    body, table, th, td, h1, p {
      font-family: ${PRINT_FONT_FAMILY};
    }
    body { padding: 0; color: #111; font-size: 10pt; }
    h1 { font-size: 16pt; margin: 0 0 4px; font-weight: 700; }
    .meta { color: #555; font-size: 9pt; margin-bottom: 12px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; vertical-align: top; }
    th { background: #eee; font-weight: 700; font-size: 8pt; }
    tr { break-inside: avoid; page-break-inside: avoid; }
    td.mono, .mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 9pt; }
    .barcode-cell { min-width: 200px; }
    .barcode-block { margin-bottom: 8px; }
    .barcode-block:last-child { margin-bottom: 0; }
    .barcode-label { font-size: 8pt; color: #555; margin-bottom: 2px; }
    .barcode-cell svg { max-width: 100%; height: auto; display: block; }
    @media print {
      .no-print { display: none !important; }
    }
  </style>
</head>
<body>
  <h1>${escapeHtml(t('printTitle'))}</h1>
  <p class="meta">${escapeHtml(t('printMeta', { count: filtered.length, date: new Date().toLocaleString() }))}</p>
  <table>
    <thead>
      <tr>
        <th style="width:14%">${escapeHtml(t('category'))}</th>
        <th style="width:22%">${escapeHtml(t('nameEnglish'))}</th>
        <th style="width:22%">${escapeHtml(t('nameChinese'))}</th>
        <th style="width:42%">${escapeHtml(t('barcode'))}</th>
      </tr>
    </thead>
    <tbody>${rowsHtml}</tbody>
  </table>
  <p class="no-print" style="margin-top: 20px;">
    <button onclick="window.print()">${escapeHtml(t('print'))}</button>
    <button onclick="window.close()">${escapeHtml(t('close'))}</button>
  </p>
</body>
</html>`;

    const win = window.open('', '_blank');
    if (!win) {
      alert(t('popupBlocked'));
      setPrinting(false);
      return;
    }
    win.document.write(html);
    win.document.close();
    win.focus();
    void printDocumentWhenReady(win).finally(() => setPrinting(false));
  };

  return (
    <Box sx={{ p: { xs: 2, md: 3 } }}>
      <Typography variant="h5" sx={{ mb: 1 }}>
        {t('title')}
      </Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {t('subtitle')}
      </Typography>

      <Paper sx={{ p: 2, mb: 2 }}>
        <Box
          sx={{
            display: 'flex',
            flexWrap: 'wrap',
            gap: 2,
            alignItems: 'center',
          }}
        >
          <TextField
            size="small"
            label={t('search')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            sx={{ minWidth: 220, flex: '1 1 220px' }}
          />
          <FormControl size="small" sx={{ minWidth: 180 }}>
            <InputLabel>{t('category')}</InputLabel>
            <Select
              label={t('category')}
              value={category}
              onChange={(e) => setCategory(e.target.value)}
            >
              <MenuItem value="">{t('allCategories')}</MenuItem>
              {categories.map((c) => (
                <MenuItem key={c} value={c}>
                  {c}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          <Typography variant="body2" color="text.secondary" sx={{ flex: '1 1 auto' }}>
            {t('showing', { count: filtered.length, total: products.length })}
          </Typography>
          <Button
            variant="contained"
            startIcon={<PrintIcon />}
            onClick={handlePrint}
            disabled={loading || printing || filtered.length === 0}
          >
            {printing ? t('preparing') : t('print')}
          </Button>
        </Box>
      </Paper>

      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      ) : (
        <TableContainer component={Paper}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>{t('category')}</TableCell>
                <TableCell>{t('nameEnglish')}</TableCell>
                <TableCell>{t('nameChinese')}</TableCell>
                <TableCell>{t('barcode')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {filtered.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={4} align="center">
                    {t('noProducts')}
                  </TableCell>
                </TableRow>
              ) : (
                filtered.map((p) => {
                  const entries = productBarcodeEntries(p);
                  return (
                    <TableRow key={p.id} hover>
                      <TableCell sx={{ whiteSpace: 'nowrap' }}>
                        {categoryLabel(p.category, t('uncategorized'))}
                      </TableCell>
                      <TableCell>{p.name || '—'}</TableCell>
                      <TableCell>{p.name_chinese || '—'}</TableCell>
                      <TableCell>
                        {entries.length === 0 ? (
                          '—'
                        ) : (
                          entries.map((entry) => (
                            <BarcodeSvg
                              key={`${p.id}-${entry.kind}-${entry.code}`}
                              value={entry.code}
                              label={barcodeKindLabel(entry.kind)}
                              renderOptions={BARCODE_RENDER_OPTS}
                            />
                          ))
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Box>
  );
}
