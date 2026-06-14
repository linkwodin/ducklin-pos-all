import { useCallback, useEffect, useMemo, useState, type MouseEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Box,
  Button,
  CircularProgress,
  IconButton,
  MenuItem,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Tooltip,
  Typography,
} from '@mui/material';
import {
  Refresh as RefreshIcon,
  ChevronRight as ChevronRightIcon,
  LocalShipping as ShipmentIcon,
  ViewList as ViewListIcon,
  GridView as GridViewIcon,
} from '@mui/icons-material';
import { format, subDays } from 'date-fns';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import { useAuth } from '../context/AuthContext';
import ShipmentCourierPickupDialog from '../components/ShipmentCourierPickupDialog';
import ShipmentMonitorGrid from '../components/ShipmentMonitorGrid';
import ShipmentPackingQueueDialog from '../components/ShipmentPackingQueueDialog';
import { settingsAPI, shipmentsAPI, storesAPI } from '../services/api';
import type { CompanySettings } from '../types';
import { shipmentCourierOptionsFromSettings } from '../utils/shipmentCouriers';
import { mergeShipmentListRow, sortShipmentsByOrderTimeDesc } from '../utils/shipmentOrderTime';
import type { Shipment, Store } from '../types';
import { effectiveShipmentItemQty } from '../utils/wholesaleOrderAssignment';
import {
  shipmentNeedsPacking,
} from '../utils/shipmentStatus';

const VIEW_STORAGE_KEY = 'wholesaleShipmentsView';
const MONITOR_REFRESH_MS = 30_000;
const MONITOR_COMPLETED_DAYS = 3;
const LIST_COMPLETED_DAYS = 10;

type ViewMode = 'list' | 'monitor';

function shipmentMatchesSearch(shipment: Shipment, rawQuery: string): boolean {
  const q = rawQuery.trim().toLowerCase();
  if (!q) return true;
  const order = shipment.wholesale_order;
  const clientName = order?.wholesale_client?.name?.trim() ?? '';
  const orderNumber = order?.order_number?.trim() ?? '';
  const fields = [
    orderNumber,
    orderNumber.replace(/^WO-/i, ''),
    order?.ref_no?.trim(),
    order?.po_number?.trim(),
    clientName,
  ]
    .filter((v): v is string => !!v)
    .map((v) => v.toLowerCase());
  return fields.some((field) => field.includes(q));
}

export default function WholesaleShipmentsPage() {
  const { t, i18n } = useTranslation('wholesaleShipments');
  const { t: tOrder } = useTranslation('wholesaleOrderDetail');
  const { t: tStores } = useTranslation('stores');
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const { user } = useAuth();

  const [shipments, setShipments] = useState<Shipment[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [storeFilter, setStoreFilter] = useState<number | ''>('');
  const [search, setSearch] = useState('');
  const [storeFilterReady, setStoreFilterReady] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    const saved = localStorage.getItem(VIEW_STORAGE_KEY);
    if (saved === 'list') return 'list';
    return 'monitor';
  });
  const [companySettings, setCompanySettings] = useState<CompanySettings | null>(null);
  const [packingQueueOpen, setPackingQueueOpen] = useState(false);
  const [packingQueue, setPackingQueue] = useState<Shipment[]>([]);
  const [courierPickupOpen, setCourierPickupOpen] = useState(false);
  const [courierPickupQueue, setCourierPickupQueue] = useState<Shipment[]>([]);

  const courierOptions = useMemo(
    () => shipmentCourierOptionsFromSettings(companySettings?.shipment_couriers),
    [companySettings?.shipment_couriers],
  );

  const loadStores = useCallback(async () => {
    try {
      const all = await storesAPI.list();
      const userStores = user?.stores?.length
        ? all.filter((s) => user.stores!.some((us) => us.id === s.id))
        : all;
      const list = userStores.length ? userStores : all;
      setStores(list);
      if (!storeFilterReady) {
        const defaultStore = user?.stores?.[0]?.id ?? list[0]?.id ?? '';
        setStoreFilter(defaultStore);
        setStoreFilterReady(true);
      }
    } catch {
      enqueueSnackbar(t('loadStoresFailed'), { variant: 'error' });
    }
  }, [enqueueSnackbar, storeFilterReady, t, user?.stores]);

  const includeOldCompleted = viewMode === 'list';

  const loadShipments = useCallback(async () => {
    if (!storeFilterReady) return;
    try {
      setLoading(true);
      const data = await shipmentsAPI.list({
        store_id: storeFilter ? Number(storeFilter) : undefined,
        include_old_completed: includeOldCompleted,
      });
      setShipments(data);
    } catch {
      enqueueSnackbar(t('loadFailed'), { variant: 'error' });
      setShipments([]);
    } finally {
      setLoading(false);
    }
  }, [enqueueSnackbar, includeOldCompleted, storeFilter, storeFilterReady, t]);

  useEffect(() => {
    settingsAPI.getCompany().then(setCompanySettings).catch(() => {});
  }, []);

  useEffect(() => {
    loadStores();
  }, [loadStores]);

  useEffect(() => {
    loadShipments();
  }, [loadShipments]);

  useEffect(() => {
    localStorage.setItem(VIEW_STORAGE_KEY, viewMode);
  }, [viewMode]);

  useEffect(() => {
    if (viewMode !== 'monitor') return;
    const id = window.setInterval(() => {
      void loadShipments();
    }, MONITOR_REFRESH_MS);
    return () => window.clearInterval(id);
  }, [viewMode, loadShipments]);

  const filteredShipments = useMemo(() => {
    const q = search.trim().toLowerCase();
    const searched = q ? shipments.filter((s) => shipmentMatchesSearch(s, q)) : shipments;
    const completedDays = includeOldCompleted ? LIST_COMPLETED_DAYS : MONITOR_COMPLETED_DAYS;
    const completedCutoff = subDays(new Date(), completedDays);
    const filtered =
      viewMode === 'monitor'
        ? searched.filter((s) => {
            if (s.status !== 'completed') return true;
            const at = s.updated_at ? new Date(s.updated_at) : null;
            return at ? at >= completedCutoff : false;
          })
        : searched;
    return [...filtered].sort(sortShipmentsByOrderTimeDesc);
  }, [includeOldCompleted, search, shipments, viewMode]);

  const monitorCompletedDays = includeOldCompleted ? LIST_COMPLETED_DAYS : MONITOR_COMPLETED_DAYS;

  const handleViewModeChange = (_: MouseEvent<HTMLElement>, next: ViewMode | null) => {
    if (next) setViewMode(next);
  };

  const patchShipmentInList = useCallback((updated: Shipment) => {
    setShipments((list) =>
      list.map((s) => (s.id === updated.id ? mergeShipmentListRow(s, updated) : s)),
    );
  }, []);

  const handleStartPackingQueue = (queue: Shipment[]) => {
    setPackingQueue(queue.filter((s) => shipmentNeedsPacking(s.status)));
    setPackingQueueOpen(true);
  };

  const handleStartCourierPickup = (queue: Shipment[]) => {
    setCourierPickupQueue(queue.filter((s) => s.status === 'packed'));
    setCourierPickupOpen(true);
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 3, gap: 2, flexWrap: 'wrap' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <ShipmentIcon color="primary" />
          <Typography variant="h4">{t('title')}</Typography>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <ToggleButtonGroup
            size="small"
            value={viewMode}
            exclusive
            onChange={handleViewModeChange}
            aria-label={t('viewMode')}
          >
            <ToggleButton value="list" aria-label={t('viewList')}>
              <Tooltip title={t('viewList')}>
                <ViewListIcon fontSize="small" />
              </Tooltip>
            </ToggleButton>
            <ToggleButton value="monitor" aria-label={t('viewMonitor')}>
              <Tooltip title={t('viewMonitor')}>
                <GridViewIcon fontSize="small" />
              </Tooltip>
            </ToggleButton>
          </ToggleButtonGroup>
          <Tooltip title={t('refresh')}>
            <IconButton onClick={loadShipments} disabled={loading}>
              <RefreshIcon />
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 2, mb: 2, alignItems: 'center' }}>
        <TextField
          select
          label={t('filterStore')}
          value={storeFilter}
          onChange={(e) => setStoreFilter(e.target.value ? Number(e.target.value) : '')}
          size="small"
          sx={{ minWidth: 200 }}
        >
          {user?.stores?.length ? null : (
            <MenuItem value="">{t('allStores')}</MenuItem>
          )}
          {stores.map((s) => (
            <MenuItem key={s.id} value={s.id}>
              {s.name}
              {s.is_warehouse_only ? ` (${tStores('warehouseOnly')})` : ''}
            </MenuItem>
          ))}
        </TextField>
        {viewMode === 'monitor' ? (
          <Typography variant="body2" color="text.secondary" sx={{ alignSelf: 'center' }}>
            {t('monitorViewHint')}
          </Typography>
        ) : null}
        <TextField
          label={t('search')}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          size="small"
          placeholder={t('searchPlaceholder')}
          sx={{ minWidth: { xs: '100%', sm: 280 }, flex: 1 }}
        />
      </Box>

      {loading && filteredShipments.length === 0 ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
          <CircularProgress />
        </Box>
      ) : viewMode === 'monitor' ? (
        filteredShipments.length === 0 ? (
          <Paper sx={{ p: 4, textAlign: 'center' }}>
            <Typography color="text.secondary">{t('noShipments')}</Typography>
          </Paper>
        ) : (
          <>
            <ShipmentMonitorGrid
              shipments={filteredShipments}
              lang={i18n.language}
              t={t}
              onProcessLabel={t('process')}
              onViewLabel={t('view')}
              completedDaysLabel={monitorCompletedDays}
              onStartPackingQueue={handleStartPackingQueue}
              onStartCourierPickup={handleStartCourierPickup}
            />
            <ShipmentPackingQueueDialog
              open={packingQueueOpen}
              queue={packingQueue}
              lang={i18n.language}
              courierOptions={courierOptions}
              t={t}
              tOrder={tOrder}
              onClose={() => {
                setPackingQueueOpen(false);
                void loadShipments();
              }}
              onShipmentPacked={(updated) => {
                patchShipmentInList(updated);
                setPackingQueue((q) => q.filter((s) => s.id !== updated.id));
              }}
            />
            <ShipmentCourierPickupDialog
              open={courierPickupOpen}
              queue={courierPickupQueue}
              courierOptions={courierOptions}
              t={t}
              onClose={() => {
                setCourierPickupOpen(false);
                void loadShipments();
              }}
              onShipmentShipped={(updated) => {
                patchShipmentInList(updated);
                setCourierPickupQueue((q) => q.filter((s) => s.id !== updated.id));
              }}
            />
          </>
        )
      ) : (
        <TableContainer component={Paper}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>{t('orderNumber')}</TableCell>
                <TableCell>{t('poNumber')}</TableCell>
                <TableCell>{t('client')}</TableCell>
                <TableCell>{t('store')}</TableCell>
                <TableCell align="right">{t('items')}</TableCell>
                <TableCell>{t('updated')}</TableCell>
                <TableCell align="right">{t('actions')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {filteredShipments.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={7} align="center" sx={{ py: 4 }}>
                    <Typography color="text.secondary">{t('noShipments')}</Typography>
                  </TableCell>
                </TableRow>
              ) : (
                filteredShipments.map((s) => {
                  const order = s.wholesale_order;
                  const itemCount = s.items?.length ?? 0;
                  const totalQty =
                    s.items?.reduce((sum, si) => sum + effectiveShipmentItemQty(si), 0) ?? 0;
                  return (
                    <TableRow
                      key={s.id}
                      hover
                      sx={{ cursor: 'pointer' }}
                      onClick={() => navigate(`/wholesale-shipments/${s.id}`)}
                    >
                      <TableCell sx={{ fontWeight: 600 }}>
                        {order?.order_number ?? `#${s.wholesale_order_id}`}
                      </TableCell>
                      <TableCell>{order?.po_number || '—'}</TableCell>
                      <TableCell>{order?.wholesale_client?.name || '—'}</TableCell>
                      <TableCell>{s.store?.name ?? `Store #${s.store_id}`}</TableCell>
                      <TableCell align="right">
                        {itemCount > 0 ? `${itemCount} (${totalQty})` : '—'}
                      </TableCell>
                      <TableCell>
                        {s.updated_at ? format(new Date(s.updated_at), 'dd MMM yyyy HH:mm') : '—'}
                      </TableCell>
                      <TableCell align="right" onClick={(e) => e.stopPropagation()}>
                        <Button
                          size="small"
                          variant={shipmentNeedsPacking(s.status) ? 'contained' : 'outlined'}
                          endIcon={<ChevronRightIcon />}
                          onClick={() => navigate(`/wholesale-shipments/${s.id}`)}
                        >
                          {shipmentNeedsPacking(s.status) ? t('process') : t('view')}
                        </Button>
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
