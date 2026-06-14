import { useEffect, useState, useRef, useMemo, type MouseEvent } from 'react';
import axios from 'axios';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Box,
  Paper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  Chip,
  Button,
  IconButton,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Fab,
  Autocomplete,
  useMediaQuery,
  Checkbox,
  ButtonGroup,
  Menu,
  Divider,
} from '@mui/material';
import { useTheme } from '@mui/material/styles';
import {
  Download as DownloadIcon,
  Refresh as RefreshIcon,
  Add as AddIcon,
  UnfoldMore as SortIcon,
  ArrowUpward as SortAscIcon,
  ArrowDownward as SortDescIcon,
  PictureAsPdf as PictureAsPdfIcon,
  Archive as ArchiveIcon,
  ArrowDropDown as ArrowDropDownIcon,
} from '@mui/icons-material';
import { wholesaleOrdersAPI, storesAPI, wholesaleClientsAPI, settingsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { WholesaleOrder, Store, WholesaleClient } from '../types';
import {
  downloadWholesaleOrdersSummaryPdf,
  buildWholesaleAttachmentZip,
  type BulkAttachmentKind,
} from '../utils/wholesaleOrdersBulkExport';
import {
  isWholesaleOrderCompleted,
  wholesaleOrderStatusColor,
  wholesaleOrderStatusLabel,
} from '../utils/wholesaleOrderEmail';
import { isWholesaleOrderPaymentConfirmationPhase, buildWholesaleOrderWorkflowContext } from '../utils/wholesaleOrderWorkflow';

/** Above this count, attachment ZIP is requested by email (server builds ZIP) instead of browser download. */
const BULK_ZIP_EMAIL_THRESHOLD = 10;
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import UserDisplay from '../components/UserDisplay';

type WholesalePendingExport = { kind: 'pdf' } | { kind: 'zip'; zipKind: BulkAttachmentKind };

function deliveryLocationNameForOrder(order: WholesaleOrder): string {
  const loc = order.wholesale_client_store?.name?.trim();
  if (loc) return loc;
  const clientName = order.wholesale_client?.name?.trim();
  if (clientName) return clientName;
  return '—';
}

function trackingNumbersForOrder(order: WholesaleOrder): string {
  const vals = (order.shipments ?? [])
    .map((s) => s.tracking_number?.trim())
    .filter((v): v is string => Boolean(v));
  if (!vals.length) return '—';
  return Array.from(new Set(vals)).join(', ');
}

function couriersForOrder(order: WholesaleOrder): string {
  const vals = (order.shipments ?? [])
    .map((s) => s.courier?.trim())
    .filter((v): v is string => Boolean(v));
  if (!vals.length) return '—';
  return Array.from(new Set(vals)).join(', ');
}

function csvCell(value: string): string {
  const normalized = value.replace(/\r?\n/g, ' ').trim();
  const escaped = normalized.replace(/"/g, '""');
  return /[",]/.test(escaped) ? `"${escaped}"` : escaped;
}

export default function WholesaleOrdersPage() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { t } = useTranslation();
  const [orders, setOrders] = useState<WholesaleOrder[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [clients, setClients] = useState<WholesaleClient[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [sortBy, setSortBy] = useState<'ref_no' | 'po_number' | 'total' | 'order_date'>('ref_no');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [clientFilter, setClientFilter] = useState<WholesaleClient | null>(null);
  const [deliveryLocationFilter, setDeliveryLocationFilter] = useState('');
  const [poNumberFilter, setPONumberFilter] = useState('');
  const [orderNumberFilter, setOrderNumberFilter] = useState('');
  const [refNoFilter, setRefNoFilter] = useState('');
  const [orderDateFrom, setOrderDateFrom] = useState('');
  const [orderDateTo, setOrderDateTo] = useState('');
  const [pageSize, setPageSize] = useState<number>(25);
  const [page, setPage] = useState<number>(0);
  const [selectedIds, setSelectedIds] = useState<number[]>([]);
  const [attachMenuAnchor, setAttachMenuAnchor] = useState<null | HTMLElement>(null);
  const [exportingZip, setExportingZip] = useState(false);
  const [pdfExporting, setPdfExporting] = useState(false);
  const [csvExporting, setCsvExporting] = useState(false);
  const [exportConfirmOpen, setExportConfirmOpen] = useState(false);
  const [zipRecipientEmail, setZipRecipientEmail] = useState('');
  const [zipEmailSubmitting, setZipEmailSubmitting] = useState(false);
  const selectAllInputRef = useRef<HTMLInputElement | null>(null);
  const attachMenuOpen = Boolean(attachMenuAnchor);
  const [pendingExport, setPendingExport] = useState<WholesalePendingExport | null>(null);
  const { enqueueSnackbar } = useSnackbar();
  const theme = useTheme();
  const isListMobile = useMediaQuery(theme.breakpoints.down('md'));

  const renderSortIcon = (column: 'ref_no' | 'po_number' | 'total' | 'order_date') => {
    const active = sortBy === column;
    if (!active) {
      return <SortIcon fontSize="small" sx={{ color: 'text.disabled' }} />;
    }
    if (sortDir === 'asc') {
      return <SortAscIcon fontSize="small" sx={{ color: 'text.primary' }} />;
    }
    return <SortDescIcon fontSize="small" sx={{ color: 'text.primary' }} />;
  };

  const fetchStores = async () => {
    try {
      const [storesData, clientsData] = await Promise.all([
        storesAPI.list(),
        wholesaleClientsAPI.list(),
      ]);
      setStores(storesData);
      setClients(clientsData);
    } catch {
      enqueueSnackbar('Failed to load data', { variant: 'error' });
    }
  };

  const fetchOrders = async () => {
    try {
      setPage(0);
      setLoading(true);
      const params: Record<string, string> = {};
      // UI has derived status filters that map to backend "approved".
      const statusForAPI =
        statusFilter === 'awaiting_payment' || statusFilter === 'completed'
          ? 'approved'
          : statusFilter;
      if (statusForAPI) params.status = statusForAPI;
      if (clientFilter) params.client = clientFilter.name;
      if (deliveryLocationFilter.trim()) params.delivery_location = deliveryLocationFilter.trim();
      if (poNumberFilter.trim()) params.po_number = poNumberFilter.trim();
      if (orderNumberFilter.trim()) params.order_number = orderNumberFilter.trim();
      if (refNoFilter.trim()) params.ref_no = refNoFilter.trim();
      if (orderDateFrom) params.order_date_from = orderDateFrom;
      if (orderDateTo) params.order_date_to = orderDateTo;
      params.sort_by = sortBy;
      params.sort_dir = sortDir;
      const data = await wholesaleOrdersAPI.list(params);

      let filtered = data;
      if (statusFilter === 'awaiting_payment') {
        filtered = data.filter((o) => isWholesaleOrderPaymentConfirmationPhase(o));
      } else if (statusFilter === 'completed') {
        filtered = data.filter((o) => isWholesaleOrderCompleted(o));
      }
      setSelectedIds([]);
      setOrders(filtered);
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Failed to load wholesale orders';
      enqueueSnackbar(msg, { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStores();
  }, []);

  // Initialize client filter from URL (persists across refresh)
  const clientIdFromUrl = searchParams.get('client_id');
  useEffect(() => {
    if (clients.length === 0 || !clientIdFromUrl) return;
    const id = Number(clientIdFromUrl);
    if (Number.isNaN(id)) return;
    const found = clients.find((c) => c.id === id);
    if (found) setClientFilter((prev) => (prev?.id === found.id ? prev : found));
  }, [clientIdFromUrl, clients]);

  // Keep URL in sync when client filter changes
  const setClientFilterAndUrl = (client: WholesaleClient | null) => {
    setClientFilter(client);
    const next = new URLSearchParams(searchParams);
    if (client) next.set('client_id', String(client.id));
    else next.delete('client_id');
    setSearchParams(next, { replace: true });
  };

  useEffect(() => {
    fetchOrders();
  }, [statusFilter, sortBy, sortDir, clientFilter, deliveryLocationFilter, poNumberFilter, orderNumberFilter, refNoFilter, orderDateFrom, orderDateTo]);

  const pageSizeOptions = [10, 25, 50, 100];
  const pageCount = Math.max(1, Math.ceil(orders.length / pageSize));
  const safePage = Math.min(page, pageCount - 1);
  const pagedOrders = orders.slice(safePage * pageSize, safePage * pageSize + pageSize);
  const deliveryLocationOptions = useMemo(
    () =>
      Array.from(
        new Set(
          (clientFilter ? clientFilter.stores ?? [] : clients.flatMap((c) => c.stores ?? []))
            .map((s) => s.name?.trim())
            .filter((name): name is string => Boolean(name)),
        ),
      ).sort((a, b) => a.localeCompare(b)),
    [clients, clientFilter],
  );
  /** Rows included in bulk PDF/ZIP: checked rows if any, otherwise the entire filtered list. */
  const ordersForBulkExport = useMemo(() => {
    if (selectedIds.length > 0) {
      const idSet = new Set(selectedIds);
      return orders.filter((o) => idSet.has(o.id));
    }
    return orders;
  }, [orders, selectedIds]);
  const pageIds = useMemo(() => pagedOrders.map((o) => o.id), [pagedOrders]);
  const pageAllSelected = pageIds.length > 0 && pageIds.every((id) => selectedIds.includes(id));
  const pageSomeSelected = pageIds.some((id) => selectedIds.includes(id));

  useEffect(() => {
    const el = selectAllInputRef.current;
    if (el) el.indeterminate = pageSomeSelected && !pageAllSelected;
  }, [pageSomeSelected, pageAllSelected]);

  const toggleSelectAllPage = () => {
    if (pageAllSelected) {
      setSelectedIds((prev) => prev.filter((id) => !pageIds.includes(id)));
    } else {
      setSelectedIds((prev) => [...new Set([...prev, ...pageIds])]);
    }
  };

  const toggleRowSelected = (id: number) => {
    setSelectedIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  const openOrderDetail = (order: WholesaleOrder) => {
    navigate(`/wholesale-orders/${order.id}`);
  };

  const stopRowClick = (e: MouseEvent) => {
    e.stopPropagation();
  };

  const totalForOrder = (order: WholesaleOrder) =>
    (order.total_net ?? order.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0) + (Number(order.shipping_fee) || 0);

  const executeExportPdf = async (exportOrders: WholesaleOrder[]) => {
    if (!exportOrders.length) return;
    setPdfExporting(true);
    try {
      const statusFilterLabel = (): string => {
        if (statusFilter === '') return t('wholesaleOrdersPage.filterAll');
        if (statusFilter === 'awaiting_payment') return t('wholesaleOrderDetail.statusAwaitingPayment');
        if (statusFilter === 'completed') return t('wholesaleOrderDetail.statusCompleted');
        switch (statusFilter) {
          case 'pending_approval':
            return t('wholesaleOrdersPage.statusPendingApproval');
          case 'assign_shipment':
            return t('wholesaleOrdersPage.statusAssignShipment');
          case 'approved':
            return t('wholesaleOrdersPage.statusApproved');
          case 'rejected':
            return t('wholesaleOrdersPage.statusRejected');
          case 'deleted':
            return t('wholesaleOrdersPage.statusDeleted');
          default:
            return statusFilter;
        }
      };
      const sortColumnLabel =
        sortBy === 'ref_no'
          ? t('wholesaleOrdersPage.ocNumber')
          : sortBy === 'po_number'
            ? t('wholesaleOrdersPage.poNumber')
            : sortBy === 'total'
              ? t('wholesaleOrdersPage.total')
              : t('wholesaleOrdersPage.orderDate');
      const exportTotalAmount = exportOrders.reduce((sum, o) => sum + totalForOrder(o), 0);
      const pdfFilterLines: string[] = [
        `${t('wholesaleOrdersPage.filterStatus')}: ${statusFilterLabel()}`,
        ...(clientFilter ? [`${t('wholesaleOrdersPage.filterClient')}: ${clientFilter.name}`] : []),
        ...(deliveryLocationFilter.trim()
          ? [`${t('wholesaleOrdersPage.filterDeliveryLocation')}: ${deliveryLocationFilter.trim()}`]
          : []),
        ...(poNumberFilter.trim()
          ? [`${t('wholesaleOrdersPage.filterPONumber')}: ${poNumberFilter.trim()}`]
          : []),
        ...(orderNumberFilter.trim()
          ? [`${t('wholesaleOrdersPage.filterOrderNumber')}: ${orderNumberFilter.trim()}`]
          : []),
        ...(refNoFilter.trim()
          ? [`${t('wholesaleOrdersPage.filterOCNumber')}: ${refNoFilter.trim()}`]
          : []),
        ...(orderDateFrom ? [`${t('wholesaleOrdersPage.orderDate')}: ${orderDateFrom}`] : []),
        ...(orderDateTo ? [`${t('wholesaleOrdersPage.orderDateTo')}: ${orderDateTo}`] : []),
        `${t('wholesaleOrdersPage.pdfExportSort')}: ${sortColumnLabel} (${sortDir === 'asc' ? t('wholesaleOrdersPage.sortAsc') : t('wholesaleOrdersPage.sortDesc')})`,
        t('wholesaleOrdersPage.pdfExportRowCount', { count: exportOrders.length }),
        `${t('wholesaleOrdersPage.pdfExportTotalAmount')}: £${exportTotalAmount.toFixed(2)}`,
      ];

      const head = [
        t('wholesaleOrdersPage.ocNumber'),
        t('wholesaleOrdersPage.client'),
        t('wholesaleOrdersPage.deliveryLocation'),
        t('wholesaleOrdersPage.poNumber'),
        t('wholesaleOrdersPage.total'),
        t('wholesaleOrdersPage.orderDate'),
        t('wholesaleOrderDetail:courier'),
        t('wholesaleOrderDetail.trackingNumber'),
        t('wholesaleOrdersPage.status'),
      ];
      const rows = exportOrders.map((o) => {
        const orderDateIso = o.order_date || o.created_at;
        const orderDate = orderDateIso ? new Date(orderDateIso) : null;
        return [
          o.ref_no || '—',
          o.wholesale_client?.name ?? '',
          deliveryLocationNameForOrder(o),
          o.po_number || '—',
          `£${totalForOrder(o).toFixed(2)}`,
          orderDate ? format(orderDate, 'dd/MM/yyyy') : '—',
          couriersForOrder(o),
          trackingNumbersForOrder(o),
          wholesaleOrderStatusLabel(o, t, buildWholesaleOrderWorkflowContext(o)),
        ];
      });
      const companyRes = await settingsAPI.getCompany().catch(() => null);
      const companyName = companyRes?.company_name?.trim() ?? '';
      const reportSuffix = t('wholesaleOrdersPage.pdfWholesaleOrderReport');
      const reportHeadingLeft = companyName
        ? t('wholesaleOrdersPage.pdfReportHeadingWithCompany', { company: companyName, report: reportSuffix })
        : reportSuffix;
      const reportHeadingRight = format(new Date(), 'yyyy-MM-dd HH:mm:ss');
      await downloadWholesaleOrdersSummaryPdf({
        filterTitle: t('wholesaleOrdersPage.pdfExportFiltersTitle'),
        filterLines: pdfFilterLines,
        head,
        rows,
        filename: `wholesale-orders-${format(new Date(), 'yyyy-MM-dd-HHmm')}.pdf`,
        reportHeadingLeft,
        reportHeadingRight,
      });
    } catch {
      enqueueSnackbar(t('wholesaleOrdersPage.exportPdfError'), { variant: 'error' });
    } finally {
      setPdfExporting(false);
    }
  };

  const executeAttachmentZipByEmail = async (exportOrders: WholesaleOrder[], kind: BulkAttachmentKind, email: string) => {
    if (!exportOrders.length) return;
    setZipEmailSubmitting(true);
    try {
      const res = await wholesaleOrdersAPI.bulkAttachmentsZipEmail({
        order_ids: exportOrders.map((o) => o.id),
        kind,
        recipient_email: email.trim(),
      });
      enqueueSnackbar(t('wholesaleOrdersPage.exportZipEmailDone'), { variant: 'success' });
      if (res.download_url) {
        window.open(res.download_url, '_blank', 'noopener,noreferrer');
      }
    } catch (e: unknown) {
      if (axios.isAxiosError(e)) {
        const status = e.response?.status;
        const payload = e.response?.data as { error?: string; download_url?: string } | undefined;
        const serverErr = payload?.error;
        if (status === 503) {
          enqueueSnackbar(serverErr || t('wholesaleOrdersPage.exportZipEmailNotConfigured'), { variant: 'warning' });
        } else if (status === 502 && payload?.download_url) {
          enqueueSnackbar(
            `${serverErr || t('wholesaleOrdersPage.exportZipEmailSmtpFailed')} ${payload.download_url}`,
            { variant: 'warning', autoHideDuration: 25_000 },
          );
          window.open(payload.download_url, '_blank', 'noopener,noreferrer');
        } else {
          enqueueSnackbar(serverErr || t('wholesaleOrdersPage.exportZipError'), { variant: 'error' });
        }
      } else {
        enqueueSnackbar(t('wholesaleOrdersPage.exportZipError'), { variant: 'error' });
      }
    } finally {
      setZipEmailSubmitting(false);
    }
  };

  const executeAttachmentZip = async (exportOrders: WholesaleOrder[], kind: BulkAttachmentKind) => {
    if (!exportOrders.length) return;
    setExportingZip(true);
    try {
      const blob = await buildWholesaleAttachmentZip(exportOrders, kind, {
        downloadDocument: wholesaleOrdersAPI.downloadDocument,
        legacyPaymentProof: wholesaleOrdersAPI.downloadLegacyPaymentProof,
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `wholesale-attachments-${kind}-${format(new Date(), 'yyyy-MM-dd-HHmm')}.zip`;
      a.click();
      URL.revokeObjectURL(url);
      enqueueSnackbar(t('wholesaleOrdersPage.exportZipDone'), { variant: 'success' });
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'NO_FILES') {
        enqueueSnackbar(t('wholesaleOrdersPage.exportZipNoFiles'), { variant: 'warning' });
      } else if (axios.isAxiosError(e)) {
        const serverErr = (e.response?.data as { error?: string } | undefined)?.error;
        enqueueSnackbar(serverErr || t('wholesaleOrdersPage.exportZipError'), { variant: 'error' });
      } else {
        enqueueSnackbar(t('wholesaleOrdersPage.exportZipError'), { variant: 'error' });
      }
    } finally {
      setExportingZip(false);
    }
  };

  const executeExportCsv = async (exportOrders: WholesaleOrder[]) => {
    if (!exportOrders.length) return;
    setCsvExporting(true);
    try {
      const statusFilterLabel = (): string => {
        if (statusFilter === '') return t('wholesaleOrdersPage.filterAll');
        if (statusFilter === 'awaiting_payment') return t('wholesaleOrderDetail.statusAwaitingPayment');
        if (statusFilter === 'completed') return t('wholesaleOrderDetail.statusCompleted');
        switch (statusFilter) {
          case 'pending_approval':
            return t('wholesaleOrdersPage.statusPendingApproval');
          case 'assign_shipment':
            return t('wholesaleOrdersPage.statusAssignShipment');
          case 'approved':
            return t('wholesaleOrdersPage.statusApproved');
          case 'rejected':
            return t('wholesaleOrdersPage.statusRejected');
          case 'deleted':
            return t('wholesaleOrdersPage.statusDeleted');
          default:
            return statusFilter;
        }
      };
      const sortColumnLabel =
        sortBy === 'ref_no'
          ? t('wholesaleOrdersPage.ocNumber')
          : sortBy === 'po_number'
            ? t('wholesaleOrdersPage.poNumber')
            : sortBy === 'total'
              ? t('wholesaleOrdersPage.total')
              : t('wholesaleOrdersPage.orderDate');
      const filterPairs: [string, string][] = [
        [t('wholesaleOrdersPage.filterStatus'), statusFilterLabel()],
        [t('wholesaleOrdersPage.filterClient'), clientFilter?.name ?? t('wholesaleOrdersPage.filterAll')],
        [
          t('wholesaleOrdersPage.filterDeliveryLocation'),
          deliveryLocationFilter.trim() || t('wholesaleOrdersPage.filterAll'),
        ],
        [t('wholesaleOrdersPage.filterPONumber'), poNumberFilter.trim() || t('wholesaleOrdersPage.filterAll')],
        [t('wholesaleOrdersPage.filterOrderNumber'), orderNumberFilter.trim() || t('wholesaleOrdersPage.filterAll')],
        [t('wholesaleOrdersPage.filterOCNumber'), refNoFilter.trim() || t('wholesaleOrdersPage.filterAll')],
        [t('wholesaleOrdersPage.orderDate'), orderDateFrom || t('wholesaleOrdersPage.filterAll')],
        [t('wholesaleOrdersPage.orderDateTo'), orderDateTo || t('wholesaleOrdersPage.filterAll')],
        [
          t('wholesaleOrdersPage.pdfExportSort'),
          `${sortColumnLabel} (${sortDir === 'asc' ? t('wholesaleOrdersPage.sortAsc') : t('wholesaleOrdersPage.sortDesc')})`,
        ],
        [t('wholesaleOrdersPage.pdfExportRowCount'), String(exportOrders.length)],
      ];
      const head = [
        t('wholesaleOrdersPage.ocNumber'),
        t('wholesaleOrdersPage.client'),
        t('wholesaleOrdersPage.deliveryLocation'),
        t('wholesaleOrdersPage.poNumber'),
        t('wholesaleOrdersPage.total'),
        t('wholesaleOrdersPage.orderDate'),
        t('wholesaleOrderDetail:courier'),
        t('wholesaleOrderDetail.trackingNumber'),
        t('wholesaleOrdersPage.status'),
      ];
      const rows = exportOrders.map((o) => {
        const orderDateIso = o.order_date || o.created_at;
        const orderDate = orderDateIso ? format(new Date(orderDateIso), 'dd/MM/yyyy') : '—';
        return [
          o.ref_no || '—',
          o.wholesale_client?.name ?? '',
          deliveryLocationNameForOrder(o),
          o.po_number || '—',
          `${totalForOrder(o).toFixed(2)}`,
          orderDate,
          couriersForOrder(o),
          trackingNumbersForOrder(o),
          wholesaleOrderStatusLabel(o, t, buildWholesaleOrderWorkflowContext(o)),
        ];
      });
      const filterRows = [
        [t('wholesaleOrdersPage.pdfExportFiltersTitle')],
        filterPairs.map(([k]) => k),
        filterPairs.map(([, v]) => v),
        [],
      ];
      const csv = [...filterRows, head, ...rows].map((r) => r.map(csvCell).join(',')).join('\r\n');
      const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `wholesale-orders-${format(new Date(), 'yyyy-MM-dd-HHmm')}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      enqueueSnackbar(t('wholesaleOrdersPage.exportCsvDone'), { variant: 'success' });
    } catch {
      enqueueSnackbar(t('wholesaleOrdersPage.exportCsvError'), { variant: 'error' });
    } finally {
      setCsvExporting(false);
    }
  };

  const requestExportPdf = () => {
    if (loading || !orders.length) {
      enqueueSnackbar(t('wholesaleOrdersPage.exportNoOrders'), { variant: 'warning' });
      return;
    }
    if (!ordersForBulkExport.length) {
      enqueueSnackbar(t('wholesaleOrdersPage.exportNoOrders'), { variant: 'warning' });
      return;
    }
    setPendingExport({ kind: 'pdf' });
    setExportConfirmOpen(true);
  };

  const requestExportZip = (zipKind: BulkAttachmentKind) => {
    setAttachMenuAnchor(null);
    if (loading || !orders.length) {
      enqueueSnackbar(t('wholesaleOrdersPage.exportNoOrders'), { variant: 'warning' });
      return;
    }
    if (!ordersForBulkExport.length) {
      enqueueSnackbar(t('wholesaleOrdersPage.exportNoOrders'), { variant: 'warning' });
      return;
    }
    setPendingExport({ kind: 'zip', zipKind });
    setExportConfirmOpen(true);
  };

  const handleExportConfirm = () => {
    const toExport = ordersForBulkExport;
    if (!toExport.length || !pendingExport) {
      setExportConfirmOpen(false);
      setPendingExport(null);
      return;
    }
    const pe = pendingExport;
    if (pe.kind === 'zip' && toExport.length >= BULK_ZIP_EMAIL_THRESHOLD) {
      const em = zipRecipientEmail.trim();
      if (!em) {
        enqueueSnackbar(t('wholesaleOrdersPage.exportZipEmailRequired'), { variant: 'warning' });
        return;
      }
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(em)) {
        enqueueSnackbar(t('wholesaleOrdersPage.exportZipEmailInvalid'), { variant: 'warning' });
        return;
      }
      setExportConfirmOpen(false);
      setPendingExport(null);
      setZipRecipientEmail('');
      void executeAttachmentZipByEmail(toExport, pe.zipKind, em);
      return;
    }
    setExportConfirmOpen(false);
    setPendingExport(null);
    setZipRecipientEmail('');
    if (pe.kind === 'pdf') {
      void executeExportPdf(toExport);
    } else {
      void executeAttachmentZip(toExport, pe.zipKind);
    }
  };

  const totalAllFilteredOrders = orders.reduce((sum, o) => sum + totalForOrder(o), 0);
  const totalNonCompleteOrRejectedOrders = orders.reduce((sum, o) => {
    if (o.status === 'deleted') return sum;
    if (!isWholesaleOrderCompleted(o) || o.status === 'rejected') return sum + totalForOrder(o);
    return sum;
  }, 0);

  const attachmentKindMenuLabel = (k: BulkAttachmentKind): string => {
    switch (k) {
      case 'all':
        return t('wholesaleOrdersPage.attachAll');
      case 'order_confirmation':
        return t('wholesaleOrdersPage.attachOC');
      case 'po_attachment':
        return t('wholesaleOrdersPage.attachPO');
      case 'delivery_note':
        return t('wholesaleOrdersPage.attachDN');
      case 'signed_delivery_note':
        return t('wholesaleOrdersPage.attachSignedDn');
      case 'invoice':
        return t('wholesaleOrdersPage.attachInvoice');
      case 'payment_proof':
        return t('wholesaleOrdersPage.attachPaymentProof');
      default:
        return String(k);
    }
  };

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 }, position: 'relative' }}>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          mb: 3,
          flexWrap: 'wrap',
          gap: 1.5,
        }}
      >
        <Typography variant="h5" sx={{ typography: { xs: 'h6', md: 'h5' } }}>
          {t('nav.wholesaleOrders')}
        </Typography>
        <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap sx={{ justifyContent: 'flex-end' }}>
          <Tooltip title={t('wholesaleOrdersPage.exportTablePdf')}>
            <span>
              <Button
                variant="outlined"
                size="small"
                startIcon={pdfExporting ? <CircularProgress size={16} color="inherit" /> : <PictureAsPdfIcon />}
                onClick={requestExportPdf}
                disabled={!orders.length || loading || pdfExporting || exportingZip}
                sx={{ whiteSpace: 'nowrap' }}
              >
                {t('wholesaleOrdersPage.exportTablePdfButton')}
              </Button>
            </span>
          </Tooltip>
          <Tooltip title={t('wholesaleOrdersPage.exportTableCsv')}>
            <span>
              <Button
                variant="outlined"
                size="small"
                startIcon={csvExporting ? <CircularProgress size={16} color="inherit" /> : <DownloadIcon />}
                onClick={() => void executeExportCsv(ordersForBulkExport)}
                disabled={!orders.length || loading || csvExporting || pdfExporting || exportingZip}
                sx={{ whiteSpace: 'nowrap' }}
              >
                {t('wholesaleOrdersPage.exportTableCsvButton')}
              </Button>
            </span>
          </Tooltip>
          <ButtonGroup variant="outlined" size="small" disabled={!orders.length || loading || exportingZip}>
            <Button
              startIcon={exportingZip ? <CircularProgress size={16} /> : <ArchiveIcon />}
              onClick={() => requestExportZip('all')}
              sx={{ whiteSpace: 'nowrap' }}
            >
              {t('wholesaleOrdersPage.downloadAttachments')}
            </Button>
            <Button
              sx={{ px: 0.75, minWidth: 40 }}
              onClick={(e) => setAttachMenuAnchor(e.currentTarget)}
              aria-label={t('wholesaleOrdersPage.attachmentMenuAria')}
            >
              <ArrowDropDownIcon />
            </Button>
          </ButtonGroup>
          <Button variant="contained" startIcon={<AddIcon />} onClick={() => navigate('/wholesale-orders/new')}>
            {t('wholesaleOrdersPage.createTitle')}
          </Button>
          <Tooltip title={t('wholesaleOrdersPage.refresh')}>
            <IconButton onClick={fetchOrders} disabled={loading}>
              <RefreshIcon />
            </IconButton>
          </Tooltip>
        </Stack>
      </Box>

      <Menu
        anchorEl={attachMenuAnchor}
        open={attachMenuOpen}
        onClose={() => setAttachMenuAnchor(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
        transformOrigin={{ vertical: 'top', horizontal: 'right' }}
      >
        <MenuItem onClick={() => requestExportZip('all')}>
          {t('wholesaleOrdersPage.attachAll')}
        </MenuItem>
        <Divider component="li" sx={{ my: 0.5, borderStyle: 'dashed' }} />
        <MenuItem onClick={() => requestExportZip('order_confirmation')}>
          {t('wholesaleOrdersPage.attachOC')}
        </MenuItem>
        <MenuItem onClick={() => requestExportZip('po_attachment')}>
          {t('wholesaleOrdersPage.attachPO')}
        </MenuItem>
        <MenuItem onClick={() => requestExportZip('delivery_note')}>
          {t('wholesaleOrdersPage.attachDN')}
        </MenuItem>
        <MenuItem onClick={() => requestExportZip('signed_delivery_note')}>
          {t('wholesaleOrdersPage.attachSignedDn')}
        </MenuItem>
        <MenuItem onClick={() => requestExportZip('invoice')}>
          {t('wholesaleOrdersPage.attachInvoice')}
        </MenuItem>
        <MenuItem onClick={() => requestExportZip('payment_proof')}>
          {t('wholesaleOrdersPage.attachPaymentProof')}
        </MenuItem>
      </Menu>

      <Paper sx={{ p: 2, mb: 3 }}>
        <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
          <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
          <FormControl size="small" sx={{ minWidth: { xs: 0, sm: 170 }, width: { xs: '100%', sm: 'auto' } }}>
            <InputLabel>{t('wholesaleOrdersPage.filterStatus')}</InputLabel>
            <Select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              label={t('wholesaleOrdersPage.filterStatus')}
            >
              <MenuItem value="">{t('wholesaleOrdersPage.filterAll')}</MenuItem>
              <MenuItem value="pending_approval">{t('wholesaleOrdersPage.statusPendingApproval')}</MenuItem>
              <MenuItem value="assign_shipment">{t('wholesaleOrdersPage.statusAssignShipment')}</MenuItem>
              <MenuItem value="awaiting_payment">{t('wholesaleOrderDetail.statusAwaitingPayment')}</MenuItem>
              <MenuItem value="completed">{t('wholesaleOrderDetail.statusCompleted')}</MenuItem>
              <MenuItem value="rejected">{t('wholesaleOrdersPage.statusRejected')}</MenuItem>
              <MenuItem value="deleted">{t('wholesaleOrdersPage.statusDeleted')}</MenuItem>
            </Select>
          </FormControl>
          <Autocomplete
            size="small"
            options={clients}
            getOptionLabel={(o) => o.name}
            value={clientFilter}
            onChange={(_, v) => setClientFilterAndUrl(v)}
            renderInput={(params) => <TextField {...params} label={t('wholesaleOrdersPage.filterClient')} />}
            sx={{ width: { xs: '100%', sm: 200 }, minWidth: 0 }}
            isOptionEqualToValue={(o, v) => o.id === v.id}
          />
          <Autocomplete
            size="small"
            freeSolo
            options={deliveryLocationOptions}
            value={null}
            inputValue={deliveryLocationFilter}
            onInputChange={(_, value) => setDeliveryLocationFilter(value)}
            renderInput={(params) => (
              <TextField {...params} label={t('wholesaleOrdersPage.filterDeliveryLocation')} />
            )}
            sx={{ width: { xs: '100%', sm: 200 }, minWidth: 0 }}
          />
          <TextField
            size="small"
            label={t('wholesaleOrdersPage.filterPONumber')}
            value={poNumberFilter}
            onChange={(e) => setPONumberFilter(e.target.value)}
            sx={{ width: { xs: '100%', sm: 140 }, minWidth: 0 }}
          />
          <TextField
            size="small"
            label={t('wholesaleOrdersPage.filterOrderNumber')}
            value={orderNumberFilter}
            onChange={(e) => setOrderNumberFilter(e.target.value)}
            sx={{ width: { xs: '100%', sm: 180 }, minWidth: 0 }}
          />
          <TextField
            size="small"
            label={t('wholesaleOrdersPage.filterOCNumber')}
            value={refNoFilter}
            onChange={(e) => setRefNoFilter(e.target.value)}
            sx={{ width: { xs: '100%', sm: 140 }, minWidth: 0 }}
          />
          <TextField
            size="small"
            type="date"
            label={t('wholesaleOrdersPage.orderDate')}
            InputLabelProps={{ shrink: true }}
            value={orderDateFrom}
            onChange={(e) => setOrderDateFrom(e.target.value)}
            sx={{ width: { xs: '100%', sm: 170 }, minWidth: 0 }}
          />
          <TextField
            size="small"
            type="date"
            label={t('wholesaleOrdersPage.orderDateTo')}
            InputLabelProps={{ shrink: true }}
            value={orderDateTo}
            onChange={(e) => setOrderDateTo(e.target.value)}
            sx={{ width: { xs: '100%', sm: 170 }, minWidth: 0 }}
          />
          </Box>
          <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
            <Button
              variant="outlined"
              size="small"
              onClick={() => {
                setStatusFilter('');
                setClientFilter(null);
                setDeliveryLocationFilter('');
                setPONumberFilter('');
                setOrderNumberFilter('');
                setRefNoFilter('');
                setOrderDateFrom('');
                setOrderDateTo('');
                setSortBy('ref_no');
                setSortDir('desc');
              }}
            >
              {t('wholesaleOrdersPage.clearFilters')}
            </Button>
          </Box>
        </Box>
      </Paper>

      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: 2,
          mb: 1,
          px: 1,
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
          <Typography variant="body2" color="text.secondary">
            {t('wholesaleOrdersPage.foundAndSelected', {
              found: orders.length,
              selected: selectedIds.length,
            })}
          </Typography>
          <Button size="small" disabled={!selectedIds.length} onClick={() => setSelectedIds([])}>
            {t('wholesaleOrdersPage.clearSelection')}
          </Button>
        </Box>
        <Box sx={{ display: 'flex', gap: 3, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <Typography variant="body2" color="text.secondary">
            {t('wholesaleOrdersPage.totalAllFilteredOrders')}: £{totalAllFilteredOrders.toFixed(2)}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            {t('wholesaleOrdersPage.totalNonCompleteOrRejectedOrders')}: £{totalNonCompleteOrRejectedOrders.toFixed(2)}
          </Typography>
        </Box>
      </Box>

      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 2, mb: 1, px: 1, flexWrap: 'wrap' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Typography variant="body2" color="text.secondary">
            {t('wholesaleOrdersPage.pageSize')}
          </Typography>
          <Select
            size="small"
            value={pageSize}
            onChange={(e) => {
              setPageSize(Number(e.target.value));
              setPage(0);
            }}
            sx={{ width: 110 }}
          >
            {pageSizeOptions.map((s) => (
              <MenuItem key={s} value={s}>
                {s}
              </MenuItem>
            ))}
          </Select>

          <Typography variant="body2" color="text.secondary">
            {t('wholesaleOrdersPage.page')}
          </Typography>
          <Select
            size="small"
            value={safePage + 1}
            onChange={(e) => setPage(Math.max(0, Number(e.target.value) - 1))}
            sx={{ width: 90 }}
          >
            {Array.from({ length: pageCount }, (_, idx) => idx + 1).map((n) => (
              <MenuItem key={n} value={n}>
                {n}
              </MenuItem>
            ))}
          </Select>
        </Box>

        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Button size="small" variant="outlined" disabled={safePage <= 0} onClick={() => setPage((p) => Math.max(0, p - 1))}>
            {t('wholesaleOrdersPage.prev')}
          </Button>
          <Button
            size="small"
            variant="outlined"
            disabled={safePage >= pageCount - 1}
            onClick={() => setPage((p) => Math.min(pageCount - 1, p + 1))}
          >
            {t('wholesaleOrdersPage.next')}
          </Button>
        </Box>
      </Box>

      {isListMobile ? (
        <Stack spacing={1.5} component={Paper} sx={{ p: 1.5 }}>
          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress size={28} />
            </Box>
          ) : orders.length === 0 ? (
            <Typography align="center" color="text.secondary" sx={{ py: 4 }}>
              {t('wholesaleOrdersPage.noOrders')}
            </Typography>
          ) : (
            pagedOrders.map((order) => {
              const orderDateIso = order.order_date || order.created_at;
              const orderDate = orderDateIso ? new Date(orderDateIso) : null;
              return (
                <Paper
                  key={order.id}
                  variant="outlined"
                  onClick={() => openOrderDetail(order)}
                  sx={{ p: 1.5, borderRadius: 2, cursor: 'pointer' }}
                >
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 1, mb: 1 }}>
                    <Checkbox
                      size="small"
                      checked={selectedIds.includes(order.id)}
                      onClick={stopRowClick}
                      onChange={() => toggleRowSelected(order.id)}
                      sx={{ p: 0.5, alignSelf: 'flex-start' }}
                      inputProps={{ 'aria-label': t('wholesaleOrdersPage.toggleThisOrder') }}
                    />
                    <Box sx={{ minWidth: 0, flex: 1 }}>
                      <Typography variant="subtitle1" sx={{ fontWeight: 700, wordBreak: 'break-word', lineHeight: 1.3 }}>
                        {order.order_number}
                      </Typography>
                      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.25 }}>
                        {t('wholesaleOrdersPage.ocNumber')} {order.ref_no || '—'} · {t('wholesaleOrdersPage.poNumber')} {order.po_number || '—'}
                      </Typography>
                    </Box>
                    <Chip
                      label={wholesaleOrderStatusLabel(order, t, buildWholesaleOrderWorkflowContext(order))}
                      color={wholesaleOrderStatusColor(order, buildWholesaleOrderWorkflowContext(order))}
                      size="small"
                      sx={{ flexShrink: 0, maxWidth: '45%', height: 'auto', '& .MuiChip-label': { whiteSpace: 'normal', textAlign: 'right', py: 0.5 } }}
                    />
                  </Box>
                  <Stack spacing={0.5} sx={{ mb: 1.5 }}>
                    <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
                      <Box component="span" sx={{ color: 'text.secondary' }}>
                        {t('wholesaleOrdersPage.client')}{' '}
                      </Box>
                      {order.wholesale_client?.name ?? `Client #${order.wholesale_client_id}`}
                    </Typography>
                    <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
                      <Box component="span" sx={{ color: 'text.secondary' }}>
                        {t('wholesaleOrdersPage.deliveryLocation')}{' '}
                      </Box>
                      {deliveryLocationNameForOrder(order)}
                    </Typography>
                    <Typography variant="body2">
                      <Box component="span" sx={{ color: 'text.secondary' }}>
                        {t('wholesaleOrdersPage.total')}{' '}
                      </Box>
                      £{totalForOrder(order).toFixed(2)}
                    </Typography>
                    <Typography variant="body2">
                      <Box component="span" sx={{ color: 'text.secondary' }}>
                        {t('wholesaleOrdersPage.orderDate')}{' '}
                      </Box>
                      {orderDate ? format(orderDate, 'dd/MM/yyyy') : '—'}
                    </Typography>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
                      <Typography variant="caption" color="text.secondary">
                        {t('wholesaleOrdersPage.createdBy')}
                      </Typography>
                      {order.user ? (
                        <UserDisplay user={order.user} size="small" />
                      ) : (
                        <Typography variant="body2">{`User #${order.user_id}`}</Typography>
                      )}
                    </Box>
                  </Stack>
                </Paper>
              );
            })
          )}
        </Stack>
      ) : (
        <TableContainer component={Paper}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell padding="checkbox" sx={{ verticalAlign: 'middle' }}>
                  <Tooltip title={t('wholesaleOrdersPage.selectAllOnPage')}>
                    <Checkbox
                      inputRef={selectAllInputRef}
                      size="small"
                      checked={pageAllSelected}
                      onChange={toggleSelectAllPage}
                    />
                  </Tooltip>
                </TableCell>
                <TableCell
                  sx={{ cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: sortBy === 'ref_no' ? 700 : 500 }}
                  onClick={() => {
                    setSortBy('ref_no');
                    setSortDir((prev) => (sortBy === 'ref_no' && prev === 'asc' ? 'desc' : 'asc'));
                  }}
                >
                  <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5 }}>
                    {t('wholesaleOrdersPage.ocNumber')}
                    {renderSortIcon('ref_no')}
                  </Box>
                </TableCell>
                <TableCell>{t('wholesaleOrdersPage.client')}</TableCell>
                <TableCell>{t('wholesaleOrdersPage.deliveryLocation')}</TableCell>
                <TableCell
                  sx={{ cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: sortBy === 'po_number' ? 700 : 500 }}
                  onClick={() => {
                    setSortBy('po_number');
                    setSortDir((prev) => (sortBy === 'po_number' && prev === 'asc' ? 'desc' : 'asc'));
                  }}
                >
                  <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5 }}>
                    {t('wholesaleOrdersPage.poNumber')}
                    {renderSortIcon('po_number')}
                  </Box>
                </TableCell>
                <TableCell
                  align="right"
                  sx={{ cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: sortBy === 'total' ? 700 : 500 }}
                  onClick={() => {
                    setSortBy('total');
                    setSortDir((prev) => (sortBy === 'total' && prev === 'asc' ? 'desc' : 'asc'));
                  }}
                >
                  <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5, justifyContent: 'flex-end' }}>
                    {t('wholesaleOrdersPage.total')}
                    {renderSortIcon('total')}
                  </Box>
                </TableCell>
                <TableCell
                  sx={{ cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: sortBy === 'order_date' ? 700 : 500 }}
                  onClick={() => {
                    setSortBy('order_date');
                    setSortDir((prev) => (sortBy === 'order_date' && prev === 'asc' ? 'desc' : 'asc'));
                  }}
                >
                  <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5 }}>
                    {t('wholesaleOrdersPage.orderDate')}
                    {renderSortIcon('order_date')}
                  </Box>
                </TableCell>
                <TableCell>{t('wholesaleOrdersPage.status')}</TableCell>
                <TableCell>{t('wholesaleOrdersPage.createdBy')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell colSpan={9} align="center">
                    <CircularProgress size={24} />
                  </TableCell>
                </TableRow>
              ) : orders.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={9} align="center">
                    {t('wholesaleOrdersPage.noOrders')}
                  </TableCell>
                </TableRow>
              ) : (
                pagedOrders.map((order) => {
                  const orderDateIso = order.order_date || order.created_at;
                  const orderDate = orderDateIso ? new Date(orderDateIso) : null;
                  return (
                    <TableRow
                      key={order.id}
                      selected={selectedIds.includes(order.id)}
                      hover
                      onClick={() => openOrderDetail(order)}
                      sx={{ cursor: 'pointer' }}
                    >
                      <TableCell padding="checkbox" sx={{ verticalAlign: 'middle' }} onClick={stopRowClick}>
                        <Checkbox
                          size="small"
                          checked={selectedIds.includes(order.id)}
                          onClick={stopRowClick}
                          onChange={() => toggleRowSelected(order.id)}
                          inputProps={{ 'aria-label': t('wholesaleOrdersPage.toggleThisOrder') }}
                        />
                      </TableCell>
                      <TableCell>{order.ref_no || '-'}</TableCell>
                      <TableCell>{order.wholesale_client?.name ?? `Client #${order.wholesale_client_id}`}</TableCell>
                      <TableCell sx={{ fontSize: 12 }}>{deliveryLocationNameForOrder(order)}</TableCell>
                      <TableCell sx={{ fontSize: 12 }}>{order.po_number || '-'}</TableCell>
                      <TableCell align="right">£{totalForOrder(order).toFixed(2)}</TableCell>
                      <TableCell>{orderDate ? format(orderDate, 'dd/MM/yyyy') : '-'}</TableCell>
                      <TableCell>
                        <Chip label={wholesaleOrderStatusLabel(order, t, buildWholesaleOrderWorkflowContext(order))} color={wholesaleOrderStatusColor(order, buildWholesaleOrderWorkflowContext(order))} size="small" />
                      </TableCell>
                      <TableCell>
                        {order.user ? (
                          <UserDisplay user={order.user} />
                        ) : (
                          `User #${order.user_id}`
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

      <Dialog
        open={exportConfirmOpen}
        onClose={() => {
          setExportConfirmOpen(false);
          setPendingExport(null);
          setZipRecipientEmail('');
        }}
      >
        <DialogTitle>{t('wholesaleOrdersPage.exportConfirmTitle')}</DialogTitle>
        <DialogContent>
          <Typography variant="body1" sx={{ mb: 1 }}>
            {t('wholesaleOrdersPage.exportConfirmCount', { count: ordersForBulkExport.length })}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: pendingExport?.kind === 'zip' ? 1 : 0 }}>
            {selectedIds.length > 0
              ? t('wholesaleOrdersPage.exportConfirmHintSelection')
              : t('wholesaleOrdersPage.exportConfirmHintFiltered')}
          </Typography>
          {pendingExport?.kind === 'zip' && (
            <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
              {t('wholesaleOrdersPage.exportConfirmAttachmentType')}: {attachmentKindMenuLabel(pendingExport.zipKind)}
            </Typography>
          )}
          {pendingExport?.kind === 'zip' && ordersForBulkExport.length >= BULK_ZIP_EMAIL_THRESHOLD && (
            <>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                {t('wholesaleOrdersPage.exportZipEmailHint', { count: BULK_ZIP_EMAIL_THRESHOLD })}
              </Typography>
              <TextField
                autoFocus
                margin="dense"
                type="email"
                label={t('wholesaleOrdersPage.exportZipEmailLabel')}
                fullWidth
                variant="outlined"
                value={zipRecipientEmail}
                onChange={(e) => setZipRecipientEmail(e.target.value)}
                disabled={zipEmailSubmitting}
              />
            </>
          )}
        </DialogContent>
        <DialogActions>
          <Button
            onClick={() => {
              setExportConfirmOpen(false);
              setPendingExport(null);
              setZipRecipientEmail('');
            }}
            disabled={zipEmailSubmitting}
          >
            {t('wholesaleOrdersPage.cancel')}
          </Button>
          <Button
            variant="contained"
            onClick={handleExportConfirm}
            disabled={
              !ordersForBulkExport.length ||
              zipEmailSubmitting ||
              (pendingExport?.kind === 'zip' &&
                ordersForBulkExport.length >= BULK_ZIP_EMAIL_THRESHOLD &&
                !zipRecipientEmail.trim())
            }
          >
            {pendingExport?.kind === 'zip' && ordersForBulkExport.length >= BULK_ZIP_EMAIL_THRESHOLD
              ? zipEmailSubmitting
                ? t('wholesaleOrdersPage.exportZipEmailSending')
                : t('wholesaleOrdersPage.exportZipEmailConfirm')
              : t('wholesaleOrdersPage.confirmExport')}
          </Button>
        </DialogActions>
      </Dialog>

      <Fab
        color="primary"
        aria-label="Create wholesale order"
        sx={{ position: 'fixed', bottom: { xs: 88, sm: 24 }, right: 24 }}
        onClick={() => navigate('/wholesale-orders/new')}
      >
        <AddIcon />
      </Fab>

    </Box>
  );
}
