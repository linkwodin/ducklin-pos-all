import { useMemo, useState, useEffect, type ReactNode } from 'react';
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from '@dnd-kit/core';
import { CSS } from '@dnd-kit/utilities';
import {
  Box,
  Paper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
  Button,
  CircularProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Chip,
  TableContainer,
  Alert,
  IconButton,
  Tooltip,
  useMediaQuery,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
} from '@mui/material';
import { alpha, useTheme } from '@mui/material/styles';
import DragIndicatorIcon from '@mui/icons-material/DragIndicator';
import InfoOutlinedIcon from '@mui/icons-material/InfoOutlined';
import MoveToInboxIcon from '@mui/icons-material/MoveToInbox';
import StorefrontIcon from '@mui/icons-material/Storefront';
import type { TFunction } from 'i18next';
import type { Stock, Store, WholesaleOrder, WholesaleOrderItem } from '../types';
import { productDisplayName } from '../utils/productDisplay';
import { stockLevelValue } from '../utils/productInventory';
import {
  buildAssignmentBoardCards,
  cellDroppableId,
  collectAssignmentStockWarnings,
  formatAssignStoreStockHint,
  formatAssignmentQty,
  parseCellDroppableId,
  storeCanFulfillItemQty,
  storeAllowsAssignmentTarget,
  storeStockHighlightLevel,
  type AssignmentBoardCard,
  type StagedStoreAssignment,
  type StoreStockHighlight,
} from '../utils/wholesaleOrderAssignment';
import { stockAPI } from '../services/api';

type Props = {
  order: WholesaleOrder;
  stores: Store[];
  staged: StagedStoreAssignment[];
  manualMode: boolean;
  lang: string;
  actioning: boolean;
  allLinesAssigned: boolean;
  pendingQtyForItem: (item: Pick<WholesaleOrderItem, 'id' | 'quantity'>) => number;
  onAssignItem: (itemId: number, storeId: number, quantity: number) => Promise<void>;
  onUnassignItem: (itemId: number, storeId: number, quantity: number, staged: boolean) => Promise<void>;
  onMoveItem: (
    itemId: number,
    fromStoreId: number,
    toStoreId: number,
    quantity: number,
    staged: boolean,
  ) => Promise<void>;
  onAssignByDefaults: () => void;
  onConfirmAllocation: () => Promise<void>;
  onBlockAssignmentTarget?: () => void;
  onCancelManual?: () => void;
  t: TFunction;
};

type AssignQtyDialogState = {
  itemId: number;
  targetStoreId: number | null | undefined;
  sourceCard: AssignmentBoardCard;
  maxQty: number;
  qty: string;
  pickStore: boolean;
};

function storeChipDroppableId(storeId: number): string {
  return `store-chip-${storeId}`;
}

function storeTableDroppableId(storeId: number): string {
  return `store-table-${storeId}`;
}

export function AssignmentHowToTooltipIcon({ t }: { t: TFunction }) {
  return (
    <Tooltip
      arrow
      placement="bottom-start"
      slotProps={{
        tooltip: {
          sx: { maxWidth: 380, p: 1.5 },
        },
      }}
      title={
        <Box>
          <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
            {t('wholesaleOrderDetail:assignHowToTitle')}
          </Typography>
          <Box component="ol" sx={{ m: 0, pl: 2, '& > li + li': { mt: 0.5 } }}>
            {([1, 2, 3] as const).map((step) => (
              <Box component="li" key={step}>
                <Typography variant="body2" component="span" sx={{ fontWeight: 600 }}>
                  {t(`wholesaleOrderDetail:assignHowToStep${step}Title`)}
                </Typography>
                <Typography variant="body2" component="span" sx={{ opacity: 0.92 }}>
                  {' — '}
                  {t(`wholesaleOrderDetail:assignHowToStep${step}Body`)}
                </Typography>
              </Box>
            ))}
          </Box>
          <Typography variant="caption" sx={{ fontWeight: 700, display: 'block', mt: 1.25, mb: 0.5 }}>
            {t('wholesaleOrderDetail:assignHowToStoreColorsTitle')}
          </Typography>
          <Typography variant="caption" component="div" sx={{ display: 'flex', alignItems: 'flex-start', gap: 0.75, mb: 0.35 }}>
            <Box
              component="span"
              sx={{ width: 10, height: 10, borderRadius: '50%', bgcolor: 'success.light', flexShrink: 0, mt: '3px' }}
            />
            {t('wholesaleOrderDetail:assignHowToStoreGreen')}
          </Typography>
          <Typography variant="caption" component="div" sx={{ display: 'flex', alignItems: 'flex-start', gap: 0.75 }}>
            <Box
              component="span"
              sx={{ width: 10, height: 10, borderRadius: '50%', bgcolor: 'warning.light', flexShrink: 0, mt: '3px' }}
            />
            {t('wholesaleOrderDetail:assignHowToStoreOrange')}
          </Typography>
        </Box>
      }
    >
      <IconButton
        size="small"
        color="info"
        aria-label={t('wholesaleOrderDetail:assignHowToTitle')}
        sx={{ p: 0.375 }}
      >
        <InfoOutlinedIcon sx={{ fontSize: 20 }} />
      </IconButton>
    </Tooltip>
  );
}

function parseStoreDroppableId(id: string): number | null {
  if (id.startsWith('store-chip-')) {
    const n = Number(id.slice(11));
    return Number.isNaN(n) ? null : n;
  }
  if (id.startsWith('store-table-')) {
    const n = Number(id.slice(12));
    return Number.isNaN(n) ? null : n;
  }
  return null;
}

function storeHeaderSx(highlight: StoreStockHighlight, dragHighlight: boolean) {
  if (dragHighlight) {
    return {
      bgcolor: (theme: { palette: { primary: { main: string } } }) => alpha(theme.palette.primary.main, 0.16),
      borderBottomColor: 'primary.main',
    };
  }
  if (highlight === 'full') {
    return {
      bgcolor: (theme: { palette: { success: { main: string } } }) => alpha(theme.palette.success.main, 0.14),
      borderBottomColor: 'success.main',
    };
  }
  if (highlight === 'partial') {
    return {
      bgcolor: (theme: { palette: { warning: { main: string } } }) => alpha(theme.palette.warning.main, 0.12),
      borderBottomColor: 'warning.main',
    };
  }
  return {
    bgcolor: (theme: { palette: { primary: { main: string } } }) => alpha(theme.palette.primary.main, 0.08),
  };
}

function storePaperSx(highlight: StoreStockHighlight, dragHighlight: boolean) {
  if (dragHighlight) {
    return { outline: '2px solid', outlineColor: 'primary.main' };
  }
  if (highlight === 'full') {
    return { borderColor: 'success.main', borderWidth: 2 };
  }
  if (highlight === 'partial') {
    return { borderColor: 'warning.main', borderWidth: 2 };
  }
  return undefined;
}

function AssignmentMobileLabelValue({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <Box
      sx={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'flex-start',
        gap: 1.5,
      }}
    >
      <Typography variant="caption" color="text.secondary" sx={{ flexShrink: 0, pt: 0.35, minWidth: '5.5rem' }}>
        {label}
      </Typography>
      <Box sx={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'flex-end', flexWrap: 'wrap', gap: 0.5 }}>
        {children}
      </Box>
    </Box>
  );
}

function AssignmentStockSummary({
  available,
  assignQty,
  stockLoading,
  t,
}: {
  available: number | null;
  assignQty: number;
  stockLoading: boolean;
  t: TFunction;
}) {
  const hint = formatAssignStoreStockHint(available, assignQty, true);
  const after =
    available != null && Number.isFinite(available) && assignQty > 0.0001
      ? available - assignQty
      : null;

  if (stockLoading) {
    return (
      <Typography variant="body2" color="text.secondary">
        …
      </Typography>
    );
  }

  return (
    <Stack spacing={0.25} sx={{ alignItems: 'flex-end' }}>
      <Typography variant="body2" sx={{ fontWeight: 500 }}>
        {available != null
          ? t('wholesaleOrderDetail:assignMobileStockOnHand', { qty: formatAssignmentQty(available) })
          : '—'}
      </Typography>
      {assignQty > 0.0001 ? (
        <Typography variant="caption" color="text.secondary">
          {t('wholesaleOrderDetail:assignMobileStockAssigned', { qty: formatAssignmentQty(assignQty) })}
        </Typography>
      ) : null}
      {after != null ? (
        <Typography
          variant="caption"
          sx={{ fontWeight: 600, color: hint.sufficient ? 'success.main' : 'error.main' }}
        >
          {t('wholesaleOrderDetail:assignMobileStockAfter', { qty: formatAssignmentQty(after) })}
        </Typography>
      ) : null}
    </Stack>
  );
}

function mobileStoreOptionsForAssign(
  stores: Store[],
  order: WholesaleOrder,
  item: WholesaleOrderItem | undefined,
  needQty: number,
  excludeStoreId: number | null | undefined,
  stockByStoreProduct: Map<string, Stock>,
): Array<{
  store: Store;
  hint: { text: string; sufficient: boolean };
}> {
  if (!item) return [];
  const qty = Number.isFinite(needQty) && needQty > 0 ? needQty : 0;
  return stores
    .filter((s) => storeAllowsAssignmentTarget(order, s.id) && s.id !== excludeStoreId)
    .map((store) => {
      const stock = stockByStoreProduct.get(`${store.id}-${item.product_id}`);
      const available = stock ? stockLevelValue(stock, item.product) : null;
      const hint = formatAssignStoreStockHint(available, qty, false);
      return { store, hint };
    })
    .sort((a, b) => {
      if (a.hint.sufficient !== b.hint.sufficient) return a.hint.sufficient ? -1 : 1;
      return a.store.name.localeCompare(b.store.name);
    });
}

function AssignmentChip({
  card,
  isGhost,
  onRemove,
  removeTooltip,
  touchAssignMode,
  onTouchAssign,
}: {
  card: AssignmentBoardCard;
  isGhost?: boolean;
  onRemove?: () => void;
  removeTooltip?: string;
  touchAssignMode?: boolean;
  onTouchAssign?: (card: AssignmentBoardCard) => void;
}) {
  const draggable = (card.store_id == null || card.can_unassign) && !touchAssignMode;
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: card.dragId,
    data: { card },
    disabled: !draggable || isGhost,
  });
  const style = transform ? { transform: CSS.Translate.toString(transform) } : undefined;

  const showDelete = !touchAssignMode && !!onRemove && card.can_unassign;

  return (
    <Box
      ref={setNodeRef}
      style={style}
      sx={{
        opacity: isDragging || isGhost ? 0.35 : 1,
        display: 'inline-flex',
        ...(showDelete
          ? {
              '@media (hover: hover)': {
                '& .MuiChip-deleteIcon': {
                  opacity: 0,
                  transition: 'opacity 0.15s ease',
                },
                '&:hover .MuiChip-deleteIcon': {
                  opacity: 0.7,
                },
                '&:hover .MuiChip-deleteIcon:hover': {
                  opacity: 1,
                },
              },
            }
          : {}),
      }}
    >
      <Chip
        size="small"
        icon={
          draggable ? (
            <Box {...listeners} {...attributes} sx={{ display: 'flex', cursor: 'grab', pl: 0.5 }}>
              <DragIndicatorIcon sx={{ fontSize: 16 }} />
            </Box>
          ) : undefined
        }
        label={formatAssignmentQty(card.quantity)}
        variant={card.staged ? 'outlined' : 'filled'}
        onDelete={showDelete ? onRemove : undefined}
        onClick={
          touchAssignMode && onTouchAssign && (card.store_id == null || card.can_unassign)
            ? () => onTouchAssign(card)
            : undefined
        }
        title={removeTooltip}
        sx={{
          ...(card.store_id != null && card.staged ? { borderStyle: 'dashed' } : undefined),
          ...(touchAssignMode && (card.store_id == null || card.can_unassign)
            ? { cursor: 'pointer' }
            : undefined),
        }}
      />
    </Box>
  );
}

function QtyDropCell({
  itemId,
  storeId,
  cards,
  stockSufficient,
  activeDragId,
  onRemove,
  removeTooltip,
  dropHint,
  dropAllowed = true,
  touchAssignMode,
  onTouchAssign,
  mobileEmptyHint,
}: {
  itemId: number;
  storeId: number | null;
  cards: AssignmentBoardCard[];
  stockSufficient?: boolean;
  activeDragId: string | null;
  onRemove: (card: AssignmentBoardCard) => void;
  removeTooltip: string;
  dropHint: string;
  dropAllowed?: boolean;
  touchAssignMode?: boolean;
  onTouchAssign?: (card: AssignmentBoardCard) => void;
  mobileEmptyHint?: string;
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: cellDroppableId(itemId, storeId),
    disabled: !dropAllowed,
  });

  return (
    <TableCell
      ref={setNodeRef}
      align="center"
      sx={{
        verticalAlign: 'middle',
        width: 120,
        bgcolor: isOver ? 'action.hover' : undefined,
        outline: isOver ? '2px solid' : undefined,
        outlineColor: isOver ? 'primary.main' : undefined,
        ...(storeId != null && cards.length > 0 && stockSufficient === false
          ? { bgcolor: (theme) => alpha(theme.palette.error.main, 0.08) }
          : undefined),
      }}
    >
      <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0.5, py: 0.5, minHeight: 36 }}>
        {cards.length === 0 ? (
          <Typography variant="caption" color="text.disabled" sx={{ fontStyle: 'italic' }}>
            {touchAssignMode ? mobileEmptyHint ?? dropHint : dropHint}
          </Typography>
        ) : (
          cards.map((card) => (
            <AssignmentChip
              key={card.dragId}
              card={card}
              isGhost={activeDragId === card.dragId}
              onRemove={() => onRemove(card)}
              removeTooltip={removeTooltip}
              touchAssignMode={touchAssignMode}
              onTouchAssign={onTouchAssign}
            />
          ))
        )}
      </Box>
    </TableCell>
  );
}

function UnassignedTable({
  order,
  byItemId,
  lang,
  activeDragId,
  onRemove,
  onTouchAssign,
  touchAssignMode,
  t,
}: {
  order: WholesaleOrder;
  byItemId: Map<number, { unassigned: AssignmentBoardCard[]; byStore: Map<number, AssignmentBoardCard[]> }>;
  lang: string;
  activeDragId: string | null;
  onRemove: (card: AssignmentBoardCard) => void;
  onTouchAssign: (card: AssignmentBoardCard) => void;
  touchAssignMode: boolean;
  t: TFunction;
}) {
  const rows = (order.items ?? []).filter((it) => (byItemId.get(it.id)?.unassigned.length ?? 0) > 0);

  return (
    <Paper
      variant="outlined"
      sx={{
        width: '100%',
        display: 'flex',
        flexDirection: 'column',
        borderStyle: 'dashed',
        borderWidth: 2,
        borderColor: 'warning.main',
        bgcolor: (theme) => alpha(theme.palette.warning.main, 0.06),
        boxShadow: 'none',
      }}
    >
      <Box
        sx={{
          px: 2,
          py: 1.5,
          borderBottom: 1,
          borderColor: 'warning.main',
          bgcolor: (theme) => alpha(theme.palette.warning.main, 0.14),
          display: 'flex',
          alignItems: 'center',
          gap: 1,
          flexWrap: 'wrap',
        }}
      >
        <MoveToInboxIcon fontSize="small" color="warning" />
        <Typography variant="subtitle2" sx={{ fontWeight: 700, color: 'warning.dark' }}>
          {t('wholesaleOrderDetail:assignBoardSectionUnassigned')}
        </Typography>
        <Chip
          size="small"
          label={rows.length}
          color="warning"
          variant={rows.length > 0 ? 'filled' : 'outlined'}
        />
      </Box>
      {touchAssignMode ? (
        <Stack spacing={1.25} sx={{ p: 1.5 }}>
          {rows.length === 0 ? (
            <Typography variant="body2" color="text.secondary" sx={{ py: 2, textAlign: 'center' }}>
              {t('wholesaleOrderDetail:assignBoardAllAssigned')}
            </Typography>
          ) : (
            rows.map((it) => {
              const row = byItemId.get(it.id)!;
              const unassignedQty = row.unassigned.reduce((s, c) => s + c.quantity, 0);
              const pname = productDisplayName(it.product, lang) || `Product #${it.product_id}`;
              return (
                <Paper key={it.id} variant="outlined" sx={{ p: 1.5, borderColor: 'warning.light' }}>
                  <Typography variant="body2" sx={{ fontWeight: 600, mb: 1.25, lineHeight: 1.35, wordBreak: 'break-word' }}>
                    {pname}
                  </Typography>
                  <Stack spacing={1}>
                    <AssignmentMobileLabelValue label={t('wholesaleOrderDetail:qty')}>
                      <Typography variant="body2">{formatAssignmentQty(it.quantity)}</Typography>
                    </AssignmentMobileLabelValue>
                    <AssignmentMobileLabelValue label={t('wholesaleOrderDetail:assignBoardUnassigned')}>
                      <Typography variant="body2" sx={{ fontWeight: 600, color: 'warning.dark' }}>
                        {formatAssignmentQty(unassignedQty)}
                      </Typography>
                    </AssignmentMobileLabelValue>
                    {row.unassigned.map((card) => (
                      <Box key={card.dragId}>
                        <AssignmentChip
                          card={card}
                          onRemove={() => onRemove(card)}
                          removeTooltip={t('wholesaleOrderDetail:assignRemoveChipTooltip')}
                          touchAssignMode
                          onTouchAssign={onTouchAssign}
                        />
                        <Button
                          fullWidth
                          size="small"
                          variant="contained"
                          sx={{ mt: 1 }}
                          onClick={() => onTouchAssign(card)}
                        >
                          {t('wholesaleOrderDetail:assignMobileAssignBtn')}
                        </Button>
                      </Box>
                    ))}
                  </Stack>
                </Paper>
              );
            })
          )}
        </Stack>
      ) : (
      <TableContainer sx={{ width: '100%', overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderDetail:product')}</TableCell>
              <TableCell align="right" sx={{ fontWeight: 600, width: 96 }}>
                {t('wholesaleOrderDetail:qty')}
              </TableCell>
              <TableCell align="center" sx={{ fontWeight: 600, width: 120 }}>
                {t('wholesaleOrderDetail:assignBoardUnassigned')}
              </TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={3} align="center">
                  <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                    {t('wholesaleOrderDetail:assignBoardAllAssigned')}
                  </Typography>
                </TableCell>
              </TableRow>
            ) : (
              rows.map((it) => {
                const row = byItemId.get(it.id)!;
                return (
                  <TableRow key={it.id} hover>
                    <TableCell sx={{ fontWeight: 500 }}>
                      {productDisplayName(it.product, lang) || `Product #${it.product_id}`}
                    </TableCell>
                    <TableCell align="right">{formatAssignmentQty(it.quantity)}</TableCell>
                    <QtyDropCell
                      itemId={it.id}
                      storeId={null}
                      cards={row.unassigned}
                      activeDragId={activeDragId}
                      onRemove={onRemove}
                      removeTooltip={t('wholesaleOrderDetail:assignRemoveChipTooltip')}
                      dropHint={t('wholesaleOrderDetail:assignBoardDropHere')}
                    />
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </TableContainer>
      )}
    </Paper>
  );
}

function StoreDropChip({
  store,
  stockHighlight,
  dragHighlight,
  assignmentTargetAllowed,
  t,
}: {
  store: Store;
  stockHighlight: StoreStockHighlight;
  dragHighlight: boolean;
  assignmentTargetAllowed: boolean;
  t: TFunction;
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: storeChipDroppableId(store.id),
    disabled: !assignmentTargetAllowed,
  });

  const chipColor =
    !assignmentTargetAllowed
      ? 'default'
      : isOver || dragHighlight
        ? 'primary'
        : stockHighlight === 'full'
          ? 'success'
          : stockHighlight === 'partial'
            ? 'warning'
            : 'default';

  const chipVariant =
    !assignmentTargetAllowed
      ? 'outlined'
      : isOver || dragHighlight || stockHighlight !== 'none'
        ? 'filled'
        : 'outlined';

  return (
    <Box ref={assignmentTargetAllowed ? setNodeRef : undefined} sx={{ display: 'inline-flex' }}>
      <Chip
        label={store.name}
        variant={chipVariant}
        color={chipColor}
        sx={{
          cursor: assignmentTargetAllowed ? 'pointer' : 'not-allowed',
          opacity: assignmentTargetAllowed ? 1 : 0.55,
          fontWeight: assignmentTargetAllowed && (stockHighlight !== 'none' || dragHighlight || isOver) ? 600 : 400,
        }}
        title={
          !assignmentTargetAllowed
            ? t('wholesaleOrderDetail:assignBlockedCompletedShipment')
            : stockHighlight === 'full'
              ? t('wholesaleOrderDetail:assignBoardStoreStockOk')
              : stockHighlight === 'partial'
                ? t('wholesaleOrderDetail:assignBoardStoreStockPartial')
                : t('wholesaleOrderDetail:assignBoardStoreEmpty')
        }
      />
    </Box>
  );
}

function StoreChipBar({
  order,
  stores,
  storeHighlights,
  activeCard,
  activeDragItem,
  stockByStoreProduct,
  t,
}: {
  order: WholesaleOrder;
  stores: Store[];
  storeHighlights: Map<number, StoreStockHighlight>;
  activeCard: AssignmentBoardCard | null;
  activeDragItem: WholesaleOrderItem | undefined;
  stockByStoreProduct: Map<string, Stock>;
  t: TFunction;
}) {
  return (
    <Box
      sx={{
        position: 'sticky',
        top: 0,
        zIndex: 2,
        display: 'flex',
        alignItems: 'center',
        gap: 1,
        flexWrap: 'wrap',
        mb: 2,
        py: 1,
        bgcolor: 'background.paper',
        borderBottom: 1,
        borderColor: 'divider',
      }}
    >
      <Typography variant="caption" color="text.secondary" sx={{ mr: 0.5 }}>
        {t('wholesaleOrderDetail:assignBoardStores')}:
      </Typography>
      {stores.map((store) => {
        const dragHighlight =
          !!activeCard &&
          activeCard.store_id !== store.id &&
          !!activeDragItem &&
          storeCanFulfillItemQty(store.id, activeDragItem, activeCard.quantity, stockByStoreProduct);
        return (
          <StoreDropChip
            key={store.id}
            store={store}
            stockHighlight={storeHighlights.get(store.id) ?? 'none'}
            dragHighlight={dragHighlight}
            assignmentTargetAllowed={storeAllowsAssignmentTarget(order, store.id)}
            t={t}
          />
        );
      })}
    </Box>
  );
}

function StoreAssignmentTable({
  store,
  storeNameById,
  order,
  byItemId,
  stockHighlight,
  dragHighlight,
  lang,
  stockByStoreProduct,
  stockLoading,
  pendingQtyForItem,
  activeCard,
  activeDragId,
  onRemove,
  touchAssignMode,
  onTouchAssign,
  t,
}: {
  store: Store;
  storeNameById: Map<number, string>;
  order: WholesaleOrder;
  byItemId: Map<number, { unassigned: AssignmentBoardCard[]; byStore: Map<number, AssignmentBoardCard[]> }>;
  stockHighlight: StoreStockHighlight;
  dragHighlight: boolean;
  lang: string;
  stockByStoreProduct: Map<string, Stock>;
  stockLoading: boolean;
  pendingQtyForItem: (item: Pick<WholesaleOrderItem, 'id' | 'quantity'>) => number;
  activeCard: AssignmentBoardCard | null;
  activeDragId: string | null;
  onRemove: (card: AssignmentBoardCard) => void;
  touchAssignMode: boolean;
  onTouchAssign: (card: AssignmentBoardCard) => void;
  t: TFunction;
}) {
  const rows = (order.items ?? []).filter((it) => {
    const cards = byItemId.get(it.id)?.byStore.get(store.id) ?? [];
    return cards.length > 0;
  });

  const assignmentTargetAllowed = storeAllowsAssignmentTarget(order, store.id);

  const { setNodeRef: setTableDropRef, isOver: isTableOver } = useDroppable({
    id: storeTableDroppableId(store.id),
    disabled: !assignmentTargetAllowed,
  });

  const highlightLabel =
    stockHighlight === 'full'
      ? t('wholesaleOrderDetail:assignBoardStoreStockOk')
      : stockHighlight === 'partial'
        ? t('wholesaleOrderDetail:assignBoardStoreStockPartial')
        : null;

  return (
    <Paper
      variant="outlined"
      sx={{
        width: '100%',
        display: 'flex',
        flexDirection: 'column',
        borderLeftWidth: 4,
        borderLeftStyle: 'solid',
        borderLeftColor: 'primary.main',
        bgcolor: (theme) => alpha(theme.palette.primary.main, isTableOver ? 0.08 : 0.03),
        outline: isTableOver ? '2px dashed' : undefined,
        outlineColor: isTableOver ? 'primary.main' : undefined,
        ...storePaperSx(stockHighlight, dragHighlight),
      }}
    >
      <Box
        sx={{
          px: 2,
          py: 1.5,
          borderBottom: 1,
          borderColor: 'divider',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 1,
          flexWrap: 'wrap',
          ...storeHeaderSx(stockHighlight, dragHighlight),
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <StorefrontIcon fontSize="small" color="primary" />
          <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
            {store.name}
          </Typography>
        </Box>
        {highlightLabel ? (
          <Chip
            size="small"
            label={highlightLabel}
            color={stockHighlight === 'full' ? 'success' : 'warning'}
            variant="outlined"
          />
        ) : null}
      </Box>
      <Box ref={touchAssignMode ? setTableDropRef : undefined} sx={{ minWidth: 0 }}>
      {touchAssignMode ? (
        <Stack spacing={1.25} sx={{ p: 1.5 }}>
          {rows.length === 0 ? (
            <Typography variant="body2" color="text.disabled" sx={{ py: 2, textAlign: 'center', fontStyle: 'italic' }}>
              {t('wholesaleOrderDetail:assignBoardDropHere')}
            </Typography>
          ) : (
            rows.map((it) => {
              const cards = byItemId.get(it.id)?.byStore.get(store.id) ?? [];
              const cellQty = cards.reduce((s: number, c: AssignmentBoardCard) => s + c.quantity, 0);
              const stock = stockByStoreProduct.get(`${store.id}-${it.product_id}`);
              const available = stock ? stockLevelValue(stock, it.product) : null;
              const hint = formatAssignStoreStockHint(available, cellQty, true);
              const stockWarning = !hint.sufficient && cellQty > 0.0001;
              const pname = productDisplayName(it.product, lang) || `Product #${it.product_id}`;
              return (
                <Paper
                  key={it.id}
                  variant="outlined"
                  sx={{
                    p: 1.5,
                    borderColor: stockWarning ? 'error.light' : 'divider',
                    bgcolor: stockWarning ? (theme) => alpha(theme.palette.error.main, 0.05) : 'background.paper',
                  }}
                >
                  <Typography variant="body2" sx={{ fontWeight: 600, mb: 1, lineHeight: 1.35, wordBreak: 'break-word' }}>
                    {pname}
                  </Typography>
                  {stockWarning ? (
                    <Chip
                      size="small"
                      color="warning"
                      label={t('wholesaleOrderDetail:assignWarningNotEnoughStock')}
                      sx={{ mb: 1 }}
                    />
                  ) : null}
                  <Stack spacing={1.25}>
                    <AssignmentMobileLabelValue label={t('wholesaleOrderDetail:qty')}>
                      <Stack spacing={0.75} sx={{ alignItems: 'flex-end', width: '100%' }}>
                        {cards.map((card) => (
                          <Box key={card.dragId} sx={{ width: '100%', maxWidth: 280 }}>
                            <Box sx={{ display: 'flex', justifyContent: 'flex-end', mb: 0.75 }}>
                              <AssignmentChip
                                card={card}
                                onRemove={() => onRemove(card)}
                                removeTooltip={t('wholesaleOrderDetail:assignRemoveChipTooltip')}
                                touchAssignMode
                                onTouchAssign={onTouchAssign}
                              />
                            </Box>
                            {card.can_unassign ? (
                              <Button
                                fullWidth
                                size="small"
                                variant="outlined"
                                onClick={() => onTouchAssign(card)}
                              >
                                {t('wholesaleOrderDetail:assignMobileMoveBtn')}
                              </Button>
                            ) : null}
                          </Box>
                        ))}
                      </Stack>
                    </AssignmentMobileLabelValue>
                    <AssignmentMobileLabelValue label={t('wholesaleOrderDetail:assignStoreStock')}>
                      <AssignmentStockSummary
                        available={available}
                        assignQty={cellQty}
                        stockLoading={stockLoading}
                        t={t}
                      />
                    </AssignmentMobileLabelValue>
                  </Stack>
                </Paper>
              );
            })
          )}
        </Stack>
      ) : (
      <TableContainer ref={setTableDropRef} sx={{ width: '100%', overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderDetail:product')}</TableCell>
              <TableCell align="center" sx={{ fontWeight: 600, width: 120 }}>
                {t('wholesaleOrderDetail:qty')}
              </TableCell>
              <TableCell align="center" sx={{ fontWeight: 600, width: 140 }}>
                {t('wholesaleOrderDetail:assignStoreStock')}
              </TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={3} align="center">
                  <Typography variant="body2" color="text.disabled" sx={{ py: 2, fontStyle: 'italic' }}>
                    {t('wholesaleOrderDetail:assignBoardDropHere')}
                  </Typography>
                </TableCell>
              </TableRow>
            ) : (
              rows.map((it) => {
              const cards = byItemId.get(it.id)?.byStore.get(store.id) ?? [];
              const cellQty = cards.reduce((s: number, c: AssignmentBoardCard) => s + c.quantity, 0);
              const stock = stockByStoreProduct.get(`${store.id}-${it.product_id}`);
              const available = stock ? stockLevelValue(stock, it.product) : null;
              const hint = formatAssignStoreStockHint(available, cellQty, true);
              const stockWarning = !hint.sufficient && cellQty > 0.0001;
              const rowDragOk =
                activeCard?.item_id === it.id &&
                storeCanFulfillItemQty(store.id, it, activeCard.quantity, stockByStoreProduct);
              return (
                <TableRow
                  key={it.id}
                  hover
                  sx={
                    rowDragOk
                      ? { bgcolor: (theme) => alpha(theme.palette.success.main, 0.08) }
                      : undefined
                  }
                >
                  <TableCell sx={{ fontWeight: 500 }}>
                    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                      <Typography component="span" variant="body2" sx={{ fontWeight: 500 }}>
                        {productDisplayName(it.product, lang) || `Product #${it.product_id}`}
                      </Typography>
                      {stockWarning ? (
                        <Typography variant="caption" color="warning.main" sx={{ fontWeight: 600 }}>
                          {t('wholesaleOrderDetail:assignWarningNotEnoughStock')}
                          {available != null
                            ? ` (${formatAssignmentQty(available)} / ${formatAssignmentQty(cellQty)})`
                            : ''}
                        </Typography>
                      ) : null}
                    </Box>
                  </TableCell>
                  <QtyDropCell
                    itemId={it.id}
                    storeId={store.id}
                    cards={cards}
                    stockSufficient={hint.sufficient}
                    activeDragId={activeDragId}
                    onRemove={onRemove}
                    removeTooltip={t('wholesaleOrderDetail:assignRemoveChipTooltip')}
                    dropHint={t('wholesaleOrderDetail:assignBoardDropHere')}
                    dropAllowed={assignmentTargetAllowed}
                    touchAssignMode={touchAssignMode}
                    onTouchAssign={onTouchAssign}
                    mobileEmptyHint={t('wholesaleOrderDetail:assignMobileTapMove')}
                  />
                  <TableCell align="center">
                    <Typography
                      variant="caption"
                      sx={{ color: hint.sufficient ? 'success.main' : 'error.main', whiteSpace: 'nowrap' }}
                    >
                      {stockLoading ? '…' : hint.text}
                    </Typography>
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
    </Paper>
  );
}

export default function WholesaleOrderAssignmentBoard({
  order,
  stores,
  staged,
  manualMode,
  lang,
  actioning,
  allLinesAssigned,
  pendingQtyForItem,
  onAssignItem,
  onUnassignItem,
  onMoveItem,
  onAssignByDefaults,
  onConfirmAllocation,
  onBlockAssignmentTarget,
  onCancelManual,
  t,
}: Props) {
  const theme = useTheme();
  const touchAssignMode = useMediaQuery(theme.breakpoints.down('md'));
  const [stockByStoreProduct, setStockByStoreProduct] = useState<Map<string, Stock>>(new Map());
  const [stockLoading, setStockLoading] = useState(false);
  const [activeCard, setActiveCard] = useState<AssignmentBoardCard | null>(null);
  const [assignQtyDialog, setAssignQtyDialog] = useState<AssignQtyDialogState | null>(null);
  const [confirming, setConfirming] = useState(false);

  const storeNameById = useMemo(() => new Map(stores.map((s) => [s.id, s.name])), [stores]);

  const { byItemId, byStoreId } = useMemo(
    () => buildAssignmentBoardCards(order, staged, pendingQtyForItem, storeNameById),
    [order, staged, pendingQtyForItem, storeNameById],
  );

  const assignedStores = useMemo(
    () => stores.filter((s) => byStoreId.has(s.id)),
    [stores, byStoreId],
  );

  const storeHighlights = useMemo(() => {
    const map = new Map<number, StoreStockHighlight>();
    for (const store of stores) {
      map.set(store.id, storeStockHighlightLevel(store.id, order, pendingQtyForItem, stockByStoreProduct));
    }
    return map;
  }, [stores, order, pendingQtyForItem, stockByStoreProduct]);

  const stockWarnings = useMemo(
    () => collectAssignmentStockWarnings(order, byItemId, stockByStoreProduct),
    [order, byItemId, stockByStoreProduct],
  );

  useEffect(() => {
    let cancelled = false;
    setStockLoading(true);
    Promise.all(stores.map((s) => stockAPI.getStoreStock(s.id)))
      .then((results) => {
        if (cancelled) return;
        const map = new Map<string, Stock>();
        stores.forEach((store, index) => {
          for (const row of results[index] ?? []) {
            map.set(`${store.id}-${row.product_id}`, row);
          }
        });
        setStockByStoreProduct(map);
      })
      .catch(() => {
        if (!cancelled) setStockByStoreProduct(new Map());
      })
      .finally(() => {
        if (!cancelled) setStockLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [stores, order.id]);

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));

  const openAssignQtyDialog = (
    sourceCard: AssignmentBoardCard,
    targetStoreId: number | null | undefined,
    pickStore: boolean,
  ) => {
    setAssignQtyDialog({
      itemId: sourceCard.item_id,
      targetStoreId,
      sourceCard,
      maxQty: sourceCard.quantity,
      qty: String(sourceCard.quantity),
      pickStore,
    });
  };

  const openTouchAssignDialog = (sourceCard: AssignmentBoardCard) => {
    openAssignQtyDialog(sourceCard, undefined, true);
  };

  const openSplitDialog = (sourceCard: AssignmentBoardCard, targetStoreId: number | null) => {
    openAssignQtyDialog(sourceCard, targetStoreId, false);
  };

  const handleDragStart = (event: DragStartEvent) => {
    const card = event.active.data.current?.card as AssignmentBoardCard | undefined;
    setActiveCard(card ?? null);
  };

  const handleDragEnd = (event: DragEndEvent) => {
    setActiveCard(null);
    const card = event.active.data.current?.card as AssignmentBoardCard | undefined;
    if (!card || !event.over) return;

    const overId = String(event.over.id);
    const cellTarget = parseCellDroppableId(overId);
    const storeTarget = parseStoreDroppableId(overId);

    let targetStoreId: number | null | undefined;
    if (cellTarget) {
      if (cellTarget.itemId !== card.item_id) return;
      targetStoreId = cellTarget.storeId;
    } else if (storeTarget != null) {
      targetStoreId = storeTarget;
    } else {
      return;
    }

    const sourceStoreId = card.store_id;
    if (targetStoreId === sourceStoreId) return;

    if (targetStoreId != null && !storeAllowsAssignmentTarget(order, targetStoreId)) {
      onBlockAssignmentTarget?.();
      return;
    }

    openSplitDialog(card, targetStoreId);
  };

  const applyAssignQty = async () => {
    if (!assignQtyDialog) return;
    const qty = parseFloat(assignQtyDialog.qty);
    if (Number.isNaN(qty) || qty <= 0 || qty > assignQtyDialog.maxQty + 0.0001) return;

    const { itemId, sourceCard, pickStore } = assignQtyDialog;
    let { targetStoreId } = assignQtyDialog;
    if (pickStore && targetStoreId === undefined) return;

    if (targetStoreId != null && !storeAllowsAssignmentTarget(order, targetStoreId)) {
      onBlockAssignmentTarget?.();
      setAssignQtyDialog(null);
      return;
    }
    const sourceStoreId = sourceCard.store_id;
    setAssignQtyDialog(null);

    if (targetStoreId == null) {
      if (sourceStoreId == null) return;
      await onUnassignItem(itemId, sourceStoreId, qty, sourceCard.staged);
      return;
    }
    if (sourceStoreId == null) {
      await onAssignItem(itemId, targetStoreId, qty);
      return;
    }
    await onMoveItem(itemId, sourceStoreId, targetStoreId, qty, sourceCard.staged);
  };

  const handleRemove = (card: AssignmentBoardCard) => {
    if (card.store_id == null) return;
    void onUnassignItem(card.item_id, card.store_id, card.quantity, card.staged);
  };

  const activeItem = activeCard ? order.items?.find((it) => it.id === activeCard.item_id) : undefined;

  const activeDragItem = activeCard ? order.items?.find((it) => it.id === activeCard.item_id) : undefined;

  return (
    <Box>
      <Box
        sx={{
          display: 'flex',
          gap: 1,
          flexWrap: 'wrap',
          mb: 2,
          alignItems: 'center',
          flexDirection: { xs: 'column', sm: 'row' },
          '& .MuiButton-root': { width: { xs: '100%', sm: 'auto' } },
        }}
      >
        <Button variant="outlined" onClick={onAssignByDefaults} disabled={actioning || confirming}>
          {t('wholesaleOrderDetail:assignByDefaults')}
        </Button>
        {manualMode && onCancelManual ? (
          <Button variant="outlined" onClick={onCancelManual} disabled={actioning || confirming}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
        ) : null}
        {stockLoading ? <CircularProgress size={22} sx={{ alignSelf: 'center' }} /> : null}
        <Box sx={{ flex: 1, display: { xs: 'none', sm: 'block' } }} />
        <Button
          variant="contained"
          color="success"
          disabled={actioning || confirming || !allLinesAssigned}
          onClick={() => {
            setConfirming(true);
            void onConfirmAllocation().finally(() => setConfirming(false));
          }}
          sx={{ ml: { sm: 'auto' }, width: { xs: '100%', sm: 'auto' } }}
        >
          {confirming || actioning
            ? t('wholesaleOrderDetail:confirmingAllocation')
            : t('wholesaleOrderDetail:confirmAllocation')}
        </Button>
      </Box>

      <DndContext autoScroll={false} sensors={sensors} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
        {touchAssignMode ? (
          <Alert severity="info" sx={{ mb: 2 }}>
            {t('wholesaleOrderDetail:assignMobileHint')}
          </Alert>
        ) : null}
        {stockWarnings.length > 0 ? (
          <Alert severity="warning" sx={{ mb: 2 }}>
            <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 0.5 }}>
              {t('wholesaleOrderDetail:assignStockWarningTitle')}
            </Typography>
            {stockWarnings.map((w) => {
              const item = order.items?.find((it) => it.id === w.item_id);
              const storeName = storeNameById.get(w.store_id) ?? `Store #${w.store_id}`;
              const productName =
                (item ? productDisplayName(item.product, lang) : null) || `Product #${item?.product_id ?? w.item_id}`;
              return (
                <Typography key={`${w.item_id}-${w.store_id}`} variant="body2" sx={{ mt: 0.25 }}>
                  {t('wholesaleOrderDetail:assignStockWarningLine', {
                    product: productName,
                    store: storeName,
                    need: formatAssignmentQty(w.quantity),
                    available: w.available != null ? formatAssignmentQty(w.available) : '—',
                  })}
                </Typography>
              );
            })}
          </Alert>
        ) : null}
        {!touchAssignMode ? (
          <StoreChipBar
            order={order}
            stores={stores}
            storeHighlights={storeHighlights}
            activeCard={activeCard}
            activeDragItem={activeDragItem}
            stockByStoreProduct={stockByStoreProduct}
            t={t}
          />
        ) : null}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, width: '100%' }}>
          <UnassignedTable
            order={order}
            byItemId={byItemId}
            lang={lang}
            activeDragId={activeCard?.dragId ?? null}
            onRemove={handleRemove}
            onTouchAssign={openTouchAssignDialog}
            touchAssignMode={touchAssignMode}
            t={t}
          />
          {assignedStores.length > 0 ? (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, pt: 0.5 }}>
                <StorefrontIcon fontSize="small" color="primary" />
                <Typography variant="subtitle2" sx={{ fontWeight: 700, color: 'primary.main' }}>
                  {t('wholesaleOrderDetail:assignBoardSectionAssigned')}
                </Typography>
              </Box>
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                {assignedStores.map((store) => {
                  const dragHighlight =
                    !!activeCard &&
                    activeCard.store_id !== store.id &&
                    !!activeDragItem &&
                    storeCanFulfillItemQty(store.id, activeDragItem, activeCard.quantity, stockByStoreProduct);
                  return (
                    <StoreAssignmentTable
                      key={store.id}
                      store={store}
                      storeNameById={storeNameById}
                      order={order}
                      byItemId={byItemId}
                      stockHighlight={storeHighlights.get(store.id) ?? 'none'}
                      dragHighlight={dragHighlight}
                      lang={lang}
                      stockByStoreProduct={stockByStoreProduct}
                      stockLoading={stockLoading}
                      pendingQtyForItem={pendingQtyForItem}
                      activeCard={activeCard}
                      activeDragId={activeCard?.dragId ?? null}
                      onRemove={handleRemove}
                      touchAssignMode={touchAssignMode}
                      onTouchAssign={openTouchAssignDialog}
                      t={t}
                    />
                  );
                })}
              </Box>
            </Box>
          ) : null}
        </Box>
        <DragOverlay dropAnimation={null}>
          {activeCard && activeItem ? (
            <Chip
              size="small"
              label={`${productDisplayName(activeItem.product, lang)} · ${formatAssignmentQty(activeCard.quantity)}`}
              sx={{ boxShadow: 4 }}
            />
          ) : null}
        </DragOverlay>
      </DndContext>

      <Dialog open={assignQtyDialog != null} onClose={() => setAssignQtyDialog(null)} maxWidth="xs" fullWidth>
        <DialogTitle>
          {assignQtyDialog?.pickStore
            ? assignQtyDialog.sourceCard.store_id == null
              ? t('wholesaleOrderDetail:assignMobileAssignTitle')
              : t('wholesaleOrderDetail:assignMobileMoveTitle')
            : t('wholesaleOrderDetail:assignSplitQtyTitle')}
        </DialogTitle>
        <DialogContent>
          {assignQtyDialog ? (
            <>
              {(() => {
                const item = order.items?.find((it) => it.id === assignQtyDialog.itemId);
                const productName =
                  (item ? productDisplayName(item.product, lang) : null) ||
                  `Product #${item?.product_id ?? assignQtyDialog.itemId}`;
                return (
                  <Typography variant="body2" sx={{ fontWeight: 600, mb: 1 }}>
                    {productName}
                  </Typography>
                );
              })()}
              {assignQtyDialog.sourceCard.store_id != null ? (
                <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                  {t('wholesaleOrderDetail:assignMobileFromStore', {
                    store:
                      storeNameById.get(assignQtyDialog.sourceCard.store_id) ??
                      `Store #${assignQtyDialog.sourceCard.store_id}`,
                  })}
                </Typography>
              ) : null}
              {assignQtyDialog.pickStore ? (
                (() => {
                  const item = order.items?.find((it) => it.id === assignQtyDialog.itemId);
                  const needQty = parseFloat(assignQtyDialog.qty);
                  const assignQty = Number.isFinite(needQty) && needQty > 0 ? needQty : assignQtyDialog.maxQty;
                  const storeOptions = mobileStoreOptionsForAssign(
                    stores,
                    order,
                    item,
                    assignQty,
                    assignQtyDialog.sourceCard.store_id,
                    stockByStoreProduct,
                  );
                  return (
                <FormControl fullWidth size="small" sx={{ mb: 2 }}>
                  <InputLabel id="assign-mobile-store-label">
                    {t('wholesaleOrderDetail:assignMobilePickStore')}
                  </InputLabel>
                  <Select
                    labelId="assign-mobile-store-label"
                    label={t('wholesaleOrderDetail:assignMobilePickStore')}
                    value={
                      assignQtyDialog.targetStoreId === undefined
                        ? ''
                        : assignQtyDialog.targetStoreId === null
                          ? 'pending'
                          : String(assignQtyDialog.targetStoreId)
                    }
                    onChange={(e) => {
                      const v = e.target.value;
                      setAssignQtyDialog({
                        ...assignQtyDialog,
                        targetStoreId:
                          v === ''
                            ? undefined
                            : v === 'pending'
                              ? null
                              : Number(v),
                      });
                    }}
                  >
                    <MenuItem value="">
                      <em>{t('wholesaleOrderDetail:assignMobilePickStorePlaceholder')}</em>
                    </MenuItem>
                    {assignQtyDialog.sourceCard.store_id != null ? (
                      <MenuItem value="pending">
                        {t('wholesaleOrderDetail:assignBoardSectionUnassigned')}
                      </MenuItem>
                    ) : null}
                    {stockLoading ? (
                      <MenuItem disabled value="__loading">
                        {t('wholesaleOrderDetail:assignMobileStoreStockLoading')}
                      </MenuItem>
                    ) : (
                      storeOptions.map(({ store, hint }) => (
                        <MenuItem key={store.id} value={String(store.id)}>
                          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', py: 0.25 }}>
                            <Typography variant="body2" sx={{ fontWeight: hint.sufficient ? 600 : 400 }}>
                              {store.name}
                            </Typography>
                            <Typography
                              variant="caption"
                              sx={{ color: hint.sufficient ? 'success.main' : 'warning.main' }}
                            >
                              {hint.sufficient
                                ? t('wholesaleOrderDetail:assignMobileStoreStockOk', { stock: hint.text })
                                : t('wholesaleOrderDetail:assignMobileStoreStockLow', { stock: hint.text })}
                            </Typography>
                          </Box>
                        </MenuItem>
                      ))
                    )}
                  </Select>
                  {!stockLoading && storeOptions.some((o) => o.hint.sufficient) ? (
                    <Typography variant="caption" color="text.secondary" sx={{ mt: 0.75, display: 'block' }}>
                      {t('wholesaleOrderDetail:assignMobileStoreStockSortHint')}
                    </Typography>
                  ) : null}
                </FormControl>
                  );
                })()
              ) : null}
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('wholesaleOrderDetail:assignSplitQtyHint', {
                  max: formatAssignmentQty(assignQtyDialog.maxQty),
                })}
              </Typography>
              <TextField
                fullWidth
                type="number"
                size="small"
                label={t('wholesaleOrderDetail:assignQty', 'Assign qty')}
                value={assignQtyDialog.qty}
                onChange={(e) => setAssignQtyDialog({ ...assignQtyDialog, qty: e.target.value })}
                inputProps={{ min: 0, max: assignQtyDialog.maxQty, step: 0.001 }}
                autoFocus={!assignQtyDialog.pickStore}
              />
            </>
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAssignQtyDialog(null)}>{t('wholesaleOrderDetail:cancel')}</Button>
          <Button
            variant="contained"
            onClick={() => void applyAssignQty()}
            disabled={
              actioning ||
              (assignQtyDialog?.pickStore && assignQtyDialog.targetStoreId === undefined)
            }
          >
            {t('wholesaleOrderDetail:ok')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
