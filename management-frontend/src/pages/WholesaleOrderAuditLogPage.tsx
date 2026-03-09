import { useEffect, useState, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
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
  CircularProgress,
  Chip,
} from '@mui/material';
import { ArrowBack as BackIcon, Download as DownloadIcon } from '@mui/icons-material';
import { wholesaleOrdersAPI } from '../services/api';
import type { AuditLog } from '../types';
import { format } from 'date-fns';
import UserDisplay from '../components/UserDisplay';

const ACTION_LABELS: Record<string, { label: string; color: 'default' | 'primary' | 'success' | 'error' | 'warning' | 'info' }> = {
  wholesale_order_create: { label: 'Created', color: 'success' },
  wholesale_order_update: { label: 'Updated', color: 'primary' },
  wholesale_order_approve: { label: 'Approved', color: 'success' },
  wholesale_order_reject: { label: 'Rejected', color: 'error' },
  wholesale_order_complete_assignment: { label: 'Assignment completed', color: 'info' },
  wholesale_order_assign_stores: { label: 'Stores assigned', color: 'info' },
  wholesale_order_regenerate_oc: { label: 'OC regenerated', color: 'warning' },
  wholesale_order_generate_invoice: { label: 'Invoice generated', color: 'warning' },
  wholesale_order_generate_oc: { label: 'OC generated', color: 'warning' },
  wholesale_shipment_update: { label: 'Shipment updated', color: 'primary' },
  wholesale_shipment_complete_packing: { label: 'Packing completed', color: 'info' },
  wholesale_shipment_regenerate_dn: { label: 'DN regenerated', color: 'warning' },
  wholesale_shipment_update_case_qty: { label: 'Case qty updated', color: 'info' },
  wholesale_order_email_oc: { label: 'OC emailed', color: 'default' },
  wholesale_order_email_invoice: { label: 'Invoice emailed', color: 'default' },
  wholesale_order_email_dn: { label: 'DN emailed', color: 'default' },
};

function formatChanges(changes: Record<string, any>): React.ReactNode[] {
  return Object.entries(changes).map(([k, v]) => {
    if (k === 'items' && Array.isArray(v)) {
      return (
        <div key={k}>
          <strong>Item price changes:</strong>
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
          <strong>Assignments:</strong> {v.length} item(s)
        </div>
      );
    }
    if (k === 'changes' && typeof v === 'object' && v !== null) {
      return (
        <div key={k}>
          {Object.entries(v).map(([ck, cv]: [string, any]) => (
            <div key={ck}>
              <strong>{ck}:</strong> {cv?.old ?? '—'} → {cv?.new ?? '—'}
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
          <strong>{k}:</strong> {v.old || '(empty)'} → {v.new || '(empty)'}
        </div>
      );
    }
    if (typeof v === 'object' && v !== null) {
      return (
        <div key={k}>
          <strong>{k}:</strong> {JSON.stringify(v)}
        </div>
      );
    }
    return (
      <div key={k}>
        <strong>{k}:</strong> {String(v)}
      </div>
    );
  });
}

export default function WholesaleOrderAuditLogPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const orderId = id ? Number(id) : NaN;

  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchLogs = useCallback(async () => {
    if (Number.isNaN(orderId)) return;
    try {
      setLoading(true);
      const data = await wholesaleOrdersAPI.getAuditLogs(orderId);
      setLogs(data);
    } catch {
      /* ignore */
    } finally {
      setLoading(false);
    }
  }, [orderId]);

  useEffect(() => {
    fetchLogs();
  }, [fetchLogs]);

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Button startIcon={<BackIcon />} onClick={() => navigate(`/wholesale-orders/${id}`)}>
          Back to order
        </Button>
        <Typography variant="h6">Audit Log — Order #{id}</Typography>
      </Box>

      <Paper sx={{ p: 2 }}>
        {loading ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
            <CircularProgress />
          </Box>
        ) : logs.length === 0 ? (
          <Typography color="text.secondary" align="center" sx={{ py: 4 }}>
            No audit records found.
          </Typography>
        ) : (
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ fontWeight: 600 }}>Time</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>User</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>Event</TableCell>
                <TableCell sx={{ fontWeight: 600 }}>Details</TableCell>
                <TableCell sx={{ fontWeight: 600 }} align="center">Action</TableCell>
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
                const actionInfo = ACTION_LABELS[log.action] ?? { label: log.action, color: 'default' as const };
                const fileUrl = typeof changes.file_url === 'string' ? changes.file_url : null;
                return (
                  <TableRow key={log.id}>
                    <TableCell sx={{ whiteSpace: 'nowrap' }}>
                      {format(new Date(log.created_at), 'yyyy-MM-dd HH:mm:ss')}
                    </TableCell>
                    <TableCell>
                      <UserDisplay user={log.user} size="small" />
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={actionInfo.label}
                        color={actionInfo.color}
                        size="small"
                        variant="filled"
                      />
                    </TableCell>
                    <TableCell sx={{ maxWidth: 600, fontSize: '0.82rem' }}>
                      {formatChanges(changes)}
                    </TableCell>
                    <TableCell align="center">
                      {fileUrl ? (
                        <Button
                          size="small"
                          variant="outlined"
                          component="a"
                          href={fileUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          startIcon={<DownloadIcon fontSize="small" />}
                        >
                          Download document
                        </Button>
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
