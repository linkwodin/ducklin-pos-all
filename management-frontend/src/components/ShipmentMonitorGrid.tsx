import { useMemo, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { Box, Button, Chip, Divider, IconButton, Paper, Tooltip, Typography } from '@mui/material';
import {
  ChevronRight as ChevronRightIcon,
  PlayArrow as ProcessIcon,
  PlayCircle as PlayColumnIcon,
} from '@mui/icons-material';
import { format } from 'date-fns';
import type { TFunction } from 'i18next';
import type { Shipment } from '../types';
import { shipmentAssignedSummary } from '../utils/wholesaleOrderAssignment';
import { shipmentNeedsPacking } from '../utils/shipmentStatus';
import { monitorLinesForShipment } from '../utils/shipmentMonitorLines';
import { formatShipmentOrderDate, sortShipmentsByOrderTimeDesc } from '../utils/shipmentOrderTime';
import ProductImageWithPopover from './ProductImageWithPopover';

const ACTIVE_COLUMNS = [
  {
    id: 'packing' as const,
    labelKey: 'monitorColumnPacking',
    hintKey: 'monitorColumnPackingHint',
    statuses: ['assigned', 'packing'],
    color: 'warning.main',
    lightBg: 'warning.50',
    chipColor: 'warning' as const,
  },
  {
    id: 'packed' as const,
    labelKey: 'monitorColumnPacked',
    hintKey: 'monitorColumnPackedHint',
    statuses: ['packed'],
    color: 'info.main',
    lightBg: 'info.50',
    chipColor: 'info' as const,
  },
  {
    id: 'shipped' as const,
    labelKey: 'monitorColumnShipped',
    hintKey: 'monitorColumnShippedHint',
    statuses: ['shipped'],
    color: 'success.main',
    lightBg: 'success.50',
    chipColor: 'success' as const,
  },
];

const COMPLETED_MAX_ROWS = 12;

type ShipmentMonitorGridProps = {
  shipments: Shipment[];
  lang: string;
  t: TFunction;
  onProcessLabel: string;
  onViewLabel: string;
  completedDaysLabel: number;
  onStartPackingQueue: (shipments: Shipment[]) => void;
  onStartCourierPickup: (shipments: Shipment[]) => void;
};

function formatQtyLabel(qty: number): string {
  return qty % 1 === 0 ? String(Math.round(qty)) : qty.toFixed(2);
}

type TicketContentProps = {
  shipment: Shipment;
  columnColor: string;
  lang: string;
  t: TFunction;
  onProcessLabel: string;
  onViewLabel: string;
  onOpen: () => void;
  compact?: boolean;
};

function TicketContent({
  shipment,
  columnColor,
  lang,
  t,
  onProcessLabel,
  onViewLabel,
  onOpen,
  compact,
}: TicketContentProps) {
  const order = shipment.wholesale_order;
  const orderNumber = order?.order_number ?? `#${shipment.wholesale_order_id}`;
  const orderRef = order?.ref_no?.trim();
  const poNumber = order?.po_number?.trim();
  const clientName = order?.wholesale_client?.name?.trim();
  const storeName = shipment.store?.name?.trim();
  const needsPacking = shipmentNeedsPacking(shipment.status);
  const lines = monitorLinesForShipment(shipment, lang, (id) => t('monitorItemFallback', { id }));
  const summary = shipmentAssignedSummary(shipment);
  const orderDateLabel = formatShipmentOrderDate(shipment);

  if (compact) {
    const itemCount = lines.length || summary.productCount;
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, width: '100%' }}>
        <Typography variant="body2" sx={{ fontWeight: 700, minWidth: 0, flex: '1 1 140px' }} noWrap>
          {orderNumber}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ flex: '2 1 160px', minWidth: 0 }} noWrap>
          {clientName || '—'}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ flex: '0 0 auto', whiteSpace: 'nowrap' }}>
          {itemCount > 0 ? t('monitorCompletedItems', { count: itemCount }) : t('monitorNoItems')}
        </Typography>
        <Typography variant="caption" color="text.secondary" sx={{ flex: '0 0 auto', whiteSpace: 'nowrap' }}>
          {orderDateLabel ?? '—'}
        </Typography>
        <ChevronRightIcon fontSize="small" color="action" />
      </Box>
    );
  }

  return (
    <Paper
      variant="outlined"
      sx={{
        borderRadius: 2,
        overflow: 'hidden',
        bgcolor: 'background.paper',
        borderLeft: 4,
        borderLeftColor: columnColor,
        transition: 'box-shadow 0.15s ease, border-color 0.15s ease',
        ...(needsPacking
          ? {
              borderColor: 'warning.light',
              boxShadow: '0 0 0 1px rgba(237, 108, 2, 0.25)',
            }
          : {}),
      }}
    >
      <Box sx={{ p: 1.5 }}>
        <Box sx={{ mb: 0.75 }}>
          <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 1 }}>
            <Box sx={{ minWidth: 0 }}>
              <Typography variant="h6" sx={{ fontWeight: 800, lineHeight: 1.2 }} noWrap>
                {orderNumber}
              </Typography>
              {orderRef ? (
                <Typography variant="body2" color="text.secondary" noWrap>
                  {t('monitorOrderRef', { ref: orderRef })}
                </Typography>
              ) : null}
              {(poNumber || clientName) && (
                <Typography variant="body2" color="text.secondary" noWrap>
                  {[poNumber ? `PO ${poNumber}` : null, clientName].filter(Boolean).join(' · ')}
                </Typography>
              )}
              {storeName ? (
                <Typography variant="caption" color="text.secondary" display="block" noWrap>
                  {storeName}
                </Typography>
              ) : null}
            </Box>
            {orderDateLabel ? (
              <Chip size="small" label={orderDateLabel} variant="outlined" sx={{ flexShrink: 0 }} />
            ) : null}
          </Box>
        </Box>

        {lines.length > 0 ? (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.75, mb: 1.25 }}>
            {lines.slice(0, 5).map((line) => {
              const qtyLabel = formatQtyLabel(line.qty);
              const boxesLabel = line.boxes != null ? formatQtyLabel(line.boxes) : null;
              return (
                <Box key={line.key} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <ProductImageWithPopover imageUrl={line.imageUrl} productName={line.name} size={32} />
                  <Box sx={{ minWidth: 0, flex: 1 }}>
                    <Typography variant="body2" sx={{ fontWeight: 600, lineHeight: 1.25 }} noWrap>
                      {line.name}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {boxesLabel
                        ? t('monitorItemQtyBoxes', { qty: qtyLabel, boxes: boxesLabel })
                        : t('monitorItemQty', { qty: qtyLabel })}
                    </Typography>
                  </Box>
                </Box>
              );
            })}
            {lines.length > 5 ? (
              <Typography variant="caption" color="text.secondary">
                {t('monitorMoreItems', { count: lines.length - 5 })}
              </Typography>
            ) : null}
          </Box>
        ) : summary.productCount > 0 ? (
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1.25 }}>
            {t('monitorItemSummary', {
              count: summary.productCount,
              qty: formatQtyLabel(summary.totalQty),
            })}
          </Typography>
        ) : (
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1.25, fontStyle: 'italic' }}>
            {t('monitorNoItems')}
          </Typography>
        )}

        <Button
          fullWidth
          size="small"
          variant={needsPacking ? 'contained' : 'outlined'}
          color={needsPacking ? 'warning' : 'primary'}
          startIcon={needsPacking ? <ProcessIcon /> : undefined}
          onClick={(e) => {
            e.stopPropagation();
            onOpen();
          }}
          sx={{ fontWeight: 700, textTransform: 'none' }}
        >
          {needsPacking ? onProcessLabel : onViewLabel}
        </Button>
      </Box>
    </Paper>
  );
}

function ShipmentCard({
  shipment,
  columnColor,
  lang,
  t,
  onProcessLabel,
  onViewLabel,
  onOpen,
}: {
  shipment: Shipment;
  columnColor: string;
  lang: string;
  t: TFunction;
  onProcessLabel: string;
  onViewLabel: string;
  onOpen: () => void;
}) {
  return (
    <Box onClick={onOpen} sx={{ cursor: 'pointer' }}>
      <TicketContent
        shipment={shipment}
        columnColor={columnColor}
        lang={lang}
        t={t}
        onProcessLabel={onProcessLabel}
        onViewLabel={onViewLabel}
        onOpen={onOpen}
      />
    </Box>
  );
}

function ColumnBody({
  children,
  isEmpty,
  emptyLabel,
}: {
  children: ReactNode;
  isEmpty: boolean;
  emptyLabel: string;
}) {
  return (
    <Box
      sx={{
        p: 1.25,
        display: 'flex',
        flexDirection: 'column',
        gap: 1.25,
        overflowY: 'auto',
        flex: 1,
        minHeight: 120,
      }}
    >
      {isEmpty ? (
        <Box
          sx={{
            py: 4,
            px: 2,
            textAlign: 'center',
            border: '1px dashed',
            borderColor: 'divider',
            borderRadius: 2,
            bgcolor: 'background.paper',
          }}
        >
          <Typography variant="body2" color="text.secondary">
            {emptyLabel}
          </Typography>
        </Box>
      ) : (
        children
      )}
    </Box>
  );
}

export default function ShipmentMonitorGrid({
  shipments,
  lang,
  t,
  onProcessLabel,
  onViewLabel,
  completedDaysLabel,
  onStartPackingQueue,
  onStartCourierPickup,
}: ShipmentMonitorGridProps) {
  const navigate = useNavigate();

  const { activeByColumn, completed } = useMemo(() => {
    const ordered = [...shipments].sort(sortShipmentsByOrderTimeDesc);
    const activeMap = new Map<string, Shipment[]>();
    for (const col of ACTIVE_COLUMNS) {
      activeMap.set(col.id, []);
    }
    const completedList: Shipment[] = [];

    for (const s of ordered) {
      if (s.status === 'completed') {
        completedList.push(s);
        continue;
      }
      const col = ACTIVE_COLUMNS.find((c) =>
        (c.statuses as readonly string[]).includes(s.status),
      );
      if (col) activeMap.get(col.id)!.push(s);
    }

    for (const col of ACTIVE_COLUMNS) {
      activeMap.get(col.id)!.sort(sortShipmentsByOrderTimeDesc);
    }
    completedList.sort(sortShipmentsByOrderTimeDesc);

    return {
      activeByColumn: activeMap,
      completed: completedList.slice(0, COMPLETED_MAX_ROWS),
    };
  }, [shipments]);

  const openShipment = (id: number) => navigate(`/wholesale-shipments/${id}`);

  return (
    <Box>
      <Box
        sx={{
          display: 'grid',
          gridTemplateColumns: { xs: '1fr', md: 'repeat(3, minmax(0, 1fr))' },
          gap: 2,
          alignItems: 'start',
        }}
      >
        {ACTIVE_COLUMNS.map((column) => {
          const columnShipments = activeByColumn.get(column.id) ?? [];
          return (
            <Paper
              key={column.id}
              variant="outlined"
              sx={{
                display: 'flex',
                flexDirection: 'column',
                minWidth: 0,
                maxHeight: { md: 'calc(100vh - 320px)' },
                bgcolor: column.lightBg,
                borderColor: 'divider',
                borderRadius: 2,
                overflow: 'hidden',
              }}
            >
              <Box
                sx={{
                  px: 1.5,
                  py: 1.25,
                  bgcolor: 'background.paper',
                  borderBottom: 1,
                  borderColor: 'divider',
                  display: 'flex',
                  alignItems: 'flex-start',
                  justifyContent: 'space-between',
                  gap: 1,
                }}
              >
                <Box sx={{ display: 'flex', gap: 1, minWidth: 0, flex: 1 }}>
                  <Box sx={{ width: 4, height: 24, borderRadius: 1, bgcolor: column.color, flexShrink: 0, mt: 0.25 }} />
                  <Box sx={{ minWidth: 0 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, lineHeight: 1.3 }}>
                      {t(column.labelKey)}
                    </Typography>
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.25, lineHeight: 1.35 }}>
                      {t(column.hintKey)}
                    </Typography>
                  </Box>
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexShrink: 0, pt: 0.25 }}>
                  {column.id === 'packing' ? (
                    <Tooltip title={t('packingQueueStart')}>
                      <span>
                        <IconButton
                          size="small"
                          color="warning"
                          disabled={columnShipments.length === 0}
                          onClick={() => onStartPackingQueue(columnShipments)}
                          aria-label={t('packingQueueStart')}
                        >
                          <PlayColumnIcon />
                        </IconButton>
                      </span>
                    </Tooltip>
                  ) : null}
                  {column.id === 'packed' ? (
                    <Tooltip title={t('courierPickupStart')}>
                      <span>
                        <IconButton
                          size="small"
                          color="info"
                          disabled={columnShipments.length === 0}
                          onClick={() => onStartCourierPickup(columnShipments)}
                          aria-label={t('courierPickupStart')}
                        >
                          <PlayColumnIcon />
                        </IconButton>
                      </span>
                    </Tooltip>
                  ) : null}
                  <Chip size="small" label={columnShipments.length} color={column.chipColor} />
                </Box>
              </Box>

              <ColumnBody isEmpty={columnShipments.length === 0} emptyLabel={t('monitorColumnEmpty')}>
                {columnShipments.map((shipment) => (
                  <ShipmentCard
                    key={shipment.id}
                    shipment={shipment}
                    columnColor={column.color}
                    lang={lang}
                    t={t}
                    onProcessLabel={onProcessLabel}
                    onViewLabel={onViewLabel}
                    onOpen={() => openShipment(shipment.id)}
                  />
                ))}
              </ColumnBody>
            </Paper>
          );
        })}
      </Box>

      <Paper variant="outlined" sx={{ mt: 2, borderRadius: 2, overflow: 'hidden' }}>
        <Box
          sx={{
            px: 1.5,
            py: 1.25,
            bgcolor: 'grey.100',
            borderBottom: 1,
            borderColor: 'divider',
            display: 'flex',
            alignItems: 'flex-start',
            justifyContent: 'space-between',
            gap: 1,
            flexWrap: 'wrap',
          }}
        >
          <Box sx={{ display: 'flex', gap: 1, minWidth: 0, flex: 1 }}>
            <Box sx={{ width: 4, height: 24, borderRadius: 1, bgcolor: 'grey.500', flexShrink: 0, mt: 0.25 }} />
            <Box sx={{ minWidth: 0 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, lineHeight: 1.3 }}>
                  {t('monitorColumnCompleted')}
                </Typography>
                <Chip size="small" label={completed.length} variant="outlined" />
              </Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.25, lineHeight: 1.35 }}>
                {t('monitorColumnCompletedHint')}
              </Typography>
            </Box>
          </Box>
          <Typography variant="caption" color="text.secondary" sx={{ flexShrink: 0, pt: 0.25 }}>
            {t('monitorCompletedHint', { days: completedDaysLabel })}
          </Typography>
        </Box>

        <ColumnBody isEmpty={completed.length === 0} emptyLabel={t('monitorColumnEmpty')}>
          {completed.map((shipment, index) => (
            <Box key={shipment.id}>
              {index > 0 ? <Divider /> : null}
              <Box
                onClick={() => openShipment(shipment.id)}
                sx={{
                  px: 1.5,
                  py: 1,
                  borderRadius: 1,
                  cursor: 'pointer',
                  '&:hover': { bgcolor: 'action.hover' },
                }}
              >
                <TicketContent
                  shipment={shipment}
                  columnColor="grey.500"
                  lang={lang}
                  t={t}
                  onProcessLabel=""
                  onViewLabel=""
                  onOpen={() => openShipment(shipment.id)}
                  compact
                />
              </Box>
            </Box>
          ))}
        </ColumnBody>
      </Paper>

      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', textAlign: 'right', mt: 1 }}>
        {t('monitorLastUpdated', { time: format(new Date(), 'HH:mm:ss') })}
      </Typography>
    </Box>
  );
}
