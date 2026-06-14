import { useEffect, useState, useCallback } from 'react';
import { useParams, Link as RouterLink } from 'react-router-dom';
import {
  Box,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
  Button,
  TextField,
  CircularProgress,
  Chip,
  Link,
} from '@mui/material';
import {
  Download as DownloadIcon,
  ChevronRight as ChevronRightIcon,
  Edit as EditIcon,
  Restore as RestoreIcon,
} from '@mui/icons-material';
import { wholesaleOrdersAPI, shipmentsAPI } from '../services/api';
import type { AuditLog, WholesaleOrder } from '../types';
import { format } from 'date-fns';
import UserDisplay from '../components/UserDisplay';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import { confirmUnlockForRegen, isDocumentRegenLocked } from '../utils/documentRegenLock';

const ACTION_LABELS: Record<
  string,
  { labelKey: string; color: 'default' | 'primary' | 'success' | 'error' | 'warning' | 'info' }
> = {
  wholesale_order_create: { labelKey: 'created', color: 'success' },
  wholesale_order_update: { labelKey: 'updated', color: 'primary' },
  wholesale_order_approve: { labelKey: 'approved', color: 'success' },
  wholesale_order_reject: { labelKey: 'rejected', color: 'error' },
  wholesale_order_resubmit: { labelKey: 'resubmitted', color: 'info' },
  wholesale_order_complete_assignment: { labelKey: 'assignmentCompleted', color: 'info' },
  wholesale_order_assign_stores: { labelKey: 'storesAssigned', color: 'info' },
  wholesale_order_regenerate_oc: { labelKey: 'ocRegenerated', color: 'warning' },
  wholesale_order_generate_invoice: { labelKey: 'invoiceGenerated', color: 'warning' },
  wholesale_order_generate_oc: { labelKey: 'ocGenerated', color: 'warning' },
  wholesale_order_confirm_payment: { labelKey: 'paymentConfirmed', color: 'success' },
  wholesale_shipment_update: { labelKey: 'shipmentUpdated', color: 'primary' },
  wholesale_shipment_start: { labelKey: 'shipmentStarted', color: 'info' },
  wholesale_shipment_complete_packing: { labelKey: 'packingCompleted', color: 'info' },
  wholesale_shipment_regenerate_dn: { labelKey: 'dnRegenerated', color: 'warning' },
  wholesale_shipment_update_case_qty: { labelKey: 'caseQtyUpdated', color: 'info' },
  wholesale_order_email_oc: { labelKey: 'ocEmailed', color: 'default' },
  wholesale_order_email_invoice: { labelKey: 'invoiceEmailed', color: 'default' },
  wholesale_order_invoice_sent: { labelKey: 'invoiceSentUpdated', color: 'info' },
  wholesale_order_email_dn: { labelKey: 'dnEmailed', color: 'default' },
  wholesale_order_email: { labelKey: 'orderEmailed', color: 'default' },
  wholesale_order_delete: { labelKey: 'orderDeleted', color: 'error' },
  wholesale_order_archive: { labelKey: 'orderDeleted', color: 'error' },
  wholesale_order_restore_document: { labelKey: 'documentRestored', color: 'warning' },
  wholesale_shipment_upload_signed_dn: { labelKey: 'signedDnUploaded', color: 'info' },
  wholesale_shipment_replace_signed_dn: { labelKey: 'signedDnReplaced', color: 'info' },
};

const RESTORABLE_ACTIONS = new Set([
  'wholesale_order_generate_oc',
  'wholesale_order_regenerate_oc',
  'wholesale_order_generate_invoice',
  'wholesale_shipment_start',
  'wholesale_shipment_complete_packing',
  'wholesale_shipment_regenerate_dn',
  'wholesale_shipment_update_case_qty',
  'wholesale_shipment_upload_signed_dn',
  'wholesale_shipment_replace_signed_dn',
]);

function inferDocumentType(action: string, changes: Record<string, any>): string | null {
  if (typeof changes.document_type === 'string' && changes.document_type.trim()) {
    return changes.document_type.trim();
  }
  switch (action) {
    case 'wholesale_order_generate_oc':
    case 'wholesale_order_regenerate_oc':
      return 'order_confirmation';
    case 'wholesale_order_generate_invoice':
      return 'invoice';
    case 'wholesale_shipment_upload_signed_dn':
    case 'wholesale_shipment_replace_signed_dn':
      return 'signed_delivery_note';
    case 'wholesale_shipment_start':
    case 'wholesale_shipment_complete_packing':
    case 'wholesale_shipment_regenerate_dn':
    case 'wholesale_shipment_update_case_qty':
      return 'delivery_note';
    default:
      return null;
  }
}

function getActiveDocumentUrl(
  order: WholesaleOrder,
  action: string,
  changes: Record<string, any>,
): string | null {
  const docType = inferDocumentType(action, changes);
  if (!docType) return null;
  if (docType === 'order_confirmation' || docType === 'invoice') {
    return order.documents?.find((d) => d.type === docType)?.file_url ?? null;
  }
  const shipmentId = Number(changes.shipment_id);
  if (!Number.isFinite(shipmentId)) return null;
  const shipment = order.shipments?.find((s) => s.id === shipmentId);
  if (!shipment) return null;
  if (docType === 'signed_delivery_note') {
    return shipment.signed_delivery_note_pdf_url ?? null;
  }
  return shipment.delivery_note_pdf_url ?? null;
}

function canRestoreDocument(action: string, changes: Record<string, any>): boolean {
  if (typeof changes.file_url !== 'string' || !changes.file_url.trim()) return false;
  if (RESTORABLE_ACTIONS.has(action)) return true;
  const docType = inferDocumentType(action, changes);
  return docType === 'order_confirmation' || docType === 'invoice' || docType === 'delivery_note' || docType === 'signed_delivery_note';
}

function getFieldLabel(k: string, t: (k: string, opts?: any) => string): string {
  // Try specific mapping first; fall back to the raw key when not defined
  return t(`wholesaleOrderAudit:field.${k}`, { defaultValue: k });
}

function formatChanges(
  changes: Record<string, any>,
  t: (k: string, opts?: any) => string,
  action?: string,
): React.ReactNode[] {
  return Object.entries(changes).map(([k, v]) => {
    if (k === 'store_name' && action === 'wholesale_shipment_start') return null;
    if (k === 'items' && Array.isArray(v)) {
      return (
        <div key={k}>
          <strong>{getFieldLabel('itemPriceChanges', t)}:</strong>
          {v.map((item: any, i: number) => (
            <div key={i} style={{ paddingLeft: 12 }}>
              Item #{item.item_id}: £{Number(item.old_unit_price).toFixed(2)} → £{Number(item.new_unit_price).toFixed(2)}
            </div>
          ))}
        </div>
      );
    }
    if (k === 'assignments' && Array.isArray(v)) {
      return (
        <div key={k}>
          <strong>{getFieldLabel('assignments', t)}:</strong> {v.length} item(s)
        </div>
      );
    }
    if (k === 'changes' && typeof v === 'object' && v !== null) {
      return (
        <div key={k}>
          {Object.entries(v).map(([ck, cv]: [string, any]) => (
            <div key={ck}>
              <strong>{getFieldLabel(ck, t)}:</strong> {cv?.old ?? '—'} → {cv?.new ?? '—'}
            </div>
          ))}
        </div>
      );
    }
    if (k === 'file_url' && typeof v === 'string') {
      return null; // PDF link moved to Action column as icon
    }
    if (typeof v === 'object' && v !== null && 'old' in v) {
      return (
        <div key={k}>
          <strong>{getFieldLabel(k, t)}:</strong> {v.old || t('wholesaleOrderAudit:field.empty')} →{' '}
          {v.new || t('wholesaleOrderAudit:field.empty')}
        </div>
      );
    }
    if (typeof v === 'object' && v !== null) {
      return (
        <div key={k}>
          <strong>{getFieldLabel(k, t)}:</strong> {JSON.stringify(v)}
        </div>
      );
    }
    return (
      <div key={k}>
        <strong>{getFieldLabel(k, t)}:</strong> {String(v)}
      </div>
    );
  });
}

export default function WholesaleOrderAuditLogPage() {
  const { id } = useParams<{ id: string }>();
  const { t } = useTranslation(['wholesaleOrderAudit', 'wholesaleOrderDetail', 'layout', 'common']);
  const orderId = id ? Number(id) : NaN;
  const { enqueueSnackbar } = useSnackbar();

  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [order, setOrder] = useState<WholesaleOrder | null>(null);

  const [editingOrderDate, setEditingOrderDate] = useState(false);
  const [orderDateDraft, setOrderDateDraft] = useState('');
  const [savingOrderDate, setSavingOrderDate] = useState(false);

  const [editingShipmentCompleteDate, setEditingShipmentCompleteDate] = useState(false);
  const [shipmentCompleteDateDraft, setShipmentCompleteDateDraft] = useState('');
  const [savingShipmentCompleteDate, setSavingShipmentCompleteDate] = useState(false);
  const [restoringLogId, setRestoringLogId] = useState<number | null>(null);

  const formatOptionalDate = (v?: string | null) => {
    if (!v) return '—';
    try {
      return format(new Date(v), 'dd MMM yyyy');
    } catch {
      return '—';
    }
  };

  const fetchLogs = useCallback(async () => {
    if (Number.isNaN(orderId)) return;
    try {
      setLoading(true);
      const [logsData, orderData] = await Promise.all([
        wholesaleOrdersAPI.getAuditLogs(orderId),
        wholesaleOrdersAPI.get(orderId),
      ]);
      setLogs(logsData);
      setOrder(orderData);
    } catch {
      /* ignore */
    } finally {
      setLoading(false);
    }
  }, [orderId]);

  useEffect(() => {
    fetchLogs();
  }, [fetchLogs]);

  const completedShipments = order?.shipments?.filter((s) => s.status === 'completed') ?? [];
  const latestCompletedShipment = completedShipments.reduce<typeof completedShipments[number] | null>((acc, sh) => {
    const accCandidate = acc
      ? acc.delivery_date
        ? new Date(acc.delivery_date).getTime()
        : new Date(acc.created_at).getTime()
      : -Infinity;
    const shCandidate = sh.delivery_date ? new Date(sh.delivery_date).getTime() : new Date(sh.created_at).getTime();
    if (!acc || shCandidate > accCandidate) return sh;
    return acc;
  }, null);

  const canEditDates = !!order && !order.payment_confirmed_at;
  const canRestoreDocuments = !!order && order.status !== 'deleted';

  const restoreDocument = async (logId: number, action: string, changes: Record<string, any>) => {
    if (!order || Number.isNaN(orderId)) return;
    if (!window.confirm(t('wholesaleOrderAudit:confirmRestoreDocument'))) return;
    const docType = inferDocumentType(action, changes);
    let lockType: 'order_confirmation' | 'invoice' | 'delivery_note' | 'signed_delivery_note' | null = null;
    if (docType === 'order_confirmation' || docType === 'invoice' || docType === 'delivery_note') {
      lockType = docType;
    } else if (docType === 'signed_delivery_note') {
      lockType = 'signed_delivery_note';
    }
    const shipmentId = lockType === 'delivery_note' || lockType === 'signed_delivery_note'
      ? Number(changes.shipment_id)
      : undefined;
    const locked =
      lockType != null &&
      isDocumentRegenLocked(
        logs,
        lockType,
        Number.isFinite(shipmentId) ? shipmentId : undefined,
      );
    if (locked) {
      const label =
        lockType === 'order_confirmation'
          ? t('wholesaleOrderDetail:orderConfirmation')
          : lockType === 'invoice'
            ? t('wholesaleOrderDetail:invoice')
            : lockType === 'signed_delivery_note'
              ? t('wholesaleOrderDetail:signedDeliveryNotePdf')
              : t('wholesaleOrderDetail:deliveryNote');
      if (!confirmUnlockForRegen(t, label)) return;
    }
    try {
      setRestoringLogId(logId);
      const updated = await wholesaleOrdersAPI.restoreDocumentFromAudit(order.id, logId, {
        unlock_after_email: locked,
      });
      setOrder(updated);
      const logsData = await wholesaleOrdersAPI.getAuditLogs(orderId);
      setLogs(logsData);
      enqueueSnackbar(t('wholesaleOrderAudit:restoreDocumentSuccess'), { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e?.response?.data?.error || t('wholesaleOrderAudit:restoreDocumentFailed'), { variant: 'error' });
    } finally {
      setRestoringLogId(null);
    }
  };

  const getOrderDateDisplayValue = () => {
    if (!order) return null;
    return order.order_date ?? order.po_date ?? order.created_at ?? null;
  };

  const saveOrderDate = async () => {
    if (!order) return;
    if (!canEditDates) return;
    if (!window.confirm(t('wholesaleOrderDetail:confirmUpdateOrderDateRegenAllDocs'))) return;
    if (!orderDateDraft) return;

    try {
      setSavingOrderDate(true);
      const updated = await wholesaleOrdersAPI.update(order.id, { order_date: orderDateDraft });
      const completedShipmentIds = updated.shipments?.filter((s) => s.status === 'completed').map((s) => s.id) ?? [];

      const regenJobs: Promise<unknown>[] = [];
      const skippedDocs: string[] = [];
      // OC/invoice/DT may include the order date depending on the PDF type.
      if (updated.status === 'assign_shipment' || updated.status === 'approved') {
        if (!isDocumentRegenLocked(logs, 'order_confirmation')) {
          regenJobs.push(wholesaleOrdersAPI.regenerateOrderConfirmation(updated.id));
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:orderConfirmation'));
        }
      }
      if ((updated.shipments?.length ?? 0) > 0 && updated.shipments!.every((s) => s.status === 'completed')) {
        if (!isDocumentRegenLocked(logs, 'invoice')) {
          regenJobs.push(wholesaleOrdersAPI.generateInvoice(updated.id));
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:invoice'));
        }
      }
      completedShipmentIds.forEach((shipmentId) => {
        if (!isDocumentRegenLocked(logs, 'delivery_note', shipmentId)) {
          regenJobs.push(shipmentsAPI.regenerateDeliveryNote(shipmentId));
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:deliveryNote'));
        }
      });
      if (skippedDocs.length > 0) {
        enqueueSnackbar(
          t('wholesaleOrderDetail:documentRegenSkippedAfterEmail', {
            document: [...new Set(skippedDocs)].join(', '),
          }),
          { variant: 'warning' },
        );
      }

      if (regenJobs.length > 0) {
        const results = await Promise.allSettled(regenJobs);
        const anyRejected = results.some((r) => r.status === 'rejected');
        if (anyRejected) enqueueSnackbar('Some documents failed to re-generate.', { variant: 'warning' });
      }

      const freshOrder = await wholesaleOrdersAPI.get(updated.id, { cacheBust: true });
      setOrder(freshOrder);
      setEditingOrderDate(false);
      enqueueSnackbar('Order date updated', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e?.response?.data?.error || 'Failed to update order date', { variant: 'error' });
    } finally {
      setSavingOrderDate(false);
    }
  };

  const saveShipmentCompleteDate = async () => {
    if (!order) return;
    if (!canEditDates) return;
    if (!latestCompletedShipment) return;
    if (!shipmentCompleteDateDraft) return;

    // Only shipment delivery_date affects invoice header "Date:" (by latest completed shipment).
    const msg = t('wholesaleOrderAudit:confirmUpdateShipmentCompleteDateRegenInvoiceAndDN');
    if (!window.confirm(msg)) return;

    try {
      setSavingShipmentCompleteDate(true);
      await shipmentsAPI.update(latestCompletedShipment.id, { delivery_date: shipmentCompleteDateDraft });
      const updatedOrder = await wholesaleOrdersAPI.get(order.id, { cacheBust: true });
      setOrder(updatedOrder);

      // Regenerate invoice + delivery notes best-effort.
      const completedShipmentIds = updatedOrder.shipments?.filter((s) => s.status === 'completed').map((s) => s.id) ?? [];
      const regenJobs: Promise<unknown>[] = [];
      const skippedDocs: string[] = [];
      completedShipmentIds.forEach((shipmentId) => {
        if (!isDocumentRegenLocked(logs, 'delivery_note', shipmentId)) {
          regenJobs.push(shipmentsAPI.regenerateDeliveryNote(shipmentId));
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:deliveryNote'));
        }
      });
      if ((updatedOrder.shipments?.length ?? 0) > 0 && updatedOrder.shipments!.every((s) => s.status === 'completed')) {
        if (!isDocumentRegenLocked(logs, 'invoice')) {
          regenJobs.push(wholesaleOrdersAPI.generateInvoice(updatedOrder.id));
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:invoice'));
        }
      }
      if (skippedDocs.length > 0) {
        enqueueSnackbar(
          t('wholesaleOrderDetail:documentRegenSkippedAfterEmail', {
            document: [...new Set(skippedDocs)].join(', '),
          }),
          { variant: 'warning' },
        );
      }
      if (regenJobs.length > 0) {
        await Promise.allSettled(regenJobs);
      }

      const freshOrder = await wholesaleOrdersAPI.get(order.id, { cacheBust: true });
      setOrder(freshOrder);
      setEditingShipmentCompleteDate(false);
      enqueueSnackbar('Shipment complete date updated', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e?.response?.data?.error || 'Failed to update shipment complete date', { variant: 'error' });
    } finally {
      setSavingShipmentCompleteDate(false);
    }
  };

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2, flexWrap: 'wrap', gap: 1 }}>
        <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          <Link component={RouterLink} to="/" color="primary" underline="hover">
            {t('common:home')}
          </Link>
          <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
          <Link component={RouterLink} to="/wholesale-orders" color="primary" underline="hover">
            {t('layout:wholesaleOrders')}
          </Link>
          {order?.order_number && (
            <>
              <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
              <Link component={RouterLink} to={`/wholesale-orders/${id}`} color="primary" underline="none">
                {order.order_number}
              </Link>
            </>
          )}
          <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
          <span>{t('wholesaleOrderAudit:breadcrumb')}</span>
        </Typography>
      </Box>
      <Typography variant="h6" sx={{ mb: 2 }}>
        {t('wholesaleOrderAudit:title', { id })}
      </Typography>

      {order && !loading && (
        <Paper sx={{ p: 2, mb: 2 }}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:dateField')}</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:dateValue')}</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:actions')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:createDate')}</TableCell>
                <TableCell>{formatOptionalDate(order.created_at)}</TableCell>
                <TableCell />
              </TableRow>
              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:lastUpdate')}</TableCell>
                <TableCell>{formatOptionalDate(order.updated_at ?? order.created_at)}</TableCell>
                <TableCell />
              </TableRow>
              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:poDate')}</TableCell>
                <TableCell>{formatOptionalDate(order.po_date ?? order.created_at)}</TableCell>
                <TableCell />
              </TableRow>
              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:orderDate')}</TableCell>
                <TableCell>
                  {editingOrderDate ? (
                    <TextField
                      size="small"
                      type="date"
                      value={orderDateDraft}
                      onChange={(e) => setOrderDateDraft(e.target.value)}
                      InputLabelProps={{ shrink: true }}
                      inputProps={{ max: '9999-12-31' }}
                    />
                  ) : (
                    <>{formatOptionalDate(getOrderDateDisplayValue())}</>
                  )}
                </TableCell>
                <TableCell>
                  {editingOrderDate ? (
                    <>
                      <Button size="small" variant="contained" disabled={savingOrderDate} onClick={saveOrderDate}>
                        {savingOrderDate ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
                      </Button>
                      <Button size="small" disabled={savingOrderDate} onClick={() => setEditingOrderDate(false)}>
                        {t('wholesaleOrderDetail:cancel')}
                      </Button>
                    </>
                  ) : (
                    <>{canEditDates && !order.payment_confirmed_at ? <EditIcon sx={{ fontSize: 14, cursor: 'pointer' }} onClick={() => {
                      setOrderDateDraft(
                        (order.order_date ?? order.po_date ?? order.created_at)?.substring(0, 10) ?? '',
                      );
                      setEditingOrderDate(true);
                    }} /> : null}</>
                  )}
                </TableCell>
              </TableRow>

              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:approvalDate')}</TableCell>
                <TableCell>{formatOptionalDate(order.reviewed_at)}</TableCell>
                <TableCell />
              </TableRow>
              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:shipmentCompleteDate')}</TableCell>
                <TableCell>
                  {editingShipmentCompleteDate ? (
                    <TextField
                      size="small"
                      type="date"
                      value={shipmentCompleteDateDraft}
                      onChange={(e) => setShipmentCompleteDateDraft(e.target.value)}
                      InputLabelProps={{ shrink: true }}
                      inputProps={{ max: '9999-12-31' }}
                    />
                  ) : (
                    <>{formatOptionalDate(latestCompletedShipment ? latestCompletedShipment.delivery_date ?? latestCompletedShipment.created_at : null)}</>
                  )}
                </TableCell>
                <TableCell>
                  {editingShipmentCompleteDate ? (
                    <>
                      <Button
                        size="small"
                        variant="contained"
                        disabled={savingShipmentCompleteDate}
                        onClick={saveShipmentCompleteDate}
                      >
                        {savingShipmentCompleteDate ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
                      </Button>
                      <Button
                        size="small"
                        disabled={savingShipmentCompleteDate}
                        onClick={() => setEditingShipmentCompleteDate(false)}
                      >
                        {t('wholesaleOrderDetail:cancel')}
                      </Button>
                    </>
                  ) : (
                    <>
                      {canEditDates && latestCompletedShipment ? (
                        <EditIcon
                          sx={{ fontSize: 14, cursor: 'pointer' }}
                          onClick={() => {
                            const v = latestCompletedShipment.delivery_date ?? latestCompletedShipment.created_at;
                            setShipmentCompleteDateDraft((v ?? '').substring(0, 10));
                            setEditingShipmentCompleteDate(true);
                          }}
                        />
                      ) : null}
                    </>
                  )}
                </TableCell>
              </TableRow>
              <TableRow>
                <TableCell>{t('wholesaleOrderAudit:orderCompleteDate')}</TableCell>
                <TableCell>{formatOptionalDate(order.payment_confirmed_at)}</TableCell>
                <TableCell />
              </TableRow>
            </TableBody>
          </Table>
        </Paper>
      )}

      <Paper sx={{ p: 2 }}>
        {loading ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
            <CircularProgress />
          </Box>
        ) : logs.length === 0 ? (
          <Typography color="text.secondary" align="center" sx={{ py: 4 }}>
            {t('wholesaleOrderAudit:noRecords')}
          </Typography>
        ) : (
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:time')}</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:user')}</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:event')}</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderAudit:details')}</TableCell>
                <TableCell sx={{ fontWeight: 600 }} align="center">
                  {t('wholesaleOrderAudit:actionHeader')}
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {logs.map((log) => {
                let changes: Record<string, any> = {};
                try {
                  changes = JSON.parse(log.changes);
                } catch {
                  /* ignore */
                }
                const actionInfo =
                  ACTION_LABELS[log.action] ?? { labelKey: '', color: 'default' as const };
                const fileUrl = typeof changes.file_url === 'string' ? changes.file_url : null;
                const restorable = !!fileUrl && canRestoreDocument(log.action, changes);
                const activeUrl = order && restorable ? getActiveDocumentUrl(order, log.action, changes) : null;
                const isActiveDocument = !!fileUrl && activeUrl === fileUrl;
                const storeName = typeof changes.store_name === 'string' ? changes.store_name : null;
                const chipLabel =
                  actionInfo.labelKey
                    ? log.action === 'wholesale_shipment_start' && storeName
                      ? t('wholesaleOrderAudit:action.shipmentStartedWithStore', { store: storeName })
                      : t(`wholesaleOrderAudit:action.${actionInfo.labelKey}`)
                    : log.action;
                return (
                  <TableRow key={log.id}>
                    <TableCell sx={{ whiteSpace: 'nowrap' }}>
                      {format(new Date(log.created_at), 'yyyy-MM-dd')}
                    </TableCell>
                    <TableCell>
                      <UserDisplay user={log.user} size="small" />
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={chipLabel}
                        color={actionInfo.color}
                        size="small"
                        variant="filled"
                      />
                    </TableCell>
                    <TableCell sx={{ maxWidth: 600, fontSize: '0.82rem' }}>
                      {formatChanges(changes, t, log.action)}
                    </TableCell>
                    <TableCell align="center">
                      {fileUrl ? (
                        <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0.75 }}>
                          <Button
                            size="small"
                            variant="outlined"
                            component="a"
                            href={fileUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            startIcon={<DownloadIcon fontSize="small" />}
                          >
                            {t('wholesaleOrderAudit:downloadDocument')}
                          </Button>
                          {restorable && canRestoreDocuments ? (
                            <Button
                              size="small"
                              variant="contained"
                              color="warning"
                              disabled={isActiveDocument || restoringLogId === log.id}
                              onClick={() => restoreDocument(log.id, log.action, changes)}
                              startIcon={
                                restoringLogId === log.id ? (
                                  <CircularProgress size={14} color="inherit" />
                                ) : (
                                  <RestoreIcon fontSize="small" />
                                )
                              }
                            >
                              {isActiveDocument
                                ? t('wholesaleOrderAudit:documentAlreadyActive')
                                : t('wholesaleOrderAudit:restoreDocument')}
                            </Button>
                          ) : null}
                        </Box>
                      ) : (
                        '—'
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </Paper>
    </Box>
  );
}
