import { useEffect, useMemo, useRef, useState, Fragment, type KeyboardEvent, type ClipboardEvent, type ReactNode } from 'react';
import { useParams, useNavigate, useLocation, Link as RouterLink } from 'react-router-dom';
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
  TableFooter,
  Typography,
  Button,
  Divider,
  TextField,
  Select,
  MenuItem,
  CircularProgress,
  Chip,
  Checkbox,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogContentText,
  DialogActions,
  ButtonGroup,
  Menu,
  MenuItem as MuiMenuItem,
  Collapse,
  IconButton,
  Tooltip,
  Autocomplete,
  Link,
  useMediaQuery,
  Alert,
  FormControlLabel,
  FormGroup,
  Portal,
} from '@mui/material';
import { useTheme, keyframes, alpha, type Theme } from '@mui/material/styles';
import { useAuth } from '../context/AuthContext';
import {
  CheckCircle as CompleteIcon,
  Download as DownloadIcon,
  Refresh as RefreshIcon,
  Edit as EditIcon,
  LocalShipping as ShipmentIcon,
  Replay as RegenIcon,
  ArrowDropDown as ArrowDropDownIcon,
  ArrowDropUp as ArrowDropUpIcon,
  History as HistoryIcon,
  ChevronRight as ChevronRightIcon,
  AttachFile as AttachFileIcon,
  Delete as DeleteIcon,
  Check as CheckIcon,
  PictureAsPdf as PdfIcon,
  ZoomIn as ZoomInIcon,
  Email as EmailIcon,
  Lock as LockIcon,
  LockOpen as LockOpenIcon,
  OpenInFull as OpenInFullIcon,
  CloseFullscreen as CloseFullscreenIcon,
} from '@mui/icons-material';
import { wholesaleOrdersAPI, storesAPI, stockAPI, shipmentsAPI, wholesaleClientsAPI, settingsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { AuditLog, WholesaleOrder, WholesaleOrderItem, Store, Shipment, WholesaleClientStore, CompanySettings, EndorseAllocationPreview, Stock } from '../types';
import { format } from 'date-fns';
import { useTranslation } from 'react-i18next';
import type { TFunction } from 'i18next';
import UserDisplay from '../components/UserDisplay';
import { productDisplayName } from '../utils/productDisplay';
import { stockLevelValue } from '../utils/productInventory';
import {
  assignedCaseQtyForOrderItem,
  orderItemExpectedBoxes,
  shipmentExpectedBoxes,
} from '../utils/shipmentExpectedBoxes';
import {
  allOrderLinesFullyAssigned,
  allOrderLinesFullyStaged,
  addStagedAssignment,
  effectiveShipmentItemQty,
  formatAssignStoreStockHint,
  formatEndorseStockChange,
  formatAssignmentQty,
  orderItemStoreAssignments,
  orderAllowsAssignmentChange,
  pendingQtyForOrderItem,
  pendingQtyForOrderItemWithStaging,
  removeStagedAssignmentQty,
  shipmentAssignedSummary,
  storeAllowsAssignmentTarget,
  type StagedStoreAssignment,
} from '../utils/wholesaleOrderAssignment';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import DeliveryProofCourierWarningDialog from '../components/DeliveryProofCourierWarningDialog';
import WholesaleOrderAssignmentBoard, {
  AssignmentHowToTooltipIcon,
} from '../components/WholesaleOrderAssignmentBoard';
import {
  buildWholesaleEmailResendSummary,
  buildWholesaleOrderEmailMessageEnglish,
  buildWholesaleOrderEmailSubjectEnglish,
  buildShipmentDocumentsEmailMessageEnglish,
  buildShipmentDocumentsEmailSubjectEnglish,
  type ShipmentDocumentAttachmentKind,
  getWholesaleOrderEmailAudits,
  wholesaleOrderEmailSentAtDisplay,
  wholesaleOrderEmailSkippedAtDisplay,
  normalizeEmailContentLanguage,
  orderHasInvoiceDocument,
  orderHasPoAttachments,
  orderHasOrderConfirmationDocument,
  allShipmentsHaveSignedProof,
  isWholesaleOrderCompleted,
  wholesaleOrderStatusColor,
  wholesaleOrderStatusLabel,
  parseWholesaleOrderEmailAuditBase,
  isWholesaleOrderEmailSkippedAudit,
  isWholesaleOrderEmailSentAudit,
  wholesaleOrderEmailSkipRemark,
  WHOLESALE_ORDER_EMAIL_ATTACHMENT_KINDS,
  WHOLESALE_ORDER_EMAIL_REQUIRED_ATTACHMENTS,
  isWholesaleOrderEmailAttachmentRequired,
  wholesaleOrderDefaultEmailCcList,
  parseEmailListFromRaw,
  type EmailContentLanguage,
  type WholesaleEmailResendSummary,
  type WholesaleOrderEmailType,
} from '../utils/wholesaleOrderEmail';
import {
  computeWholesaleOrderProcessSteps,
  getCurrentWholesaleOrderProcessStepKey,
  getWholesaleOrderProcessStepCompletedAt,
  isPaymentConfirmationStepComplete,
  buildWholesaleOrderWorkflowContext,
  type WholesaleOrderProcessStepKey,
} from '../utils/wholesaleOrderWorkflow';
import {
  confirmUnlockOrder,
  isOrderUploadBlocked,
  isRegenBlockedByEmailLock,
  orderHasActiveLocks,
  shouldSendRegenUnlockFlag,
  shouldSendUploadUnlockFlag,
} from '../utils/documentRegenLock';
import {
  canUploadDeliveryProof,
  canReplaceDeliveryProof,
  canEditShipmentDetails,
  isShipmentCompleted,
  shipmentAwaitingCourierPickup,
  shipmentHasDeliveryNoteStarted,
  shipmentNeedsPacking,
  shipmentStatusChipColor,
  shipmentStatusLabel,
} from '../utils/shipmentStatus';
import { shipmentCourierOptionsFromSettings } from '../utils/shipmentCouriers';

const IMAGE_EXTS = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];

const invoiceEmailReadyEnlarge = keyframes`
  0%, 100% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.12);
  }
`;

const invoiceEmailReadyWrapperSx = {
  display: 'inline-block',
  animation: `${invoiceEmailReadyEnlarge} 1.4s ease-in-out infinite`,
  transformOrigin: 'center center',
};

const invoiceEmailReadyButtonSx = {
  fontWeight: 700,
  bgcolor: '#ffb300',
  color: '#3e2723',
  border: '1px solid rgba(255, 160, 0, 0.85)',
  boxShadow: '0 0 8px 2px rgba(255, 193, 7, 0.45)',
  '&:hover': {
    bgcolor: '#ffa000',
  },
};

type OrderActionSection = 'endorse' | 'assign' | 'orderConfirmEmail' | 'shipments' | 'deliveryCompleteEmail' | 'invoiceEmail' | 'payment';
type EmailChipField = 'to' | 'cc' | 'bcc';

const orderActionSectionHighlightSx = (theme: Theme) => ({
  border: 2,
  borderStyle: 'solid',
  borderColor: 'primary.main',
  bgcolor: alpha(theme.palette.primary.main, 0.06),
  boxShadow: `0 0 0 3px ${alpha(theme.palette.primary.main, 0.14)}`,
  transition: 'border-color 0.2s ease, background-color 0.2s ease, box-shadow 0.2s ease',
});

const orderActionSectionPendingSx = {
  opacity: 0.72,
  border: '1px dashed',
  borderColor: 'divider',
  bgcolor: 'action.hover',
  transition: 'opacity 0.2s ease',
};

const pipelineEmailSectionLayoutSx = {
  display: 'flex',
  alignItems: 'flex-start',
  justifyContent: 'space-between',
  gap: 2,
  flexWrap: 'wrap',
  flexDirection: { xs: 'column', sm: 'row' },
};

const pipelineEmailActionsSx = {
  display: 'flex',
  alignItems: { xs: 'stretch', sm: 'center' },
  justifyContent: { xs: 'stretch', sm: 'flex-end' },
  gap: 1,
  flexWrap: 'wrap',
  flexDirection: { xs: 'column', sm: 'row' },
  width: { xs: '100%', sm: 'auto' },
  flexShrink: 0,
  '& > span': { width: { xs: '100%', sm: 'auto' } },
  '& .MuiButton-root': { width: { xs: '100%', sm: 'auto' } },
};

function PipelineSectionPendingContent({
  pending,
  title,
  children,
}: {
  pending: boolean;
  title?: ReactNode;
  children: ReactNode;
}) {
  if (!pending) {
    return (
      <>
        {title ? <Box sx={{ mb: 1 }}>{title}</Box> : null}
        {children}
      </>
    );
  }
  return (
    <>
      {title ? <Box sx={{ mb: 1.25 }}>{title}</Box> : null}
      <Box
        sx={{
          position: 'relative',
          pointerEvents: 'none',
          userSelect: 'none',
          minHeight: 64,
        }}
      >
        {children}
        <Box
          aria-hidden
          sx={{
            position: 'absolute',
            inset: 0,
            zIndex: 1,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Box
            sx={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 56,
              height: 56,
              borderRadius: '50%',
              bgcolor: 'background.paper',
              boxShadow: 2,
              border: '1px solid',
              borderColor: 'divider',
            }}
          >
            <LockIcon sx={{ fontSize: 28, color: 'text.disabled' }} />
          </Box>
        </Box>
      </Box>
    </>
  );
}
const isImageFile = (doc: { file_url: string; original_filename?: string }) => {
  const name = (doc.original_filename || doc.file_url || '').toLowerCase();
  return IMAGE_EXTS.some((ext) => name.endsWith(ext));
};

function DialogLabelValueRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 2 }}>
      <Typography variant="body2" color="text.secondary" sx={{ flexShrink: 0 }}>
        {label}
      </Typography>
      <Box sx={{ minWidth: 0, textAlign: 'right' }}>{children}</Box>
    </Box>
  );
}

function AttachmentThumbnail({
  orderId,
  doc,
  displayName,
  onPreview,
  onDownload,
  onDelete,
  deleting,
  canDelete = true,
  t,
  downloadLabel = 'Download',
}: {
  orderId: number;
  doc: { id: number; file_url: string; original_filename?: string };
  displayName: string;
  onPreview: (url: string, name: string) => void;
  onDownload: () => void;
  onDelete: () => void;
  deleting: boolean;
  canDelete?: boolean;
  t: (key: string) => string;
  downloadLabel?: string;
}) {
  const [thumbUrl, setThumbUrl] = useState<string | null>(null);
  const urlRef = useRef<string | null>(null);
  const isImage = isImageFile(doc);
  useEffect(() => {
    setThumbUrl(null);
    if (!isImage) return;
    let revoked = false;
    wholesaleOrdersAPI.downloadDocument(orderId, doc.id, true).then((blob) => {
      if (!revoked) {
        const u = URL.createObjectURL(blob);
        urlRef.current = u;
        setThumbUrl(u);
      }
    }).catch(() => {});
    return () => {
      revoked = true;
      if (urlRef.current) {
        URL.revokeObjectURL(urlRef.current);
        urlRef.current = null;
      }
    };
  }, [orderId, doc.id, isImage]);
  const cardSx = {
    width: 112,
    borderRadius: 2,
    overflow: 'hidden',
    bgcolor: 'background.paper',
    boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
    border: '1px solid',
    borderColor: 'divider',
    transition: 'box-shadow 0.2s, border-color 0.2s',
    '&:hover': {
      boxShadow: '0 4px 12px rgba(0,0,0,0.12)',
      borderColor: 'action.selected',
    },
  };

  if (!isImage) {
    return (
      <Box sx={{ ...cardSx, cursor: 'pointer', position: 'relative', ...(canDelete && { '&:hover .proof-actions': { opacity: 1 } }) }} onClick={onDownload}>
        <Box sx={{ height: 112, display: 'flex', alignItems: 'center', justifyContent: 'center', bgcolor: 'grey.50', position: 'relative' }}>
          <PdfIcon sx={{ fontSize: 48, color: 'error.main', opacity: 0.9 }} />
          {canDelete && (
            <IconButton
              size="small"
              className="proof-actions"
              sx={{
                position: 'absolute',
                top: 4,
                right: 4,
                bgcolor: 'rgba(255,255,255,0.9)',
                opacity: 0,
                transition: 'opacity 0.2s',
                '&:hover': { bgcolor: 'white' },
              }}
              color="error"
              disabled={deleting}
              onClick={(e) => {
                e.stopPropagation();
                onDelete();
              }}
            >
              <DeleteIcon fontSize="small" />
            </IconButton>
          )}
        </Box>
        <Box sx={{ px: 1, py: 1 }}>
          <Typography variant="caption" sx={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {displayName}
          </Typography>
        </Box>
      </Box>
    );
  }
  return (
    <Box
      sx={{
        ...cardSx,
        cursor: thumbUrl ? 'pointer' : 'default',
        ...(canDelete && { '&:hover .proof-actions': { opacity: 1 } }),
      }}
      onClick={() => thumbUrl && onPreview(thumbUrl, displayName)}
    >
      <Box sx={{ height: 112, position: 'relative', bgcolor: 'grey.50' }}>
        {thumbUrl ? (
          <Box
            component="img"
            src={thumbUrl}
            alt={displayName}
            sx={{ width: '100%', height: '100%', objectFit: 'contain', p: 0.5 }}
          />
        ) : (
          <Box sx={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <CircularProgress size={28} />
          </Box>
        )}
        <Box
          className="proof-actions"
          sx={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 0.5,
            bgcolor: 'rgba(0,0,0,0.4)',
            opacity: 0,
            transition: 'opacity 0.2s',
          }}
          onClick={(e) => e.stopPropagation()}
        >
          <IconButton size="small" sx={{ bgcolor: 'rgba(255,255,255,0.9)', '&:hover': { bgcolor: 'white' } }} onClick={(e) => { e.stopPropagation(); onDownload(); }} title={downloadLabel}>
            <DownloadIcon fontSize="small" />
          </IconButton>
          <IconButton size="small" sx={{ bgcolor: 'rgba(255,255,255,0.9)', '&:hover': { bgcolor: 'white' } }} onClick={(e) => { e.stopPropagation(); thumbUrl && onPreview(thumbUrl, displayName); }} title={t('wholesaleOrderDetail:preview')}>
            <ZoomInIcon fontSize="small" />
          </IconButton>
          {canDelete && (
            <IconButton size="small" sx={{ bgcolor: 'rgba(255,255,255,0.9)', '&:hover': { bgcolor: 'white' } }} disabled={deleting} onClick={(e) => { e.stopPropagation(); onDelete(); }} color="error" title={t('common:delete')}>
              <DeleteIcon fontSize="small" />
            </IconButton>
          )}
        </Box>
      </Box>
      <Box sx={{ px: 1, py: 1 }}>
        <Typography variant="caption" sx={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {displayName}
        </Typography>
      </Box>
    </Box>
  );
}

type PaymentProofDocMeta = { amountPerFile?: number; transfer_date?: string; transferred_to?: string };

function PaymentProofDocsList({
  isMobile,
  proofDocs,
  orderId,
  canDeletePaymentProof,
  unlockAfterCompletion,
  metaByDocId,
  totalProofAmount,
  pendingAmount,
  displayNameFor,
  t,
  enqueueSnackbar,
  paymentProofDeletingId,
  setPaymentProofDeletingId,
  onOrderRefresh,
}: {
  isMobile: boolean;
  proofDocs: Array<{ id: number; file_url: string; original_filename?: string }>;
  orderId: number;
  canDeletePaymentProof: boolean;
  unlockAfterCompletion: boolean;
  metaByDocId: Record<number, PaymentProofDocMeta>;
  totalProofAmount: number;
  pendingAmount: number;
  displayNameFor: (doc: { file_url: string; original_filename?: string }) => string;
  t: TFunction;
  enqueueSnackbar: (message: string, options?: { variant?: 'success' | 'error' | 'warning' | 'info' }) => void;
  paymentProofDeletingId: number | null;
  setPaymentProofDeletingId: (id: number | null) => void;
  onOrderRefresh: (o: WholesaleOrder) => void;
}) {
  if (isMobile) {
    return (
      <>
        <Stack spacing={1.25} sx={{ mb: 2 }}>
          {proofDocs.map((doc, idx) => {
            const meta = metaByDocId[doc.id] || {};
            const fileName = displayNameFor(doc) || `${t('wholesaleOrderDetail:paymentProofDoc')} #${idx + 1}`;
            const isPdf = fileName.toLowerCase().endsWith('.pdf');
            const download = async () => {
              try {
                const blob = await wholesaleOrdersAPI.downloadDocument(orderId, doc.id);
                const a = document.createElement('a');
                a.href = URL.createObjectURL(blob);
                a.download = fileName || 'payment-proof';
                a.click();
                URL.revokeObjectURL(a.href);
              } catch (e: unknown) {
                const err = e as { response?: { data?: { error?: string } }; message?: string };
                enqueueSnackbar(err?.response?.data?.error || err?.message || 'Download failed', { variant: 'error' });
              }
            };
            return (
              <Paper key={doc.id} variant="outlined" sx={{ p: 1.5 }}>
                <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 1 }}>
                  <Box
                    sx={{ flex: 1, minWidth: 0, cursor: 'pointer' }}
                    onClick={() => {
                      void download();
                    }}
                  >
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                      {isPdf ? (
                        <PdfIcon sx={{ fontSize: 22, color: 'error.main', flexShrink: 0 }} />
                      ) : (
                        <AttachFileIcon sx={{ fontSize: 22, color: 'text.secondary', flexShrink: 0 }} />
                      )}
                      <Typography variant="body2" sx={{ textDecoration: 'underline', wordBreak: 'break-word' }}>
                        {fileName}
                      </Typography>
                    </Box>
                    <Stack spacing={0.35}>
                      <Typography variant="caption" color="text.secondary">
                        {t('wholesaleOrderDetail:paymentProofAmount')}:{' '}
                        {meta.amountPerFile != null ? `£${meta.amountPerFile.toFixed(2)}` : '–'}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {t('wholesaleOrderDetail:paymentProofDate')}:{' '}
                        {meta.transfer_date ? format(new Date(meta.transfer_date), 'dd/MM/yyyy') : '–'}
                      </Typography>
                      <Typography variant="caption" color="text.secondary" sx={{ wordBreak: 'break-word' }}>
                        {t('wholesaleOrderDetail:paymentProofAccount')}: {meta.transferred_to || '–'}
                      </Typography>
                    </Stack>
                  </Box>
                  {canDeletePaymentProof && (
                    <Tooltip title={t('wholesaleOrderDetail:remove')}>
                      <IconButton
                        size="small"
                        color="error"
                        sx={{ flexShrink: 0 }}
                        onClick={async () => {
                          const ok = window.confirm(t('wholesaleOrderDetail:confirmRemovePaymentProof'));
                          if (!ok) return;
                          setPaymentProofDeletingId(doc.id);
                          try {
                            await wholesaleOrdersAPI.deletePaymentProof(orderId, doc.id, {
                              unlock_after_completion: unlockAfterCompletion,
                            });
                            const updated = await wholesaleOrdersAPI.get(orderId);
                            onOrderRefresh(updated);
                            enqueueSnackbar('Payment proof removed', { variant: 'success' });
                          } catch (e: unknown) {
                            const err = e as { response?: { data?: { error?: string } } };
                            enqueueSnackbar(err.response?.data?.error || 'Failed to remove', { variant: 'error' });
                          } finally {
                            setPaymentProofDeletingId(null);
                          }
                        }}
                        disabled={paymentProofDeletingId === doc.id}
                      >
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                </Box>
              </Paper>
            );
          })}
        </Stack>
        <Paper variant="outlined" sx={{ p: 1.5, bgcolor: 'action.hover' }}>
          <Typography variant="body2" sx={{ fontWeight: 600, mb: 0.5 }}>
            {t('wholesaleOrderDetail:paymentProofTotals')}
          </Typography>
          <Typography variant="body2">
            £{totalProofAmount.toFixed(2)} · {t('wholesaleOrderDetail:pendingAmount', { amount: pendingAmount.toFixed(2) })}
          </Typography>
        </Paper>
      </>
    );
  }

  return (
    <Table size="small" sx={{ mb: 2 }}>
      <TableHead>
        <TableRow>
          <TableCell>{t('wholesaleOrderDetail:paymentProofDoc')}</TableCell>
          <TableCell>{t('wholesaleOrderDetail:paymentProofAmount')}</TableCell>
          <TableCell>{t('wholesaleOrderDetail:paymentProofDate')}</TableCell>
          <TableCell>{t('wholesaleOrderDetail:paymentProofAccount')}</TableCell>
          <TableCell align="right">{t('wholesaleOrderDetail:actions')}</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {proofDocs.map((doc, idx) => {
          const meta = metaByDocId[doc.id] || {};
          const fileName = displayNameFor(doc) || `${t('wholesaleOrderDetail:paymentProofDoc')} #${idx + 1}`;
          const isPdf = fileName.toLowerCase().endsWith('.pdf');
          return (
            <TableRow key={doc.id}>
              <TableCell
                sx={{ cursor: 'pointer' }}
                onClick={async () => {
                  try {
                    const blob = await wholesaleOrdersAPI.downloadDocument(orderId, doc.id);
                    const a = document.createElement('a');
                    a.href = URL.createObjectURL(blob);
                    a.download = fileName || 'payment-proof';
                    a.click();
                    URL.revokeObjectURL(a.href);
                  } catch (e: unknown) {
                    const err = e as { response?: { data?: { error?: string } }; message?: string };
                    enqueueSnackbar(err?.response?.data?.error || err?.message || 'Download failed', { variant: 'error' });
                  }
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  {isPdf ? (
                    <PdfIcon sx={{ fontSize: 20, color: 'error.main' }} />
                  ) : (
                    <AttachFileIcon sx={{ fontSize: 20, color: 'text.secondary' }} />
                  )}
                  <Typography variant="body2" sx={{ textDecoration: 'underline' }}>
                    {fileName}
                  </Typography>
                </Box>
              </TableCell>
              <TableCell>{meta.amountPerFile != null ? `£${meta.amountPerFile.toFixed(2)}` : '–'}</TableCell>
              <TableCell>{meta.transfer_date ? format(new Date(meta.transfer_date), 'dd/MM/yyyy') : '–'}</TableCell>
              <TableCell>{meta.transferred_to || '–'}</TableCell>
              <TableCell align="right">
                {canDeletePaymentProof && (
                  <Tooltip title={t('wholesaleOrderDetail:remove')}>
                    <IconButton
                      size="small"
                      color="error"
                      onClick={async () => {
                        const ok = window.confirm(t('wholesaleOrderDetail:confirmRemovePaymentProof'));
                        if (!ok) return;
                        setPaymentProofDeletingId(doc.id);
                        try {
                          await wholesaleOrdersAPI.deletePaymentProof(orderId, doc.id, {
                            unlock_after_completion: unlockAfterCompletion,
                          });
                          const updated = await wholesaleOrdersAPI.get(orderId);
                          onOrderRefresh(updated);
                          enqueueSnackbar('Payment proof removed', { variant: 'success' });
                        } catch (e: unknown) {
                          const err = e as { response?: { data?: { error?: string } } };
                          enqueueSnackbar(err.response?.data?.error || 'Failed to remove', { variant: 'error' });
                        } finally {
                          setPaymentProofDeletingId(null);
                        }
                      }}
                      disabled={paymentProofDeletingId === doc.id}
                    >
                      <DeleteIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                )}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
      <TableFooter>
        <TableRow>
          <TableCell sx={{ fontWeight: 600 }}>{t('wholesaleOrderDetail:paymentProofTotals')}</TableCell>
          <TableCell sx={{ fontWeight: 600 }}>£{totalProofAmount.toFixed(2)}</TableCell>
          <TableCell />
          <TableCell sx={{ fontWeight: 600 }}>
            {t('wholesaleOrderDetail:pendingAmount', { amount: pendingAmount.toFixed(2) })}
          </TableCell>
          <TableCell />
        </TableRow>
      </TableFooter>
    </Table>
  );
}

export default function WholesaleOrderDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { t, i18n } = useTranslation(['wholesaleOrderDetail', 'wholesaleOrderAudit', 'wholesaleOrdersPage', 'layout', 'common']);
  const lang = i18n.language || 'en';
  const ORDER_CHANNEL_OPTIONS: { value: string; label: string }[] = [
    { value: 'po', label: t('wholesaleOrderDetail:orderChannelPo') },
    { value: 'whatsapp', label: t('wholesaleOrderDetail:orderChannelWhatsapp') },
    { value: 'wechat', label: t('wholesaleOrderDetail:orderChannelWechat') },
    { value: 'email', label: t('wholesaleOrderDetail:orderChannelEmail') },
    { value: 'na', label: t('wholesaleOrderDetail:orderChannelNA') },
  ];
  const [order, setOrder] = useState<WholesaleOrder | null>(null);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [actioning, setActioning] = useState(false);
  const [assignmentDraft, setAssignmentDraft] = useState<Record<number, number | ''>>({});
  const [selectedItemIds, setSelectedItemIds] = useState<Set<number>>(new Set());
  const [assignToStoreId, setAssignToStoreId] = useState<number | ''>('');
  const [wholesaleShipFromMap, setWholesaleShipFromMap] = useState<Record<number, number>>({});
  const [rejectReason, setRejectReason] = useState('');
  const [showReject, setShowReject] = useState(false);
  const [assignWarningByItemId, setAssignWarningByItemId] = useState<Record<number, { reason: string; detail?: string }>>({});
  const [regenConfirmLoading, setRegenConfirmLoading] = useState(false);
  const [editingShipment, setEditingShipment] = useState<Shipment | null>(null);
  const [shipmentCourier, setShipmentCourier] = useState('');
  const [shipmentTracking, setShipmentTracking] = useState('');
  const [shipmentDeliveryDateDraft, setShipmentDeliveryDateDraft] = useState('');
  const [shipmentSaving, setShipmentSaving] = useState(false);
  const [regenShipmentId, setRegenShipmentId] = useState<number | null>(null);
  const [startShipmentDialog, setStartShipmentDialog] = useState<Shipment | null>(null);
  const [startShipmentSubmitting, setStartShipmentSubmitting] = useState(false);
  const [startShipmentDeliveryDateDraft, setStartShipmentDeliveryDateDraft] = useState('');
  const [startShipmentCourierDraft, setStartShipmentCourierDraft] = useState('');
  const [startShipmentTrackingDraft, setStartShipmentTrackingDraft] = useState('');
  const [uploadSignedNoteShipment, setUploadSignedNoteShipment] = useState<Shipment | null>(null);
  const [uploadSignedNoteSubmitting, setUploadSignedNoteSubmitting] = useState(false);
  const [courierPickupWarnShipment, setCourierPickupWarnShipment] = useState<Shipment | null>(null);
  const deliveryProofInputRefs = useRef<Record<number, HTMLInputElement | null>>({});
  const [caseQtyByOrderItemId, setCaseQtyByOrderItemId] = useState<Record<number, string>>({});
  const [forceCompleteShipmentDialog, setForceCompleteShipmentDialog] = useState<Shipment | null>(null);
  const [forceCompleteShipmentSubmitting, setForceCompleteShipmentSubmitting] = useState(false);
  const [forceCompleteDeliveryDateDraft, setForceCompleteDeliveryDateDraft] = useState('');
  const [shippingFeeDialogOpen, setShippingFeeDialogOpen] = useState(false);
  const [shippingFeeDraft, setShippingFeeDraft] = useState('');
  const [shippingFeeSaving, setShippingFeeSaving] = useState(false);
  const [discountDialogOpen, setDiscountDialogOpen] = useState(false);
  const [discountDraft, setDiscountDraft] = useState('');
  const [discountSaving, setDiscountSaving] = useState(false);
  const [showAssignment, setShowAssignment] = useState(true);
  const [allocationConfirmed, setAllocationConfirmed] = useState(false);
  const [docMenuAnchorEl, setDocMenuAnchorEl] = useState<null | HTMLElement>(null);
  const [invoiceMenuAnchorEl, setInvoiceMenuAnchorEl] = useState<null | HTMLElement>(null);
  const [regenInvoiceLoading, setRegenInvoiceLoading] = useState(false);
  const [orderLockUnlocked, setOrderLockUnlocked] = useState(false);
  const [editingPriceItemId, setEditingPriceItemId] = useState<number | null>(null);
  const [editingItemPrice, setEditingItemPrice] = useState('');
  const [editingDiscountItemId, setEditingDiscountItemId] = useState<number | null>(null);
  const [editingItemDiscount, setEditingItemDiscount] = useState('');
  const [shippingDialogOpen, setShippingDialogOpen] = useState(false);
  const [shippingSaving, setShippingSaving] = useState(false);
  // ''  = company address, number = existing store, 'new' = brand new shipping location
  const [shippingStoreIdDraft, setShippingStoreIdDraft] = useState<number | '' | 'new'>('');
  // When the user picks "Other address" and saves, we create/update that store and keep its id here
  // so future edits update the same record (no duplicates).
  const [otherAddressStoreId, setOtherAddressStoreId] = useState<number | null>(null);
  const [shippingStores, setShippingStores] = useState<WholesaleClientStore[]>([]);
  const [shippingNameDraft, setShippingNameDraft] = useState('');
  const [shippingAddress1Draft, setShippingAddress1Draft] = useState('');
  const [shippingAddress2Draft, setShippingAddress2Draft] = useState('');
  const [shippingCityDraft, setShippingCityDraft] = useState('');
  const [shippingPostcodeDraft, setShippingPostcodeDraft] = useState('');
  const [poChannelDialogOpen, setPOChannelDialogOpen] = useState(false);
  const [editingRefNo, setEditingRefNo] = useState(false);
  const [editingPODate, setEditingPODate] = useState(false);
  const [editingOrderDate, setEditingOrderDate] = useState(false);
  const [editingShipmentCompleteDate, setEditingShipmentCompleteDate] = useState(false);
  const [shipmentCompleteDateDraft, setShipmentCompleteDateDraft] = useState('');
  const [savingShipmentCompleteDate, setSavingShipmentCompleteDate] = useState(false);
  const [editingInvoiceDate, setEditingInvoiceDate] = useState(false);
  const [invoiceDateDraft, setInvoiceDateDraft] = useState('');
  const [savingInvoiceDate, setSavingInvoiceDate] = useState(false);
  const [editingInvoiceSentAt, setEditingInvoiceSentAt] = useState(false);
  const [invoiceSentDraft, setInvoiceSentDraft] = useState('');
  const [savingInvoiceSentAt, setSavingInvoiceSentAt] = useState(false);
  const [poNumberDraft, setPONumberDraft] = useState('');
  const [orderChannelDraft, setOrderChannelDraft] = useState('');
  const [recentOrderChannels, setRecentOrderChannels] = useState<string[]>([]);
  const [poChannelSaving, setPOChannelSaving] = useState(false);
  const [refNoDraft, setRefNoDraft] = useState('');
  const [poDateDraft, setPODateDraft] = useState('');
  const [orderDateDraft, setOrderDateDraft] = useState('');
  const [poAttachmentUploading, setPoAttachmentUploading] = useState(false);
  const [poAttachmentDeletingId, setPoAttachmentDeletingId] = useState<number | null>(null);
  const [poDropActive, setPoDropActive] = useState(false);
  const [editingPoAttachments, setEditingPoAttachments] = useState(false);
  const [assignmentBoxesByItemId, setAssignmentBoxesByItemId] = useState<Record<number, string>>({});
  const [assignmentQtyByItemId, setAssignmentQtyByItemId] = useState<Record<number, string>>({});
  const [expandedShipmentIds, setExpandedShipmentIds] = useState<Set<number>>(new Set());
  const [shipmentsFullscreen, setShipmentsFullscreen] = useState(false);
  const [assignmentDeliveryDateByItemId, setAssignmentDeliveryDateByItemId] = useState<Record<number, string>>({});
  const [assignConfirmOpen, setAssignConfirmOpen] = useState(false);
  const [endorsePreviewOpen, setEndorsePreviewOpen] = useState(false);
  const [endorsePreview, setEndorsePreview] = useState<EndorseAllocationPreview | null>(null);
  const [endorsePreviewLoading, setEndorsePreviewLoading] = useState(false);
  const [stagedManualAssignments, setStagedManualAssignments] = useState<StagedStoreAssignment[]>([]);
  const [assignStoreStock, setAssignStoreStock] = useState<Stock[]>([]);
  const [assignStoreStockLoading, setAssignStoreStockLoading] = useState(false);
  const [paymentProofUploading, setPaymentProofUploading] = useState(false);
  const [paymentProofDropActive, setPaymentProofDropActive] = useState(false);
  const [paymentProofDeletingId, setPaymentProofDeletingId] = useState<number | null>(null);
  const [filePreview, setFilePreview] = useState<{ url: string; name: string } | null>(null);
  const [paymentConfirming, setPaymentConfirming] = useState(false);
  const [confirmOrderNoProofDialogOpen, setConfirmOrderNoProofDialogOpen] = useState(false);
  const [forceCompleteHasProof, setForceCompleteHasProof] = useState(false);
  const [forceConfirmPaymentDialogOpen, setForceConfirmPaymentDialogOpen] = useState(false);
  const [pendingPaymentProofFiles, setPendingPaymentProofFiles] = useState<File[] | null>(null);
  const [pendingProofPreviewUrls, setPendingProofPreviewUrls] = useState<Record<string, string>>({});
  const [paymentAmountDraft, setPaymentAmountDraft] = useState('');
  const [paymentTransferDateDraft, setPaymentTransferDateDraft] = useState('');
  const [paymentTransferredToDraft, setPaymentTransferredToDraft] = useState('');
  const [companySettings, setCompanySettings] = useState<CompanySettings | null>(null);
  const { enqueueSnackbar } = useSnackbar();
  const location = useLocation();
  const promptOrderConfirmHandled = useRef(false);
  const assignSectionRef = useRef<HTMLDivElement>(null);
  const orderConfirmEmailSectionRef = useRef<HTMLDivElement>(null);
  const [emailDialogOpen, setEmailDialogOpen] = useState(false);
  const [emailTo, setEmailTo] = useState<string[]>([]);
  const [emailCc, setEmailCc] = useState<string[]>([]);
  const [emailBcc, setEmailBcc] = useState<string[]>([]);
  const [emailToInput, setEmailToInput] = useState('');
  const [emailCcInput, setEmailCcInput] = useState('');
  const [emailBccInput, setEmailBccInput] = useState('');
  const [emailSubject, setEmailSubject] = useState('');
  const [emailMessage, setEmailMessage] = useState('');
  const [emailContentLangs, setEmailContentLangs] = useState<EmailContentLanguage[]>(['en']);
  const [emailAttachments, setEmailAttachments] = useState<Record<string, boolean>>({});
  const [emailSending, setEmailSending] = useState(false);
  const [emailSubjectLocked, setEmailSubjectLocked] = useState(false);
  const [emailKind, setEmailKind] = useState<WholesaleOrderEmailType | null>(null);
  const [emailShipmentIds, setEmailShipmentIds] = useState<number[] | null>(null);
  const [isShipmentDocumentsEmail, setIsShipmentDocumentsEmail] = useState(false);
  const [selectedShipmentIdsForEmail, setSelectedShipmentIdsForEmail] = useState<Set<number>>(
    () => new Set(),
  );
  const [emailResendSummary, setEmailResendSummary] = useState<WholesaleEmailResendSummary | null>(null);
  const [emailChipSelection, setEmailChipSelection] = useState<{
    field: EmailChipField | null;
    indices: number[];
  }>({ field: null, indices: [] });
  const [skippedEmailPrompts, setSkippedEmailPrompts] = useState<WholesaleOrderEmailType[]>([]);
  const [skipEmailDialogOpen, setSkipEmailDialogOpen] = useState(false);
  const [skipEmailKind, setSkipEmailKind] = useState<WholesaleOrderEmailType | null>(null);
  const [skipEmailRemark, setSkipEmailRemark] = useState('');
  const theme = useTheme();
  // Card layout below xl: the order page uses a 300px audit sidebar from lg up, leaving too
  // little width for the wide shipments table (especially with the app nav drawer).
  const isShipmentsMobile = useMediaQuery(theme.breakpoints.down('md'));

  useEffect(() => {
    settingsAPI.getCompany().then(setCompanySettings).catch(() => {});
  }, []);

  useEffect(() => {
    if (!shipmentsFullscreen) return;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKeyDown = (e: globalThis.KeyboardEvent) => {
      if (e.key === 'Escape') setShipmentsFullscreen(false);
    };
    window.addEventListener('keydown', onKeyDown);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [shipmentsFullscreen]);

  const shipmentCourierOptions = useMemo(
    () => shipmentCourierOptionsFromSettings(companySettings?.shipment_couriers),
    [companySettings?.shipment_couriers],
  );

  const transferAccountOptions = useMemo(() => {
    const parseLines = (v?: string | null) =>
      (v ?? '')
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => l.length > 0);

    // Only use dedicated payment_transfer_to_info for the "轉入帳戶" dropdown.
    const transferToInfoLines = parseLines(companySettings?.payment_transfer_to_info);
    if (transferToInfoLines.length > 0) return transferToInfoLines;

    // If nothing configured, provide a single default option so the user can still record payment.
    return [t('wholesaleOrderDetail:defaultTransferredAccount')];
  }, [companySettings, t]);

  const openForceConfirmPaymentDialog = (o: WholesaleOrder, files: FileList | null) => {
    const orderTotalForDialog = (o.total_net ?? totalForOrder(o)) + (Number(o.shipping_fee) || 0);
    const remaining = Math.max(0, orderTotalForDialog - totalProofAmount);
    const amountDefault = remaining || orderTotalForDialog || 0;
    setPaymentAmountDraft(String(amountDefault.toFixed(2)));
    setPaymentTransferDateDraft(new Date().toISOString().slice(0, 10));
    setPaymentTransferredToDraft(transferAccountOptions[0] ?? '');
    // Make a defensive copy of the FileList so it is not cleared
    // when the underlying file input value is reset.
    setPendingPaymentProofFiles(files ? Array.from(files) : null);
    setForceConfirmPaymentDialogOpen(true);
  };

  useEffect(() => {
    // If the dialog was opened before company settings loaded, populate the account once available.
    if (forceConfirmPaymentDialogOpen && !paymentTransferredToDraft && transferAccountOptions.length > 0) {
      setPaymentTransferredToDraft(transferAccountOptions[0]);
    }
  }, [forceConfirmPaymentDialogOpen, paymentTransferredToDraft, transferAccountOptions]);

  useEffect(() => {
    if (!forceConfirmPaymentDialogOpen || !pendingPaymentProofFiles?.length) {
      setPendingProofPreviewUrls((prev) => {
        Object.values(prev).forEach((url) => URL.revokeObjectURL(url));
        return {};
      });
      return;
    }
    const isImage = (f: File) => f.type.startsWith('image/');
    const isPdf = (f: File) => f.type === 'application/pdf';
    const next: Record<string, string> = {};
    pendingPaymentProofFiles.forEach((f, idx) => {
      if (isImage(f) || isPdf(f)) {
        next[`${f.name}-${idx}`] = URL.createObjectURL(f);
      }
    });
    setPendingProofPreviewUrls((prev) => {
      Object.values(prev).forEach((url) => URL.revokeObjectURL(url));
      return next;
    });
    return () => {
      Object.values(next).forEach((url) => URL.revokeObjectURL(url));
    };
  }, [forceConfirmPaymentDialogOpen, pendingPaymentProofFiles]);

  const submitForceConfirmPayment = async () => {
    if (!order) return;
    if (!pendingPaymentProofFiles || pendingPaymentProofFiles.length === 0) {
      enqueueSnackbar(t('wholesaleOrderDetail:paymentProofRequired'), { variant: 'error' });
      return;
    }
    const amount = parseFloat(paymentAmountDraft);
    if (Number.isNaN(amount) || amount <= 0) {
      enqueueSnackbar(t('wholesaleOrderDetail:paymentAmountRequired'), { variant: 'error' });
      return;
    }
    if (!paymentTransferDateDraft) {
      enqueueSnackbar(t('wholesaleOrderDetail:paymentDateRequired'), { variant: 'error' });
      return;
    }
    if (!paymentTransferredToDraft) {
      enqueueSnackbar(t('wholesaleOrderDetail:paymentTransferredToRequired'), { variant: 'error' });
      return;
    }

    try {
      setPaymentConfirming(true);
      await uploadPaymentProofFiles(pendingPaymentProofFiles, {
        amount,
        transfer_date: paymentTransferDateDraft,
        transferred_to: paymentTransferredToDraft,
      });
      setForceConfirmPaymentDialogOpen(false);
      setPendingPaymentProofFiles(null);
      enqueueSnackbar('Payment proof uploaded', { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || 'Failed to upload payment proof', { variant: 'error' });
    } finally {
      setPaymentConfirming(false);
    }
  };

  const acceptPoFile = (file: File) =>
    file.type === 'application/pdf' || file.type.startsWith('image/');
  const uploadPaymentProofFiles = async (
    files: FileList | File[] | null,
    meta?: { amount: number; transfer_date: string; transferred_to: string },
  ) => {
    if (!order) return;
    const unlockUpload = shouldSendUploadUnlockFlag(order, orderLockUnlocked);
    if (order.payment_confirmed_at && !unlockUpload) {
      enqueueSnackbar('Payment already confirmed; cannot upload more payment proof', { variant: 'warning' });
      return;
    }
    const fileArray = files ? Array.from(files as File[] | FileList) : [];
    if (!fileArray.length) return;
    const valid = fileArray.filter(acceptPoFile);
    if (!valid.length) return;
    const toUpload = valid;
    if (!toUpload.length) {
      return;
    }
    setPaymentProofUploading(true);
    try {
      const updated = await wholesaleOrdersAPI.uploadPaymentProofs(order.id, toUpload, meta, {
        unlock_after_completion: unlockUpload,
      });
      setOrder(updated);
      // Keep audit section in sync after adding payment proof.
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => []);
      setAuditLogs(freshAuditLogs);
      enqueueSnackbar('Payment proof(s) added', { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || 'Failed to upload', { variant: 'error' });
    } finally {
      setPaymentProofUploading(false);
    }
  };
  const uploadPoFiles = async (files: FileList | null) => {
    if (!order || !files?.length) return;
    const endorsed = order.status !== 'pending_approval' && order.status !== 'rejected';
    if (endorsed && !editingPoAttachments) return;
    const valid = Array.from(files).filter(acceptPoFile);
    if (!valid.length) return;
    const poCount = order.documents?.filter((d) => d.type === 'po_attachment').length ?? 0;
    const toUpload = valid.slice(0, Math.max(0, 5 - poCount));
    if (!toUpload.length) {
      enqueueSnackbar(t('wholesaleOrderDetail:maxPoAttachmentsReached'), { variant: 'info' });
      return;
    }
    setPoAttachmentUploading(true);
    try {
      await wholesaleOrdersAPI.uploadPoAttachments(order.id, toUpload, {
        unlock_after_completion: shouldSendUploadUnlockFlag(order, orderLockUnlocked),
      });
      const updated = await wholesaleOrdersAPI.get(order.id);
      setOrder(updated);
      enqueueSnackbar('PO attachment(s) added', { variant: 'success' });
    } catch (err: any) {
      enqueueSnackbar(err.response?.data?.error || 'Failed to upload', { variant: 'error' });
    } finally {
      setPoAttachmentUploading(false);
    }
  };
  const orderId = id ? Number(id) : NaN;
  const canAssign =
    order?.status === 'pending_approval' ||
    order?.status === 'assign_shipment' ||
    order?.status === 'approved';
  const usesStagedAssignment = order?.status === 'pending_approval';
  const storeNameById = useMemo(() => new Map(stores.map((s) => [s.id, s.name])), [stores]);

  const pendingQtyForItem = (item: Pick<WholesaleOrderItem, 'id' | 'quantity'>) => {
    if (!order) return 0;
    if (usesStagedAssignment) {
      return pendingQtyForOrderItemWithStaging(order, item, stagedManualAssignments);
    }
    return pendingQtyForOrderItem(order, item);
  };

  const assignStoreStockByProduct = useMemo(
    () => new Map(assignStoreStock.map((s) => [s.product_id, s])),
    [assignStoreStock],
  );

  useEffect(() => {
    if (assignToStoreId === '') {
      setAssignStoreStock([]);
      return undefined;
    }
    let cancelled = false;
    setAssignStoreStockLoading(true);
    stockAPI
      .getStoreStock(assignToStoreId as number)
      .then((rows) => {
        if (!cancelled) setAssignStoreStock(rows);
      })
      .catch(() => {
        if (!cancelled) setAssignStoreStock([]);
      })
      .finally(() => {
        if (!cancelled) setAssignStoreStockLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [assignToStoreId]);

  useEffect(() => {
    setOrderLockUnlocked(false);
  }, [orderId]);

  useEffect(() => {
    if (!id || Number.isNaN(orderId)) return;
    promptOrderConfirmHandled.current = false;
    setSkippedEmailPrompts([]);
    setEditingPoAttachments(false);
    const load = async () => {
      try {
        setLoading(true);
        const [orderData, storesData, channels, auditLogsData, shipFromRaw] = await Promise.all([
          wholesaleOrdersAPI.get(orderId),
          storesAPI.list(),
          wholesaleOrdersAPI.getRecentOrderChannels().catch(() => []),
          wholesaleOrdersAPI.getAuditLogs(orderId).catch(() => []),
          stockAPI.getWholesaleShipFromMap().catch(() => ({})),
        ]);
        setOrder(orderData);
        setAuditLogs(auditLogsData);
        setStores(storesData);
        setRecentOrderChannels(channels);
        const shipFromMap: Record<number, number> = {};
        Object.entries(shipFromRaw as Record<string, number>).forEach(([productId, storeId]) => {
          shipFromMap[Number(productId)] = Number(storeId);
        });
        setWholesaleShipFromMap(shipFromMap);
        const draft: Record<number, number | ''> = {};
        orderData.items?.forEach((it) => {
          draft[it.id] = it.assigned_store_id ?? '';
        });
        setAssignmentDraft(draft);
        setShowAssignment(!allOrderLinesFullyAssigned(orderData));
        setAllocationConfirmed(allOrderLinesFullyAssigned(orderData));
        if (orderData.status !== 'pending_approval') {
          setStagedManualAssignments([]);
        }
      } catch {
        enqueueSnackbar('Failed to load order', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [id, orderId, enqueueSnackbar]);

  useEffect(() => {
    const shipment = startShipmentDialog ?? forceCompleteShipmentDialog ?? editingShipment;
    if (!shipment?.items?.length) {
      setCaseQtyByOrderItemId({});
      return;
    }
    const next: Record<number, string> = {};
    shipment.items.forEach((it) => {
      const expected = shipmentExpectedBoxes(it);
      next[it.wholesale_order_item_id] = expected > 0 ? String(expected) : '';
    });
    setCaseQtyByOrderItemId(next);
  }, [startShipmentDialog, forceCompleteShipmentDialog, editingShipment]);

  // Load client stores for shipping-address editing when order changes
  useEffect(() => {
    const loadClientStores = async () => {
      if (!order?.wholesale_client_id) return;
      try {
        const client = await wholesaleClientsAPI.get(order.wholesale_client_id);
        setShippingStores(client.stores || []);
      } catch {
        // ignore; dialog will still allow company address editing
      }
    };
    loadClientStores();
  }, [order?.wholesale_client_id]);

  // If the user edits the address fields while a specific store/company is selected,
  // automatically switch to "Other address" so we don't overwrite existing locations unintentionally.
  useEffect(() => {
    if (!order) return;
    if (shippingStoreIdDraft === 'new') return;
    const stores = order.wholesale_client?.stores ?? shippingStores;
    let base1 = '';
    let base2 = '';
    let baseCity = '';
    let basePostcode = '';
    if (shippingStoreIdDraft === '') {
      base1 = order.wholesale_client?.address_line1 ?? '';
      base2 = order.wholesale_client?.address_line2 ?? '';
      basePostcode = order.wholesale_client?.postcode ?? '';
    } else {
      const store = stores.find((s) => s.id === shippingStoreIdDraft);
      if (store) {
        base1 = store.address_line1 ?? '';
        base2 = store.address_line2 ?? '';
        baseCity = store.city ?? '';
        basePostcode = store.postcode ?? '';
      }
    }
    const a1 = shippingAddress1Draft ?? '';
    const a2 = shippingAddress2Draft ?? '';
    const c = shippingCityDraft ?? '';
    const p = shippingPostcodeDraft ?? '';
    const changed =
      a1.trim() !== base1.trim() ||
      a2.trim() !== base2.trim() ||
      c.trim() !== baseCity.trim() ||
      p.trim() !== basePostcode.trim();
    if (changed) {
      setShippingStoreIdDraft('new');
    }
  }, [
    order,
    shippingStores,
    shippingStoreIdDraft,
    shippingAddress1Draft,
    shippingAddress2Draft,
    shippingCityDraft,
    shippingPostcodeDraft,
  ]);

  useEffect(() => {
    if (startShipmentDialog) {
      setStartShipmentDeliveryDateDraft(format(new Date(), 'yyyy-MM-dd'));
      const existing = (startShipmentDialog.courier ?? '').trim();
      setStartShipmentCourierDraft(
        existing || shipmentCourierOptions[0] || '',
      );
      setStartShipmentTrackingDraft(startShipmentDialog.tracking_number ?? '');
    }
  }, [startShipmentDialog, shipmentCourierOptions]);

  useEffect(() => {
    if (!forceCompleteShipmentDialog) return;
    setForceCompleteDeliveryDateDraft(
      forceCompleteShipmentDialog.delivery_date
        ? String(forceCompleteShipmentDialog.delivery_date).substring(0, 10)
        : format(new Date(), 'yyyy-MM-dd'),
    );
  }, [forceCompleteShipmentDialog]);

  useEffect(() => {
    if (assignConfirmOpen && order) {
      const today = format(new Date(), 'yyyy-MM-dd');
      const selected = Array.from(selectedItemIds);
      setAssignmentBoxesByItemId((prev) => {
        const next = { ...prev };
        selected.forEach((id) => {
          if (next[id]?.trim()) return;
          const assigned = assignedCaseQtyForOrderItem(order.shipments, id);
          if (assigned != null && assigned > 0) {
            next[id] = String(assigned);
            return;
          }
          const item = order.items?.find((it) => it.id === id);
          if (item) {
            const expected = orderItemExpectedBoxes(item);
            if (expected > 0) next[id] = String(expected);
          }
        });
        return next;
      });
      setAssignmentQtyByItemId((prev) => {
        const next = { ...prev };
        selected.forEach((id) => {
          if (next[id]?.trim()) return;
          const item = order.items?.find((it) => it.id === id);
          if (!item) return;
          const pending = pendingQtyForOrderItem(order, item);
          if (pending > 0) next[id] = String(pending);
        });
        return next;
      });
      setAssignmentDeliveryDateByItemId((prev) => {
        const next = { ...prev };
        selected.forEach((id) => {
          if (!next[id]) next[id] = today;
        });
        return next;
      });
    }
  }, [assignConfirmOpen, order?.id, selectedItemIds]);

  const totalForOrder = (o: WholesaleOrder) =>
    o.total_net != null
      ? o.total_net
      : o.items?.reduce((sum, it) => sum + (it.line_total || 0), 0) ?? 0;

  const orderChannelOptions = useMemo(() => {
    const seen = new Set(recentOrderChannels.map((c) => c.toLowerCase()));
    const standard = ORDER_CHANNEL_OPTIONS.map((o) => o.value).filter((v) => !seen.has(v.toLowerCase()));
    return [...recentOrderChannels, ...standard];
  }, [recentOrderChannels]);

  const emailAttachmentOptions = useMemo(() => {
    if (!order) return [];
    const poCount = order.documents?.filter((d) => d.type === 'po_attachment').length ?? 0;
    const proofCount =
      (order.documents?.filter((d) => d.type === 'payment_proof').length ?? 0) +
      (order.payment_proof_url && !order.documents?.some((d) => d.type === 'payment_proof') ? 1 : 0);
    const dnCount = order.shipments?.filter((s) => s.delivery_note_pdf_url).length ?? 0;
    const signedDnCount = order.shipments?.filter((s) => s.signed_delivery_note_pdf_url).length ?? 0;
    return [
      {
        key: 'order_confirmation',
        label: t('wholesaleOrderDetail:orderConfirmation'),
        available: !!order.documents?.some((d) => d.type === 'order_confirmation'),
      },
      {
        key: 'invoice',
        label: t('wholesaleOrderDetail:invoice'),
        available: !!order.documents?.some((d) => d.type === 'invoice'),
      },
      {
        key: 'po_attachment',
        label: t('wholesaleOrderDetail:emailAttachPo'),
        available: poCount > 0,
        hint: poCount > 1 ? `×${poCount}` : undefined,
      },
      {
        key: 'payment_proof',
        label: t('wholesaleOrderDetail:emailAttachPaymentProof'),
        available: proofCount > 0,
        hint: proofCount > 1 ? `×${proofCount}` : undefined,
      },
      {
        key: 'delivery_note',
        label: t('wholesaleOrderDetail:deliveryNote'),
        available: dnCount > 0,
        hint: dnCount > 1 ? `×${dnCount}` : undefined,
      },
      {
        key: 'signed_delivery_note',
        label: t('wholesaleOrderDetail:deliveryProof'),
        available: signedDnCount > 0,
        hint: signedDnCount > 1 ? `×${signedDnCount}` : undefined,
      },
    ];
  }, [order, t]);

  const emailAttachmentOptionsForDialog = useMemo(() => {
    if (!emailShipmentIds?.length) return emailAttachmentOptions;
    return emailAttachmentOptions
      .filter((opt) => opt.key === 'delivery_note' || opt.key === 'signed_delivery_note')
      .map((opt) => {
        const count = emailShipmentIds.filter((id) => {
          const sh = order?.shipments?.find((s) => s.id === id);
          if (!sh) return false;
          if (opt.key === 'delivery_note') return !!sh.delivery_note_pdf_url?.trim();
          return !!sh.signed_delivery_note_pdf_url?.trim();
        }).length;
        return {
          ...opt,
          available: count > 0,
          hint: count > 1 ? `×${count}` : undefined,
        };
      });
  }, [emailAttachmentOptions, emailShipmentIds, order?.shipments]);

  const dedupeEmailList = (values: string[]): string[] => {
    const out: string[] = [];
    const seen = new Set<string>();
    values.forEach((raw) => {
      parseEmailListFromRaw(raw).forEach((email) => {
        const key = email.toLowerCase();
        if (seen.has(key)) return;
        seen.add(key);
        out.push(email);
      });
    });
    return out;
  };

  const applyEmailChipList = (values: string[], notifyDuplicate = true): string[] => {
    const out: string[] = [];
    const seen = new Set<string>();
    const duplicates: string[] = [];
    values.forEach((raw) => {
      parseEmailListFromRaw(raw).forEach((email) => {
        const key = email.toLowerCase();
        if (seen.has(key)) {
          if (!duplicates.some((d) => d.toLowerCase() === key)) duplicates.push(email);
          return;
        }
        seen.add(key);
        out.push(email);
      });
    });
    if (notifyDuplicate && duplicates.length > 0) {
      enqueueSnackbar(
        t('wholesaleOrderDetail:emailDuplicateAddress', { email: duplicates.join(', ') }),
        { variant: 'warning' },
      );
    }
    return out;
  };

  const addEmailsToChipList = (existing: string[], toAdd: string[]): string[] =>
    applyEmailChipList([...existing, ...toAdd]);

  const emailListHasMultipleAddresses = (raw: string): boolean => /[,;\n\r]/.test(raw);

  const isValidEmail = (email: string): boolean => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);

  const invalidEmailChips = useMemo(
    () => [...emailTo, ...emailCc, ...emailBcc].filter((v) => !isValidEmail(v)),
    [emailTo, emailCc, emailBcc],
  );

  const resolvedEmailToList = useMemo(() => {
    const pending = emailToInput.trim();
    const combined = pending ? [...emailTo, pending] : emailTo;
    return dedupeEmailList(combined);
  }, [emailTo, emailToInput]);

  const hasValidEmailTo = useMemo(
    () => resolvedEmailToList.some((v) => isValidEmail(v)),
    [resolvedEmailToList],
  );

  const emailToInputInvalid = useMemo(() => {
    const pending = emailToInput.trim();
    if (!pending) return false;
    if (emailListHasMultipleAddresses(pending)) {
      const parts = parseEmailListFromRaw(pending);
      return parts.length === 0 || parts.some((p) => !isValidEmail(p));
    }
    return !isValidEmail(pending);
  }, [emailToInput]);

  const canSendEmail =
    !emailSending &&
    hasValidEmailTo &&
    invalidEmailChips.length === 0 &&
    !emailToInputInvalid &&
    !!emailSubject.trim() &&
    Object.values(emailAttachments).some(Boolean);

  const openPOChannelDialog = () => {
    if (order) {
      setOrderChannelDraft(order.order_channel || '');
      setPONumberDraft(order.po_number || '');
      setPOChannelDialogOpen(true);
    }
  };

  const savePOAndChannel = async () => {
    if (!order) return;
    setPOChannelSaving(true);
    try {
      const channelTrimmed = orderChannelDraft.trim();
      const poTrimmed = poNumberDraft.trim();
      const updated = await wholesaleOrdersAPI.update(order.id, {
        order_channel: channelTrimmed || undefined,
        // Allow empty PO to be sent so backend can regenerate or clear it
        po_number: poTrimmed,
      });
      setOrder(updated);
      setPOChannelDialogOpen(false);
      enqueueSnackbar('PO & channel updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update', { variant: 'error' });
    } finally {
      setPOChannelSaving(false);
    }
  };

  const orderChannelDisplayLabel = (ch: string) =>
    ORDER_CHANNEL_OPTIONS.find((o) => o.value === ch)?.label ?? ch;

  const saveRefNo = async () => {
    if (!order) return;
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { ref_no: refNoDraft });
      setOrder(updated);
      setEditingRefNo(false);
      enqueueSnackbar('OC Number updated', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to update OC Number', { variant: 'error' });
      // Keep editing so user can fix and retry
    }
  };

  const savePODate = async () => {
    if (!order) return;
    try {
      const completedShipmentIds =
        order.shipments?.filter((s: any) => s.status === 'completed').map((s: any) => s.id) ?? [];
      const allShipmentsCompletedNow =
        (order.shipments?.length ?? 0) > 0 && order.shipments!.every((s: any) => s.status === 'completed');

      const updated = await wholesaleOrdersAPI.update(order.id, { po_date: poDateDraft || '' });

      // PO date affects OC/invoice/2nd-table (PO Date), so regenerate best-effort (skip emailed docs).
      const regenJobs: Promise<unknown>[] = [];
      const skippedDocs: string[] = [];
      if (!isRegenBlockedByEmailLock(auditLogs, 'order_confirmation', orderLockUnlocked)) {
        regenJobs.push(
          wholesaleOrdersAPI.regenerateOrderConfirmation(updated.id, {
            unlock_after_email: shouldSendRegenUnlockFlag(
              auditLogs,
              'order_confirmation',
              orderLockUnlocked,
            ),
          }),
        );
      } else {
        skippedDocs.push(t('wholesaleOrderDetail:orderConfirmation'));
      }
      completedShipmentIds.forEach((shipmentId) => {
        if (!isRegenBlockedByEmailLock(auditLogs, 'delivery_note', orderLockUnlocked, shipmentId)) {
          regenJobs.push(
            shipmentsAPI.regenerateDeliveryNote(shipmentId, {
              unlock_after_email: shouldSendRegenUnlockFlag(
                auditLogs,
                'delivery_note',
                orderLockUnlocked,
                shipmentId,
              ),
            }),
          );
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:deliveryNote'));
        }
      });
      if (allShipmentsCompletedNow) {
        if (!isRegenBlockedByEmailLock(auditLogs, 'invoice', orderLockUnlocked)) {
          regenJobs.push(
            wholesaleOrdersAPI.generateInvoice(updated.id, {
              unlock_after_email: shouldSendRegenUnlockFlag(auditLogs, 'invoice', orderLockUnlocked),
            }),
          );
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
      if (regenJobs.length > 0) await Promise.allSettled(regenJobs);

      const freshOrder = await wholesaleOrdersAPI.get(updated.id, { cacheBust: true });
      setOrder(freshOrder);
      setEditingPODate(false);
      enqueueSnackbar('PO Date updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update PO Date', { variant: 'error' });
    }
  };

  const saveOrderDate = async () => {
    if (!order) return;
    const confirmMsg = t('wholesaleOrderDetail:confirmUpdateOrderDateRegenAllDocs');
    if (!window.confirm(confirmMsg)) return;

    const allShipmentsCompletedNow =
      (order.shipments?.length ?? 0) > 0 && order.shipments!.every((s: any) => s.status === 'completed');
    const completedShipmentIds =
      order.shipments?.filter((s: any) => s.status === 'completed').map((s: any) => s.id) ?? [];
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { order_date: orderDateDraft || '' });

      // Order date affects OC/invoice headers, so regenerate existing docs best-effort (skip emailed docs).
      const regenJobs: Promise<unknown>[] = [];
      const skippedDocs: string[] = [];
      if (updated.status === 'approved' || updated.status === 'assign_shipment') {
        if (!isRegenBlockedByEmailLock(auditLogs, 'order_confirmation', orderLockUnlocked)) {
          regenJobs.push(
            wholesaleOrdersAPI.regenerateOrderConfirmation(updated.id, {
              unlock_after_email: shouldSendRegenUnlockFlag(
                auditLogs,
                'order_confirmation',
                orderLockUnlocked,
              ),
            }),
          );
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:orderConfirmation'));
        }
      }
      if (allShipmentsCompletedNow) {
        if (!isRegenBlockedByEmailLock(auditLogs, 'invoice', orderLockUnlocked)) {
          regenJobs.push(
            wholesaleOrdersAPI.generateInvoice(updated.id, {
              unlock_after_email: shouldSendRegenUnlockFlag(auditLogs, 'invoice', orderLockUnlocked),
            }),
          );
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:invoice'));
        }
      }
      completedShipmentIds.forEach((shipmentId) => {
        if (!isRegenBlockedByEmailLock(auditLogs, 'delivery_note', orderLockUnlocked, shipmentId)) {
          regenJobs.push(
            shipmentsAPI.regenerateDeliveryNote(shipmentId, {
              unlock_after_email: shouldSendRegenUnlockFlag(
                auditLogs,
                'delivery_note',
                orderLockUnlocked,
                shipmentId,
              ),
            }),
          );
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
        if (anyRejected) {
          enqueueSnackbar('Some documents failed to re-generate.', { variant: 'warning' });
        }
      }

      const freshOrder = await wholesaleOrdersAPI.get(updated.id, { cacheBust: true });
      setOrder(freshOrder);
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(updated.id).catch(() => []);
      setAuditLogs(freshAuditLogs);
      setEditingOrderDate(false);
      enqueueSnackbar('Order date updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update order date', { variant: 'error' });
    }
  };

  const saveShipmentCompleteDate = async () => {
    if (!order) return;
    const completedShipments = order.shipments?.filter((s: any) => s.status === 'completed') ?? [];
    if (completedShipments.length === 0) return;

    // Must match backend: candidate = delivery_date if set, else created_at; pick latest.
    const latestCompletedShipment = completedShipments.reduce<any>((acc: any, sh: any) => {
      const accCandidate = acc.delivery_date ?? acc.created_at;
      const shCandidate = sh.delivery_date ?? sh.created_at;
      return new Date(shCandidate).getTime() > new Date(accCandidate).getTime() ? sh : acc;
    }, completedShipments[0]);

    if (!shipmentCompleteDateDraft) return;

    try {
      setSavingShipmentCompleteDate(true);
      const msg = t('wholesaleOrderAudit:confirmUpdateShipmentCompleteDateRegenInvoiceAndDN');
      if (!window.confirm(msg)) return;

      await shipmentsAPI.update(latestCompletedShipment.id, { delivery_date: shipmentCompleteDateDraft });

      const completedShipmentIds = completedShipments.map((s: any) => s.id);
      const allShipmentsCompletedNow =
        (order.shipments?.length ?? 0) > 0 && order.shipments!.every((s: any) => s.status === 'completed');

      // Regenerate invoice (header "Date:") + delivery notes best-effort (skip emailed docs).
      const regenJobs: Promise<unknown>[] = [];
      const skippedDocs: string[] = [];
      completedShipmentIds.forEach((shipmentId: number) => {
        if (!isRegenBlockedByEmailLock(auditLogs, 'delivery_note', orderLockUnlocked, shipmentId)) {
          regenJobs.push(
            shipmentsAPI.regenerateDeliveryNote(shipmentId, {
              unlock_after_email: shouldSendRegenUnlockFlag(
                auditLogs,
                'delivery_note',
                orderLockUnlocked,
                shipmentId,
              ),
            }),
          );
        } else {
          skippedDocs.push(t('wholesaleOrderDetail:deliveryNote'));
        }
      });
      if (allShipmentsCompletedNow) {
        if (!isRegenBlockedByEmailLock(auditLogs, 'invoice', orderLockUnlocked)) {
          regenJobs.push(
            wholesaleOrdersAPI.generateInvoice(order.id, {
              unlock_after_email: shouldSendRegenUnlockFlag(auditLogs, 'invoice', orderLockUnlocked),
            }),
          );
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
      if (regenJobs.length > 0) await Promise.allSettled(regenJobs);

      const freshOrder = await wholesaleOrdersAPI.get(order.id, { cacheBust: true });
      setOrder(freshOrder);
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => []);
      setAuditLogs(freshAuditLogs);
      setEditingShipmentCompleteDate(false);
      enqueueSnackbar('Shipment complete date updated', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e?.response?.data?.error || 'Failed to update shipment complete date', { variant: 'error' });
    } finally {
      setSavingShipmentCompleteDate(false);
    }
  };

  const saveInvoiceDate = async () => {
    if (!order) return;
    if (!invoiceDateDraft || invoiceDateDraft.length < 10) return;
    try {
      setSavingInvoiceDate(true);
      await wholesaleOrdersAPI.update(order.id, { invoice_date: invoiceDateDraft.substring(0, 10) });
      if (isRegenBlockedByEmailLock(auditLogs, 'invoice', orderLockUnlocked)) {
        const freshOrder = await wholesaleOrdersAPI.get(order.id, { cacheBust: true });
        setOrder(freshOrder);
        setEditingInvoiceDate(false);
        enqueueSnackbar(
          t('wholesaleOrderDetail:documentRegenSkippedAfterEmail', { document: t('wholesaleOrderDetail:invoice') }),
          { variant: 'warning' },
        );
        return;
      }
      await wholesaleOrdersAPI.generateInvoice(order.id, {
        unlock_after_email: shouldSendRegenUnlockFlag(auditLogs, 'invoice', orderLockUnlocked),
      });
      const freshOrder = await wholesaleOrdersAPI.get(order.id, { cacheBust: true });
      setOrder(freshOrder);
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => []);
      setAuditLogs(freshAuditLogs);
      setEditingInvoiceDate(false);
      enqueueSnackbar('Invoice date updated', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e?.response?.data?.error || 'Failed to update invoice date', { variant: 'error' });
    } finally {
      setSavingInvoiceDate(false);
    }
  };

  const saveInvoiceSentAt = async () => {
    if (!order) return;
    const raw = invoiceSentDraft.trim();
    if (raw && raw.length < 10) return;
    try {
      setSavingInvoiceSentAt(true);
      const updated = await wholesaleOrdersAPI.setInvoiceSentAt(order.id, {
        invoice_sent_at: raw ? raw.substring(0, 10) : '',
      });
      setOrder(updated);
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => []);
      setAuditLogs(freshAuditLogs);
      setEditingInvoiceSentAt(false);
      enqueueSnackbar(t('wholesaleOrderDetail:invoiceSentDateSaved'), { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e?.response?.data?.error || t('wholesaleOrderDetail:invoiceSentDateSaveError'), { variant: 'error' });
    } finally {
      setSavingInvoiceSentAt(false);
    }
  };

  const saveItemPrice = async (itemId: number) => {
    if (!order) return;
    const price = parseFloat(editingItemPrice);
    if (isNaN(price) || price < 0) return;
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { items: [{ id: itemId, unit_price: price }] });
      setOrder(updated);
      setEditingPriceItemId(null);
      enqueueSnackbar('Unit price updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update unit price', { variant: 'error' });
    }
  };

  const saveItemDiscount = async (itemId: number) => {
    if (!order) return;
    const disc = parseFloat(editingItemDiscount);
    if (isNaN(disc) || disc < 0) return;
    try {
      const updated = await wholesaleOrdersAPI.update(order.id, { items: [{ id: itemId, line_discount_amount: disc }] });
      setOrder(updated);
      setEditingDiscountItemId(null);
      enqueueSnackbar('Line discount updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update line discount', { variant: 'error' });
    }
  };

  const toggleItemSelected = (itemId: number) => {
    setSelectedItemIds((prev) => {
      const next = new Set(prev);
      if (next.has(itemId)) next.delete(itemId);
      else next.add(itemId);
      return next;
    });
  };

  const performAssignment = async () => {
    if (!order?.items?.length || assignToStoreId === '') return;
    const selected = Array.from(selectedItemIds);
    const store = stores.find((s) => s.id === assignToStoreId);
    const storeName = store?.name ?? `Store #${assignToStoreId}`;
    try {
      setActioning(true);
      const assignments = selected.map((id) => {
        const it = order.items!.find((item) => item.id === id)!;
        const pending = pendingQtyForItem(it);
        const qtyDraft = assignmentQtyByItemId[id]?.trim();
        const quantity = qtyDraft
          ? Math.min(Math.max(0, parseFloat(qtyDraft) || 0), pending)
          : pending;
        const boxesDraft = assignmentBoxesByItemId[id]?.trim();
        const case_qty = boxesDraft ? Math.max(0, parseFloat(boxesDraft) || 0) : undefined;
        return {
          wholesale_order_item_id: id,
          store_id: assignToStoreId as number,
          quantity,
          ...(case_qty !== undefined ? { case_qty } : {}),
        };
      });
      if (usesStagedAssignment) {
        const newStaged = [...stagedManualAssignments, ...assignments];
        setStagedManualAssignments(newStaged);
        setSelectedItemIds(new Set());
        setAssignmentQtyByItemId({});
        setAssignmentBoxesByItemId({});
        setAssignConfirmOpen(false);
        setAllocationConfirmed(false);
        enqueueSnackbar(
          t('wholesaleOrderDetail:manualEndorseStagedAssign', {
            count: selected.length,
            store: storeName,
          }),
          { variant: 'success' },
        );
        return;
      }
      const updated = await wholesaleOrdersAPI.assignStores(order.id, assignments);
      setOrder(updated);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setSelectedItemIds(new Set());
      setAssignmentQtyByItemId({});
      setAllocationConfirmed(false);
      enqueueSnackbar(
        allOrderLinesFullyAssigned(updated)
          ? t('wholesaleOrderDetail:assignedLinesToStore', { count: selected.length, store: storeName })
          : t('wholesaleOrderDetail:assignedLinesToStore', { count: selected.length, store: storeName }),
        { variant: 'success' },
      );
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to assign', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleAssignByDefaults = async () => {
    if (!order) return;
    try {
      setActioning(true);
      if (usesStagedAssignment) {
        const preview = await wholesaleOrdersAPI.getEndorseAllocationPreview(order.id);
        const staged = preview.assignments.map((a) => ({
          wholesale_order_item_id: a.wholesale_order_item_id,
          store_id: a.store_id,
          quantity: a.quantity,
        }));
        setStagedManualAssignments(staged);
        setSelectedItemIds(new Set());
        setAllocationConfirmed(false);
        enqueueSnackbar(t('wholesaleOrderDetail:manualEndorseDefaultsStaged'), { variant: 'success' });
        return;
      }
      const updated = await wholesaleOrdersAPI.assignByDefaults(order.id);
      setOrder(updated);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setSelectedItemIds(new Set());
      setAllocationConfirmed(false);
      enqueueSnackbar(t('wholesaleOrderDetail:assignByDefaultsDone'), { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('wholesaleOrderDetail:assignByDefaultsFailed'), { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleUnassignAssignment = async (
    itemId: number,
    storeId: number,
    quantity: number,
    staged: boolean,
  ) => {
    if (!order) return;
    if (staged && usesStagedAssignment) {
      setStagedManualAssignments((prev) => removeStagedAssignmentQty(prev, itemId, storeId, quantity));
      setAllocationConfirmed(false);
      enqueueSnackbar(t('wholesaleOrderDetail:assignmentRemoved'), { variant: 'info' });
      return;
    }
    try {
      setActioning(true);
      const updated = await wholesaleOrdersAPI.unassignStores(order.id, [
        { wholesale_order_item_id: itemId, store_id: storeId, quantity },
      ]);
      setOrder(updated);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setShowAssignment(true);
      setAllocationConfirmed(false);
      enqueueSnackbar(t('wholesaleOrderDetail:assignmentRemoved'), { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('wholesaleOrderDetail:unassignFailed'), { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const assignItemToStoreDirect = async (itemId: number, storeId: number, quantity: number) => {
    if (!order) return;
    if (!storeAllowsAssignmentTarget(order, storeId)) {
      enqueueSnackbar(t('wholesaleOrderDetail:assignBlockedCompletedShipment'), { variant: 'warning' });
      return;
    }
    const item = order.items?.find((it) => it.id === itemId);
    if (!item) return;
    const storeName = stores.find((s) => s.id === storeId)?.name ?? `Store #${storeId}`;
    const totalBoxes = orderItemExpectedBoxes(item);
    const case_qty =
      totalBoxes > 0 && item.quantity > 0
        ? Math.round(((totalBoxes * quantity) / item.quantity) * 1000) / 1000
        : undefined;
    const assignment = {
      wholesale_order_item_id: itemId,
      store_id: storeId,
      quantity,
      ...(case_qty !== undefined && case_qty > 0 ? { case_qty } : {}),
    };
    try {
      setActioning(true);
      if (usesStagedAssignment) {
        setStagedManualAssignments((prev) => addStagedAssignment(prev, assignment));
        setAllocationConfirmed(false);
        enqueueSnackbar(
          t('wholesaleOrderDetail:manualEndorseStagedAssign', { count: 1, store: storeName }),
          { variant: 'success' },
        );
        return;
      }
      const updated = await wholesaleOrdersAPI.assignStores(order.id, [assignment]);
      setOrder(updated);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setAllocationConfirmed(false);
      enqueueSnackbar(
        t('wholesaleOrderDetail:assignedLinesToStore', { count: 1, store: storeName }),
        { variant: 'success' },
      );
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to assign', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const moveAssignmentItem = async (
    itemId: number,
    fromStoreId: number,
    toStoreId: number,
    quantity: number,
    staged: boolean,
  ) => {
    if (!order) return;
    if (!storeAllowsAssignmentTarget(order, toStoreId)) {
      enqueueSnackbar(t('wholesaleOrderDetail:assignBlockedCompletedShipment'), { variant: 'warning' });
      return;
    }
    const storeName = stores.find((s) => s.id === toStoreId)?.name ?? `Store #${toStoreId}`;
    const item = order.items?.find((it) => it.id === itemId);
    if (!item) return;
    const totalBoxes = orderItemExpectedBoxes(item);
    const case_qty =
      totalBoxes > 0 && item.quantity > 0
        ? Math.round(((totalBoxes * quantity) / item.quantity) * 1000) / 1000
        : undefined;
    if (staged && usesStagedAssignment) {
      setStagedManualAssignments((prev) =>
        addStagedAssignment(removeStagedAssignmentQty(prev, itemId, fromStoreId, quantity), {
          wholesale_order_item_id: itemId,
          store_id: toStoreId,
          quantity,
          ...(case_qty !== undefined && case_qty > 0 ? { case_qty } : {}),
        }),
      );
      setAllocationConfirmed(false);
      enqueueSnackbar(
        t('wholesaleOrderDetail:assignedLinesToStore', { count: 1, store: storeName }),
        { variant: 'success' },
      );
      return;
    }
    try {
      setActioning(true);
      let updated = await wholesaleOrdersAPI.unassignStores(order.id, [
        { wholesale_order_item_id: itemId, store_id: fromStoreId, quantity },
      ]);
      updated = await wholesaleOrdersAPI.assignStores(updated.id, [
        {
          wholesale_order_item_id: itemId,
          store_id: toStoreId,
          quantity,
          ...(case_qty !== undefined && case_qty > 0 ? { case_qty } : {}),
        },
      ]);
      setOrder(updated);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setAllocationConfirmed(false);
      enqueueSnackbar(
        t('wholesaleOrderDetail:assignedLinesToStore', { count: 1, store: storeName }),
        { variant: 'success' },
      );
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to move assignment', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleConfirmAllocation = async () => {
    if (!order) return;
    if (usesStagedAssignment) {
      if (!allOrderLinesFullyStaged(order, stagedManualAssignments)) {
        enqueueSnackbar(t('wholesaleOrderDetail:assignAllBeforeConfirm'), { variant: 'warning' });
        return;
      }
      await finalizeStagedAllocation(stagedManualAssignments);
      return;
    }
    if (!allOrderLinesFullyAssigned(order)) {
      enqueueSnackbar(t('wholesaleOrderDetail:assignAllBeforeConfirm'), { variant: 'warning' });
      return;
    }
    setAllocationConfirmed(true);
    setShowAssignment(false);
    enqueueSnackbar(t('wholesaleOrderDetail:allocationConfirmedSuccess'), { variant: 'success' });
    scrollToOrderConfirmEmailSection();
  };

  const handleAssignToStore = async () => {
    if (!order?.items?.length || assignToStoreId === '') return;
    const selected = Array.from(selectedItemIds);
    if (selected.length === 0) {
      enqueueSnackbar(t('wholesaleOrderDetail:selectLinesToAssign'), { variant: 'warning' });
      return;
    }
    try {
      setActioning(true);
      const storeStock =
        assignStoreStock.length > 0
          ? assignStoreStock
          : await stockAPI.getStoreStock(assignToStoreId as number);
      const stockByProduct = new Map(storeStock.map((s) => [s.product_id, s]));
      const selectedItems = order.items.filter((it) => selected.includes(it.id));
      const qtyPrefill: Record<number, string> = {};
      selectedItems.forEach((it) => {
        const pending = pendingQtyForItem(it);
        if (pending > 0) qtyPrefill[it.id] = String(pending);
      });
      setAssignmentQtyByItemId((prev) => ({ ...prev, ...qtyPrefill }));
      const warnings: Record<number, { reason: string; detail?: string }> = {};
      selectedItems.forEach((it) => {
        const assignQtyRaw = qtyPrefill[it.id]?.trim();
        const pending = pendingQtyForItem(it);
        const assignQty = assignQtyRaw
          ? Math.min(Math.max(0, parseFloat(assignQtyRaw) || 0), pending)
          : pending;
        const stock = stockByProduct.get(it.product_id);
        if (!stock) {
          warnings[it.id] = {
            reason: t('wholesaleOrderDetail:assignWarningNoProduct'),
            detail: '—',
          };
          return;
        }
        const stockBefore = stockLevelValue(stock, it.product);
        const stockAfter = stockBefore - assignQty;
        if (stockBefore + 0.0001 < assignQty) {
          warnings[it.id] = {
            reason: t('wholesaleOrderDetail:assignWarningNotEnoughStock'),
            detail: `${formatAssignmentQty(stockBefore)} → ${formatAssignmentQty(stockAfter)}`,
          };
        } else if (stockAfter + 0.0001 < stock.low_stock_threshold) {
          warnings[it.id] = {
            reason: t('wholesaleOrderDetail:assignWarningLowRemaining'),
            detail: `${formatAssignmentQty(stockBefore)} → ${formatAssignmentQty(stockAfter)}`,
          };
        }
      });
      setAssignWarningByItemId(warnings);
      setAssignConfirmOpen(true);
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to check stock', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const closeEmailDialog = () => {
    if (emailSending) return;
    setEmailDialogOpen(false);
    setEmailToInput('');
    setEmailCcInput('');
    setEmailBccInput('');
    setEmailShipmentIds(null);
    setIsShipmentDocumentsEmail(false);
    setEmailChipSelection({ field: null, indices: [] });
  };

  const handleEmailDialogSkip = () => {
    if (emailKind) {
      setSkippedEmailPrompts((prev) => (prev.includes(emailKind) ? prev : [...prev, emailKind]));
    }
    closeEmailDialog();
  };

  const openSkipEmailDialog = (kind: WholesaleOrderEmailType) => {
    setSkipEmailKind(kind);
    setSkipEmailRemark('');
    setSkipEmailDialogOpen(true);
  };

  const handleConfirmSkipEmail = async () => {
    if (!order || !skipEmailKind) return;
    const remark = skipEmailRemark.trim();
    if (!remark) {
      enqueueSnackbar(t('wholesaleOrderDetail:emailSkipRemarkRequired'), { variant: 'warning' });
      return;
    }
    const snackKeys: Record<WholesaleOrderEmailType, string> = {
      order_confirm: 'wholesaleOrderDetail:orderConfirmEmailSkipped',
      shipments_delivered: 'wholesaleOrderDetail:shipmentsDeliveredEmailSkipped',
      invoice: 'wholesaleOrderDetail:invoiceEmailSkipped',
    };
    const errorKeys: Record<WholesaleOrderEmailType, string> = {
      order_confirm: 'wholesaleOrderDetail:skipOrderConfirmEmailFailed',
      shipments_delivered: 'wholesaleOrderDetail:skipShipmentsDeliveredEmailFailed',
      invoice: 'wholesaleOrderDetail:skipInvoiceEmailFailed',
    };
    try {
      setActioning(true);
      await wholesaleOrdersAPI.skipOrderEmail(order.id, { email_type: skipEmailKind, remark });
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => auditLogs);
      setAuditLogs(freshAuditLogs);
      setSkipEmailDialogOpen(false);
      setSkipEmailKind(null);
      setSkipEmailRemark('');
      enqueueSnackbar(t(snackKeys[skipEmailKind]), { variant: 'info' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t(errorKeys[skipEmailKind]), { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleSkipOrderConfirmEmail = () => openSkipEmailDialog('order_confirm');
  const handleSkipShipmentsDeliveredEmail = () => openSkipEmailDialog('shipments_delivered');
  const handleSkipInvoiceEmail = () => openSkipEmailDialog('invoice');

  const scrollToOrderConfirmEmailSection = () => {
    window.setTimeout(() => {
      orderConfirmEmailSectionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 100);
  };

  const handleEmailDialogLater = () => {
    closeEmailDialog();
  };

  const openEmailDialog = (options?: {
    kind?: WholesaleOrderEmailType;
    shipmentIds?: number[];
    to?: string;
    cc?: string;
    bcc?: string;
    subject?: string;
    message?: string;
    attachments?: Record<string, boolean>;
    resendSummary?: WholesaleEmailResendSummary | null;
  }) => {
    if (!order) return;
    const parseEmailInput = (raw?: string): string[] => parseEmailListFromRaw(raw);
    const kind = options?.kind ?? null;
    const shipmentIds = options?.shipmentIds?.length ? [...options.shipmentIds] : null;
    setEmailKind(kind);
    setEmailShipmentIds(shipmentIds);
    setIsShipmentDocumentsEmail(!!shipmentIds?.length);
    const structuredEmail = kind != null;
    const initialLangs: EmailContentLanguage[] = structuredEmail
      ? ['en']
      : [normalizeEmailContentLanguage(i18n.language)];
    setEmailTo(parseEmailInput(options?.to ?? order.wholesale_client?.email?.trim() ?? ''));
    setEmailCc(
      options?.cc != null && options.cc !== ''
        ? parseEmailInput(options.cc)
        : wholesaleOrderDefaultEmailCcList(companySettings),
    );
    setEmailBcc(parseEmailInput(options?.bcc ?? ''));
    setEmailContentLangs(initialLangs);
    const attachmentKindsFromOptions = Object.entries(options?.attachments ?? {})
      .filter(([, checked]) => checked)
      .map(([key]) => key as ShipmentDocumentAttachmentKind);
    const subjectToSet =
      options?.subject ??
      (shipmentIds?.length
        ? buildShipmentDocumentsEmailSubjectEnglish(
            order,
            shipmentIds,
            attachmentKindsFromOptions.length > 0
              ? attachmentKindsFromOptions
              : ['delivery_note', 'signed_delivery_note'],
            companySettings?.wholesale_order_email_subject_template,
          )
        : kind
          ? buildWholesaleOrderEmailSubjectEnglish(
              kind,
              order,
              companySettings?.wholesale_order_email_subject_template,
            )
          : buildWholesaleOrderEmailSubjectEnglish(
              'order_confirm',
              order,
              companySettings?.wholesale_order_email_subject_template,
            ));
    setEmailSubject(subjectToSet);
    setEmailSubjectLocked(!!options?.subject);
    setEmailMessage(
      options?.message ??
        (shipmentIds?.length
          ? buildShipmentDocumentsEmailMessageEnglish(order, companySettings?.email)
          : kind
            ? buildWholesaleOrderEmailMessageEnglish(kind, order, companySettings?.email)
            : buildWholesaleOrderEmailMessageEnglish('order_confirm', order, companySettings?.email)),
    );
    const defaultAttachments: Record<string, boolean> = {};
    if (kind) {
      for (const attachmentKey of WHOLESALE_ORDER_EMAIL_REQUIRED_ATTACHMENTS[kind]) {
        defaultAttachments[attachmentKey] = true;
      }
      if (kind === 'order_confirm' && orderHasPoAttachments(order)) {
        defaultAttachments.po_attachment = true;
      }
    }
    setEmailAttachments(options?.attachments ?? defaultAttachments);
    setEmailResendSummary(options?.resendSummary ?? null);
    setEmailToInput('');
    setEmailDialogOpen(true);
  };

  const openEmailForKind = (kind: WholesaleOrderEmailType) => {
    if (!order) return;
    const existingAudit = getWholesaleOrderEmailAudits(auditLogs)[kind];
    if (existingAudit) {
      const base = parseWholesaleOrderEmailAuditBase(existingAudit.changes);
      const toFromList =
        Array.isArray(base.to) && base.to.length > 0 ? (base.to as string[]).join(', ') : String(base.recipient ?? '').trim();
      const ccFromList =
        Array.isArray(base.cc_list) && base.cc_list.length > 0
          ? (base.cc_list as string[]).join(', ')
          : String(base.cc ?? '').trim();
      const bccFromList =
        Array.isArray(base.bcc_list) && base.bcc_list.length > 0
          ? (base.bcc_list as string[]).join(', ')
          : String(base.bcc ?? '').trim();
      const attachmentKinds = Array.isArray(base.attachment_kinds)
        ? (base.attachment_kinds as string[])
        : WHOLESALE_ORDER_EMAIL_ATTACHMENT_KINDS[kind];
      const attachments: Record<string, boolean> = {};
      attachmentKinds.forEach((attachmentKey) => {
        if (typeof attachmentKey === 'string' && attachmentKey.trim()) attachments[attachmentKey] = true;
      });
      openEmailDialog({
        kind,
        to: toFromList,
        cc: ccFromList,
        bcc: bccFromList,
        subject: typeof base.subject === 'string' ? base.subject : undefined,
        message: typeof base.message === 'string' ? base.message : undefined,
        attachments,
        resendSummary: buildWholesaleEmailResendSummary(base, order, t, existingAudit.created_at, kind),
      });
      return;
    }
    openEmailDialog({ kind });
  };

  const showEmailPromptIfNeeded = (kind: WholesaleOrderEmailType, targetOrder: WholesaleOrder, logs: AuditLog[]) => {
    if (skippedEmailPrompts.includes(kind)) return;
    const existingAudit = getWholesaleOrderEmailAudits(logs)[kind];
    if (existingAudit) {
      const base = parseWholesaleOrderEmailAuditBase(existingAudit.changes);
      if (isWholesaleOrderEmailSkippedAudit(base) || isWholesaleOrderEmailSentAudit(base)) return;
    }
    if (kind === 'shipments_delivered' && !allShipmentsHaveSignedProof(targetOrder)) return;
    openEmailForKind(kind);
  };

  const promptOrderConfirmEmailIfNeeded = (targetOrder: WholesaleOrder, logs: AuditLog[]) => {
    showEmailPromptIfNeeded('order_confirm', targetOrder, logs);
  };

  const promptShipmentsDeliveredEmailIfNeeded = (targetOrder: WholesaleOrder, logs: AuditLog[]) => {
    showEmailPromptIfNeeded('shipments_delivered', targetOrder, logs);
  };

  const toggleShipmentEmailSelection = (shipmentId: number) => {
    setSelectedShipmentIdsForEmail((prev) => {
      const next = new Set(prev);
      if (next.has(shipmentId)) next.delete(shipmentId);
      else next.add(shipmentId);
      return next;
    });
  };

  const allShipmentsSelectedForEmail =
    !!order?.shipments?.length &&
    order.shipments.every((s) => selectedShipmentIdsForEmail.has(s.id));
  const someShipmentsSelectedForEmail =
    !!order?.shipments?.some((s) => selectedShipmentIdsForEmail.has(s.id)) && !allShipmentsSelectedForEmail;

  const toggleAllShipmentsEmailSelection = () => {
    if (!order?.shipments?.length) return;
    if (allShipmentsSelectedForEmail) {
      setSelectedShipmentIdsForEmail(new Set());
      return;
    }
    setSelectedShipmentIdsForEmail(new Set(order.shipments.map((s) => s.id)));
  };

  const openShipmentDocumentsEmail = () => {
    if (!order) return;
    const ids = Array.from(selectedShipmentIdsForEmail).sort((a, b) => a - b);
    if (ids.length === 0) {
      enqueueSnackbar(t('wholesaleOrderDetail:selectShipmentsForEmail'), { variant: 'warning' });
      return;
    }
    const hasDocuments = ids.some((id) => {
      const sh = order.shipments?.find((s) => s.id === id);
      return (
        !!sh?.delivery_note_pdf_url?.trim() || !!sh?.signed_delivery_note_pdf_url?.trim()
      );
    });
    if (!hasDocuments) {
      enqueueSnackbar(t('wholesaleOrderDetail:noShipmentDocumentsForSelected'), { variant: 'warning' });
      return;
    }
    openEmailDialog({ shipmentIds: ids, attachments: {} });
  };

  const copyEmailChipSelection = async (field: EmailChipField, indices: number[], values: string[]) => {
    const text = [...indices]
      .sort((a, b) => a - b)
      .map((i) => values[i])
      .filter(Boolean)
      .join(', ');
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      enqueueSnackbar(t('wholesaleOrderDetail:emailCopyRecipientsFailed'), { variant: 'error' });
    }
  };

  const cutEmailChipSelection = async (field: EmailChipField, indices: number[], values: string[]) => {
    const text = [...indices]
      .sort((a, b) => a - b)
      .map((i) => values[i])
      .filter(Boolean)
      .join(', ');
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      const selected = new Set(indices);
      const remaining = values.filter((_, i) => !selected.has(i));
      if (field === 'to') setEmailTo(remaining);
      else if (field === 'cc') setEmailCc(remaining);
      else setEmailBcc(remaining);
      setEmailChipSelection({ field: null, indices: [] });
    } catch {
      enqueueSnackbar(t('wholesaleOrderDetail:emailCopyRecipientsFailed'), { variant: 'error' });
    }
  };

  const emailValuesForField = (field: EmailChipField) =>
    field === 'to' ? emailTo : field === 'cc' ? emailCc : emailBcc;

  const handleEmailDialogKeyDown = (e: KeyboardEvent) => {
    const mod = e.metaKey || e.ctrlKey;
    if (!mod) return;

    const target = e.target as HTMLElement;
    const fieldAttr = target.closest('[data-email-chip-field]')?.getAttribute('data-email-chip-field');
    const field =
      fieldAttr === 'to' || fieldAttr === 'cc' || fieldAttr === 'bcc' ? fieldAttr : null;

    if (e.key === 'a') {
      if (!field) return;
      const values = emailValuesForField(field);
      if (values.length === 0) return;
      e.preventDefault();
      setEmailChipSelection({ field, indices: values.map((_, i) => i) });
      return;
    }

    if (e.key !== 'c' && e.key !== 'x') return;
    if (emailChipSelection.indices.length === 0 || !emailChipSelection.field) return;
    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && sel.toString().trim()) {
      return;
    }
    e.preventDefault();
    const values = emailValuesForField(emailChipSelection.field);
    if (e.key === 'c') {
      void copyEmailChipSelection(emailChipSelection.field, emailChipSelection.indices, values);
    } else {
      void cutEmailChipSelection(emailChipSelection.field, emailChipSelection.indices, values);
    }
  };

  const renderEmailChipInput = (
    fieldId: EmailChipField,
    label: string,
    values: string[],
    setValues: (values: string[]) => void,
    inputValue: string,
    onInputValueChange: (value: string) => void,
    helperText?: string,
    placeholder?: string,
    autoFocus = false,
  ) => {
    const chipSelected =
      emailChipSelection.field === fieldId ? new Set(emailChipSelection.indices) : new Set<number>();

    const selectChip = (index: number, additive: boolean) => {
      setEmailChipSelection((prev) => {
        if (!additive || prev.field !== fieldId) {
          return { field: fieldId, indices: [index] };
        }
        const next = new Set(prev.indices);
        if (next.has(index)) next.delete(index);
        else next.add(index);
        return { field: fieldId, indices: [...next].sort((a, b) => a - b) };
      });
    };

    const clearChipSelection = () => {
      setEmailChipSelection((prev) =>
        prev.field === fieldId ? { field: null, indices: [] } : prev,
      );
    };

    const commitPendingInput = (raw: string) => {
      const pending = raw.trim();
      if (!pending) return;
      setValues(addEmailsToChipList(values, parseEmailListFromRaw(pending)));
      onInputValueChange('');
      clearChipSelection();
    };

    const handleRecipientPaste = (e: ClipboardEvent<HTMLInputElement>) => {
      const text = e.clipboardData.getData('text/plain') || e.clipboardData.getData('text');
      if (!text.trim()) return;
      const parsed = parseEmailListFromRaw(text);
      if (parsed.length === 0) return;
      e.preventDefault();
      e.stopPropagation();
      const pending = inputValue.trim();
      const merged = pending
        ? addEmailsToChipList(values, [...parseEmailListFromRaw(pending), ...parsed])
        : addEmailsToChipList(values, parsed);
      setValues(merged);
      onInputValueChange('');
      clearChipSelection();
    };

    return (
      <Box
        data-email-chip-field={fieldId}
        sx={{ width: '100%' }}
        onPasteCapture={(e) => {
          const target = e.target as HTMLElement;
          if (!target.closest('input')) return;
          if (e.defaultPrevented) return;
          handleRecipientPaste(e as unknown as ClipboardEvent<HTMLInputElement>);
        }}
      >
      <Autocomplete
        multiple
        freeSolo
        options={[]}
        value={values}
        inputValue={inputValue}
        onInputChange={(_: unknown, value: string, reason: string) => {
          if (reason === 'reset') return;
          onInputValueChange(value);
          clearChipSelection();
        }}
        onChange={(_, next) => {
          setValues(applyEmailChipList(next as string[]));
          onInputValueChange('');
          clearChipSelection();
        }}
        renderTags={(tagValue: readonly string[], getTagProps) =>
          tagValue.map((option: string, index: number) => {
            const { key, onDelete, ...tagProps } = getTagProps({ index });
            const valid = isValidEmail(option);
            const selected = chipSelected.has(index);
            return (
              <Chip
                key={key}
                label={option}
                size="small"
                {...tagProps}
                onDelete={onDelete}
                color={valid ? 'default' : 'error'}
                onMouseDown={(e) => {
                  e.preventDefault();
                  selectChip(index, e.metaKey || e.ctrlKey);
                }}
                sx={{
                  cursor: 'default',
                  userSelect: 'text',
                  '& .MuiChip-label': { userSelect: 'text' },
                  ...(selected
                    ? {
                        bgcolor: 'primary.main',
                        color: 'primary.contrastText',
                        '& .MuiChip-deleteIcon': {
                          color: alpha(theme.palette.primary.contrastText, 0.7),
                          '&:hover': { color: 'primary.contrastText' },
                        },
                      }
                    : {}),
                }}
              />
            );
          })
        }
        renderInput={(params) => (
          <TextField
            {...params}
            label={label}
            size="small"
            placeholder={placeholder}
            helperText={helperText}
            autoFocus={autoFocus}
            error={values.some((v) => !isValidEmail(v))}
            onFocus={() => setEmailChipSelection({ field: null, indices: [] })}
            onMouseDown={(e) => {
              if ((e.target as HTMLElement).closest('.MuiChip-root')) return;
              if (chipSelected.size > 0) clearChipSelection();
            }}
            onKeyDown={(e) => {
              params.inputProps?.onKeyDown?.(e as KeyboardEvent<HTMLInputElement>);
              const pending = inputValue.trim();
              if (e.key === 'Enter' && pending) {
                e.preventDefault();
                e.stopPropagation();
                commitPendingInput(pending);
                return;
              }
              if (e.key === 'Backspace' && chipSelected.size > 0 && !pending) {
                e.preventDefault();
                const remaining = values.filter((_, i) => !chipSelected.has(i));
                setValues(remaining);
                clearChipSelection();
              }
            }}
            inputProps={{
              ...params.inputProps,
              style: { ...(params.inputProps?.style ?? {}), userSelect: 'text' },
              onPaste: (e) => {
                handleRecipientPaste(e as ClipboardEvent<HTMLInputElement>);
              },
            }}
          />
        )}
      />
      </Box>
    );
  };

  const sendEmailOrder = async () => {
    if (!order) return;
    const toList = resolvedEmailToList.filter((v) => isValidEmail(v));
    if (toList.length === 0) {
      enqueueSnackbar(t('wholesaleOrderDetail:emailRecipientRequired'), { variant: 'warning' });
      return;
    }
    if (invalidEmailChips.length > 0 || emailToInputInvalid) {
      enqueueSnackbar(`Invalid email: ${invalidEmailChips[0] ?? emailToInput.trim()}`, { variant: 'warning' });
      return;
    }
    const selectedAttachments = Object.entries(emailAttachments)
      .filter(([, checked]) => checked)
      .map(([key]) => key);
    if (selectedAttachments.length === 0) {
      enqueueSnackbar(t('wholesaleOrderDetail:emailNoAttachmentsSelected'), { variant: 'warning' });
      return;
    }
    try {
      setEmailSending(true);
      const ccList = dedupeEmailList(emailCc);
      const bccList = dedupeEmailList(emailBcc);
      const onlySignedDn =
        selectedAttachments.length === 1 && selectedAttachments[0] === 'signed_delivery_note';
      const shipmentIdsForSend = isShipmentDocumentsEmail
        ? Array.from(selectedShipmentIdsForEmail).sort((a, b) => a - b)
        : emailKind === 'shipments_delivered'
          ? (order.shipments ?? []).map((s) => s.id).sort((a, b) => a - b)
          : undefined;
      if (isShipmentDocumentsEmail && !shipmentIdsForSend?.length) {
        enqueueSnackbar(t('wholesaleOrderDetail:selectShipmentsForEmail'), { variant: 'warning' });
        return;
      }
      const result = await wholesaleOrdersAPI.emailOrder(order.id, {
        recipient: toList.join(', '),
        to: toList.length > 0 ? toList : undefined,
        cc: ccList.join(', ') || undefined,
        cc_list: ccList.length > 0 ? ccList : undefined,
        bcc: bccList.join(', ') || undefined,
        bcc_list: bccList.length > 0 ? bccList : undefined,
        subject: emailSubject.trim() || undefined,
        message: emailMessage.trim() || undefined,
        attachments: selectedAttachments,
        email_type: emailKind ?? undefined,
        shipment_ids: shipmentIdsForSend,
        signed_delivery_shipment_id:
          shipmentIdsForSend?.length === 1 && onlySignedDn ? shipmentIdsForSend[0] : undefined,
      });
      if (result.order) setOrder(result.order);
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => auditLogs);
      setAuditLogs(freshAuditLogs);
      enqueueSnackbar(t('wholesaleOrderDetail:emailSentSuccess'), { variant: 'success' });
      if (isShipmentDocumentsEmail) {
        setSelectedShipmentIdsForEmail(new Set());
      }
      closeEmailDialog();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('wholesaleOrderDetail:emailSendError'), { variant: 'error' });
    } finally {
      setEmailSending(false);
    }
  };

  useEffect(() => {
    if (!order || promptOrderConfirmHandled.current) return;
    const state = location.state as { promptOrderConfirmEmail?: boolean } | null;
    if (!state?.promptOrderConfirmEmail) return;
    promptOrderConfirmHandled.current = true;
    navigate(location.pathname, { replace: true, state: {} });
    promptOrderConfirmEmailIfNeeded(order, auditLogs);
  }, [order, auditLogs, location.pathname, location.state, navigate]);

  const handleApprove = async () => {
    if (!order) return;
    try {
      setEndorsePreviewLoading(true);
      const preview = await wholesaleOrdersAPI.getEndorseAllocationPreview(order.id);
      setEndorsePreview(preview);
      setEndorsePreviewOpen(true);
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('wholesaleOrderDetail:endorsePreviewFailed'), { variant: 'error' });
    } finally {
      setEndorsePreviewLoading(false);
    }
  };

  const performEndorseConfirm = async (options?: { autoAssign?: boolean; manualAssign?: boolean }) => {
    if (!order || !endorsePreview) return;
    const manualAssign = options?.manualAssign ?? false;

    if (manualAssign) {
      setStagedManualAssignments([]);
      setShowAssignment(true);
      const pendingIds =
        order.items?.filter((it) => pendingQtyForOrderItem(order, it) > 0.0001).map((it) => it.id) ?? [];
      setSelectedItemIds(new Set(pendingIds));
      if (endorsePreview.primary_store_id) {
        setAssignToStoreId(endorsePreview.primary_store_id);
      }
      setEndorsePreviewOpen(false);
      setEndorsePreview(null);
      enqueueSnackbar(t('wholesaleOrderDetail:assignDragHint'), { variant: 'info' });
      window.setTimeout(() => {
        assignSectionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 150);
      return;
    }

    const autoAssign =
      options?.autoAssign ??
      (endorsePreview.outcome === 'single_store' && endorsePreview.assignments.length > 0);
    try {
      setActioning(true);
      const updated = await wholesaleOrdersAPI.approve(order.id);
      let orderAfterApprove = updated;
      if (autoAssign && endorsePreview.outcome === 'single_store' && endorsePreview.assignments.length > 0) {
        orderAfterApprove = await wholesaleOrdersAPI.assignStores(
          order.id,
          endorsePreview.assignments.map((a) => ({
            wholesale_order_item_id: a.wholesale_order_item_id,
            store_id: a.store_id,
            quantity: a.quantity,
          })),
        );
      }
      setOrder(orderAfterApprove);
      const draft: Record<number, number | ''> = {};
      orderAfterApprove.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setShowAssignment(!allOrderLinesFullyAssigned(orderAfterApprove));
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => auditLogs);
      setAuditLogs(freshAuditLogs);
      enqueueSnackbar(
        allOrderLinesFullyAssigned(orderAfterApprove)
          ? t('wholesaleOrderDetail:assignAndApprovedSuccess')
          : t('wholesaleOrderDetail:endorseSuccess'),
        { variant: 'success' },
      );
      if (allOrderLinesFullyAssigned(orderAfterApprove)) {
        setAllocationConfirmed(true);
        scrollToOrderConfirmEmailSection();
      }
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('wholesaleOrderDetail:endorseFailed'), { variant: 'error' });
    } finally {
      setActioning(false);
      setEndorsePreviewOpen(false);
      setEndorsePreview(null);
    }
  };

  const finalizeStagedAllocation = async (assignments: StagedStoreAssignment[]) => {
    if (!order || !usesStagedAssignment) return;
    if (!allOrderLinesFullyStaged(order, assignments)) {
      enqueueSnackbar(t('wholesaleOrderDetail:assignAllBeforeConfirm'), { variant: 'warning' });
      return;
    }
    try {
      setActioning(true);
      let updated = await wholesaleOrdersAPI.approve(order.id);
      updated = await wholesaleOrdersAPI.assignStores(order.id, assignments);
      setOrder(updated);
      setStagedManualAssignments([]);
      const draft: Record<number, number | ''> = {};
      updated.items?.forEach((it) => { draft[it.id] = it.assigned_store_id ?? ''; });
      setAssignmentDraft(draft);
      setAllocationConfirmed(true);
      setShowAssignment(false);
      setSelectedItemIds(new Set());
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => auditLogs);
      setAuditLogs(freshAuditLogs);
      enqueueSnackbar(t('wholesaleOrderDetail:assignAndApprovedSuccess'), { variant: 'success' });
      scrollToOrderConfirmEmailSection();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || t('wholesaleOrderDetail:endorseFailed'), { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const cancelManualEndorseMode = () => {
    setStagedManualAssignments([]);
    setSelectedItemIds(new Set());
    setAssignToStoreId('');
    setShowAssignment(false);
  };

  const handleReject = async () => {
    if (!order) return;
    try {
      setActioning(true);
      await wholesaleOrdersAPI.reject(order.id, rejectReason);
      enqueueSnackbar('Order rejected', { variant: 'success' });
      navigate('/wholesale-orders');
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to reject', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleResubmit = async () => {
    if (!order) return;
    try {
      setActioning(true);
      const updated = await wholesaleOrdersAPI.resubmit(order.id);
      setOrder(updated);
      enqueueSnackbar('Order resubmitted for approval', { variant: 'success' });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to resubmit', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleDeleteOrder = async () => {
    if (!order) return;
    if (!window.confirm('Delete this order? You can restore only from database backup.')) return;
    try {
      setActioning(true);
      await wholesaleOrdersAPI.archive(order.id);
      enqueueSnackbar('Order deleted', { variant: 'success' });
      navigate('/wholesale-orders', { replace: true });
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to delete order', { variant: 'error' });
    } finally {
      setActioning(false);
    }
  };

  const handleRegenOrderConfirmation = async () => {
    if (!order?.id) return;
    if (isRegenBlockedByEmailLock(auditLogs, 'order_confirmation', orderLockUnlocked)) return;
    setRegenConfirmLoading(true);
    try {
      const updated = await wholesaleOrdersAPI.regenerateOrderConfirmation(order.id, {
        unlock_after_email: shouldSendRegenUnlockFlag(
          auditLogs,
          'order_confirmation',
          orderLockUnlocked,
        ),
      });
      setOrder(updated);
      enqueueSnackbar('Order confirmation regenerated.', { variant: 'success' });
    } catch (e: unknown) {
      enqueueSnackbar(
        (e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Failed to regenerate',
        { variant: 'error' },
      );
    } finally {
      setRegenConfirmLoading(false);
      setDocMenuAnchorEl(null);
    }
  };

  const handleRegenInvoice = async () => {
    if (!order) return;
    if (isRegenBlockedByEmailLock(auditLogs, 'invoice', orderLockUnlocked)) return;
    try {
      setRegenInvoiceLoading(true);
      const updated = await wholesaleOrdersAPI.generateInvoice(order.id, {
        unlock_after_email: shouldSendRegenUnlockFlag(auditLogs, 'invoice', orderLockUnlocked),
      });
      setOrder(updated);
      enqueueSnackbar('Invoice generated.', { variant: 'success' });
    } catch (e: unknown) {
      enqueueSnackbar(
        (e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Failed to generate invoice',
        { variant: 'error' },
      );
    } finally {
      setRegenInvoiceLoading(false);
      setInvoiceMenuAnchorEl(null);
    }
  };

  if (loading || !order) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  // Process steps: Create → Endorse → Assign → Start → Finish → Send invoice email → Complete
  const orderConfirmationDoc = order.documents?.find((d) => d.type === 'order_confirmation');
  const hasOrderConfirmation = !!orderConfirmationDoc;
  const invoiceDoc = order.documents?.find((d) => d.type === 'invoice');
  const hasInvoice = !!invoiceDoc;
  const allShipmentsCompleted =
    (order.shipments?.length ?? 0) > 0 &&
    order.shipments!.every((s) => s.status === 'completed');
  const hasShipments = (order.shipments?.length ?? 0) > 0;
  const allOrderLinesAssigned = allOrderLinesFullyAssigned(order);
  const allLinesAssignedForConfirm = usesStagedAssignment
    ? allOrderLinesFullyStaged(order, stagedManualAssignments)
    : allOrderLinesAssigned;
  const assignmentExpanded =
    showAssignment || !allOrderLinesAssigned || !allocationConfirmed;
  const showAssignmentPanel = canAssign && (assignmentExpanded || (usesStagedAssignment && !allocationConfirmed));
  const allShipmentsStarted =
    hasShipments &&
    (order.shipments?.every((s) => shipmentHasDeliveryNoteStarted(s)) ?? false);
  const completedShipments = order.shipments?.filter((s) => s.status === 'completed') ?? [];
  const latestCompletedShipment = completedShipments.reduce<Shipment | null>((acc, sh) => {
    if (!acc) return sh;
    const accCandidate = acc.delivery_date ?? acc.created_at;
    const shCandidate = sh.delivery_date ?? sh.created_at;
    return new Date(shCandidate).getTime() > new Date(accCandidate).getTime() ? sh : acc;
  }, null);

  const stepEndorsed = order.status !== 'pending_approval' && order.status !== 'rejected';
  const orderFlowPipelineVisible =
    stepEndorsed && order.status !== 'rejected' && order.status !== 'deleted';
  const emailAudits = getWholesaleOrderEmailAudits(auditLogs);
  const orderConfirmAuditChanges = emailAudits.order_confirm
    ? parseWholesaleOrderEmailAuditBase(emailAudits.order_confirm.changes)
    : null;
  const orderConfirmEmailSent = orderConfirmAuditChanges
    ? isWholesaleOrderEmailSentAudit(orderConfirmAuditChanges)
    : false;
  const orderConfirmEmailSkipped = orderConfirmAuditChanges
    ? isWholesaleOrderEmailSkippedAudit(orderConfirmAuditChanges)
    : false;
  const orderConfirmEmailDone = orderConfirmEmailSent || orderConfirmEmailSkipped;
  const orderConfirmSentAtDisplay = wholesaleOrderEmailSentAtDisplay(
    orderConfirmAuditChanges,
    emailAudits.order_confirm,
    orderConfirmEmailSent,
  );
  const orderConfirmSkippedAtDisplay = wholesaleOrderEmailSkippedAtDisplay(
    orderConfirmAuditChanges,
    emailAudits.order_confirm,
    orderConfirmEmailSkipped,
  );
  const orderConfirmRecipient =
    (Array.isArray(orderConfirmAuditChanges?.to) && (orderConfirmAuditChanges.to as string[]).length > 0
      ? (orderConfirmAuditChanges.to as string[]).join(', ')
      : null) ??
    (typeof orderConfirmAuditChanges?.recipient === 'string' && orderConfirmAuditChanges.recipient.trim()
      ? orderConfirmAuditChanges.recipient.trim()
      : null) ??
    order.wholesale_client?.email?.trim() ??
    '';
  const orderConfirmSkippedBy =
    typeof orderConfirmAuditChanges?.initiated_by === 'string' && orderConfirmAuditChanges.initiated_by.trim()
      ? orderConfirmAuditChanges.initiated_by.trim()
      : '';
  const orderConfirmSkipRemark = orderConfirmAuditChanges
    ? wholesaleOrderEmailSkipRemark(orderConfirmAuditChanges)
    : '';

  const renderOrderLockToggle = () => {
    if (!orderHasActiveLocks(auditLogs, order)) return null;
    return (
      <Button
        size="small"
        variant="outlined"
        color={orderLockUnlocked ? 'inherit' : 'warning'}
        startIcon={orderLockUnlocked ? <LockIcon fontSize="small" /> : <LockOpenIcon fontSize="small" />}
        onClick={() => {
          if (orderLockUnlocked) {
            setOrderLockUnlocked(false);
            return;
          }
          if (!confirmUnlockOrder(t)) return;
          setOrderLockUnlocked(true);
        }}
      >
        {orderLockUnlocked ? t('wholesaleOrderDetail:lockRegen') : t('wholesaleOrderDetail:unlockRegen')}
      </Button>
    );
  };
  const showShipmentsSection = orderFlowPipelineVisible && orderConfirmEmailDone && hasShipments;
  const shipmentsDeliveredAuditChanges = emailAudits.shipments_delivered
    ? parseWholesaleOrderEmailAuditBase(emailAudits.shipments_delivered.changes)
    : null;
  const shipmentsDeliveredEmailSent = shipmentsDeliveredAuditChanges
    ? isWholesaleOrderEmailSentAudit(shipmentsDeliveredAuditChanges)
    : false;
  const shipmentsDeliveredEmailSkipped = shipmentsDeliveredAuditChanges
    ? isWholesaleOrderEmailSkippedAudit(shipmentsDeliveredAuditChanges)
    : false;
  const shipmentsDeliveredEmailDone = shipmentsDeliveredEmailSent || shipmentsDeliveredEmailSkipped;
  const shipmentsDeliveredSentAtDisplay = wholesaleOrderEmailSentAtDisplay(
    shipmentsDeliveredAuditChanges,
    emailAudits.shipments_delivered,
    shipmentsDeliveredEmailSent,
  );
  const shipmentsDeliveredSkippedAtDisplay = wholesaleOrderEmailSkippedAtDisplay(
    shipmentsDeliveredAuditChanges,
    emailAudits.shipments_delivered,
    shipmentsDeliveredEmailSkipped,
  );
  const shipmentsDeliveredRecipient =
    (Array.isArray(shipmentsDeliveredAuditChanges?.to) &&
    (shipmentsDeliveredAuditChanges.to as string[]).length > 0
      ? (shipmentsDeliveredAuditChanges.to as string[]).join(', ')
      : null) ??
    (typeof shipmentsDeliveredAuditChanges?.recipient === 'string' &&
    shipmentsDeliveredAuditChanges.recipient.trim()
      ? shipmentsDeliveredAuditChanges.recipient.trim()
      : null) ??
    order.wholesale_client?.email?.trim() ??
    '';
  const shipmentsDeliveredSkippedBy =
    typeof shipmentsDeliveredAuditChanges?.initiated_by === 'string' &&
    shipmentsDeliveredAuditChanges.initiated_by.trim()
      ? shipmentsDeliveredAuditChanges.initiated_by.trim()
      : '';
  const shipmentsDeliveredSkipRemark = shipmentsDeliveredAuditChanges
    ? wholesaleOrderEmailSkipRemark(shipmentsDeliveredAuditChanges)
    : '';
  const canSendOrderConfirmEmail =
    stepEndorsed &&
    orderHasOrderConfirmationDocument(order) &&
    order.status !== 'deleted' &&
    order.status !== 'rejected';
  const canSendShipmentsDeliveredEmail =
    allShipmentsHaveSignedProof(order) && order.status !== 'deleted' && order.status !== 'rejected';
  const canShowInvoiceEmailButton =
    orderHasInvoiceDocument(order) && order.status !== 'deleted' && order.status !== 'rejected';
  const invoiceAuditChanges = emailAudits.invoice
    ? parseWholesaleOrderEmailAuditBase(emailAudits.invoice.changes)
    : null;
  const invoiceEmailSentFromAudit = invoiceAuditChanges
    ? isWholesaleOrderEmailSentAudit(invoiceAuditChanges)
    : false;
  const invoiceRecipient =
    (Array.isArray(invoiceAuditChanges?.to) && (invoiceAuditChanges.to as string[]).length > 0
      ? (invoiceAuditChanges.to as string[]).join(', ')
      : null) ??
    (typeof invoiceAuditChanges?.recipient === 'string' && invoiceAuditChanges.recipient.trim()
      ? invoiceAuditChanges.recipient.trim()
      : null) ??
    order.wholesale_client?.email?.trim() ??
    '';
  const invoiceEmailSkipped = invoiceAuditChanges
    ? isWholesaleOrderEmailSkippedAudit(invoiceAuditChanges)
    : false;
  const invoiceEmailSent = invoiceEmailSentFromAudit;
  const invoiceEmailDone = invoiceEmailSent || invoiceEmailSkipped;
  const invoiceSentAtDisplay = wholesaleOrderEmailSentAtDisplay(
    invoiceAuditChanges,
    emailAudits.invoice,
    invoiceEmailSent,
  );
  const invoiceSkippedAtDisplay = wholesaleOrderEmailSkippedAtDisplay(
    invoiceAuditChanges,
    emailAudits.invoice,
    invoiceEmailSkipped,
  );
  const invoiceSkippedBy =
    typeof invoiceAuditChanges?.initiated_by === 'string' && invoiceAuditChanges.initiated_by.trim()
      ? invoiceAuditChanges.initiated_by.trim()
      : '';
  const invoiceSkipRemark = invoiceAuditChanges ? wholesaleOrderEmailSkipRemark(invoiceAuditChanges) : '';
  const invoiceEmailEnabled = shipmentsDeliveredEmailDone && orderHasInvoiceDocument(order);
  const stepFinishShipment = allShipmentsCompleted;
  const orderCompleted = isWholesaleOrderCompleted(order);
  const showDeliveryCompleteEmailSection =
    showShipmentsSection && allShipmentsCompleted && orderFlowPipelineVisible;
  const deliveryCompleteEmailReady =
    showDeliveryCompleteEmailSection && !shipmentsDeliveredEmailDone;
  const showInvoiceEmailSection =
    shipmentsDeliveredEmailDone &&
    canShowInvoiceEmailButton &&
    orderFlowPipelineVisible;
  const invoiceEmailReady = showInvoiceEmailSection && !invoiceEmailDone;
  const invoiceStepComplete = !canShowInvoiceEmailButton || invoiceEmailDone;
  const showOrderConfirmationEmailSection =
    allocationConfirmed && order.status !== 'rejected' && order.status !== 'deleted';
  const orderConfirmEmailReady = allocationConfirmed && !orderConfirmEmailDone;
  const canChangeAssignment =
    canAssign &&
    allOrderLinesAssigned &&
    allocationConfirmed &&
    orderAllowsAssignmentChange(order, pendingQtyForItem);
  const assignmentCompletedAt =
    auditLogs.find((l) => l.action === 'wholesale_order_complete_assignment')?.created_at ??
    (allOrderLinesAssigned
      ? auditLogs.find((l) => l.action === 'wholesale_order_assign_stores')?.created_at
      : null) ??
    (allOrderLinesAssigned && hasShipments
      ? order.shipments!.reduce<string | null>((earliest, s) => {
          const at = s.created_at;
          if (!at) return earliest;
          return !earliest || at < earliest ? at : earliest;
        }, null)
      : null);
  const stepStartShipment = allShipmentsStarted;
  // UI pending-payment state: all deliveries done, waiting for payment proof.
  const orderPendingPayment =
    order.status === 'approved' && !order.payment_confirmed_at && allShipmentsCompleted;
  const orderUploadBlocked = isOrderUploadBlocked(order, orderLockUnlocked);
  const paymentProofUnlockUpload = shouldSendUploadUnlockFlag(order, orderLockUnlocked);
  const canDeletePaymentProof = !orderCompleted || orderLockUnlocked;
  const poAttachmentsEditable =
    !orderUploadBlocked &&
    order.status !== 'rejected' &&
    order.status !== 'deleted' &&
    (!stepEndorsed || editingPoAttachments);
  const showPoAttachmentsEditButton =
    stepEndorsed &&
    !orderUploadBlocked &&
    order.status !== 'rejected' &&
    order.status !== 'deleted' &&
    !editingPoAttachments;
  // Show when the order is in "pending shipment / start shipment" territory
  // (both `assign_shipment` and `approved` are editable stages), but payment isn't confirmed yet.
  // The button unblocks the UI so it can reach the pending-payment flow.
  const canForceMoveToPendingPayment =
    hasShipments &&
    !order.payment_confirmed_at &&
    order.status !== 'rejected' &&
    // Hide once backend moves the order into "approved (pending payment)".
    order.status !== 'approved';
  const canDeleteOrder =
    order.status !== 'deleted' &&
    !orderCompleted &&
    (user?.role === 'management' || (user as unknown as { role?: string } | null)?.role === 'system_admin');

  const renderShipmentItemsDetail = (s: Shipment) => {
    const items = s.items ?? [];
    if (items.length === 0) {
      return (
        <Typography variant="body2" color="text.secondary">
          —
        </Typography>
      );
    }
    return (
      <Stack spacing={0.5} sx={{ py: 0.25 }}>
        {items.map((si) => {
          const product = si.wholesale_order_item?.product;
          const name = product
            ? productDisplayName(product, lang)
            : `Item #${si.wholesale_order_item_id}`;
          const qty = formatAssignmentQty(effectiveShipmentItemQty(si));
          const boxes =
            si.case_qty != null && si.case_qty > 0 ? formatAssignmentQty(si.case_qty) : null;
          return (
            <Typography key={si.id} variant="body2" sx={{ fontSize: '0.8125rem', lineHeight: 1.4 }}>
              {name} × {qty}
              {boxes ? ` · ${boxes} ${t('wholesaleOrderDetail:box')}` : ''}
            </Typography>
          );
        })}
      </Stack>
    );
  };

  const toggleShipmentExpanded = (shipmentId: number) => {
    setExpandedShipmentIds((prev) => {
      const next = new Set(prev);
      if (next.has(shipmentId)) next.delete(shipmentId);
      else next.add(shipmentId);
      return next;
    });
  };

  const renderShipmentItemsSummary = (s: Shipment) => {
    const expanded = expandedShipmentIds.has(s.id);
    const { productCount, totalQty } = shipmentAssignedSummary(s);
    if (productCount === 0) {
      return (
        <Typography variant="body2" color="text.secondary">
          {t('wholesaleOrderDetail:assignedProductsSummaryEmpty', 'No products assigned')}
        </Typography>
      );
    }
    return (
      <Box
        sx={{ display: 'flex', alignItems: 'center', gap: 0.25, cursor: 'pointer', userSelect: 'none' }}
        onClick={() => toggleShipmentExpanded(s.id)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            toggleShipmentExpanded(s.id);
          }
        }}
      >
        <IconButton
          size="small"
          aria-label={expanded ? t('wholesaleOrderDetail:collapseItems') : t('wholesaleOrderDetail:expandItems')}
          sx={{ ml: -0.5, pointerEvents: 'none' }}
        >
          {expanded ? <ArrowDropUpIcon fontSize="small" /> : <ArrowDropDownIcon fontSize="small" />}
        </IconButton>
        <Typography variant="body2">
          {t('wholesaleOrderDetail:assignedProductsSummary', {
            count: productCount,
            total: formatAssignmentQty(totalQty),
            defaultValue: '{{count}} products · {{total}} units',
          })}
        </Typography>
      </Box>
    );
  };

  const uploadDeliveryProofForShipment = async (s: Shipment, file: File) => {
    if (!order) return;
    setUploadSignedNoteShipment(s);
    setUploadSignedNoteSubmitting(true);
    try {
      if (order.status === 'assign_shipment') {
        const baseOrder = await wholesaleOrdersAPI.completeAssignment(order.id);
        setOrder(baseOrder);
      }
      await shipmentsAPI.uploadSignedDeliveryNote(s.id, file, {
        unlock_after_completion: shouldSendUploadUnlockFlag(order, orderLockUnlocked),
      });
      const freshOrder = await wholesaleOrdersAPI.get(order.id);
      setOrder(freshOrder);
      const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => auditLogs);
      setAuditLogs(freshAuditLogs);
      enqueueSnackbar(t('wholesaleOrderDetail:uploadSignedDeliveryNoteSuccess'), {
        variant: 'success',
      });
      promptShipmentsDeliveredEmailIfNeeded(freshOrder, freshAuditLogs);
    } catch (err: any) {
      enqueueSnackbar(
        err.response?.data?.error || t('wholesaleOrderDetail:uploadSignedDeliveryNoteFailed'),
        { variant: 'error' },
      );
    } finally {
      setUploadSignedNoteSubmitting(false);
      setUploadSignedNoteShipment(null);
    }
  };

  const beginDeliveryProofUpload = (s: Shipment) => {
    if (shipmentAwaitingCourierPickup(s)) {
      setCourierPickupWarnShipment(s);
      return;
    }
    deliveryProofInputRefs.current[s.id]?.click();
  };

  const proceedDeliveryProofUpload = () => {
    const s = courierPickupWarnShipment;
    setCourierPickupWarnShipment(null);
    if (s) deliveryProofInputRefs.current[s.id]?.click();
  };

  const shipmentDeliveryNoteCell = (s: Shipment) =>
    s.delivery_note_pdf_url ? (
      <Button
        size="small"
        variant="outlined"
        href={s.delivery_note_pdf_url}
        target="_blank"
        rel="noopener noreferrer"
        component="a"
        startIcon={<DownloadIcon />}
      >
        {t('wholesaleOrderDetail:deliveryNotePdf')}
      </Button>
    ) : (
      <Typography component="span" variant="body2" color="text.secondary">
        —
      </Typography>
    );

  const shipmentDeliveryProofCell = (s: Shipment) =>
    s.signed_delivery_note_pdf_url ? (
      <Button
        size="small"
        variant="outlined"
        color="secondary"
        href={s.signed_delivery_note_pdf_url}
        target="_blank"
        rel="noopener noreferrer"
        component="a"
        startIcon={<DownloadIcon />}
      >
        {t('wholesaleOrderDetail:signedDeliveryNotePdf')}
      </Button>
    ) : shipmentAwaitingCourierPickup(s) ? (
      <Typography component="span" variant="body2" color="warning.main">
        {t('wholesaleOrderDetail:uploadSignedDeliveryNoteAwaitingCourier')}
      </Typography>
    ) : (
      <Typography component="span" variant="body2" color="text.secondary">
        —
      </Typography>
    );

  const shipmentRowActions = (s: Shipment) => (
    <>
      {!orderCompleted && canEditShipmentDetails(s) && (
        <Button
          size="small"
          startIcon={<EditIcon />}
          onClick={() => {
            setEditingShipment(s);
            setShipmentCourier(s.courier ?? '');
            setShipmentTracking(s.tracking_number ?? '');
            setShipmentDeliveryDateDraft(
              s.delivery_date ? String(s.delivery_date).substring(0, 10) : format(new Date(), 'yyyy-MM-dd'),
            );
          }}
        >
          {t('wholesaleOrderDetail:edit')}
        </Button>
      )}
      {s.delivery_note_pdf_url && !orderCompleted && canEditShipmentDetails(s) && (
        <>
          <Button
            size="small"
            startIcon={regenShipmentId === s.id ? <CircularProgress size={14} /> : <RegenIcon />}
            disabled={
              regenShipmentId !== null ||
              isRegenBlockedByEmailLock(auditLogs, 'delivery_note', orderLockUnlocked, s.id)
            }
            onClick={async () => {
            if (!order) return;
            if (isRegenBlockedByEmailLock(auditLogs, 'delivery_note', orderLockUnlocked, s.id)) return;
            setRegenShipmentId(s.id);
            try {
              const updated = await shipmentsAPI.regenerateDeliveryNote(s.id, {
                unlock_after_email: shouldSendRegenUnlockFlag(
                  auditLogs,
                  'delivery_note',
                  orderLockUnlocked,
                  s.id,
                ),
              });
              setOrder((prev) =>
                prev
                  ? {
                      ...prev,
                      shipments: prev.shipments?.map((sh) => (sh.id === updated.id ? updated : sh)) ?? [],
                    }
                  : null,
              );
              enqueueSnackbar('Delivery note regenerated', { variant: 'success' });
            } catch (e: any) {
              enqueueSnackbar(e.response?.data?.error || 'Failed to regenerate delivery note', {
                variant: 'error',
              });
            } finally {
              setRegenShipmentId(null);
            }
          }}
        >
          {t('wholesaleOrderDetail:regen')}
        </Button>
        </>
      )}
      {!isShipmentCompleted(s.status) && !s.delivery_note_pdf_url && shipmentNeedsPacking(s.status) && (
        <Button size="small" color="primary" variant="outlined" onClick={() => setStartShipmentDialog(s)}>
          {t('wholesaleOrderDetail:startShipment')}
        </Button>
      )}
      {!orderUploadBlocked && canReplaceDeliveryProof(s) && (
        <Button
          size="small"
          startIcon={<EditIcon />}
          component="label"
          disabled={uploadSignedNoteSubmitting}
        >
          {uploadSignedNoteSubmitting && uploadSignedNoteShipment?.id === s.id
            ? t('wholesaleOrderDetail:uploading')
            : t('wholesaleOrderDetail:edit')}
          <input
            type="file"
            hidden
            accept=".pdf,.png,.jpg,.jpeg,.gif,.webp"
            onChange={async (e) => {
              const file = e.target.files?.[0];
              if (!file || !order) return;
              setUploadSignedNoteShipment(s);
              setUploadSignedNoteSubmitting(true);
              try {
                await shipmentsAPI.uploadSignedDeliveryNote(s.id, file, {
                  unlock_after_completion: shouldSendUploadUnlockFlag(order, orderLockUnlocked),
                });
                const freshOrder = await wholesaleOrdersAPI.get(order.id);
                setOrder(freshOrder);
                const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => auditLogs);
                setAuditLogs(freshAuditLogs);
                enqueueSnackbar(t('wholesaleOrderDetail:replaceSignedDeliveryNoteSuccess'), {
                  variant: 'success',
                });
              } catch (err: any) {
                enqueueSnackbar(
                  err.response?.data?.error || t('wholesaleOrderDetail:replaceSignedDeliveryNoteFailed'),
                  { variant: 'error' },
                );
              } finally {
                setUploadSignedNoteSubmitting(false);
                setUploadSignedNoteShipment(null);
                e.target.value = '';
              }
            }}
          />
        </Button>
      )}
      {canUploadDeliveryProof(s) && (
        <>
          <Button
            size="small"
            color="primary"
            variant="contained"
            disabled={uploadSignedNoteSubmitting}
            onClick={() => beginDeliveryProofUpload(s)}
          >
            {uploadSignedNoteSubmitting && uploadSignedNoteShipment?.id === s.id
              ? t('wholesaleOrderDetail:uploading')
              : t('wholesaleOrderDetail:uploadSignedDeliveryNote')}
          </Button>
          <input
            ref={(el) => {
              deliveryProofInputRefs.current[s.id] = el;
            }}
            type="file"
            hidden
            accept=".pdf,.png,.jpg,.jpeg,.gif,.webp"
            onChange={async (e) => {
              const file = e.target.files?.[0];
              if (!file) return;
              await uploadDeliveryProofForShipment(s, file);
              e.target.value = '';
            }}
          />
        </>
      )}
      {!isShipmentCompleted(s.status) && s.delivery_note_pdf_url && !orderCompleted && !order.payment_confirmed_at && (
        <Button
          size="small"
          color="warning"
          variant="outlined"
          disabled={forceCompleteShipmentSubmitting}
          startIcon={<CompleteIcon sx={{ fontSize: 16 }} />}
          onClick={() => setForceCompleteShipmentDialog(s)}
        >
          {t('wholesaleOrderDetail:forceCompleteShipment')}
        </Button>
      )}
    </>
  );

  const parseAuditChanges = (changes: string): Record<string, any> | null => {
    try {
      return JSON.parse(changes);
    } catch {
      return null;
    }
  };

  const lastUpdateAuditLog = (() => {
    let best: AuditLog | null = null;
    let bestAt = -Infinity;
    for (const l of auditLogs) {
      if (l.action !== 'wholesale_order_update' && l.action !== 'wholesale_shipment_update') continue;
      const at = l.created_at ? new Date(l.created_at).getTime() : -Infinity;
      if (at > bestAt) {
        bestAt = at;
        best = l;
      }
    }
    return best;
  })();

  const lastOrderDateUpdateAuditLog = (() => {
    // auditLogs are already sorted DESC by backend: created_at DESC, id DESC.
    for (const l of auditLogs) {
      if (l.action !== 'wholesale_order_update') continue;
      const parsed = parseAuditChanges(l.changes);
      if (parsed && Object.prototype.hasOwnProperty.call(parsed, 'order_date')) return l;
    }
    return null;
  })();

  const orderDateByUser = lastOrderDateUpdateAuditLog?.user ?? order.user;

  const shipmentCompleteDateUpdateAuditLog = (() => {
    if (!latestCompletedShipment) return null;
    let bestForThisShipment: AuditLog | null = null;
    let bestForThisShipmentAt = -Infinity;
    let bestAny: AuditLog | null = null;
    let bestAnyAt = -Infinity;

    for (const l of auditLogs) {
      if (l.action !== 'wholesale_shipment_update') continue;
      const parsed = parseAuditChanges(l.changes);
      if (!parsed) continue;
      const changesObj = parsed.changes;
      if (!changesObj || !Object.prototype.hasOwnProperty.call(changesObj, 'delivery_date')) continue;

      const at = l.created_at ? new Date(l.created_at).getTime() : -Infinity;

      const shipmentId = typeof parsed.shipment_id === 'number' ? parsed.shipment_id : Number(parsed.shipment_id);
      if (shipmentId && shipmentId === latestCompletedShipment.id) {
        if (at > bestForThisShipmentAt) {
          bestForThisShipmentAt = at;
          bestForThisShipment = l;
        }
      }

      if (at > bestAnyAt) {
        bestAnyAt = at;
        bestAny = l;
      }
    }

    return bestForThisShipment ?? bestAny;
  })();

  const shipmentCompleteDateByUser = shipmentCompleteDateUpdateAuditLog?.user ?? order.user;

  const lastInvoiceDateUpdateAuditLog = (() => {
    for (const l of auditLogs) {
      if (l.action !== 'wholesale_order_update') continue;
      const parsed = parseAuditChanges(l.changes);
      if (parsed && Object.prototype.hasOwnProperty.call(parsed, 'invoice_date')) return l;
    }
    return null;
  })();
  const invoiceDateByUser = lastInvoiceDateUpdateAuditLog?.user ?? order.user;

  type PaymentProofMeta = { amountPerFile?: number; transfer_date?: string; transferred_to?: string };
  const paymentProofMetaByDocId: Record<number, PaymentProofMeta> = {};
  let totalProofAmount = 0;
  if (order.documents && order.documents.length > 0) {
    const proofDocs = order.documents.filter((d) => d.type === 'payment_proof');
    const uploadAudits = auditLogs
      .filter((l) => l.action === 'wholesale_order_upload_payment_proof')
      .map((l) => {
        const parsed = parseAuditChanges(l.changes);
        if (!parsed) return null;
        const base = parsed.changes ?? parsed;
        const fileCountRaw = base.file_count ?? base.files ?? 1;
        const file_count = Number.isFinite(Number(fileCountRaw)) ? Number(fileCountRaw) : 1;
        const amountRaw = base.amount;
        const amountNum = typeof amountRaw === 'number' ? amountRaw : Number(amountRaw);
        const amount = Number.isFinite(amountNum) ? amountNum : undefined;
        const transfer_date = typeof base.transfer_date === 'string' ? base.transfer_date : undefined;
        const transferred_to = typeof base.transferred_to === 'string' ? base.transferred_to : undefined;
        return {
          id: l.id,
          created_at: l.created_at,
          file_count,
          amount,
          transfer_date,
          transferred_to,
        };
      })
      .filter(Boolean) as {
        id: number;
        created_at: string;
        file_count: number;
        amount?: number;
        transfer_date?: string;
        transferred_to?: string;
      }[];

      if (uploadAudits.length > 0 && proofDocs.length > 0) {
      const docsSorted = [...proofDocs].sort(
        (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
      );
      const auditsSorted = [...uploadAudits].sort(
        (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
      );
        let docIndex = 0;

        for (const audit of auditsSorted) {
          let remaining = audit.file_count || 1;
          const perFileAmount =
            audit.amount != null && remaining > 0 ? audit.amount / remaining : undefined;
          while (remaining > 0 && docIndex < docsSorted.length) {
            const doc = docsSorted[docIndex++];
            paymentProofMetaByDocId[doc.id] = {
              amountPerFile: perFileAmount,
              transfer_date: audit.transfer_date,
              transferred_to: audit.transferred_to,
            };
            remaining -= 1;
          }
        }

        // Sum only over currently existing documents (each doc contributes its per-file amount).
        for (const doc of docsSorted) {
          const meta = paymentProofMetaByDocId[doc.id];
          if (meta?.amountPerFile != null) {
            totalProofAmount += meta.amountPerFile;
          }
      }
    }
  }
  const orderTotal = (order.total_net ?? totalForOrder(order)) + (Number(order.shipping_fee) || 0);
  const pendingAmount = Math.max(0, orderTotal - totalProofAmount);

  const workflowCtx = buildWholesaleOrderWorkflowContext(order, auditLogs);
  const processSteps = computeWholesaleOrderProcessSteps(order, workflowCtx);
  const processStepCount = processSteps.length;
  const lastProcessStepIndex = processStepCount - 1;
  const currentProcessStepKey = getCurrentWholesaleOrderProcessStepKey(processSteps);
  const orderWorkflowComplete = processSteps.every((s) => s.done);

  type PipelineFlowSection = 'orderConfirmEmail' | 'shipments' | 'deliveryCompleteEmail' | 'invoiceEmail' | 'payment';

  // Dimmed section previews show during assignment too (incl. pending_approval staged assign).
  const orderFlowPipelinePreviewVisible =
    order.status !== 'rejected' &&
    order.status !== 'deleted' &&
    (canAssign || stepEndorsed);

  const pipelineFlowSections = ((): PipelineFlowSection[] => {
    const sections: PipelineFlowSection[] = [
      'orderConfirmEmail',
      'shipments',
      'deliveryCompleteEmail',
    ];
    if (canShowInvoiceEmailButton) sections.push('invoiceEmail');
    sections.push('payment');
    return sections;
  })();

  const isPipelineFlowSectionDone = (section: PipelineFlowSection): boolean => {
    switch (section) {
      case 'orderConfirmEmail':
        return orderConfirmEmailDone;
      case 'shipments':
        return allShipmentsCompleted;
      case 'deliveryCompleteEmail':
        return shipmentsDeliveredEmailDone;
      case 'invoiceEmail':
        return invoiceEmailDone;
      case 'payment':
        return isPaymentConfirmationStepComplete(order, workflowCtx);
      default:
        return false;
    }
  };

  const currentPipelineFlowIndex = ((): number => {
    if (!orderFlowPipelinePreviewVisible) return pipelineFlowSections.length;
    if (!allocationConfirmed) return -1;
    if (!orderConfirmEmailDone) return 0;
    if (!allShipmentsCompleted) return 1;
    if (!shipmentsDeliveredEmailDone) return 2;
    if (canShowInvoiceEmailButton) {
      if (!invoiceEmailDone) return 3;
      if (!isPaymentConfirmationStepComplete(order, workflowCtx)) return 4;
      return pipelineFlowSections.length;
    }
    if (!isPaymentConfirmationStepComplete(order, workflowCtx)) return 3;
    return pipelineFlowSections.length;
  })();

  const shouldShowPipelineSection = (section: PipelineFlowSection): boolean => {
    if (!orderFlowPipelinePreviewVisible) return false;
    const idx = pipelineFlowSections.indexOf(section);
    if (idx < 0) return false;
    if (isPipelineFlowSectionDone(section)) return true;
    if (currentPipelineFlowIndex < 0) return true;
    return idx >= currentPipelineFlowIndex;
  };

  const isPipelineSectionDimmed = (section: PipelineFlowSection): boolean => {
    if (isPipelineFlowSectionDone(section)) return false;
    const idx = pipelineFlowSections.indexOf(section);
    if (idx < 0) return false;
    if (currentPipelineFlowIndex < 0) return true;
    return idx > currentPipelineFlowIndex;
  };

  const isPipelineSectionActive = (section: PipelineFlowSection): boolean => {
    if (currentPipelineFlowIndex < 0) return false;
    return (
      pipelineFlowSections.indexOf(section) === currentPipelineFlowIndex &&
      !isPipelineFlowSectionDone(section)
    );
  };


  const showOrderConfirmationEmailSectionVisible = shouldShowPipelineSection('orderConfirmEmail');
  const orderConfirmEmailSectionPending = isPipelineSectionDimmed('orderConfirmEmail');
  const showShipmentsSectionVisible = shouldShowPipelineSection('shipments');
  const shipmentsSectionPending = isPipelineSectionDimmed('shipments');
  const showDeliveryCompleteEmailSectionVisible = shouldShowPipelineSection('deliveryCompleteEmail');
  const deliveryCompleteEmailSectionPending = isPipelineSectionDimmed('deliveryCompleteEmail');
  const showInvoiceEmailSectionVisible = shouldShowPipelineSection('invoiceEmail');
  const invoiceEmailSectionPending = isPipelineSectionDimmed('invoiceEmail');
  const paymentFullyConfirmed = isPaymentConfirmationStepComplete(order, workflowCtx);
  const paymentProofReady =
    orderFlowPipelineVisible &&
    allShipmentsCompleted &&
    invoiceStepComplete &&
    !paymentFullyConfirmed;
  const showPaymentProofSectionVisible =
    shouldShowPipelineSection('payment') && !paymentFullyConfirmed;
  const paymentProofSectionPending = isPipelineSectionDimmed('payment');

  const currentActionSection = ((): OrderActionSection | null => {
    if (order.status === 'deleted' || order.status === 'rejected' || orderWorkflowComplete) {
      return null;
    }
    if (order.status === 'pending_approval' || (canAssign && !allocationConfirmed)) return 'assign';
    if (orderConfirmEmailReady) return 'orderConfirmEmail';
    if (deliveryCompleteEmailReady) return 'deliveryCompleteEmail';
    if (invoiceEmailReady) return 'invoiceEmail';
    if (paymentProofReady) return 'payment';

    switch (currentProcessStepKey) {
      case 'stepOrderConfirmation':
        if (canAssign && !allOrderLinesAssigned) return 'assign';
        if (canAssign && !allocationConfirmed) return 'assign';
        return null;
      case 'stepStartShipment':
      case 'stepFinishShipment':
        return hasShipments ? 'shipments' : null;
      case 'stepSendInvoiceEmail':
        return canShowInvoiceEmailButton ? 'invoiceEmail' : null;
      case 'stepPaymentConfirmation':
      case 'stepComplete':
        return paymentProofReady ? 'payment' : null;
      default:
        return null;
    }
  })();

  const actionSectionPaperSx = (
    section: OrderActionSection,
    base: object = {},
    options?: { pending?: boolean },
  ) => {
    const pipelineSection = section as PipelineFlowSection;
    const isActive = (() => {
      if (options?.pending) return false;
      if (pipelineFlowSections.includes(pipelineSection)) {
        return isPipelineSectionActive(pipelineSection);
      }
      return currentActionSection === section;
    })();
    return {
      ...base,
      ...(options?.pending ? orderActionSectionPendingSx : {}),
      ...(isActive ? orderActionSectionHighlightSx(theme) : {}),
    };
  };

  const renderActionNeededChip = (section: OrderActionSection, pending = false) => {
    const pipelineSection = section as PipelineFlowSection;
    const isActive =
      !pending &&
      (pipelineFlowSections.includes(pipelineSection)
        ? isPipelineSectionActive(pipelineSection)
        : currentActionSection === section);
    return isActive ? (
      <Chip
        label={t('wholesaleOrderDetail:actionNeeded')}
        size="small"
        color="primary"
        sx={{ ml: 1, fontWeight: 600, verticalAlign: 'middle' }}
      />
    ) : null;
  };

  const getProcessStepCompletedAt = (labelKey: string): string | null =>
    getWholesaleOrderProcessStepCompletedAt(order, labelKey as WholesaleOrderProcessStepKey, {
      auditLogs,
      assignmentCompletedAt,
      stepFinishShipment,
    });

  const showDocButtons =
    orderConfirmationDoc ||
    invoiceDoc ||
    (order.shipments && order.shipments.length > 0 && order.shipments.every((s) => s.status === 'completed'));

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          mb: 2,
          flexWrap: 'wrap',
          gap: 1,
        }}
      >
        <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          <Link component={RouterLink} to="/" color="primary" underline="hover">{t('common:home')}</Link>
          <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
          <Link component={RouterLink} to="/wholesale-orders" color="primary" underline="hover">
            {t('layout:wholesaleOrders')}
          </Link>
          {order?.order_number && (
            <>
              <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
              <span>{order.order_number}</span>
            </>
          )}
        </Typography>
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: { xs: 'stretch', sm: 'flex-end' },
            gap: 1,
            width: { xs: '100%', sm: 'auto' },
          }}
        >
          {showDocButtons && (
            <Box
              sx={{
                display: 'flex',
                alignItems: 'center',
                gap: 1,
                flexWrap: 'wrap',
                justifyContent: { xs: 'flex-start', sm: 'flex-end' },
              }}
            >
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                {renderOrderLockToggle()}
                <Typography variant="subtitle2" color="text.secondary" sx={{ fontWeight: 600 }}>
                  {t('wholesaleOrderDetail:rePrint')}
                </Typography>
              </Box>
              <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap' }}>
                {orderConfirmationDoc?.file_url && (
                  <>
                    <ButtonGroup
                      size="small"
                      sx={{
                        '& .MuiButton-root': {
                          backgroundColor: '#0d47a1',
                          color: '#fff',
                          borderColor: '#0d47a1',
                        },
                        '& .MuiButton-root:hover': {
                          backgroundColor: '#1565c0',
                          color: '#fff',
                          borderColor: '#1565c0',
                        },
                        '& .MuiButton-root.Mui-disabled': {
                          backgroundColor: 'rgba(0,0,0,0.12)',
                          color: 'rgba(0,0,0,0.26)',
                        },
                      }}
                    >
                      <Button
                        onClick={async () => {
                          try {
                            const refNoSafe = (order.ref_no || '').trim().replace(/[/\\\s]+/g, '_') || `D${order.id}`;
                            const ts = format(new Date(), 'yyyyMMddHHmmss');
                            const fallbackFilename = `${refNoSafe}_${orderConfirmationDoc.type}_${orderConfirmationDoc.id}_${ts}.pdf`;
                            const { blob, filename } = await wholesaleOrdersAPI.downloadDocumentWithFilename(
                              order.id,
                              orderConfirmationDoc.id,
                              false,
                              fallbackFilename,
                            );
                            const a = document.createElement('a');
                            a.href = URL.createObjectURL(blob);
                            a.download = filename || 'download';
                            a.click();
                            URL.revokeObjectURL(a.href);
                          } catch (e: any) {
                            enqueueSnackbar(e?.response?.data?.error || e?.message || 'Download failed', { variant: 'error' });
                          }
                        }}
                      >
                        {t('wholesaleOrderDetail:orderConfirmation')}
                      </Button>
                      <Button
                        aria-label="More actions for order confirmation"
                        onClick={(e) => setDocMenuAnchorEl(e.currentTarget)}
                      >
                        {docMenuAnchorEl ? (
                          <ArrowDropUpIcon fontSize="small" />
                        ) : (
                          <ArrowDropDownIcon fontSize="small" />
                        )}
                      </Button>
                    </ButtonGroup>
                    <Menu
                      anchorEl={docMenuAnchorEl}
                      open={Boolean(docMenuAnchorEl)}
                      onClose={() => setDocMenuAnchorEl(null)}
                    >
                      <MuiMenuItem
                        onClick={handleRegenOrderConfirmation}
                        disabled={
                          regenConfirmLoading ||
                          isRegenBlockedByEmailLock(auditLogs, 'order_confirmation', orderLockUnlocked)
                        }
                      >
                        {regenConfirmLoading ? (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <CircularProgress size={16} />
                            <span>{t('wholesaleOrderDetail:reGenerate')}</span>
                          </Box>
                        ) : (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <RefreshIcon fontSize="small" />
                            <span>{t('wholesaleOrderDetail:reGenerate')}</span>
                          </Box>
                        )}
                      </MuiMenuItem>
                    </Menu>
                  </>
                )}
                {(invoiceDoc?.file_url ||
                  (order.shipments &&
                    order.shipments.length > 0 &&
                    order.shipments.every((s) => s.status === 'completed'))) && (
                  <>
                    <ButtonGroup
                      size="small"
                      sx={{
                        '& .MuiButton-root': {
                          backgroundColor: '#0d47a1',
                          color: '#fff',
                          borderColor: '#0d47a1',
                        },
                        '& .MuiButton-root:hover': {
                          backgroundColor: '#1565c0',
                          color: '#fff',
                          borderColor: '#1565c0',
                        },
                        '& .MuiButton-root.Mui-disabled': {
                          backgroundColor: 'rgba(0,0,0,0.12)',
                          color: 'rgba(0,0,0,0.26)',
                        },
                      }}
                    >
                      <Button
                        disabled={!invoiceDoc?.id}
                        onClick={async () => {
                          if (!invoiceDoc?.id) return;
                          try {
                          const refNoSafe = (order.ref_no || '').trim().replace(/[/\\\s]+/g, '_') || `D${order.id}`;
                          const ts = format(new Date(), 'yyyyMMddHHmmss');
                          const fallbackFilename = `${refNoSafe}_${invoiceDoc.type}_${invoiceDoc.id}_${ts}.pdf`;
                          const { blob, filename } = await wholesaleOrdersAPI.downloadDocumentWithFilename(
                            order.id,
                            invoiceDoc.id,
                            false,
                            fallbackFilename,
                          );
                            const a = document.createElement('a');
                            a.href = URL.createObjectURL(blob);
                            a.download = filename || 'download';
                            a.click();
                            URL.revokeObjectURL(a.href);
                          } catch (e: any) {
                            enqueueSnackbar(e?.response?.data?.error || e?.message || 'Download failed', { variant: 'error' });
                          }
                        }}
                      >
                        {t('wholesaleOrderDetail:invoice')}
                      </Button>
                      <Button
                        aria-label="More actions for invoice"
                        onClick={(e) => setInvoiceMenuAnchorEl(e.currentTarget)}
                      >
                        {invoiceMenuAnchorEl ? (
                          <ArrowDropUpIcon fontSize="small" />
                        ) : (
                          <ArrowDropDownIcon fontSize="small" />
                        )}
                      </Button>
                    </ButtonGroup>
                    <Menu
                      anchorEl={invoiceMenuAnchorEl}
                      open={Boolean(invoiceMenuAnchorEl)}
                      onClose={() => setInvoiceMenuAnchorEl(null)}
                    >
                      <MuiMenuItem
                        onClick={handleRegenInvoice}
                        disabled={
                          regenInvoiceLoading ||
                          isRegenBlockedByEmailLock(auditLogs, 'invoice', orderLockUnlocked)
                        }
                      >
                        {regenInvoiceLoading ? (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <CircularProgress size={16} />
                            <span>{t('wholesaleOrderDetail:reGenerate')}</span>
                          </Box>
                        ) : (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <RefreshIcon fontSize="small" />
                            <span>{t('wholesaleOrderDetail:reGenerate')}</span>
                          </Box>
                        )}
                      </MuiMenuItem>
                    </Menu>
                  </>
                )}
              </Box>
            </Box>
          )}
        </Box>
      </Box>

      <Box
        sx={{
          display: 'flex',
          flexDirection: { xs: 'column', md: 'row' },
          alignItems: { xs: 'flex-start', md: 'center' },
          gap: { xs: 1, md: 2 },
          mb: 1,
          py: 1.5,
          flexWrap: { md: 'wrap' },
          position: { xs: 'static', md: 'sticky' },
          top: { md: 0 },
          zIndex: { md: 10 },
          backgroundColor: 'background.default',
        }}
      >
        <Box
          sx={{
            display: 'flex',
            flexWrap: 'wrap',
            alignItems: 'center',
            gap: { xs: 1, md: 2 },
            flex: 1,
            minWidth: 0,
          }}
        >
          <Typography variant="h5" sx={{ typography: { xs: 'h6', md: 'h5' }, wordBreak: 'break-word' }}>
            {order.order_number}
          </Typography>
          <Chip
            size="medium"
            sx={{ maxWidth: { xs: '100%', sm: 'none' }, height: 'auto', py: 0.5, '& .MuiChip-label': { whiteSpace: 'normal', textAlign: { xs: 'left', sm: 'center' } } }}
            label={wholesaleOrderStatusLabel(order, t, workflowCtx)}
            color={wholesaleOrderStatusColor(order, workflowCtx)}
          />
        </Box>
        {canDeleteOrder && (
          <Button
            size="small"
            color="error"
            variant="outlined"
            startIcon={<DeleteIcon />}
            onClick={handleDeleteOrder}
            disabled={actioning}
            sx={{ flexShrink: 0, alignSelf: { xs: 'flex-start', md: 'auto' }, ml: { md: 'auto' } }}
          >
            {t('common:delete')}
          </Button>
        )}
      </Box>

      <Paper sx={{ p: { xs: 2, md: 3 }, mb: 3, overflow: 'hidden' }}>
        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 2 }}>
          {t('wholesaleOrderDetail:orderProgress')}
        </Typography>
        {isShipmentsMobile ? (
          <Stack spacing={0}>
            {processSteps.map((step, index) => {
              const done = step.done;
              const isRejected = order.status === 'rejected' && index === 1;
              const isInvoiceEmailStep = step.labelKey === 'stepSendInvoiceEmail';
              const isCurrentProcessStep = !done && step.labelKey === currentProcessStepKey;
              const completedAt = getProcessStepCompletedAt(step.labelKey);
              const circle = (
                <Box
                  sx={{
                    width: 32,
                    height: 32,
                    borderRadius: '50%',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontWeight: 700,
                    fontSize: '0.875rem',
                    flexShrink: 0,
                    ...(done
                      ? { bgcolor: isRejected ? 'error.main' : 'success.main', color: isRejected ? 'error.contrastText' : 'success.contrastText' }
                      : isCurrentProcessStep
                        ? {
                            border: 2,
                            borderColor: 'primary.main',
                            bgcolor: 'primary.main',
                            color: 'primary.contrastText',
                            boxShadow: `0 0 10px 2px ${alpha(theme.palette.primary.main, 0.4)}`,
                          }
                      : isInvoiceEmailStep && invoiceEmailReady
                        ? {
                            border: 2,
                            borderColor: 'warning.main',
                            bgcolor: 'warning.light',
                            color: 'warning.contrastText',
                            boxShadow: '0 0 8px 2px rgba(255, 193, 7, 0.45)',
                          }
                        : { border: 2, borderColor: isRejected ? 'error.main' : 'divider', color: 'text.secondary' }),
                  }}
                >
                  {done ? <CheckIcon sx={{ fontSize: 20 }} /> : index + 1}
                </Box>
              );
              return (
                <Box key={step.labelKey} sx={{ display: 'flex', gap: 1.5, alignItems: 'stretch' }}>
                  <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', width: 36, flexShrink: 0 }}>
                    {done && completedAt ? (
                      <Tooltip title={t('wholesaleOrderDetail:stepCompletedAt', { date: format(new Date(completedAt), 'dd MMM yyyy HH:mm') })}>
                        <span style={{ display: 'inline-flex' }}>{circle}</span>
                      </Tooltip>
                    ) : (
                      circle
                    )}
                    {index < lastProcessStepIndex &&
                      (() => {
                        const prevDone = processSteps[index]?.done ?? false;
                        const nextDone = processSteps[index + 1]?.done ?? false;
                        const isLeadingToOngoing = prevDone && !nextDone;
                        const fillColor = order.status === 'rejected' && index === 1 ? 'error.main' : 'success.main';
                        if (isLeadingToOngoing) {
                          return (
                            <Box
                              sx={{
                                flex: 1,
                                minHeight: 20,
                                ml: '17px',
                                borderLeft: '2px dotted',
                                borderColor: 'grey.400',
                                pt: 0.25,
                              }}
                            />
                          );
                        }
                        return (
                          <Box
                            sx={{
                              width: 3,
                              flex: 1,
                              minHeight: 20,
                              borderRadius: 1,
                              position: 'relative',
                              bgcolor: 'action.hover',
                              mx: 'auto',
                              mt: 0.25,
                            }}
                          >
                            <Box
                              sx={{
                                position: 'absolute',
                                top: 0,
                                left: 0,
                                right: 0,
                                height: prevDone ? '100%' : 0,
                                bgcolor: fillColor,
                                borderRadius: 1,
                                transition: 'height 0.2s ease',
                              }}
                            />
                          </Box>
                        );
                      })()}
                  </Box>
                  <Box sx={{ flex: 1, minWidth: 0, pt: 0.25, pb: index < lastProcessStepIndex ? 1 : 0 }}>
                    <Typography
                      variant="body2"
                      color={done ? 'text.primary' : 'text.secondary'}
                      sx={{ fontWeight: done ? 600 : 400, lineHeight: 1.35 }}
                    >
                      {step.labelKey ? t('wholesaleOrderDetail:' + step.labelKey) : ''}
                    </Typography>
                    {done && completedAt && (
                      <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 0.25 }}>
                        {format(new Date(completedAt), 'dd MMM yyyy HH:mm')}
                      </Typography>
                    )}
                  </Box>
                </Box>
              );
            })}
          </Stack>
        ) : (
          <Box
            sx={{
              mx: { md: -3 },
              width: { md: 'calc(100% + 48px)' },
              display: 'flex',
              alignItems: 'flex-start',
              overflowX: 'auto',
              WebkitOverflowScrolling: 'touch',
            }}
          >
            {processSteps.map((step, index) => {
              const num = index + 1;
              const done = step.done;
              const isRejected = order.status === 'rejected' && index === 1;
              const isInvoiceEmailStep = step.labelKey === 'stepSendInvoiceEmail';
              const isCurrentProcessStep = !done && step.labelKey === currentProcessStepKey;
              const completedAt = getProcessStepCompletedAt(step.labelKey);
              const circle = (
                <Box
                  sx={{
                    width: 32,
                    height: 32,
                    borderRadius: '50%',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontWeight: 700,
                    fontSize: '0.875rem',
                    ...(done
                      ? { bgcolor: isRejected ? 'error.main' : 'success.main', color: isRejected ? 'error.contrastText' : 'success.contrastText' }
                      : isCurrentProcessStep
                        ? {
                            border: 2,
                            borderColor: 'primary.main',
                            bgcolor: 'primary.main',
                            color: 'primary.contrastText',
                            boxShadow: `0 0 10px 2px ${alpha(theme.palette.primary.main, 0.4)}`,
                          }
                      : isInvoiceEmailStep && invoiceEmailReady
                        ? {
                            border: 2,
                            borderColor: 'warning.main',
                            bgcolor: 'warning.light',
                            color: 'warning.contrastText',
                            boxShadow: '0 0 8px 2px rgba(255, 193, 7, 0.45)',
                          }
                        : { border: 2, borderColor: isRejected ? 'error.main' : 'divider', color: 'text.secondary' }),
                  }}
                >
                  {done ? <CheckIcon sx={{ fontSize: 20 }} /> : num}
                </Box>
              );
              return (
                <Box key={step.labelKey} sx={{ display: 'contents' }}>
                  <Box
                    sx={{
                      display: 'flex',
                      flexDirection: 'column',
                      alignItems: 'center',
                      flexShrink: 0,
                      maxWidth: 96,
                      pl: index === 0 ? 3 : 0,
                      pr: index === lastProcessStepIndex ? 3 : 0,
                    }}
                  >
                    {done && completedAt ? (
                      <Tooltip title={t('wholesaleOrderDetail:stepCompletedAt', { date: format(new Date(completedAt), 'dd MMM yyyy HH:mm') })}>
                        <span style={{ display: 'inline-flex' }}>{circle}</span>
                      </Tooltip>
                    ) : (
                      circle
                    )}
                    <Typography
                      variant="caption"
                      color="text.secondary"
                      sx={{
                        mt: 0.5,
                        textAlign: 'center',
                        lineHeight: 1.2,
                        px: 0.25,
                        wordBreak: 'break-word',
                      }}
                    >
                      {step.labelKey ? t('wholesaleOrderDetail:' + step.labelKey) : ''}
                    </Typography>
                  </Box>
                  {index < lastProcessStepIndex && (() => {
                    const prevDone = processSteps[index]?.done ?? false;
                    const nextDone = processSteps[index + 1]?.done ?? false;
                    const isLeadingToOngoing = prevDone && !nextDone;
                    return (
                      <Box
                        sx={{
                          flex: 1,
                          height: 6,
                          borderRadius: 1,
                          overflow: 'hidden',
                          mx: 0.5,
                          minWidth: 8,
                          alignSelf: 'flex-start',
                          mt: '13px',
                          ...(isLeadingToOngoing
                            ? {
                                bgcolor: 'transparent',
                                borderTop: '2px dotted',
                                borderColor: 'grey.400',
                                boxSizing: 'border-box',
                              }
                            : {
                                bgcolor: 'action.hover',
                              }),
                        }}
                      >
                        {!isLeadingToOngoing && (
                          <Box
                            sx={{
                              width: prevDone ? '100%' : 0,
                              height: '100%',
                              bgcolor: order.status === 'rejected' && index === 1 ? 'error.main' : 'success.main',
                              borderRadius: 1,
                              transition: 'width 0.2s ease',
                            }}
                          />
                        )}
                      </Box>
                    );
                  })()}
                </Box>
              );
            })}
          </Box>
        )}
      </Paper>

      <Box
        sx={{
          display: 'grid',
          gridTemplateColumns: { xs: '1fr', lg: 'minmax(0, 1fr) 300px' },
          gap: 2,
          mb: 3,
          alignItems: 'flex-start',
        }}
      >
        <Stack spacing={2} sx={{ minWidth: 0, width: '100%' }}>
        <Paper sx={{ p: { xs: 2, md: 3 } }}>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
              {t('wholesaleOrderDetail:summary')}
            </Typography>
          </Box>
          <Box
            sx={{
              display: 'grid',
              gridTemplateColumns: { xs: '1fr', md: 'auto 1fr' },
              columnGap: { xs: 0, md: 3 },
              rowGap: { xs: 1, md: 0.5 },
              alignItems: 'flex-start',
            }}
          >
            <Typography variant="body2" color="text.secondary">
              {t('wholesaleOrderDetail:client')}
            </Typography>
            <Typography variant="body2">
              {order.wholesale_client?.name ?? order.wholesale_client_id}
            </Typography>

            <Typography variant="body2" color="text.secondary">
              {t('wholesaleOrderDetail:shippingAddress')}
            </Typography>
            {order.wholesale_client_store ? (
              <Box sx={{ display: 'flex', flexDirection: 'column' }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Typography variant="body2">
                    {order.wholesale_client_store.name}
                  </Typography>
                  {!orderCompleted && (
                    <EditIcon
                      sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                      onClick={() => {
                        const currentStoreId = order.wholesale_client_store_id ?? null;
                        const isOtherAddress = otherAddressStoreId != null && currentStoreId === otherAddressStoreId;
                        setShippingStoreIdDraft(isOtherAddress ? 'new' : (currentStoreId ?? ''));
                        setOtherAddressStoreId(isOtherAddress ? otherAddressStoreId : null);
                        setShippingNameDraft(order.wholesale_client_store?.name ?? '');
                        setShippingAddress1Draft(order.wholesale_client_store?.address_line1 ?? '');
                        setShippingAddress2Draft(order.wholesale_client_store?.address_line2 ?? '');
                        setShippingCityDraft(order.wholesale_client_store?.city ?? '');
                        setShippingPostcodeDraft(order.wholesale_client_store?.postcode ?? '');
                        setShippingDialogOpen(true);
                      }}
                    />
                  )}
                </Box>
                {order.wholesale_client_store.address_line1 && (
                  <Typography variant="body2">
                    {order.wholesale_client_store.address_line1}
                  </Typography>
                )}
                {order.wholesale_client_store.address_line2 && (
                  <Typography variant="body2">
                    {order.wholesale_client_store.address_line2}
                  </Typography>
                )}
                {(order.wholesale_client_store.city || order.wholesale_client_store.postcode) && (
                  <Typography variant="body2">
                    {[order.wholesale_client_store.city, order.wholesale_client_store.postcode].filter(Boolean).join(' ')}
                  </Typography>
                )}
              </Box>
            ) : (
              <Box sx={{ display: 'flex', flexDirection: 'column' }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Typography variant="body2">
                    {t('wholesaleOrderDetail:companyAddress')}
                  </Typography>
                  {!orderCompleted && (
                    <EditIcon
                      sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                      onClick={() => {
                        setOtherAddressStoreId(null);
                        setShippingStoreIdDraft('');
                        setShippingNameDraft('');
                        setShippingAddress1Draft(order.wholesale_client?.address_line1 ?? '');
                        setShippingAddress2Draft(order.wholesale_client?.address_line2 ?? '');
                        setShippingCityDraft(''); // company has no city field in model
                        setShippingPostcodeDraft(order.wholesale_client?.postcode ?? '');
                        setShippingDialogOpen(true);
                      }}
                    />
                  )}
                </Box>
                {order.wholesale_client?.address_line1 && (
                  <Typography variant="body2">
                    {order.wholesale_client.address_line1}
                  </Typography>
                )}
                {order.wholesale_client?.address_line2 && (
                  <Typography variant="body2">
                    {order.wholesale_client.address_line2}
                  </Typography>
                )}
                {order.wholesale_client?.postcode && (
                  <Typography variant="body2">
                    {order.wholesale_client.postcode}
                  </Typography>
                )}
              </Box>
            )}

            <Typography variant="body2" color="text.secondary">
              {t('wholesaleOrderDetail:poNumberChannel')}
            </Typography>
            <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 1, flexWrap: 'wrap' }}>
              <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
                {order.po_number || '-'} ·{' '}
                {order.order_channel ? orderChannelDisplayLabel(order.order_channel) : '-'}
              </Typography>
              {!orderCompleted && (
                <EditIcon
                  sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                  onClick={openPOChannelDialog}
                />
              )}
            </Box>

            <Typography variant="body2" color="text.secondary">
              {t('wholesaleOrderDetail:ocNumber')}
            </Typography>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              {editingRefNo && !orderCompleted ? (
                <>
                  <TextField
                    size="small"
                    value={refNoDraft}
                    onChange={(e) => setRefNoDraft(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') saveRefNo();
                      if (e.key === 'Escape') setEditingRefNo(false);
                    }}
                    autoFocus
                    sx={{ width: { xs: '100%', sm: 200 }, maxWidth: '100%' }}
                  />
                  <Button size="small" onClick={saveRefNo}>
                    {t('wholesaleOrderDetail:save')}
                  </Button>
                  <Button size="small" onClick={() => setEditingRefNo(false)}>
                    {t('wholesaleOrderDetail:cancel')}
                  </Button>
                </>
              ) : (
                <>
                  <Typography variant="body2">{order.ref_no || '-'}</Typography>
                  {!orderCompleted && (
                    <EditIcon
                      sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                      onClick={() => {
                        setRefNoDraft(order.ref_no || '');
                        setEditingRefNo(true);
                      }}
                    />
                  )}
                </>
              )}
            </Box>
          </Box>
          {order.notes && (
            <Typography sx={{ mt: 1.5 }} variant="body2">
              {t('wholesaleOrderDetail:notes')}: {order.notes}
            </Typography>
          )}
          {order.rejection_reason && (
            <Typography sx={{ mt: 1.5 }} color="error" variant="body2">
              {t('wholesaleOrderDetail:rejection')}: {order.rejection_reason}
            </Typography>
          )}
        </Paper>

        <Paper
          sx={{
            p: { xs: 2, md: 3 },
            border: poAttachmentsEditable ? '2px dashed' : '1px solid',
            borderColor: poAttachmentsEditable && poDropActive ? 'primary.main' : 'divider',
            bgcolor: poAttachmentsEditable && poDropActive ? 'action.hover' : 'transparent',
            borderRadius: 2,
            transition: 'border-color 0.15s ease, background-color 0.15s ease',
          }}
          onDragOver={
            poAttachmentsEditable
              ? (e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  if (!poAttachmentUploading) setPoDropActive(true);
                }
              : undefined
          }
          onDragLeave={
            poAttachmentsEditable
              ? (e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  setPoDropActive(false);
                }
              : undefined
          }
          onDrop={
            poAttachmentsEditable
              ? (e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  setPoDropActive(false);
                  uploadPoFiles(e.dataTransfer.files);
                }
              : undefined
          }
        >
          {(() => {
            const poDocs = order.documents?.filter((d) => d.type === 'po_attachment') ?? [];
            const displayName = (doc: { file_url: string; original_filename?: string }) =>
              doc.original_filename?.trim() || (() => {
                try {
                  const p = new URL(doc.file_url).pathname;
                  return p.split('/').pop() || t('wholesaleOrderDetail:attachment');
                } catch {
                  return t('wholesaleOrderDetail:attachment');
                }
              })();
            return (
              <>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1.5, flexWrap: 'wrap', gap: 1 }}>
                  <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                    {t('wholesaleOrderDetail:poAttachments')} ({poDocs.length}/5)
                  </Typography>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                    {showPoAttachmentsEditButton ? (
                      <Button
                        size="small"
                        startIcon={<EditIcon />}
                        onClick={() => setEditingPoAttachments(true)}
                      >
                        {t('wholesaleOrderDetail:edit')}
                      </Button>
                    ) : null}
                    {editingPoAttachments && stepEndorsed ? (
                      <Button size="small" onClick={() => setEditingPoAttachments(false)}>
                        {t('wholesaleOrderDetail:doneEditingPoAttachments')}
                      </Button>
                    ) : null}
                    {poAttachmentsEditable && poDocs.length > 0 && poDocs.length < 5 ? (
                      <>
                        <Typography variant="body2" color="text.secondary">
                          {t('wholesaleOrderDetail:poAttachmentsHint')}
                        </Typography>
                        <Button
                          variant="outlined"
                          component="label"
                          size="small"
                          startIcon={poAttachmentUploading ? <CircularProgress size={16} /> : <AttachFileIcon />}
                          disabled={poAttachmentUploading}
                        >
                          {poAttachmentUploading ? t('wholesaleOrderDetail:uploading') : t('wholesaleOrderDetail:chooseFiles')}
                          <input
                            accept=".pdf,image/*"
                            type="file"
                            multiple
                            hidden
                            onChange={(e) => {
                              uploadPoFiles(e.target.files);
                              e.target.value = '';
                            }}
                          />
                        </Button>
                      </>
                    ) : null}
                  </Box>
                </Box>
                {poDocs.length > 0 ? (
                  <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))', gap: 1.5, mb: 2 }}>
                    {poDocs.map((doc) => (
                      <AttachmentThumbnail
                        key={doc.id}
                        orderId={order.id}
                        doc={doc}
                        displayName={displayName(doc) || t('wholesaleOrderDetail:attachment')}
                        t={t}
                        onPreview={(url, name) => setFilePreview({ url, name })}
                        onDownload={async () => {
                          try {
                            const blob = await wholesaleOrdersAPI.downloadDocument(order.id, doc.id);
                            const a = document.createElement('a');
                            a.href = URL.createObjectURL(blob);
                            a.download = displayName(doc) || t('wholesaleOrderDetail:attachment');
                            a.click();
                            URL.revokeObjectURL(a.href);
                          } catch (e: any) {
                            enqueueSnackbar(e?.response?.data?.error || e?.message || 'Download failed', { variant: 'error' });
                          }
                        }}
                        onDelete={async () => {
                          if (!order) return;
                          setPoAttachmentDeletingId(doc.id);
                          try {
                            await wholesaleOrdersAPI.deletePoAttachment(order.id, doc.id, {
                              unlock_after_completion: shouldSendUploadUnlockFlag(order, orderLockUnlocked),
                            });
                            const updated = await wholesaleOrdersAPI.get(order.id);
                            setOrder(updated);
                            enqueueSnackbar('Attachment removed', { variant: 'success' });
                          } catch (e: any) {
                            enqueueSnackbar(e.response?.data?.error || 'Failed to remove attachment', { variant: 'error' });
                          } finally {
                            setPoAttachmentDeletingId(null);
                          }
                        }}
                        deleting={poAttachmentDeletingId === doc.id}
                        canDelete={poAttachmentsEditable}
                        downloadLabel={t('wholesaleOrderDetail:download')}
                      />
                    ))}
                  </Box>
                ) : poDocs.length >= 5 ? (
                  <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                    {t('wholesaleOrderDetail:maxPoAttachmentsReached')}
                  </Typography>
                ) : poAttachmentsEditable ? (
                  <>
                    <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>
                      {t('wholesaleOrderDetail:poAttachmentsHint')}
                    </Typography>
                    <Box sx={{ py: 2, px: 2, textAlign: 'center' }}>
                      <input
                        accept=".pdf,image/*"
                        id="po-attachment-detail-input"
                        type="file"
                        multiple
                        style={{ display: 'none' }}
                        onChange={(e) => {
                          uploadPoFiles(e.target.files);
                          e.target.value = '';
                        }}
                      />
                      <label htmlFor="po-attachment-detail-input" style={{ cursor: poAttachmentUploading ? 'default' : 'pointer' }}>
                        <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                          {poDropActive ? t('wholesaleOrderDetail:dropFilesHere') : t('wholesaleOrderDetail:dragDropOrChoose')}
                        </Typography>
                        <Button
                          variant="outlined"
                          component="span"
                          size="small"
                          startIcon={poAttachmentUploading ? <CircularProgress size={16} /> : <AttachFileIcon />}
                          disabled={poAttachmentUploading}
                        >
                          {poAttachmentUploading ? t('wholesaleOrderDetail:uploading') : t('wholesaleOrderDetail:chooseFiles')}
                        </Button>
                      </label>
                    </Box>
                  </>
                ) : (
                  <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                    {t('wholesaleOrderDetail:poAttachmentsLockedHint')}
                  </Typography>
                )}
              </>
            );
          })()}
        </Paper>

      {order.items?.length ? (
        <Paper sx={{ p: { xs: 2, sm: 3, md: 6 }, mb: 3, gridColumn: { xs: '1', md: '1' }, minWidth: 0, width: '100%' }}>
          <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 2 }}>
            {t('wholesaleOrderDetail:orderEntries')}
          </Typography>
          {isShipmentsMobile ? (
            <Stack spacing={1.5}>
              {order.items.map((it) => {
                const beforeDiscount = it.unit_price * it.quantity;
                const discountAmt = it.line_discount_amount ?? 0;
                const discountRate = beforeDiscount > 0 ? (discountAmt / beforeDiscount) * 100 : 0;
                const isEditingPrice = editingPriceItemId === it.id;
                const isEditingDiscount = editingDiscountItemId === it.id;
                const pname = productDisplayName(it.product, lang) || `Product #${it.product_id}`;
                return (
                  <Paper key={it.id} variant="outlined" sx={{ p: 1.5, overflow: 'hidden' }}>
                    <Stack direction="row" spacing={1.25} alignItems="flex-start">
                      <Box sx={{ flexShrink: 0 }}>
                        <ProductImageWithPopover imageUrl={it.product?.image_url} productName={pname} size={48} />
                      </Box>
                      <Box sx={{ flex: 1, minWidth: 0 }}>
                        <Typography variant="body2" sx={{ fontWeight: 600, mb: 1, lineHeight: 1.35, wordBreak: 'break-word' }}>
                          {pname}
                        </Typography>
                        <Stack spacing={0.75}>
                          <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 1, alignItems: 'baseline' }}>
                            <Typography variant="caption" color="text.secondary">{t('wholesaleOrderDetail:qty')}</Typography>
                            <Typography variant="body2">{it.quantity}</Typography>
                          </Box>
                          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 1, flexWrap: 'wrap' }}>
                            <Typography variant="caption" color="text.secondary" sx={{ pt: 0.25 }}>
                              {t('wholesaleOrderDetail:unitPrice')}
                            </Typography>
                            <Box sx={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'flex-end' }}>
                              {isEditingPrice && !orderCompleted ? (
                                <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 0.75, width: '100%', maxWidth: 240 }}>
                                  <TextField
                                    size="small"
                                    type="number"
                                    value={editingItemPrice}
                                    onChange={(e) => setEditingItemPrice(e.target.value)}
                                    onKeyDown={(e) => {
                                      if (e.key === 'Enter') saveItemPrice(it.id);
                                      if (e.key === 'Escape') setEditingPriceItemId(null);
                                    }}
                                    autoFocus
                                    fullWidth
                                    inputProps={{ step: '0.01', min: 0 }}
                                  />
                                  <Button size="small" onClick={() => saveItemPrice(it.id)}>{t('wholesaleOrderDetail:ok')}</Button>
                                </Box>
                              ) : (
                                <Box
                                  sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5, cursor: orderCompleted ? 'default' : 'pointer' }}
                                  onClick={orderCompleted ? undefined : () => {
                                    setEditingDiscountItemId(null);
                                    setEditingItemDiscount('');
                                    setEditingPriceItemId(it.id);
                                    setEditingItemPrice(it.unit_price.toFixed(2));
                                  }}
                                >
                                  £{it.unit_price.toFixed(2)}
                                  {!orderCompleted && <EditIcon sx={{ fontSize: 13, color: 'text.secondary' }} />}
                                </Box>
                              )}
                            </Box>
                          </Box>
                          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 1, flexWrap: 'wrap' }}>
                            <Typography variant="caption" color="text.secondary" sx={{ pt: 0.25 }}>
                              {t('wholesaleOrderDetail:discount')}
                            </Typography>
                            <Box sx={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'flex-end' }}>
                              {isEditingDiscount && !orderCompleted ? (
                                <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 0.75, width: '100%', maxWidth: 240 }}>
                                  <TextField
                                    size="small"
                                    type="number"
                                    value={editingItemDiscount}
                                    onChange={(e) => setEditingItemDiscount(e.target.value)}
                                    onKeyDown={(e) => {
                                      if (e.key === 'Enter') saveItemDiscount(it.id);
                                      if (e.key === 'Escape') {
                                        setEditingDiscountItemId(null);
                                        setEditingItemDiscount('');
                                      }
                                    }}
                                    autoFocus
                                    fullWidth
                                    inputProps={{ step: '0.01', min: 0 }}
                                  />
                                  <Button size="small" onClick={() => saveItemDiscount(it.id)}>{t('wholesaleOrderDetail:ok')}</Button>
                                </Box>
                              ) : (
                                <Box
                                  sx={{
                                    display: 'inline-flex',
                                    alignItems: 'center',
                                    gap: 0.5,
                                    cursor: orderCompleted ? 'default' : 'pointer',
                                    textAlign: 'right',
                                    flexWrap: 'wrap',
                                    justifyContent: 'flex-end',
                                  }}
                                  onClick={orderCompleted ? undefined : () => {
                                    setEditingPriceItemId(null);
                                    setEditingItemPrice('');
                                    setEditingDiscountItemId(it.id);
                                    setEditingItemDiscount(discountAmt > 0 ? discountAmt.toFixed(2) : '0.00');
                                  }}
                                >
                                  {discountAmt > 0
                                    ? `£${discountAmt.toFixed(2)} (${discountRate.toFixed(0)}%)`
                                    : '—'}
                                  {!orderCompleted && <EditIcon sx={{ fontSize: 13, color: 'text.secondary' }} />}
                                </Box>
                              )}
                            </Box>
                          </Box>
                          <Divider />
                          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 1 }}>
                            <Typography variant="body2" sx={{ fontWeight: 700 }}>
                              {t('wholesaleOrderDetail:total')}
                            </Typography>
                            <Typography variant="body2" sx={{ fontWeight: 700 }}>£{it.line_total.toFixed(2)}</Typography>
                          </Box>
                        </Stack>
                      </Box>
                    </Stack>
                  </Paper>
                );
              })}
            </Stack>
          ) : (
            <Table size="small" sx={{ tableLayout: 'fixed', width: '100%', minWidth: 0 }}>
              <TableHead>
                <TableRow>
                  <TableCell sx={{ width: 52 }}></TableCell>
                  <TableCell sx={{ width: '40%' }}>{t('wholesaleOrderDetail:product')}</TableCell>
                  <TableCell align="right" sx={{ width: '10%' }}>{t('wholesaleOrderDetail:qty')}</TableCell>
                  <TableCell align="right" sx={{ width: '15%' }}>{t('wholesaleOrderDetail:unitPrice')}</TableCell>
                  <TableCell align="right" sx={{ width: '15%' }}>{t('wholesaleOrderDetail:discount')}</TableCell>
                  <TableCell align="right" sx={{ width: '20%' }}>{t('wholesaleOrderDetail:total')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {order.items.map((it) => {
                  const beforeDiscount = it.unit_price * it.quantity;
                  const discountAmt = it.line_discount_amount ?? 0;
                  const discountRate = beforeDiscount > 0 ? (discountAmt / beforeDiscount) * 100 : 0;
                  const isEditingPrice = editingPriceItemId === it.id;
                  const isEditingDiscount = editingDiscountItemId === it.id;
                  return (
                    <TableRow key={it.id}>
                      <TableCell sx={{ verticalAlign: 'middle' }}>
                        <ProductImageWithPopover imageUrl={it.product?.image_url} productName={productDisplayName(it.product, lang)} size={40} />
                      </TableCell>
                      <TableCell>{productDisplayName(it.product, lang) || `Product #${it.product_id}`}</TableCell>
                      <TableCell align="right">{it.quantity}</TableCell>
                      <TableCell align="right">
                        {isEditingPrice && !orderCompleted ? (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, justifyContent: 'flex-end' }}>
                            <TextField
                              size="small"
                              type="number"
                              value={editingItemPrice}
                              onChange={(e) => setEditingItemPrice(e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') saveItemPrice(it.id);
                                if (e.key === 'Escape') setEditingPriceItemId(null);
                              }}
                              autoFocus
                              sx={{ width: 90 }}
                              inputProps={{ step: '0.01', min: 0 }}
                            />
                            <Button size="small" onClick={() => saveItemPrice(it.id)}>{t('wholesaleOrderDetail:ok')}</Button>
                          </Box>
                        ) : (
                          <Box
                            sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5, cursor: orderCompleted ? 'default' : 'pointer' }}
                            onClick={orderCompleted ? undefined : () => {
                              setEditingDiscountItemId(null);
                              setEditingItemDiscount('');
                              setEditingPriceItemId(it.id);
                              setEditingItemPrice(it.unit_price.toFixed(2));
                            }}
                          >
                            £{it.unit_price.toFixed(2)}
                            {!orderCompleted && <EditIcon sx={{ fontSize: 13, color: 'text.secondary' }} />}
                          </Box>
                        )}
                      </TableCell>
                      <TableCell align="right">
                        {isEditingDiscount && !orderCompleted ? (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, justifyContent: 'flex-end' }}>
                            <TextField
                              size="small"
                              type="number"
                              value={editingItemDiscount}
                              onChange={(e) => setEditingItemDiscount(e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') saveItemDiscount(it.id);
                                if (e.key === 'Escape') {
                                  setEditingDiscountItemId(null);
                                  setEditingItemDiscount('');
                                }
                              }}
                              autoFocus
                              sx={{ width: 90 }}
                              inputProps={{ step: '0.01', min: 0 }}
                            />
                            <Button size="small" onClick={() => saveItemDiscount(it.id)}>{t('wholesaleOrderDetail:ok')}</Button>
                          </Box>
                        ) : (
                          <Box
                            sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5, cursor: orderCompleted ? 'default' : 'pointer' }}
                            onClick={orderCompleted ? undefined : () => {
                              setEditingPriceItemId(null);
                              setEditingItemPrice('');
                              setEditingDiscountItemId(it.id);
                              setEditingItemDiscount(discountAmt > 0 ? discountAmt.toFixed(2) : '0.00');
                            }}
                          >
                            {discountAmt > 0
                              ? `£${discountAmt.toFixed(2)} (${discountRate.toFixed(0)}%)`
                              : '—'}
                            {!orderCompleted && <EditIcon sx={{ fontSize: 13, color: 'text.secondary' }} />}
                          </Box>
                        )}
                      </TableCell>
                      <TableCell align="right">£{it.line_total.toFixed(2)}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
          <Box sx={{ mt: 2, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 0.5 }}>
            <Typography variant="body2" color="text.secondary">
              {t('wholesaleOrderDetail:subtotal')}: £{(order.subtotal ?? order.items.reduce((s: number, it: any) => s + it.unit_price * it.quantity, 0)).toFixed(2)}
            </Typography>
            {(order.discount_amount ?? 0) > 0 && (
              <Typography variant="body2" color="text.secondary">
                {t('wholesaleOrderDetail:discount')}: £{(order.discount_amount ?? 0).toFixed(2)}
              </Typography>
            )}
            <Typography fontWeight="bold">{t('wholesaleOrderDetail:total')}: £{totalForOrder(order).toFixed(2)}</Typography>
          </Box>
        </Paper>
      ) : null}
      {order.status === 'rejected' && (
        <Paper sx={{ p: 3, mb: 3 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>{t('wholesaleOrderDetail:resubmitHint')}</Typography>
          <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
            <Button variant="contained" color="primary" startIcon={<CompleteIcon />} onClick={handleResubmit} disabled={actioning}>
              {t('wholesaleOrderDetail:resubmitForApproval')}
            </Button>
          </Box>
        </Paper>
      )}
      {canAssign && (showAssignmentPanel || (allocationConfirmed && !showAssignment)) && (
        <Paper ref={assignSectionRef} sx={actionSectionPaperSx('assign', { p: { xs: 2, md: 3 }, mb: 3, minWidth: 0, overflow: 'hidden' })}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2, flexWrap: 'wrap' }}>
            <Typography variant="subtitle1" component="span">
              {t('wholesaleOrderDetail:orderConfirmationSection')}
            </Typography>
            {showAssignmentPanel ? <AssignmentHowToTooltipIcon t={t} /> : null}
            {renderActionNeededChip('assign')}
          </Box>
          {showAssignmentPanel ? (
            <>
              <WholesaleOrderAssignmentBoard
                order={order}
                stores={stores}
                staged={usesStagedAssignment ? stagedManualAssignments : []}
                manualMode={usesStagedAssignment}
                lang={lang}
                actioning={actioning}
                allLinesAssigned={allLinesAssignedForConfirm}
                pendingQtyForItem={pendingQtyForItem}
                onAssignItem={assignItemToStoreDirect}
                onUnassignItem={handleUnassignAssignment}
                onMoveItem={moveAssignmentItem}
                onAssignByDefaults={handleAssignByDefaults}
                onConfirmAllocation={handleConfirmAllocation}
                onBlockAssignmentTarget={() =>
                  enqueueSnackbar(t('wholesaleOrderDetail:assignBlockedCompletedShipment'), { variant: 'warning' })
                }
                t={t}
              />
            </>
          ) : (
            <Box>
              <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
                {t('wholesaleOrderDetail:allLinesAssignedSummary')}
              </Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {t('wholesaleOrderDetail:assignReassignHint')}
              </Typography>
            </Box>
          )}
        </Paper>
      )}

      {showOrderConfirmationEmailSectionVisible && (
        <Paper
          ref={orderConfirmEmailSectionRef}
          sx={actionSectionPaperSx(
            'orderConfirmEmail',
            { p: { xs: 2, md: 2.5 }, mb: 1.5 },
            { pending: orderConfirmEmailSectionPending },
          )}
        >
          <PipelineSectionPendingContent
            pending={orderConfirmEmailSectionPending}
            title={
              <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 1.5 }}>
                <EmailIcon
                  color={
                    orderConfirmEmailSectionPending
                      ? 'disabled'
                      : orderConfirmEmailSent
                        ? 'success'
                        : orderConfirmEmailSkipped
                          ? 'disabled'
                          : 'action'
                  }
                  sx={{ mt: 0.25 }}
                />
                <Typography
                  variant="subtitle2"
                  sx={{ fontWeight: 600 }}
                  component="span"
                  display="inline-flex"
                  alignItems="center"
                  flexWrap="wrap"
                >
                  {t('wholesaleOrderDetail:emailOrderConfirmTitle')}
                  {renderActionNeededChip('orderConfirmEmail', orderConfirmEmailSectionPending)}
                </Typography>
              </Box>
            }
          >
          <Box sx={pipelineEmailSectionLayoutSx}>
            <Box sx={{ minWidth: 0, flex: 1, width: { xs: '100%', sm: 'auto' } }}>
                {orderConfirmEmailSent && !orderConfirmEmailSkipped && orderConfirmSentAtDisplay && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailStatusSentAt', {
                      date: format(new Date(orderConfirmSentAtDisplay), 'dd MMM yyyy HH:mm'),
                    })}
                  </Typography>
                )}
                {orderConfirmEmailSkipped && orderConfirmSkippedAtDisplay && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailStatusSkippedAt', {
                      date: format(new Date(orderConfirmSkippedAtDisplay), 'dd MMM yyyy HH:mm'),
                    })}
                  </Typography>
                )}
                {orderConfirmEmailSent && orderConfirmRecipient ? (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:invoiceSentReceiver', { receiver: orderConfirmRecipient })}
                  </Typography>
                ) : null}
                {orderConfirmEmailSkipped && orderConfirmSkippedBy ? (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailSkippedBy', { name: orderConfirmSkippedBy })}
                  </Typography>
                ) : null}
                {orderConfirmEmailSkipped && orderConfirmSkipRemark ? (
                  <Typography variant="body2" color="text.secondary" sx={{ fontStyle: 'italic' }}>
                    {t('wholesaleOrderDetail:emailSkipRemark', { remark: orderConfirmSkipRemark })}
                  </Typography>
                ) : null}
                {!orderConfirmEmailDone && (
                  <Typography variant="body2" color="text.secondary">
                    {!allocationConfirmed
                      ? t('wholesaleOrderDetail:emailSendOrderConfirmAwaitingConfirmation')
                      : !orderHasOrderConfirmationDocument(order)
                        ? t('wholesaleOrderDetail:emailSendOrderConfirmNeedsOc')
                        : t('wholesaleOrderDetail:emailSendOrderConfirmHint')}
                  </Typography>
                )}
            </Box>
            <Box sx={pipelineEmailActionsSx}>
              {!orderConfirmEmailDone && (
                <Button
                  size="small"
                  variant="outlined"
                  onClick={handleSkipOrderConfirmEmail}
                  disabled={actioning}
                >
                  {t('wholesaleOrderDetail:emailPromptSkip')}
                </Button>
              )}
              <Tooltip
                title={
                  !canSendOrderConfirmEmail && !orderConfirmEmailDone
                    ? !allocationConfirmed
                      ? t('wholesaleOrderDetail:emailSendOrderConfirmAwaitingConfirmation')
                      : !orderHasOrderConfirmationDocument(order)
                        ? t('wholesaleOrderDetail:emailSendOrderConfirmNeedsOc')
                        : ''
                    : ''
                }
              >
                <span>
                  <Button
                    size="small"
                    variant={orderConfirmEmailDone ? 'outlined' : 'contained'}
                    startIcon={<EmailIcon />}
                    onClick={() => openEmailForKind('order_confirm')}
                    disabled={!canSendOrderConfirmEmail && !orderConfirmEmailDone}
                  >
                    {orderConfirmEmailDone
                      ? t('wholesaleOrderDetail:emailResendOrderConfirm')
                      : t('wholesaleOrderDetail:emailSendOrderConfirm')}
                  </Button>
                </span>
              </Tooltip>
            </Box>
          </Box>
          </PipelineSectionPendingContent>
        </Paper>
      )}

      {shipmentsFullscreen && (
        <Box sx={{ minHeight: { xs: 220, sm: 260 }, visibility: 'hidden' }} aria-hidden />
      )}

      {showShipmentsSectionVisible && (
        <Portal disablePortal={!shipmentsFullscreen}>
        <Box
          sx={{
            minWidth: 0,
            ...(shipmentsFullscreen && {
              position: 'fixed',
              inset: 0,
              zIndex: theme.zIndex.modal,
              bgcolor: 'background.default',
              overflow: 'auto',
              p: { xs: 1.5, sm: 2, md: 3 },
              '@keyframes shipmentsFullscreenIn': {
                from: { opacity: 0, transform: 'scale(0.96)' },
                to: { opacity: 1, transform: 'scale(1)' },
              },
              animation: 'shipmentsFullscreenIn 0.32s ease-out',
            }),
          }}
        >
          <Paper
            sx={actionSectionPaperSx('shipments', {
              position: 'relative',
              p: { xs: 2, md: 3 },
              mb:
                shipmentsFullscreen
                  ? 0
                  : showDeliveryCompleteEmailSectionVisible || showInvoiceEmailSectionVisible || showPaymentProofSectionVisible
                    ? 1.5
                    : 3,
              minWidth: 0,
              overflow: 'hidden',
              ...(shipmentsFullscreen && {
                boxShadow: theme.shadows[2],
                height: '100%',
                display: 'flex',
                flexDirection: 'column',
              }),
            }, { pending: shipmentsSectionPending })}
          >
          <PipelineSectionPendingContent
            pending={shipmentsSectionPending}
            title={
              <Typography variant="subtitle1" display="flex" alignItems="center" gap={1} flexWrap="wrap" sx={{ fontWeight: 600 }}>
                <ShipmentIcon fontSize="small" /> {t('wholesaleOrderDetail:shipments')}
                {renderActionNeededChip('shipments', shipmentsSectionPending)}
              </Typography>
            }
          >
          <Tooltip
            title={
              shipmentsFullscreen
                ? t('wholesaleOrderDetail:shipmentsCompactTable')
                : t('wholesaleOrderDetail:shipmentsFullTable')
            }
          >
            <IconButton
              size="small"
              onClick={() => setShipmentsFullscreen((v) => !v)}
              aria-label={
                shipmentsFullscreen
                  ? t('wholesaleOrderDetail:shipmentsCompactTable')
                  : t('wholesaleOrderDetail:shipmentsFullTable')
              }
              sx={{
                position: 'absolute',
                top: { xs: 8, md: 12 },
                right: { xs: 8, md: 12 },
                zIndex: 1,
                border: '1px solid',
                borderColor: 'divider',
                borderRadius: 1,
                bgcolor: 'background.paper',
              }}
            >
              {shipmentsFullscreen ? (
                <CloseFullscreenIcon fontSize="small" />
              ) : (
                <OpenInFullIcon fontSize="small" />
              )}
            </IconButton>
          </Tooltip>
          <Box
            sx={{
              display: 'flex',
              flexWrap: 'wrap',
              gap: 1,
              alignItems: 'center',
              justifyContent: { xs: 'flex-start', sm: 'flex-end' },
              mb: 2,
              pr: { xs: 5, sm: 5 },
              flexDirection: { xs: 'column', sm: 'row' },
              '& .MuiButton-root': { width: { xs: '100%', sm: 'auto' } },
            }}
          >
            {canChangeAssignment && (
                <Button
                  variant="outlined"
                  size="small"
                  onClick={() => {
                    setShowAssignment(true);
                    setAllocationConfirmed(false);
                  }}
                >
                  {t('wholesaleOrderDetail:changeAssignment')}
                </Button>
              )}
              {canForceMoveToPendingPayment && (
                <Button
                  size="small"
                  variant="contained"
                  color="error"
                  startIcon={<CompleteIcon sx={{ fontSize: 16 }} />}
                  onClick={async () => {
                    if (!order) return;
                    if (window.confirm(t('wholesaleOrderDetail:forceMoveToPendingPaymentConfirm'))) {
                      try {
                        const _ = await wholesaleOrdersAPI.completeAssignment(order.id);
                        const freshOrder = await wholesaleOrdersAPI.get(order.id);
                        setOrder(freshOrder);
                        enqueueSnackbar('Order moved to pending payment', { variant: 'success' });
                      } catch (e: any) {
                        enqueueSnackbar(e.response?.data?.error || 'Failed to move order', { variant: 'error' });
                      }
                    }
                  }}
                >
                  {t('wholesaleOrderDetail:forceMoveToPendingPayment')}
                </Button>
              )}
          </Box>
          {isShipmentsMobile && !shipmentsFullscreen ? (
            <Stack spacing={1.5} sx={{ width: '100%', minWidth: 0 }}>
              {(order.shipments ?? []).map((s) => (
                <Paper key={s.id} variant="outlined" sx={{ p: 1.5, overflow: 'hidden' }}>
                  <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1, wordBreak: 'break-word' }}>
                    {s.store?.name ?? `Store #${s.store_id}`}
                  </Typography>
                  <Stack spacing={1.25}>
                    <Box>
                      <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.25 }}>
                        {t('wholesaleOrderDetail:product')}
                      </Typography>
                      {renderShipmentItemsSummary(s)}
                      <Collapse in={expandedShipmentIds.has(s.id)} timeout="auto" unmountOnExit>
                        <Box sx={{ mt: 1 }}>{renderShipmentItemsDetail(s)}</Box>
                      </Collapse>
                    </Box>
                    <Box>
                      <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.25 }}>
                        {t('wholesaleOrderDetail:status')}
                      </Typography>
                      <Chip size="small" label={shipmentStatusLabel(s.status, t)} color={shipmentStatusChipColor(s.status)} />
                    </Box>
                    <Box>
                      <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.25 }}>
                        {t('wholesaleOrderDetail:deliveryProof')}
                      </Typography>
                      {shipmentDeliveryProofCell(s)}
                    </Box>
                    <Box>
                      <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.25 }}>
                        {t('wholesaleOrderDetail:deliveryNote')}
                      </Typography>
                      {shipmentDeliveryNoteCell(s)}
                    </Box>
                    <Box>
                      <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.5 }}>
                        {t('wholesaleOrderDetail:actions')}
                      </Typography>
                      <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 0.75 }}>
                        {shipmentRowActions(s)}
                      </Box>
                    </Box>
                  </Stack>
                </Paper>
              ))}
            </Stack>
          ) : (
          <TableContainer sx={{ width: '100%', overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
            <Table size="small" sx={{ tableLayout: shipmentsFullscreen ? 'auto' : 'fixed', width: '100%', minWidth: shipmentsFullscreen ? 1080 : isShipmentsMobile ? 720 : undefined }}>
              <TableHead>
                <TableRow sx={{ '& .MuiTableCell-head': { verticalAlign: 'middle', whiteSpace: 'nowrap' } }}>
                  <TableCell sx={{ width: shipmentsFullscreen ? undefined : '15%' }}>{t('wholesaleOrderDetail:store')}</TableCell>
                  <TableCell sx={{ width: shipmentsFullscreen ? undefined : '24%' }}>{t('wholesaleOrderDetail:product')}</TableCell>
                  <TableCell sx={{ width: shipmentsFullscreen ? undefined : '12%' }}>{t('wholesaleOrderDetail:status')}</TableCell>
                  <TableCell sx={{ width: shipmentsFullscreen ? undefined : '15%' }}>{t('wholesaleOrderDetail:deliveryProof')}</TableCell>
                  <TableCell sx={{ width: shipmentsFullscreen ? undefined : '15%' }}>{t('wholesaleOrderDetail:deliveryNote')}</TableCell>
                  {shipmentsFullscreen ? (
                    <>
                      <TableCell>{t('wholesaleOrderDetail:courier')}</TableCell>
                      <TableCell>{t('wholesaleOrderDetail:trackingNumber')}</TableCell>
                      <TableCell align="right">{t('wholesaleOrderDetail:numberOfCase')}</TableCell>
                    </>
                  ) : null}
                  <TableCell align="right" sx={{ width: shipmentsFullscreen ? undefined : '19%' }}>
                    {t('wholesaleOrderDetail:actions')}
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {(order.shipments ?? []).map((s) => {
                  const totalCase =
                    s.items?.reduce((sum, it) => sum + (typeof it.case_qty === 'number' ? it.case_qty : 0), 0) ?? 0;
                  const expanded = expandedShipmentIds.has(s.id);
                  const shipmentColSpan = shipmentsFullscreen ? 9 : 6;
                  return (
                    <Fragment key={s.id}>
                      <TableRow hover>
                        <TableCell sx={{ wordBreak: 'break-word', verticalAlign: 'top' }}>
                          {s.store?.name ?? `Store #${s.store_id}`}
                        </TableCell>
                        <TableCell sx={{ verticalAlign: 'top' }}>{renderShipmentItemsSummary(s)}</TableCell>
                        <TableCell sx={{ verticalAlign: 'top' }}>
                          <Chip size="small" label={shipmentStatusLabel(s.status, t)} color={shipmentStatusChipColor(s.status)} />
                        </TableCell>
                        <TableCell sx={{ verticalAlign: 'top' }}>{shipmentDeliveryProofCell(s)}</TableCell>
                        <TableCell sx={{ verticalAlign: 'top' }}>{shipmentDeliveryNoteCell(s)}</TableCell>
                        {shipmentsFullscreen ? (
                          <>
                            <TableCell sx={{ whiteSpace: 'nowrap', verticalAlign: 'top' }}>{s.courier || '—'}</TableCell>
                            <TableCell sx={{ maxWidth: 140, wordBreak: 'break-word', verticalAlign: 'top' }}>
                              {s.tracking_number || '—'}
                            </TableCell>
                            <TableCell align="right" sx={{ verticalAlign: 'top' }}>
                              {totalCase > 0 ? totalCase : '—'}
                            </TableCell>
                          </>
                        ) : null}
                        <TableCell align="right" sx={{ verticalAlign: 'top' }}>
                          <Box
                            sx={{
                              display: 'flex',
                              flexWrap: 'wrap',
                              gap: 0.5,
                              justifyContent: 'flex-end',
                            }}
                          >
                            {shipmentRowActions(s)}
                          </Box>
                        </TableCell>
                      </TableRow>
                      {shipmentsFullscreen ? (
                        <TableRow key={`${s.id}-items`}>
                          <TableCell
                            colSpan={shipmentColSpan}
                            sx={{ py: 0, px: 2, borderBottom: expanded ? undefined : 'none' }}
                          >
                            <Collapse in={expanded} timeout="auto" unmountOnExit>
                              <Box sx={{ py: 1.5, pl: 3.5 }}>{renderShipmentItemsDetail(s)}</Box>
                            </Collapse>
                          </TableCell>
                        </TableRow>
                      ) : null}
                    </Fragment>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
          )}
          </PipelineSectionPendingContent>
          </Paper>
        </Box>
        </Portal>
      )}

      {showDeliveryCompleteEmailSectionVisible && !shipmentsFullscreen && (
        <Paper
          sx={actionSectionPaperSx('deliveryCompleteEmail', {
            p: { xs: 2, md: 2.5 },
            mb: showInvoiceEmailSectionVisible || showPaymentProofSectionVisible ? 1.5 : 3,
          }, { pending: deliveryCompleteEmailSectionPending })}
        >
          <PipelineSectionPendingContent
            pending={deliveryCompleteEmailSectionPending && !shipmentsDeliveredEmailDone}
            title={
              <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 1.5 }}>
                <EmailIcon
                  color={
                    deliveryCompleteEmailSectionPending && !shipmentsDeliveredEmailDone
                      ? 'disabled'
                      : shipmentsDeliveredEmailSent
                        ? 'success'
                        : shipmentsDeliveredEmailSkipped
                          ? 'disabled'
                          : 'action'
                  }
                  sx={{ mt: 0.25 }}
                />
                <Typography
                  variant="subtitle2"
                  sx={{ fontWeight: 600 }}
                  component="span"
                  display="inline-flex"
                  alignItems="center"
                  flexWrap="wrap"
                >
                  {t('wholesaleOrderDetail:emailShipmentsDeliveredTitle')}
                  {renderActionNeededChip('deliveryCompleteEmail', deliveryCompleteEmailSectionPending)}
                </Typography>
              </Box>
            }
          >
          <Box sx={pipelineEmailSectionLayoutSx}>
            <Box sx={{ minWidth: 0, flex: 1, width: { xs: '100%', sm: 'auto' } }}>
                {shipmentsDeliveredEmailSent && !shipmentsDeliveredEmailSkipped && shipmentsDeliveredSentAtDisplay && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailStatusSentAt', {
                      date: format(new Date(shipmentsDeliveredSentAtDisplay), 'dd MMM yyyy HH:mm'),
                    })}
                  </Typography>
                )}
                {shipmentsDeliveredEmailSkipped && shipmentsDeliveredSkippedAtDisplay && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailStatusSkippedAt', {
                      date: format(new Date(shipmentsDeliveredSkippedAtDisplay), 'dd MMM yyyy HH:mm'),
                    })}
                  </Typography>
                )}
                {shipmentsDeliveredEmailSent && shipmentsDeliveredRecipient ? (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:invoiceSentReceiver', { receiver: shipmentsDeliveredRecipient })}
                  </Typography>
                ) : null}
                {shipmentsDeliveredEmailSkipped && shipmentsDeliveredSkippedBy ? (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailSkippedBy', { name: shipmentsDeliveredSkippedBy })}
                  </Typography>
                ) : null}
                {shipmentsDeliveredEmailSkipped && shipmentsDeliveredSkipRemark ? (
                  <Typography variant="body2" color="text.secondary" sx={{ fontStyle: 'italic' }}>
                    {t('wholesaleOrderDetail:emailSkipRemark', { remark: shipmentsDeliveredSkipRemark })}
                  </Typography>
                ) : null}
                {!shipmentsDeliveredEmailDone && (
                  <Typography variant="body2" color="text.secondary">
                    {!canSendShipmentsDeliveredEmail
                      ? t('wholesaleOrderDetail:emailSendDeliveryCompleteAwaitingProof')
                      : t('wholesaleOrderDetail:emailSendDeliveryCompleteHint')}
                  </Typography>
                )}
            </Box>
            <Box sx={pipelineEmailActionsSx}>
              {!shipmentsDeliveredEmailDone && (
                <Button
                  size="small"
                  variant="outlined"
                  onClick={handleSkipShipmentsDeliveredEmail}
                  disabled={actioning}
                >
                  {t('wholesaleOrderDetail:emailPromptSkip')}
                </Button>
              )}
              <Tooltip
                title={
                  !canSendShipmentsDeliveredEmail && !shipmentsDeliveredEmailSent
                    ? t('wholesaleOrderDetail:emailSendDeliveryCompleteAwaitingProof')
                    : ''
                }
              >
                <span>
                  <Button
                    size="small"
                    variant={shipmentsDeliveredEmailDone ? 'outlined' : 'contained'}
                    startIcon={<EmailIcon />}
                    onClick={() => openEmailForKind('shipments_delivered')}
                    disabled={!canSendShipmentsDeliveredEmail && !shipmentsDeliveredEmailSent}
                  >
                    {shipmentsDeliveredEmailDone
                      ? t('wholesaleOrderDetail:emailResendShipmentsDelivered')
                      : t('wholesaleOrderDetail:emailSendShipmentsDelivered')}
                  </Button>
                </span>
              </Tooltip>
            </Box>
          </Box>
          </PipelineSectionPendingContent>
        </Paper>
      )}

      {showInvoiceEmailSectionVisible && (
            <Paper sx={actionSectionPaperSx('invoiceEmail', { p: { xs: 2, md: 2.5 }, mb: showPaymentProofSectionVisible ? 1.5 : 3 }, { pending: invoiceEmailSectionPending })}>
              <PipelineSectionPendingContent
                pending={invoiceEmailSectionPending && !invoiceEmailDone}
                title={
                  <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 1.5 }}>
                    <EmailIcon
                      color={
                        invoiceEmailSectionPending && !invoiceEmailDone
                          ? 'disabled'
                          : invoiceEmailSent
                            ? 'success'
                            : invoiceEmailSkipped
                              ? 'disabled'
                              : 'action'
                      }
                      sx={{ mt: 0.25 }}
                    />
                    <Typography
                      variant="subtitle2"
                      sx={{ fontWeight: 600 }}
                      component="span"
                      display="inline-flex"
                      alignItems="center"
                      flexWrap="wrap"
                    >
                      {t('wholesaleOrderDetail:invoiceSendBanner')}
                      {renderActionNeededChip('invoiceEmail', invoiceEmailSectionPending)}
                    </Typography>
                  </Box>
                }
              >
              <Box sx={pipelineEmailSectionLayoutSx}>
                <Box sx={{ minWidth: 0, flex: 1, width: { xs: '100%', sm: 'auto' } }}>
                    {invoiceEmailSent && !invoiceEmailSkipped && invoiceSentAtDisplay && (
                      <Typography variant="body2" color="text.secondary">
                        {t('wholesaleOrderDetail:emailStatusSentAt', {
                          date: format(new Date(invoiceSentAtDisplay), 'dd MMM yyyy HH:mm'),
                        })}
                      </Typography>
                    )}
                    {invoiceEmailSkipped && invoiceSkippedAtDisplay && (
                      <Typography variant="body2" color="text.secondary">
                        {t('wholesaleOrderDetail:emailStatusSkippedAt', {
                          date: format(new Date(invoiceSkippedAtDisplay), 'dd MMM yyyy HH:mm'),
                        })}
                      </Typography>
                    )}
                    {invoiceEmailSent && invoiceRecipient ? (
                      <Typography variant="body2" color="text.secondary">
                        {t('wholesaleOrderDetail:invoiceSentReceiver', { receiver: invoiceRecipient })}
                      </Typography>
                    ) : null}
                    {invoiceEmailSkipped && invoiceSkippedBy ? (
                      <Typography variant="body2" color="text.secondary">
                        {t('wholesaleOrderDetail:emailSkippedBy', { name: invoiceSkippedBy })}
                      </Typography>
                    ) : null}
                    {invoiceEmailSkipped && invoiceSkipRemark ? (
                      <Typography variant="body2" color="text.secondary" sx={{ fontStyle: 'italic' }}>
                        {t('wholesaleOrderDetail:emailSkipRemark', { remark: invoiceSkipRemark })}
                      </Typography>
                    ) : null}
                    {!invoiceEmailDone && (
                      <Typography variant="body2" color="text.secondary">
                        {t('wholesaleOrderDetail:emailSendInvoiceReadyHint')}
                      </Typography>
                    )}
                </Box>
                <Box sx={pipelineEmailActionsSx}>
                  {!invoiceEmailDone && (
                    <Button
                      size="small"
                      variant="outlined"
                      onClick={handleSkipInvoiceEmail}
                      disabled={actioning}
                    >
                      {t('wholesaleOrderDetail:emailPromptSkip')}
                    </Button>
                  )}
                  <span>
                    <Button
                      size="small"
                      variant={invoiceEmailDone ? 'outlined' : 'contained'}
                      startIcon={<EmailIcon />}
                      onClick={() => openEmailForKind('invoice')}
                      disabled={!invoiceEmailEnabled && !invoiceEmailSent}
                    >
                      {invoiceEmailDone
                        ? t('wholesaleOrderDetail:emailResendInvoice')
                        : t('wholesaleOrderDetail:emailSendInvoice')}
                    </Button>
                  </span>
                </Box>
              </Box>
              </PipelineSectionPendingContent>
            </Paper>
      )}

        {showPaymentProofSectionVisible && (
          <Paper
            sx={actionSectionPaperSx('payment', {
              p: { xs: 2, md: 3 },
              borderRadius: 2,
              mb: 3,
              ...(!paymentProofSectionPending && currentActionSection !== 'payment'
                ? {
                    border: '2px dashed',
                    borderColor: paymentProofDropActive ? 'primary.main' : 'divider',
                    bgcolor: paymentProofDropActive ? 'action.hover' : 'transparent',
                  }
                : {}),
              transition: 'border-color 0.15s ease, background-color 0.15s ease, box-shadow 0.2s ease',
            }, { pending: paymentProofSectionPending })}
            onDragOver={(e) => {
              if (paymentProofSectionPending) return;
              e.preventDefault();
              e.stopPropagation();
              if (!paymentProofUploading) setPaymentProofDropActive(true);
            }}
            onDragLeave={(e) => {
              if (paymentProofSectionPending) return;
              e.preventDefault();
              e.stopPropagation();
              setPaymentProofDropActive(false);
            }}
            onDrop={(e) => {
              if (paymentProofSectionPending) return;
              e.preventDefault();
              e.stopPropagation();
              setPaymentProofDropActive(false);
              openForceConfirmPaymentDialog(order, e.dataTransfer.files);
            }}
          >
            <PipelineSectionPendingContent
              pending={paymentProofSectionPending}
              title={
                <Typography variant="subtitle1" sx={{ fontWeight: 600 }} component="span" display="inline-flex" alignItems="center" flexWrap="wrap">
                  {t('wholesaleOrderDetail:confirmPaymentReceived')}
                  {!paymentProofSectionPending
                    ? ` (${(order.documents?.filter((d) => d.type === 'payment_proof') ?? []).length + (!order.documents?.some((d) => d.type === 'payment_proof') && order.payment_proof_url ? 1 : 0)})`
                    : ''}
                  {renderActionNeededChip('payment', paymentProofSectionPending)}
                </Typography>
              }
            >
            {(() => {
              const proofDocs = order.documents?.filter((d) => d.type === 'payment_proof') ?? [];
              const hasLegacyProof = !proofDocs.length && order.payment_proof_url;
              const proofCount = proofDocs.length + (hasLegacyProof ? 1 : 0);
              const canAddMore = true;
              const hasProofs = proofCount > 0;
              const displayName = (doc: { file_url: string; original_filename?: string }) =>
                doc.original_filename?.trim() || (() => {
                  try {
                    const p = new URL(doc.file_url).pathname;
                    return p.split('/').pop() || t('wholesaleOrderDetail:attachment');
                  } catch {
                    return t('wholesaleOrderDetail:attachment');
                  }
                })();
              const openForceCompleteDialog = () => {
                setForceCompleteHasProof(!!(hasProofs || hasLegacyProof));
                setConfirmOrderNoProofDialogOpen(true);
              };
              const uploadPaymentProofButton = (opts?: { fullWidth?: boolean }) => (
                <Button
                  variant="contained"
                  color="primary"
                  component="label"
                  size="medium"
                  fullWidth={opts?.fullWidth}
                  startIcon={paymentProofUploading ? <CircularProgress size={16} color="inherit" /> : <AttachFileIcon />}
                  disabled={paymentProofUploading}
                >
                  {paymentProofUploading ? t('wholesaleOrderDetail:uploading') : t('wholesaleOrderDetail:uploadPaymentProof')}
                  <input
                    accept=".pdf,image/*"
                    type="file"
                    multiple
                    hidden
                    onChange={(e) => {
                      openForceConfirmPaymentDialog(order, e.target.files);
                      e.target.value = '';
                    }}
                  />
                </Button>
              );
              return (
                <>
                  {!hasProofs && !hasLegacyProof ? (
                    <Box sx={{ py: 1, px: 2, textAlign: 'center' }}>
                      <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>
                        {canShowInvoiceEmailButton
                          ? t('wholesaleOrderDetail:paymentProofAfterInvoiceHint')
                          : t('wholesaleOrderDetail:confirmPaymentReceivedHint')}
                      </Typography>
                      <Box sx={{ display: 'flex', justifyContent: 'center' }}>
                        <Button
                          variant="outlined"
                          color="warning"
                          size="small"
                          disabled={paymentConfirming}
                          onClick={openForceCompleteDialog}
                        >
                          {paymentConfirming ? t('wholesaleOrderDetail:confirming') : t('wholesaleOrderDetail:forceComplete')}
                        </Button>
                      </Box>
                    </Box>
                  ) : (
                    <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 1, flexWrap: 'wrap', mb: 1.5 }}>
                      <Button
                        variant="outlined"
                        color="warning"
                        size="small"
                        disabled={paymentConfirming}
                        onClick={openForceCompleteDialog}
                      >
                        {paymentConfirming ? t('wholesaleOrderDetail:confirming') : t('wholesaleOrderDetail:forceComplete')}
                      </Button>
                    </Box>
                  )}
                  {proofDocs.length > 0 ? (
                    <PaymentProofDocsList
                      isMobile={isShipmentsMobile}
                      proofDocs={proofDocs}
                      orderId={order.id}
                      canDeletePaymentProof={canDeletePaymentProof}
                      unlockAfterCompletion={paymentProofUnlockUpload}
                      metaByDocId={paymentProofMetaByDocId}
                      totalProofAmount={totalProofAmount}
                      pendingAmount={pendingAmount}
                      displayNameFor={displayName}
                      t={t}
                      enqueueSnackbar={enqueueSnackbar}
                      paymentProofDeletingId={paymentProofDeletingId}
                      setPaymentProofDeletingId={setPaymentProofDeletingId}
                      onOrderRefresh={setOrder}
                    />
                  ) : null}
                  {hasLegacyProof && (
                    <Box sx={{ mb: 2 }}>
                      <Box
                        sx={{
                          width: 112,
                          height: 112,
                          border: '1px solid',
                          borderColor: 'divider',
                          borderRadius: 2,
                          display: 'flex',
                          flexDirection: 'column',
                          alignItems: 'center',
                          justifyContent: 'center',
                          cursor: 'pointer',
                          bgcolor: 'grey.50',
                          '&:hover': { bgcolor: 'grey.100' },
                        }}
                        onClick={async () => {
                          try {
                            const blob = await wholesaleOrdersAPI.downloadLegacyPaymentProof(order.id);
                            const a = document.createElement('a');
                            a.href = URL.createObjectURL(blob);
                            a.download = 'payment-proof';
                            a.click();
                            URL.revokeObjectURL(a.href);
                          } catch (e: any) {
                            enqueueSnackbar(e?.response?.data?.error || e?.message || 'Download failed', { variant: 'error' });
                          }
                        }}
                      >
                        <PdfIcon sx={{ fontSize: 48, color: 'error.main', opacity: 0.9 }} />
                        <Typography variant="caption" sx={{ mt: 0.5 }}>{t('wholesaleOrderDetail:downloadPaymentProof')}</Typography>
                      </Box>
                    </Box>
                  )}
                  {!canAddMore && (
                    <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                      {t('wholesaleOrderDetail:maxProofsReached')}
                    </Typography>
                  )}
                  {canAddMore ? (
                    <Box sx={{ mt: 2, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1 }}>
                      {hasProofs || hasLegacyProof ? (
                        <Typography variant="body2" color="text.secondary">
                          {t('wholesaleOrderDetail:addMoreProofHint')}
                        </Typography>
                      ) : null}
                      {uploadPaymentProofButton()}
                    </Box>
                  ) : null}
                </>
              );
            })()}
            </PipelineSectionPendingContent>
          </Paper>
        )}

        {allShipmentsCompleted && order.payment_confirmed_at && paymentFullyConfirmed && (
          <Paper sx={{ p: { xs: 2, md: 3 }, borderRadius: 2 }}>
            {(() => {
              const proofDocs = order.documents?.filter((d) => d.type === 'payment_proof') ?? [];
              const hasLegacyProof = !proofDocs.length && order.payment_proof_url;
              const proofCount = proofDocs.length + (hasLegacyProof ? 1 : 0);
              const displayName = (doc: { file_url: string; original_filename?: string }) =>
                doc.original_filename?.trim() || (() => {
                  try {
                    const p = new URL(doc.file_url).pathname;
                    return p.split('/').pop() || t('wholesaleOrderDetail:attachment');
                  } catch {
                    return t('wholesaleOrderDetail:attachment');
                  }
                })();
              return (
                <>
                  <Box sx={{ mb: 1.5 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                      {t('wholesaleOrderDetail:paymentConfirmed')} ({proofCount})
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      {t('wholesaleOrderDetail:paymentConfirmedAt', {
                        date: format(new Date(order.payment_confirmed_at), 'dd MMM yyyy HH:mm'),
                      })}
                    </Typography>
                  </Box>
                  {proofDocs.length > 0 ? (
                    <PaymentProofDocsList
                      isMobile={isShipmentsMobile}
                      proofDocs={proofDocs}
                      orderId={order.id}
                      canDeletePaymentProof={canDeletePaymentProof}
                      unlockAfterCompletion={paymentProofUnlockUpload}
                      metaByDocId={paymentProofMetaByDocId}
                      totalProofAmount={totalProofAmount}
                      pendingAmount={pendingAmount}
                      displayNameFor={displayName}
                      t={t}
                      enqueueSnackbar={enqueueSnackbar}
                      paymentProofDeletingId={paymentProofDeletingId}
                      setPaymentProofDeletingId={setPaymentProofDeletingId}
                      onOrderRefresh={setOrder}
                    />
                  ) : null}
                  {hasLegacyProof && (
                    <Box sx={{ mb: 2 }}>
                      <Box
                        sx={{
                          width: 80,
                          height: 80,
                          border: '1px solid',
                          borderColor: 'divider',
                          borderRadius: 1,
                          display: 'flex',
                          flexDirection: 'column',
                          alignItems: 'center',
                          justifyContent: 'center',
                          cursor: 'pointer',
                          '&:hover': { bgcolor: 'action.hover' },
                        }}
                        onClick={async () => {
                          try {
                            const blob = await wholesaleOrdersAPI.downloadLegacyPaymentProof(order.id);
                            const a = document.createElement('a');
                            a.href = URL.createObjectURL(blob);
                            a.download = 'payment-proof';
                            a.click();
                            URL.revokeObjectURL(a.href);
                          } catch (e: any) {
                            enqueueSnackbar(e?.response?.data?.error || e?.message || 'Download failed', { variant: 'error' });
                          }
                        }}
                      >
                        <PdfIcon sx={{ fontSize: 32, color: 'error.main' }} />
                        <Typography variant="caption" sx={{ mt: 0.5 }}>{t('wholesaleOrderDetail:downloadPaymentProof')}</Typography>
                      </Box>
                    </Box>
                  )}
                  {proofCount === 0 ? (
                    <Typography variant="body2" color="text.secondary">
                      {t('wholesaleOrderDetail:noPaymentProofOnFile', 'No payment proof on file.')}
                    </Typography>
                  ) : null}
                  {paymentProofUnlockUpload ? (
                    <Box sx={{ mt: 2, display: 'flex', justifyContent: 'center' }}>
                      <Button
                        variant="contained"
                        color="primary"
                        component="label"
                        size="medium"
                        startIcon={paymentProofUploading ? <CircularProgress size={16} color="inherit" /> : <AttachFileIcon />}
                        disabled={paymentProofUploading}
                      >
                        {paymentProofUploading ? t('wholesaleOrderDetail:uploading') : t('wholesaleOrderDetail:uploadPaymentProof')}
                        <input
                          accept=".pdf,image/*"
                          type="file"
                          multiple
                          hidden
                          onChange={(e) => {
                            void uploadPaymentProofFiles(e.target.files);
                            e.target.value = '';
                          }}
                        />
                      </Button>
                    </Box>
                  ) : null}
                </>
              );
            })()}
          </Paper>
        )}

        </Stack>
        <Box
          sx={{
            position: { lg: 'sticky' },
            top: { lg: 88 },
            alignSelf: 'flex-start',
            minWidth: 0,
            width: '100%',
          }}
        >
            <Box
              sx={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                mb: 1.5,
                flexWrap: 'wrap',
                gap: 1,
              }}
            >
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                {t('wholesaleOrderDetail:audit')}
              </Typography>
              <Button
                size="small"
                startIcon={<HistoryIcon fontSize="small" />}
                onClick={() => navigate(`/wholesale-orders/${order.id}/audit-log`)}
              >
                {t('wholesaleOrderDetail:allHistory')}
              </Button>
            </Box>
            <Box
              sx={{
                display: 'flex',
                flexDirection: 'column',
                gap: 1.5,
                width: '100%',
              }}
            >
              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderDetail:created')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Typography variant="body2" noWrap>
                  {format(new Date(order.created_at), 'dd MMM yyyy HH:mm')}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {order.user ? (
                    <UserDisplay user={order.user} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>{`User #${order.user_id}`}</Typography>
                  )}
                </Box>
              </Box>
            </Box>

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderDetail:updated')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Typography variant="body2" noWrap>
                  {lastUpdateAuditLog
                    ? format(new Date(lastUpdateAuditLog.created_at), 'dd MMM yyyy HH:mm')
                    : order.updated_at
                      ? format(new Date(order.updated_at), 'dd MMM yyyy HH:mm')
                      : '—'}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {lastUpdateAuditLog?.user ? (
                    <UserDisplay user={lastUpdateAuditLog.user} size="small" />
                  ) : order.reviewer ? (
                    <UserDisplay user={order.reviewer} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>—</Typography>
                  )}
                </Box>
              </Box>
            </Box>

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderDetail:poDate')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  {editingPODate && !orderCompleted ? (
                    <>
                      <TextField
                        size="small"
                        type="date"
                        value={poDateDraft}
                        onChange={(e) => setPODateDraft(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') savePODate();
                          if (e.key === 'Escape') setEditingPODate(false);
                        }}
                        autoFocus
                        sx={{ width: 200 }}
                        InputLabelProps={{ shrink: true }}
                      />
                      <Button size="small" onClick={savePODate}>
                        {t('wholesaleOrderDetail:save')}
                      </Button>
                      <Button size="small" onClick={() => setEditingPODate(false)}>
                        {t('wholesaleOrderDetail:cancel')}
                      </Button>
                    </>
                  ) : (
                    <>
                      <Typography variant="body2">
                        {order.po_date
                          ? format(new Date(order.po_date), 'dd MMM yyyy')
                          : format(new Date(order.created_at), 'dd MMM yyyy')}
                      </Typography>
                      {!orderCompleted && (
                        <EditIcon
                          sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                          onClick={() => {
                            setPODateDraft(
                              order.po_date ? order.po_date.substring(0, 10) : order.created_at.substring(0, 10),
                            );
                            setEditingPODate(true);
                          }}
                        />
                      )}
                    </>
                  )}
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {orderDateByUser ? (
                    <UserDisplay user={orderDateByUser} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>{`User #${order.user_id}`}</Typography>
                  )}
                </Box>
              </Box>
            </Box>

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderDetail:orderDate')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  {editingOrderDate && !orderCompleted ? (
                    <>
                      <TextField
                        size="small"
                        type="date"
                        value={orderDateDraft}
                        onChange={(e) => setOrderDateDraft(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') saveOrderDate();
                          if (e.key === 'Escape') setEditingOrderDate(false);
                        }}
                        autoFocus
                        sx={{ width: 200 }}
                        InputLabelProps={{ shrink: true }}
                      />
                      <Button size="small" onClick={saveOrderDate}>
                        {t('wholesaleOrderDetail:save')}
                      </Button>
                      <Button size="small" onClick={() => setEditingOrderDate(false)}>
                        {t('wholesaleOrderDetail:cancel')}
                      </Button>
                    </>
                  ) : (
                    <>
                      <Typography variant="body2">
                        {order.order_date
                          ? format(new Date(order.order_date), 'dd MMM yyyy')
                          : format(new Date(order.created_at), 'dd MMM yyyy')}
                      </Typography>
                      {!orderCompleted && (
                        <EditIcon
                          sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                          onClick={() => {
                            setOrderDateDraft(
                              order.order_date ? order.order_date.substring(0, 10) : order.created_at.substring(0, 10),
                            );
                            setEditingOrderDate(true);
                          }}
                        />
                      )}
                    </>
                  )}
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {shipmentCompleteDateByUser ? (
                    <UserDisplay user={shipmentCompleteDateByUser} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>{`User #${order.user_id}`}</Typography>
                  )}
                </Box>
              </Box>
            </Box>

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderDetail:endorsed')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Typography variant="body2" noWrap>
                  {order.reviewed_at ? format(new Date(order.reviewed_at), 'dd MMM yyyy HH:mm') : '—'}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {order.reviewer ? <UserDisplay user={order.reviewer} size="small" /> : <Typography variant="body2" noWrap>—</Typography>}
                </Box>
              </Box>
            </Box>

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderAudit:shipmentCompleteDate')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  {editingShipmentCompleteDate && !orderCompleted ? (
                    <>
                      <TextField
                        size="small"
                        type="date"
                        value={shipmentCompleteDateDraft}
                        onChange={(e) => setShipmentCompleteDateDraft(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') saveShipmentCompleteDate();
                          if (e.key === 'Escape') setEditingShipmentCompleteDate(false);
                        }}
                        autoFocus
                        sx={{ width: 200 }}
                        InputLabelProps={{ shrink: true }}
                      />
                      <Button size="small" variant="contained" disabled={savingShipmentCompleteDate} onClick={saveShipmentCompleteDate}>
                        {savingShipmentCompleteDate ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
                      </Button>
                      <Button size="small" disabled={savingShipmentCompleteDate} onClick={() => setEditingShipmentCompleteDate(false)}>
                        {t('wholesaleOrderDetail:cancel')}
                      </Button>
                    </>
                  ) : (
                    <>
                      <Typography variant="body2">
                        {latestCompletedShipment
                          ? format(
                              new Date(latestCompletedShipment.delivery_date ?? latestCompletedShipment.created_at),
                              'dd MMM yyyy',
                            )
                          : '—'}
                      </Typography>
                      {!orderCompleted && latestCompletedShipment && (
                        <EditIcon
                          sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                          onClick={() => {
                            const v = latestCompletedShipment.delivery_date ?? latestCompletedShipment.created_at;
                            setShipmentCompleteDateDraft((v ?? '').substring(0, 10));
                            setEditingShipmentCompleteDate(true);
                          }}
                        />
                      )}
                    </>
                  )}
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {order.user ? (
                    <UserDisplay user={order.user} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>{`User #${order.user_id}`}</Typography>
                  )}
                </Box>
              </Box>
            </Box>

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderAudit:invoiceDate')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  {editingInvoiceDate && !orderCompleted ? (
                    <>
                      <TextField
                        size="small"
                        type="date"
                        value={invoiceDateDraft}
                        onChange={(e) => setInvoiceDateDraft(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') saveInvoiceDate();
                          if (e.key === 'Escape') setEditingInvoiceDate(false);
                        }}
                        autoFocus
                        sx={{ width: 200 }}
                        InputLabelProps={{ shrink: true }}
                      />
                      <Button size="small" variant="contained" disabled={savingInvoiceDate} onClick={saveInvoiceDate}>
                        {savingInvoiceDate ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
                      </Button>
                      <Button size="small" disabled={savingInvoiceDate} onClick={() => setEditingInvoiceDate(false)}>
                        {t('wholesaleOrderDetail:cancel')}
                      </Button>
                    </>
                  ) : (
                    <>
                      <Typography variant="body2">
                        {format(
                          order.invoice_date ? new Date(order.invoice_date) : new Date(),
                          'dd MMM yyyy',
                        )}
                      </Typography>
                      {!orderCompleted && (
                        <EditIcon
                          sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                          onClick={() => {
                            setInvoiceDateDraft(
                              order.invoice_date ? order.invoice_date.substring(0, 10) : new Date().toISOString().slice(0, 10),
                            );
                            setEditingInvoiceDate(true);
                          }}
                        />
                      )}
                    </>
                  )}
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {invoiceDateByUser ? (
                    <UserDisplay user={invoiceDateByUser} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>{`User #${order.user_id}`}</Typography>
                  )}
                </Box>
              </Box>
            </Box>

            {hasInvoice && (
              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
                <Typography variant="caption" color="text.secondary">
                  {t('wholesaleOrderDetail:invoiceSentDate')}
                </Typography>
                <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 0.25 }}>
                  {t('wholesaleOrderDetail:invoiceSentDateHint')}
                </Typography>
                <Box
                  sx={{
                    display: 'flex',
                    alignItems: { xs: 'flex-start', sm: 'center' },
                    justifyContent: 'space-between',
                    mt: 0.75,
                    flexDirection: { xs: 'column', sm: 'row' },
                    gap: { xs: 0.75, sm: 1 },
                  }}
                >
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 1 }}>
                    {editingInvoiceSentAt ? (
                      <>
                        <TextField
                          size="small"
                          type="date"
                          value={invoiceSentDraft}
                          onChange={(e) => setInvoiceSentDraft(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') saveInvoiceSentAt();
                            if (e.key === 'Escape') setEditingInvoiceSentAt(false);
                          }}
                          autoFocus
                          sx={{ width: 200 }}
                          InputLabelProps={{ shrink: true }}
                        />
                        <Button size="small" variant="outlined" disabled={savingInvoiceSentAt} onClick={() => setInvoiceSentDraft(new Date().toISOString().slice(0, 10))}>
                          {t('wholesaleOrderDetail:invoiceSentToday')}
                        </Button>
                        <Button size="small" variant="contained" disabled={savingInvoiceSentAt} onClick={saveInvoiceSentAt}>
                          {savingInvoiceSentAt ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
                        </Button>
                        <Button size="small" disabled={savingInvoiceSentAt} onClick={() => setEditingInvoiceSentAt(false)}>
                          {t('wholesaleOrderDetail:cancel')}
                        </Button>
                        <Button
                          size="small"
                          color="warning"
                          disabled={savingInvoiceSentAt || !order.invoice_sent_at}
                          onClick={() => {
                            setInvoiceSentDraft('');
                            void (async () => {
                              if (!order) return;
                              try {
                                setSavingInvoiceSentAt(true);
                                const updated = await wholesaleOrdersAPI.setInvoiceSentAt(order.id, { invoice_sent_at: '' });
                                setOrder(updated);
                                const freshAuditLogs = await wholesaleOrdersAPI.getAuditLogs(order.id).catch(() => []);
                                setAuditLogs(freshAuditLogs);
                                setEditingInvoiceSentAt(false);
                                enqueueSnackbar(t('wholesaleOrderDetail:invoiceSentDateCleared'), { variant: 'success' });
                              } catch (e: any) {
                                enqueueSnackbar(e?.response?.data?.error || t('wholesaleOrderDetail:invoiceSentDateSaveError'), { variant: 'error' });
                              } finally {
                                setSavingInvoiceSentAt(false);
                              }
                            })();
                          }}
                        >
                          {t('wholesaleOrderDetail:clear')}
                        </Button>
                      </>
                    ) : (
                      <>
                        <Typography variant="body2">
                          {order.invoice_sent_at
                            ? format(new Date(order.invoice_sent_at), 'dd MMM yyyy')
                            : '—'}
                        </Typography>
                        <EditIcon
                          sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                          onClick={() => {
                            setInvoiceSentDraft(order.invoice_sent_at ? order.invoice_sent_at.substring(0, 10) : new Date().toISOString().slice(0, 10));
                            setEditingInvoiceSentAt(true);
                          }}
                        />
                      </>
                    )}
                  </Box>
                </Box>
              </Box>
            )}

              <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.25, width: '100%', margin: '0.5em 0' }}>
              <Typography variant="caption" color="text.secondary">
                {t('wholesaleOrderAudit:orderCompleteDate')}
              </Typography>
              <Box
                sx={{
                  display: 'flex',
                  alignItems: { xs: 'flex-start', sm: 'center' },
                  justifyContent: 'space-between',
                  mt: 0.5,
                  flexDirection: { xs: 'column', sm: 'row' },
                  gap: { xs: 0.75, sm: 0 },
                }}
              >
                <Typography variant="body2" noWrap>
                  {order.payment_confirmed_at ? format(new Date(order.payment_confirmed_at), 'dd MMM yyyy HH:mm') : '—'}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 0 }}>
                  {order.user ? (
                    <UserDisplay user={order.user} size="small" />
                  ) : (
                    <Typography variant="body2" noWrap>{`User #${order.user_id}`}</Typography>
                  )}
                </Box>
              </Box>
            </Box>

            <Paper sx={{ p: 3, mt: 2, gridColumn: '1 / -1' }}>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                  {t('wholesaleOrderDetail:amountSummary')}
                </Typography>
              </Box>
              <Box
                sx={{
                  display: 'grid',
                  gridTemplateColumns: 'auto 1fr',
                  columnGap: 3,
                  rowGap: 0.5,
                  alignItems: 'flex-start',
                }}
              >
                <Typography variant="body2" color="text.secondary">
                  {t('wholesaleOrderDetail:subtotal')}
                </Typography>
                <Typography variant="body2">£{(order.subtotal ?? 0).toFixed(2)}</Typography>

                <Typography variant="body2" color="text.secondary">
                  {t('wholesaleOrderDetail:discount')}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                  <Typography variant="body2">
                    £{(order.discount_amount ?? 0).toFixed(2)}
                  </Typography>
                  {!orderCompleted && (
                    <EditIcon
                      sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                      onClick={() => {
                        setDiscountDraft(String(order.discount_amount ?? ''));
                        setDiscountDialogOpen(true);
                      }}
                    />
                  )}
                </Box>

                <Typography variant="body2" color="text.secondary" fontWeight={600}>
                  {t('wholesaleOrderDetail:totalOrder')}
                </Typography>
                <Typography variant="body2" fontWeight={600}>
                  £{(order.total_net ?? totalForOrder(order)).toFixed(2)}
                </Typography>

                <Typography variant="body2" color="text.secondary">
                  {t('wholesaleOrderDetail:shippingFee')}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                  <Typography variant="body2">
                    £{(Number(order.shipping_fee) || 0).toFixed(2)}
                  </Typography>
                  {!orderCompleted && (
                    <EditIcon
                      sx={{ fontSize: 14, cursor: 'pointer', color: 'text.secondary' }}
                      onClick={() => {
                        setShippingFeeDraft(String(order.shipping_fee ?? ''));
                        setShippingFeeDialogOpen(true);
                      }}
                    />
                  )}
                </Box>

                <Typography variant="body2" color="text.secondary" fontWeight={700}>
                  {t('wholesaleOrderDetail:totalPrice')}
                </Typography>
                <Typography variant="body2" fontWeight={700}>
                  £{((order.total_net ?? totalForOrder(order)) + (Number(order.shipping_fee) || 0)).toFixed(2)}
                </Typography>
              </Box>
            </Paper>
        </Box>
      </Box>
      </Box>

        <Dialog
          open={confirmOrderNoProofDialogOpen}
          onClose={() => setConfirmOrderNoProofDialogOpen(false)}
        >
          <DialogTitle>
            {forceCompleteHasProof
              ? t('wholesaleOrderDetail:forceConfirmPaymentWarningTitle')
              : t('wholesaleOrderDetail:noProofWarningTitle')}
          </DialogTitle>
          <DialogContent>
            <DialogContentText>
              {forceCompleteHasProof
                ? t('wholesaleOrderDetail:forceConfirmPaymentWarningMessage')
                : t('wholesaleOrderDetail:noProofWarningMessage')}
            </DialogContentText>
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setConfirmOrderNoProofDialogOpen(false)}>{t('wholesaleOrderDetail:cancel')}</Button>
            <Button
              variant="contained"
              color="warning"
              onClick={() => {
                if (!order) return;
                setConfirmOrderNoProofDialogOpen(false);
                const amountParsed = parseFloat(paymentAmountDraft);
                const amountFallback = order.amount_due ?? order.total_net ?? 0;
                const amount = !Number.isNaN(amountParsed) && amountParsed > 0 ? amountParsed : amountFallback;
                const transfer_date = paymentTransferDateDraft || new Date().toISOString().slice(0, 10);
                const transferred_to = paymentTransferredToDraft || transferAccountOptions[0] || '';
                (async () => {
                  try {
                    setPaymentConfirming(true);
                    const updated = await wholesaleOrdersAPI.confirmPayment(order.id, { amount, transfer_date, transferred_to });
                    setOrder(updated);
                    enqueueSnackbar(
                      forceCompleteHasProof ? 'Order confirmed' : 'Order confirmed (no proof)',
                      { variant: 'success' },
                    );
                  } catch (err: any) {
                    enqueueSnackbar(err.response?.data?.error || 'Failed to confirm payment', { variant: 'error' });
                  } finally {
                    setPaymentConfirming(false);
                  }
                })();
              }}
              disabled={paymentConfirming}
            >
              {paymentConfirming ? t('wholesaleOrderDetail:confirming') : t('wholesaleOrderDetail:forceComplete')}
            </Button>
          </DialogActions>
        </Dialog>

        <Dialog
          open={forceConfirmPaymentDialogOpen}
          onClose={() => {
            setForceConfirmPaymentDialogOpen(false);
            setPendingPaymentProofFiles(null);
          }}
        >
          <DialogTitle>{t('wholesaleOrderDetail:forceConfirmPaymentTitle')}</DialogTitle>
          <DialogContent>
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1, minWidth: 320 }}>
              <TextField
                label={t('wholesaleOrderDetail:paymentAmount')}
                type="number"
                value={paymentAmountDraft}
                onChange={(e) => setPaymentAmountDraft(e.target.value)}
                inputProps={{ step: '0.01', min: '0' }}
                fullWidth
              />
              <TextField
                label={t('wholesaleOrderDetail:paymentDate')}
                type="date"
                value={paymentTransferDateDraft}
                onChange={(e) => setPaymentTransferDateDraft(e.target.value)}
                InputLabelProps={{ shrink: true }}
                inputProps={{ max: '9999-12-31' }}
                fullWidth
              />
              <TextField
                select
                label={t('wholesaleOrderDetail:transferredToAccount')}
                value={paymentTransferredToDraft}
                onChange={(e) => setPaymentTransferredToDraft(e.target.value)}
                SelectProps={{ displayEmpty: true }}
                fullWidth
              >
                <MenuItem value="" disabled>
                  {t('wholesaleOrderDetail:selectTransferredToAccount')}
                </MenuItem>
                {transferAccountOptions.map((opt) => (
                  <MenuItem key={opt} value={opt}>
                    {opt}
                  </MenuItem>
                ))}
              </TextField>
              {pendingPaymentProofFiles && pendingPaymentProofFiles.length > 0 && (
                <Box sx={{ mt: 1 }}>
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                    {t('wholesaleOrderDetail:selectedPaymentProofs')}
                  </Typography>
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5 }}>
                    {pendingPaymentProofFiles.map((f, idx) => {
                      const isImage = f.type.startsWith('image/');
                      const isPdfFile = f.type === 'application/pdf';
                      const previewUrl = pendingProofPreviewUrls[`${f.name}-${idx}`];
                      return (
                        <Box key={`${f.name}-${idx}`} sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start' }}>
                          {isImage && previewUrl ? (
                            <Box
                              component="img"
                              src={previewUrl}
                              alt={f.name}
                              sx={{
                                maxHeight: 80,
                                maxWidth: 120,
                                objectFit: 'contain',
                                border: '1px solid',
                                borderColor: 'divider',
                                borderRadius: 1,
                                bgcolor: 'grey.50',
                              }}
                            />
                          ) : isPdfFile && previewUrl ? (
                            <Box
                              component="iframe"
                              src={previewUrl}
                              title={f.name}
                              sx={{
                                width: 120,
                                height: 80,
                                border: '1px solid',
                                borderColor: 'divider',
                                borderRadius: 1,
                                bgcolor: 'grey.50',
                              }}
                            />
                          ) : (
                            <Box
                              sx={{
                                width: 48,
                                height: 48,
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                border: '1px solid',
                                borderColor: 'divider',
                                borderRadius: 1,
                                bgcolor: 'grey.50',
                              }}
                            >
                              <PdfIcon sx={{ fontSize: 28, color: 'error.main' }} />
                            </Box>
                          )}
                          <Typography variant="caption" sx={{ mt: 0.25, maxWidth: 120 }} noWrap title={f.name}>
                            {f.name}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            ({(f.size / 1024).toFixed(1)} KB)
                          </Typography>
                        </Box>
                      );
                    })}
                  </Box>
                </Box>
              )}
              {(() => {
                const amountEntered = parseFloat(paymentAmountDraft);
                const willCompleteOrder =
                  Number.isFinite(amountEntered) &&
                  pendingAmount > 0 &&
                  Math.abs(amountEntered - pendingAmount) < 0.01;
                if (!willCompleteOrder) return null;
                return (
                  <Typography variant="body2" color="success.main" sx={{ mt: 0.5, fontWeight: 500 }}>
                    {t('wholesaleOrderDetail:uploadProofWillCompleteOrderHint')}
                  </Typography>
                );
              })()}
            </Box>
          </DialogContent>
          <DialogActions>
            <Button
              onClick={() => {
                setForceConfirmPaymentDialogOpen(false);
                setPendingPaymentProofFiles(null);
              }}
              disabled={paymentConfirming}
            >
              {t('wholesaleOrderDetail:cancel')}
            </Button>
            <Button
              variant="contained"
              color="success"
              onClick={submitForceConfirmPayment}
              disabled={paymentConfirming}
            >
              {paymentConfirming ? t('wholesaleOrderDetail:uploading') : t('wholesaleOrderDetail:uploadPaymentProofWithDetails')}
            </Button>
          </DialogActions>
        </Dialog>

        <Dialog
          open={!!filePreview}
          onClose={() => setFilePreview(null)}
          maxWidth="lg"
          fullWidth
          fullScreen
          PaperProps={{ sx: { bgcolor: 'transparent', boxShadow: 'none', maxHeight: 'none' } }}
          slotProps={{ backdrop: { sx: { bgcolor: 'rgba(0,0,0,0.9)' } } }}
          sx={{ zIndex: 1300 }}
        >
          <Button
            onClick={() => setFilePreview(null)}
            startIcon={<ChevronRightIcon sx={{ transform: 'rotate(180deg)' }} />}
            sx={{
              position: 'fixed',
              top: 24,
              left: 24,
              zIndex: 1400,
              bgcolor: 'rgba(30, 40, 55, 0.95)',
              color: 'white',
              border: '1px solid rgba(255,255,255,0.2)',
              borderRadius: 2,
              px: 2,
              py: 1,
              '&:hover': { bgcolor: 'rgba(40, 55, 75, 0.95)' },
            }}
          >
            {t('wholesaleOrderDetail:backToOrder')}
          </Button>
          <DialogContent sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2, pt: 8 }} onClick={() => setFilePreview(null)}>
            {filePreview && (
              <Box
                component="img"
                src={filePreview.url}
                alt={filePreview.name}
                sx={{ maxWidth: '100%', maxHeight: '90vh', objectFit: 'contain' }}
                onClick={(e) => e.stopPropagation()}
              />
            )}
          </DialogContent>
        </Dialog>


      <Dialog open={poChannelDialogOpen} onClose={() => !poChannelSaving && setPOChannelDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>{t('wholesaleOrderDetail:editPONumberChannel')}</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
            <Autocomplete
              freeSolo
              size="small"
              options={orderChannelOptions}
              getOptionLabel={(v) => ORDER_CHANNEL_OPTIONS.find((o) => o.value === v)?.label ?? v}
              value={orderChannelDraft}
              onInputChange={(_, inputValue, reason) => {
                if (reason === 'input') setOrderChannelDraft(inputValue);
              }}
              onChange={(_, newValue) => {
                if (newValue != null) setOrderChannelDraft(String(newValue));
              }}
              renderInput={(params) => (
                <TextField {...params} label={t('wholesaleOrderDetail:orderChannel')} placeholder="e.g. WhatsApp, Email, Client PO" />
              )}
            />
            <TextField
              size="small"
              label={t('wholesaleOrderDetail:poNumber')}
              value={poNumberDraft}
              onChange={(e) => setPONumberDraft(e.target.value)}
              placeholder={orderChannelDraft.trim().toLowerCase() === 'po' ? 'Client PO reference' : 'Used when channel is Client PO'}
              helperText={orderChannelDraft.trim().toLowerCase() !== 'po' ? 'PO number is only saved when channel is Client PO.' : undefined}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPOChannelDialogOpen(false)} disabled={poChannelSaving}>{t('wholesaleOrderDetail:cancel')}</Button>
          <Button variant="contained" onClick={savePOAndChannel} disabled={poChannelSaving}>
            {poChannelSaving ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={shippingDialogOpen}
        onClose={() => !shippingSaving && setShippingDialogOpen(false)}
        maxWidth="xs"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:shippingAddress')}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" sx={{ mb: 2 }}>
            {order?.wholesale_client?.name}
          </Typography>
          <DialogContentText sx={{ mb: 1 }}>
            {t('wholesaleOrderDetail:selectStore')}
          </DialogContentText>
          <Select
            fullWidth
            size="small"
            value={shippingStoreIdDraft}
            onChange={(e) => {
              const v = e.target.value as '' | 'new' | number;
              if (v === 'new') {
                setShippingStoreIdDraft('new');
                // Keep existing street details; only clear the location name
                setShippingNameDraft('');
                return;
              }
              const val = v === '' ? '' : Number(v);
              // Leaving "Other address"
              setOtherAddressStoreId(null);
              setShippingStoreIdDraft(val);
              const stores = order?.wholesale_client?.stores ?? shippingStores;
              const selected =
                val === '' ? undefined : stores.find((s) => s.id === val);
              if (selected) {
                setShippingNameDraft(selected.name ?? '');
                setShippingAddress1Draft(selected.address_line1 ?? '');
                setShippingAddress2Draft(selected.address_line2 ?? '');
                setShippingCityDraft(selected.city ?? '');
                setShippingPostcodeDraft(selected.postcode ?? '');
              } else if (order?.wholesale_client) {
                // Company address
                setShippingNameDraft('');
                setShippingAddress1Draft(order.wholesale_client.address_line1 ?? '');
                setShippingAddress2Draft(order.wholesale_client.address_line2 ?? '');
                setShippingCityDraft('');
                setShippingPostcodeDraft(order.wholesale_client.postcode ?? '');
              }
            }}
          >
            <MenuItem value="">
              <em>{t('wholesaleOrderDetail:companyAddress')}</em>
            </MenuItem>
            {(order?.wholesale_client?.stores ?? shippingStores).map((s) => (
              <MenuItem key={s.id} value={s.id}>
                {s.name}
                {s.address_line1 ? ` — ${s.address_line1}${s.postcode ? `, ${s.postcode}` : ''}` : ''}
              </MenuItem>
            ))}
            <MenuItem value="new" disabled>
              <em>{t('wholesaleOrderDetail:newShippingLocation')}</em>
            </MenuItem>
          </Select>

          <Box sx={{ mt: 2, display: 'flex', flexDirection: 'column', gap: 1.5 }}>
            {shippingStoreIdDraft !== '' && (
              <TextField
                fullWidth
                size="small"
                label="Location name"
                value={shippingNameDraft}
                onChange={(e) => setShippingNameDraft(e.target.value)}
              />
            )}
            <TextField
              fullWidth
              size="small"
              label="Address line 1"
              value={shippingAddress1Draft}
              onChange={(e) => setShippingAddress1Draft(e.target.value)}
            />
            <TextField
              fullWidth
              size="small"
              label="Address line 2"
              value={shippingAddress2Draft}
              onChange={(e) => setShippingAddress2Draft(e.target.value)}
            />
            <TextField
              fullWidth
              size="small"
              label="City"
              value={shippingCityDraft}
              onChange={(e) => setShippingCityDraft(e.target.value)}
            />
            <TextField
              fullWidth
              size="small"
              label="Postcode"
              value={shippingPostcodeDraft}
              onChange={(e) => setShippingPostcodeDraft(e.target.value)}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setShippingDialogOpen(false)} disabled={shippingSaving}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            disabled={shippingSaving}
            onClick={async () => {
              if (!order) return;
              try {
                setShippingSaving(true);
                // Ensure we have client stores if not already loaded on the order
                let client = order.wholesale_client;
                if (!client && order.wholesale_client_id) {
                  client = await wholesaleClientsAPI.get(order.wholesale_client_id);
                }
                let resolvedOtherStoreId: number | null = otherAddressStoreId;
                // Update either company address or a specific store
                if (client) {
                  if (shippingStoreIdDraft === '') {
                    resolvedOtherStoreId = null;
                    setOtherAddressStoreId(null);
                    await wholesaleClientsAPI.update(client.id, {
                      address_line1: shippingAddress1Draft.trim() || undefined,
                      address_line2: shippingAddress2Draft.trim() || undefined,
                      postcode: shippingPostcodeDraft.trim() || undefined,
                    } as any);
                  } else if (shippingStoreIdDraft === 'new') {
                    // Create-or-update the "Other address" shipping location.
                    // If otherAddressStoreId is already set, update that store to avoid duplicates.
                    if (resolvedOtherStoreId == null) {
                      const createdStore = await wholesaleClientsAPI.createStore(client.id, {
                        name: shippingNameDraft.trim() || order.wholesale_client?.name || 'Delivery location',
                        address_line1: shippingAddress1Draft.trim(),
                        address_line2: shippingAddress2Draft.trim() || undefined,
                        city: shippingCityDraft.trim() || undefined,
                        postcode: shippingPostcodeDraft.trim() || undefined,
                      } as any);
                      resolvedOtherStoreId = createdStore.id;
                      setOtherAddressStoreId(createdStore.id);
                      setShippingStores((prev) => (prev.some((s) => s.id === createdStore.id) ? prev : [...prev, createdStore]));
                    } else {
                      await wholesaleClientsAPI.updateStore(client.id, resolvedOtherStoreId, {
                        name: shippingNameDraft.trim() || client.stores?.find((s) => s.id === resolvedOtherStoreId)?.name,
                        address_line1: shippingAddress1Draft.trim() || undefined,
                        address_line2: shippingAddress2Draft.trim() || undefined,
                        city: shippingCityDraft.trim() || undefined,
                        postcode: shippingPostcodeDraft.trim() || undefined,
                      } as any);
                    }
                  } else {
                    resolvedOtherStoreId = null;
                    setOtherAddressStoreId(null);
                    const storeId = shippingStoreIdDraft as number;
                    await wholesaleClientsAPI.updateStore(client.id, storeId, {
                      name: shippingNameDraft.trim() || client.stores?.find((s) => s.id === storeId)?.name,
                      address_line1: shippingAddress1Draft.trim() || undefined,
                      address_line2: shippingAddress2Draft.trim() || undefined,
                      city: shippingCityDraft.trim() || undefined,
                      postcode: shippingPostcodeDraft.trim() || undefined,
                    } as any);
                  }
                }

                const currentStoreId = order.wholesale_client_store_id ?? null;
                const newStoreId =
                  shippingStoreIdDraft === ''
                    ? null
                    : shippingStoreIdDraft === 'new'
                      ? (resolvedOtherStoreId ?? null)
                      : (shippingStoreIdDraft as number);

                const selectionChanged = currentStoreId !== newStoreId;
                let updated: typeof order;
                if (selectionChanged) {
                  if (newStoreId == null) {
                    updated = await wholesaleOrdersAPI.update(order.id, { clear_wholesale_client_store_id: true });
                  } else {
                    updated = await wholesaleOrdersAPI.update(order.id, { wholesale_client_store_id: newStoreId });
                  }
                } else {
                  updated = await wholesaleOrdersAPI.get(order.id, { cacheBust: true });
                }
                setOrder(updated);
                setShippingDialogOpen(false);
                enqueueSnackbar('Shipping address updated', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to update shipping address', { variant: 'error' });
              } finally {
                setShippingSaving(false);
              }
            }}
          >
            {shippingSaving ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={shippingFeeDialogOpen}
        onClose={() => !shippingFeeSaving && setShippingFeeDialogOpen(false)}
        maxWidth="xs"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:updateShippingFee')}</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            {order?.shipments && order.shipments.length > 0 && order.shipments.every((sh) => sh.status === 'completed')
              ? t('wholesaleOrderDetail:shippingFeeAllComplete')
              : t('wholesaleOrderDetail:shippingFeeHint')}
          </DialogContentText>
          <TextField
            fullWidth
            label={t('wholesaleOrderDetail:shippingFeeLabel')}
            type="number"
            value={shippingFeeDraft}
            onChange={(e) => setShippingFeeDraft(e.target.value)}
            inputProps={{ min: 0, step: 0.01 }}
            placeholder="0"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setShippingFeeDialogOpen(false)} disabled={shippingFeeSaving}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            disabled={shippingFeeSaving}
            onClick={async () => {
              if (!order) return;
              const fee = parseFloat(shippingFeeDraft);
              if (!Number.isFinite(fee) || fee < 0) {
                enqueueSnackbar('Enter a valid fee (0 or more)', { variant: 'warning' });
                return;
              }
              setShippingFeeSaving(true);
              try {
                const updated = await wholesaleOrdersAPI.update(order.id, { shipping_fee: fee });
                setOrder(updated);
                setShippingFeeDialogOpen(false);
                enqueueSnackbar('Shipping fee updated', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to update shipping fee', { variant: 'error' });
              } finally {
                setShippingFeeSaving(false);
              }
            }}
          >
            {shippingFeeSaving ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={discountDialogOpen}
        onClose={() => !discountSaving && setDiscountDialogOpen(false)}
        maxWidth="xs"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:updateDiscount')}</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            {order?.shipments && order.shipments.length > 0 && order.shipments.every((sh) => sh.status === 'completed')
              ? t('wholesaleOrderDetail:discountAllComplete')
              : t('wholesaleOrderDetail:discountHint', { max: (order?.subtotal ?? 0).toFixed(2) })}
          </DialogContentText>
          <TextField
            fullWidth
            label={t('wholesaleOrderDetail:orderDiscountLabel')}
            type="number"
            value={discountDraft}
            onChange={(e) => setDiscountDraft(e.target.value)}
            inputProps={{ min: 0, max: order?.subtotal ?? 0, step: 0.01 }}
            placeholder="0"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDiscountDialogOpen(false)} disabled={discountSaving}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            disabled={discountSaving}
            onClick={async () => {
              if (!order) return;
              const amount = parseFloat(discountDraft);
              const subtotal = order.subtotal ?? 0;
              if (!Number.isFinite(amount) || amount < 0) {
                enqueueSnackbar('Enter a valid amount (0 or more)', { variant: 'warning' });
                return;
              }
              if (amount > subtotal) {
                enqueueSnackbar('Discount cannot exceed subtotal (£' + subtotal.toFixed(2) + ')', { variant: 'warning' });
                return;
              }
              setDiscountSaving(true);
              try {
                const updated = await wholesaleOrdersAPI.update(order.id, { discount_amount: amount });
                setOrder(updated);
                setDiscountDialogOpen(false);
                enqueueSnackbar('Order discount updated', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to update discount', { variant: 'error' });
              } finally {
                setDiscountSaving(false);
              }
            }}
          >
            {discountSaving ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!editingShipment}
        onClose={() => !shipmentSaving && setEditingShipment(null)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:editShipment')}</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
            <TextField
              size="small"
              label={t('wholesaleOrderDetail:courier')}
              value={shipmentCourier}
              onChange={(e) => setShipmentCourier(e.target.value)}
              placeholder="e.g. DPD"
            />
            <TextField
              size="small"
              label={t('wholesaleOrderDetail:trackingNumber')}
              value={shipmentTracking}
              onChange={(e) => setShipmentTracking(e.target.value)}
            />
            <TextField
              size="small"
              label={t('wholesaleOrderDetail:deliveryDate')}
              type="date"
              value={shipmentDeliveryDateDraft}
              onChange={(e) => setShipmentDeliveryDateDraft(e.target.value)}
              InputLabelProps={{ shrink: true }}
              inputProps={{ max: '9999-12-31' }}
            />
            {editingShipment?.items?.length ? (
              <>
                <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                  {t('wholesaleOrderDetail:editBoxesHint')}
                </Typography>
                <Table size="small" sx={{ mt: 0.5 }}>
                  <TableHead>
                    <TableRow>
                      <TableCell>{t('wholesaleOrderDetail:product')}</TableCell>
                      <TableCell align="right" sx={{ width: 120 }}>
                        {t('wholesaleOrderDetail:box')}
                      </TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {editingShipment.items.map((si) => {
                      const product = si.wholesale_order_item?.product;
                      const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                      const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                      return (
                        <TableRow key={si.id}>
                          <TableCell>{name}</TableCell>
                          <TableCell align="right">
                            <TextField
                              type="number"
                              size="small"
                              inputProps={{ min: 0, step: 1 }}
                              value={value}
                              onChange={(e) =>
                                setCaseQtyByOrderItemId((prev) => ({
                                  ...prev,
                                  [si.wholesale_order_item_id]: e.target.value,
                                }))
                              }
                              sx={{ width: 96 }}
                            />
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </>
            ) : null}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditingShipment(null)} disabled={shipmentSaving}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            disabled={shipmentSaving || !editingShipment}
            onClick={async () => {
              if (!editingShipment || !order) return;
              setShipmentSaving(true);
              try {
                await shipmentsAPI.update(editingShipment.id, {
                  courier: shipmentCourier || undefined,
                  tracking_number: shipmentTracking || undefined,
                  delivery_date: shipmentDeliveryDateDraft.trim() || undefined,
                });
                if (editingShipment.items?.length && editingShipment.delivery_note_pdf_url) {
                  if (
                    isRegenBlockedByEmailLock(
                      auditLogs,
                      'delivery_note',
                      orderLockUnlocked,
                      editingShipment.id,
                    )
                  ) {
                    throw new Error('cancelled');
                  }
                  const case_qty = editingShipment.items.map((si) => ({
                    wholesale_order_item_id: si.wholesale_order_item_id,
                    case_qty: Math.max(
                      0,
                      parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0,
                    ),
                  }));
                  await shipmentsAPI.updateCaseQty(editingShipment.id, {
                    case_qty,
                    unlock_after_email: shouldSendRegenUnlockFlag(
                      auditLogs,
                      'delivery_note',
                      orderLockUnlocked,
                      editingShipment.id,
                    ),
                  });
                } else if (editingShipment.items?.length) {
                  const case_qty = editingShipment.items.map((si) => ({
                    wholesale_order_item_id: si.wholesale_order_item_id,
                    case_qty: Math.max(
                      0,
                      parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0,
                    ),
                  }));
                  await shipmentsAPI.updateCaseQty(editingShipment.id, { case_qty });
                }
                const updated = await wholesaleOrdersAPI.get(order.id);
                setOrder(updated);
                setEditingShipment(null);
                enqueueSnackbar('Shipment updated', { variant: 'success' });
              } catch (e: any) {
                if (e?.message === 'cancelled') {
                  enqueueSnackbar(
                    t('wholesaleOrderDetail:documentRegenSkippedAfterEmail', {
                      document: t('wholesaleOrderDetail:deliveryNote'),
                    }),
                    { variant: 'warning' },
                  );
                  return;
                }
                enqueueSnackbar(e.response?.data?.error || 'Failed to update shipment', { variant: 'error' });
              } finally {
                setShipmentSaving(false);
              }
            }}
          >
            {shipmentSaving ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:save')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!startShipmentDialog}
        onClose={() => !startShipmentSubmitting && setStartShipmentDialog(null)}
        maxWidth="sm"
        fullWidth
        fullScreen={isShipmentsMobile}
      >
        <DialogTitle>{t('wholesaleOrderDetail:startShipment')}</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            {t('wholesaleOrderDetail:startShipmentHint')}
          </DialogContentText>
          <Autocomplete
            freeSolo
            options={shipmentCourierOptions}
            value={startShipmentCourierDraft}
            onChange={(_e, value) =>
              setStartShipmentCourierDraft(typeof value === 'string' ? value : value ?? '')
            }
            onInputChange={(_e, value) => setStartShipmentCourierDraft(value)}
            renderInput={(params) => (
              <TextField
                {...params}
                label={t('wholesaleOrderDetail:courier')}
                margin="normal"
                size="small"
                fullWidth
              />
            )}
          />
          <TextField
            label={t('wholesaleOrderDetail:trackingNumber')}
            value={startShipmentTrackingDraft}
            onChange={(e) => setStartShipmentTrackingDraft(e.target.value)}
            placeholder={t('wholesaleOrderDetail:trackingNumberOptional')}
            fullWidth
            margin="normal"
            size="small"
            helperText={t('wholesaleOrderDetail:trackingNumberHint')}
          />
          <TextField
            label={t('wholesaleOrderDetail:deliveryDate')}
            type="date"
            value={startShipmentDeliveryDateDraft}
            onChange={(e) => setStartShipmentDeliveryDateDraft(e.target.value)}
            fullWidth
            margin="normal"
            InputLabelProps={{ shrink: true }}
            inputProps={{ max: '9999-12-31' }}
          />
          {startShipmentDialog?.items?.length ? (
            isShipmentsMobile ? (
              <Stack spacing={1.5} sx={{ mb: 2 }}>
                {startShipmentDialog.items.map((si) => {
                  const product = si.wholesale_order_item?.product;
                  const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                  const lineQty = formatAssignmentQty(effectiveShipmentItemQty(si));
                  const expected = shipmentExpectedBoxes(si);
                  const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                  const actual = parseFloat(value) || 0;
                  const delta = actual - expected;
                  const deltaText = delta > 0 ? `+${delta}` : delta < 0 ? String(delta) : '—';
                  return (
                    <Paper key={si.id} variant="outlined" sx={{ p: 1.5 }}>
                      <Typography variant="subtitle2" sx={{ mb: 1.5, wordBreak: 'break-word' }}>
                        {name}
                      </Typography>
                      <Stack spacing={1}>
                        <DialogLabelValueRow label={t('wholesaleOrderDetail:qty')}>
                          <Typography variant="body2">{lineQty}</Typography>
                        </DialogLabelValueRow>
                        <DialogLabelValueRow label={t('wholesaleOrderDetail:expectedBoxes', 'Expected boxes')}>
                          <Typography variant="body2" color="text.secondary">
                            {expected}
                          </Typography>
                        </DialogLabelValueRow>
                        <DialogLabelValueRow label={t('wholesaleOrderDetail:box')}>
                          <TextField
                            type="number"
                            size="small"
                            inputProps={{ min: 0, step: 1 }}
                            value={value}
                            onChange={(e) =>
                              setCaseQtyByOrderItemId((prev) => ({
                                ...prev,
                                [si.wholesale_order_item_id]: e.target.value,
                              }))
                            }
                            sx={{ width: 96 }}
                          />
                        </DialogLabelValueRow>
                        <DialogLabelValueRow label={t('wholesaleOrderDetail:addedOrReduced', 'Added/Reduced')}>
                          <Typography
                            variant="body2"
                            sx={{
                              fontWeight: 500,
                              color: delta > 0 ? 'success.main' : delta < 0 ? 'error.main' : 'text.secondary',
                            }}
                          >
                            {deltaText}
                          </Typography>
                        </DialogLabelValueRow>
                      </Stack>
                    </Paper>
                  );
                })}
              </Stack>
            ) : (
            <TableContainer sx={{ mb: 2, overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
            <Table size="small" sx={{ minWidth: 520 }}>
              <TableHead>
                <TableRow>
                  <TableCell>{t('wholesaleOrderDetail:product')}</TableCell>
                  <TableCell align="right" sx={{ width: 80 }}>{t('wholesaleOrderDetail:qty')}</TableCell>
                  <TableCell align="right" sx={{ width: 100 }}>{t('wholesaleOrderDetail:expectedBoxes', 'Expected boxes')}</TableCell>
                  <TableCell align="right" sx={{ width: 100 }}>{t('wholesaleOrderDetail:box')}</TableCell>
                  <TableCell align="right" sx={{ width: 100 }}>{t('wholesaleOrderDetail:addedOrReduced', 'Added/Reduced')}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {startShipmentDialog.items.map((si) => {
                  const product = si.wholesale_order_item?.product;
                  const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                  const lineQty = formatAssignmentQty(effectiveShipmentItemQty(si));
                  const expected = shipmentExpectedBoxes(si);
                  const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                  const actual = parseFloat(value) || 0;
                  const delta = actual - expected;
                  const deltaText = delta > 0 ? `+${delta}` : delta < 0 ? String(delta) : '—';
                  return (
                    <TableRow key={si.id}>
                      <TableCell sx={{ wordBreak: 'break-word' }}>{name}</TableCell>
                      <TableCell align="right">{lineQty}</TableCell>
                      <TableCell align="right" sx={{ color: 'text.secondary' }}>{expected}</TableCell>
                      <TableCell align="right">
                        <TextField
                          type="number"
                          size="small"
                          inputProps={{ min: 0, step: 1 }}
                          value={value}
                          onChange={(e) =>
                            setCaseQtyByOrderItemId((prev) => ({
                              ...prev,
                              [si.wholesale_order_item_id]: e.target.value,
                            }))
                          }
                          sx={{ width: 80 }}
                        />
                      </TableCell>
                      <TableCell align="right" sx={{ fontWeight: 500, color: delta > 0 ? 'success.main' : delta < 0 ? 'error.main' : 'text.secondary' }}>
                        {deltaText}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
            </TableContainer>
            )
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setStartShipmentDialog(null)} disabled={startShipmentSubmitting}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            color="primary"
            disabled={startShipmentSubmitting}
            onClick={async () => {
              if (!startShipmentDialog || !order) return;
              setStartShipmentSubmitting(true);
              try {
                let baseOrder = order;
                if (baseOrder.status === 'assign_shipment') {
                  baseOrder = await wholesaleOrdersAPI.completeAssignment(baseOrder.id);
                  setOrder(baseOrder);
                }
                const case_qty =
                  startShipmentDialog.items?.map((si) => ({
                    wholesale_order_item_id: si.wholesale_order_item_id,
                    case_qty: Math.max(
                      0,
                      parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0,
                    ),
                  })) ?? [];
                await shipmentsAPI.startShipment(startShipmentDialog.id, {
                  case_qty,
                  delivery_date: startShipmentDeliveryDateDraft.trim() || undefined,
                  courier: startShipmentCourierDraft.trim() || undefined,
                  tracking_number: startShipmentTrackingDraft.trim() || undefined,
                });
                const freshOrder = await wholesaleOrdersAPI.get(order.id);
                setOrder(freshOrder);
                setStartShipmentDialog(null);
                enqueueSnackbar('Shipment packed. Use courier pickup to mark shipped.', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(e.response?.data?.error || 'Failed to start shipment', { variant: 'error' });
              } finally {
                setStartShipmentSubmitting(false);
              }
            }}
          >
            {startShipmentSubmitting ? t('wholesaleOrderDetail:starting') : t('wholesaleOrderDetail:startShipment')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!forceCompleteShipmentDialog}
        onClose={() => !forceCompleteShipmentSubmitting && setForceCompleteShipmentDialog(null)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:forceCompleteShipment')}</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            {t('wholesaleOrderDetail:completeShipmentHint')}
          </DialogContentText>
          <TextField
            label={t('wholesaleOrderDetail:deliveryDate')}
            type="date"
            value={forceCompleteDeliveryDateDraft}
            onChange={(e) => setForceCompleteDeliveryDateDraft(e.target.value)}
            fullWidth
            margin="normal"
            InputLabelProps={{ shrink: true }}
            inputProps={{ max: '9999-12-31' }}
            sx={{ mb: 2 }}
          />
          {forceCompleteShipmentDialog?.items?.length ? (
            <Table size="small" sx={{ mb: 2 }}>
              <TableHead>
                <TableRow>
                  <TableCell>{t('wholesaleOrderDetail:product')}</TableCell>
                  <TableCell align="right" sx={{ width: 100 }}>
                    {t('wholesaleOrderDetail:box')}
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {forceCompleteShipmentDialog.items.map((si) => {
                  const product = si.wholesale_order_item?.product;
                  const name = product ? productDisplayName(product, lang) : `Item #${si.wholesale_order_item_id}`;
                  const value = caseQtyByOrderItemId[si.wholesale_order_item_id] ?? '';
                  return (
                    <TableRow key={si.id}>
                      <TableCell>{name}</TableCell>
                      <TableCell align="right">
                        <TextField
                          type="number"
                          size="small"
                          inputProps={{ min: 0, step: 1 }}
                          value={value}
                          onChange={(e) =>
                            setCaseQtyByOrderItemId((prev) => ({
                              ...prev,
                              [si.wholesale_order_item_id]: e.target.value,
                            }))
                          }
                          sx={{ width: 80 }}
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setForceCompleteShipmentDialog(null)} disabled={forceCompleteShipmentSubmitting}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            color="warning"
            disabled={forceCompleteShipmentSubmitting || !forceCompleteShipmentDialog || !order}
            onClick={async () => {
              if (!forceCompleteShipmentDialog || !order) return;
              setForceCompleteShipmentSubmitting(true);
              try {
                let baseOrder = order;
                // If the order is still in "assign shipment", move it to the next stage first
                // so the UI shows "pending payment" (not "assign shipment").
                if (baseOrder.status === 'assign_shipment') {
                  baseOrder = await wholesaleOrdersAPI.completeAssignment(baseOrder.id);
                  setOrder(baseOrder);
                }

                const case_qty =
                  forceCompleteShipmentDialog.items?.map((si) => ({
                    wholesale_order_item_id: si.wholesale_order_item_id,
                    case_qty:
                      Math.max(0, parseFloat(String(caseQtyByOrderItemId[si.wholesale_order_item_id])) || 0),
                  })) ?? [];

                await shipmentsAPI.completePacking(forceCompleteShipmentDialog.id, {
                  case_qty,
                  delivery_date: forceCompleteDeliveryDateDraft.trim() || undefined,
                  force_complete: true,
                });

                const updated = await wholesaleOrdersAPI.get(order.id);
                setOrder(updated);
                setForceCompleteShipmentDialog(null);
                enqueueSnackbar('Shipment completed (forced)', { variant: 'success' });
              } catch (e: any) {
                enqueueSnackbar(
                  e.response?.data?.error || 'Failed to force complete shipment',
                  { variant: 'error' },
                );
              } finally {
                setForceCompleteShipmentSubmitting(false);
              }
            }}
          >
            {forceCompleteShipmentSubmitting
              ? t('wholesaleOrderDetail:completing')
              : t('wholesaleOrderDetail:forceCompleteShipment')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={endorsePreviewOpen}
        onClose={() => !actioning && setEndorsePreviewOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:endorseStockPreviewTitle')}</DialogTitle>
        <DialogContent>
          {endorsePreview?.outcome === 'single_store' ? (
            <Alert severity="info" sx={{ mb: 2 }}>
              {t('wholesaleOrderDetail:endorseSingleStoreConfirm', {
                store: endorsePreview.primary_store_name || `#${endorsePreview.primary_store_id}`,
              })}
            </Alert>
          ) : null}
          {endorsePreview?.outcome === 'split_required' ? (
            <Alert severity="warning" sx={{ mb: 2 }}>
              {t('wholesaleOrderDetail:endorseSplitRequiredWarning', {
                count: endorsePreview.store_ids.length,
              })}
            </Alert>
          ) : null}
          {endorsePreview?.outcome === 'insufficient_stock' ? (
            <Alert severity="error" sx={{ mb: 2 }}>
              {t('wholesaleOrderDetail:endorseInsufficientStockWarning')}
            </Alert>
          ) : null}
          {endorsePreview?.assignments.length ? (
            <Typography variant="subtitle2" sx={{ mb: 1 }}>
              {t('wholesaleOrderDetail:endorseSuggestedAllocation')}
            </Typography>
          ) : null}
          <Table size="small" sx={{ mb: 2 }}>
            <TableHead>
              <TableRow>
                <TableCell>{t('wholesaleOrderDetail:product')}</TableCell>
                <TableCell align="right">{t('wholesaleOrderDetail:qty')}</TableCell>
                <TableCell align="right">{t('wholesaleOrderDetail:endorseStockBeforeAfter')}</TableCell>
                <TableCell>{t('wholesaleOrderDetail:defaultShipStore')}</TableCell>
                <TableCell>{t('wholesaleOrderDetail:endorseSuggestedStore')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {endorsePreview?.lines.map((line) => {
                const item = order?.items?.find((it) => it.id === line.wholesale_order_item_id);
                const lineAssignments = endorsePreview.assignments.filter(
                  (a) => a.wholesale_order_item_id === line.wholesale_order_item_id,
                );
                const hasShortfall = line.shortfall > 0.0001;
                const suggested = lineAssignments
                  .map((a) => `${a.store_name || `Store #${a.store_id}`} (${formatAssignmentQty(a.quantity)})`)
                  .join(', ');
                const stockChange = formatEndorseStockChange(lineAssignments);
                return (
                  <TableRow
                    key={line.wholesale_order_item_id}
                    sx={
                      hasShortfall
                        ? {
                            bgcolor: (theme) => alpha(theme.palette.error.main, 0.08),
                            '& .MuiTableCell-root': { color: 'error.main' },
                          }
                        : undefined
                    }
                  >
                    <TableCell>{productDisplayName(item?.product, lang) || `Product #${line.product_id}`}</TableCell>
                    <TableCell align="right">{formatAssignmentQty(line.needed)}</TableCell>
                    <TableCell align="right">{stockChange}</TableCell>
                    <TableCell>{line.default_store_name || '—'}</TableCell>
                    <TableCell>{suggested || '—'}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </DialogContent>
        <DialogActions sx={{ flexWrap: 'wrap', gap: 1, px: 3, pb: 2 }}>
          <Button onClick={() => setEndorsePreviewOpen(false)} disabled={actioning}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Box sx={{ flex: 1 }} />
          <Button
            variant="outlined"
            disabled={actioning}
            onClick={() => performEndorseConfirm({ autoAssign: false, manualAssign: true })}
          >
            {actioning ? t('wholesaleOrderDetail:endorsing') : t('wholesaleOrderDetail:endorseAssignManually')}
          </Button>
          <Button
            variant="contained"
            color={endorsePreview?.outcome === 'insufficient_stock' ? 'warning' : 'success'}
            disabled={actioning}
            onClick={() =>
              performEndorseConfirm({
                autoAssign: endorsePreview?.outcome === 'single_store' && (endorsePreview?.assignments.length ?? 0) > 0,
              })
            }
          >
            {actioning
              ? t('wholesaleOrderDetail:endorsing')
              : endorsePreview?.outcome === 'single_store'
                ? t('wholesaleOrderDetail:endorseConfirmAndAssign')
                : t('wholesaleOrderDetail:endorseConfirmAnyway')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={assignConfirmOpen}
        onClose={() => !actioning && setAssignConfirmOpen(false)}
        maxWidth="lg"
        fullWidth
      >
        <DialogTitle>{t('wholesaleOrderDetail:assignLinesToStore')}</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            {t('wholesaleOrderDetail:assignTo')} {stores.find((s) => s.id === assignToStoreId)?.name ?? ''}
          </DialogContentText>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>{t('wholesaleOrderDetail:product')}</TableCell>
                <TableCell align="right" sx={{ width: 72 }}>{t('wholesaleOrderDetail:qty')}</TableCell>
                <TableCell align="right" sx={{ width: 72 }}>{t('wholesaleOrderDetail:pendingQty', 'Pending')}</TableCell>
                <TableCell align="right" sx={{ width: 100 }}>{t('wholesaleOrderDetail:assignQty', 'Assign qty')}</TableCell>
                <TableCell align="right" sx={{ width: 100 }}>{t('wholesaleOrderDetail:expectedBoxes', 'Expected boxes')}</TableCell>
                <TableCell sx={{ width: 150 }}>{t('wholesaleOrderDetail:deliveryDate')}</TableCell>
                <TableCell sx={{ width: 160 }}>{t('wholesaleOrderDetail:warning', 'Warning')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {order?.items
                ?.filter((it) => selectedItemIds.has(it.id))
                .map((it) => {
                  const w = assignWarningByItemId[it.id];
                  const pending = pendingQtyForItem(it);
                  return (
                    <TableRow key={it.id}>
                      <TableCell>{productDisplayName(it.product, lang) || `Product #${it.product_id}`}</TableCell>
                      <TableCell align="right">{formatAssignmentQty(it.quantity)}</TableCell>
                      <TableCell align="right">{formatAssignmentQty(pending)}</TableCell>
                      <TableCell align="right">
                        <TextField
                          type="number"
                          size="small"
                          value={assignmentQtyByItemId[it.id] ?? ''}
                          onChange={(e) =>
                            setAssignmentQtyByItemId((prev) => ({ ...prev, [it.id]: e.target.value }))
                          }
                          inputProps={{ min: 0, max: pending, step: 0.001 }}
                          sx={{ width: 96 }}
                        />
                      </TableCell>
                      <TableCell align="right">
                        <TextField
                          type="number"
                          size="small"
                          value={assignmentBoxesByItemId[it.id] ?? ''}
                          onChange={(e) =>
                            setAssignmentBoxesByItemId((prev) => ({ ...prev, [it.id]: e.target.value }))
                          }
                          inputProps={{ min: 0, step: 1 }}
                          sx={{ width: 100 }}
                        />
                      </TableCell>
                      <TableCell>
                        <TextField
                          type="date"
                          size="small"
                          value={assignmentDeliveryDateByItemId[it.id] ?? ''}
                          onChange={(e) =>
                            setAssignmentDeliveryDateByItemId((prev) => ({ ...prev, [it.id]: e.target.value }))
                          }
                          InputLabelProps={{ shrink: true }}
                          sx={{ width: 150 }}
                        />
                      </TableCell>
                      <TableCell sx={{ color: w ? 'warning.main' : 'text.secondary', fontSize: '0.85rem' }}>
                        {w ? `${w.reason}${w.detail ? ` (${w.detail})` : ''}` : '—'}
                      </TableCell>
                    </TableRow>
                  );
                })}
            </TableBody>
          </Table>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAssignConfirmOpen(false)} disabled={actioning}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button
            variant="contained"
            disabled={actioning}
            onClick={async () => {
              const selected = Array.from(selectedItemIds);
              const missing = selected.some((id) => {
                const qty = assignmentQtyByItemId[id]?.trim();
                const boxes = assignmentBoxesByItemId[id]?.trim();
                const date = assignmentDeliveryDateByItemId[id]?.trim();
                return !qty || !boxes || !date;
              });
              const invalidQty = selected.some((id) => {
                const item = order?.items?.find((it) => it.id === id);
                if (!item || !order) return true;
                const pending = pendingQtyForItem(item);
                const qty = parseFloat(assignmentQtyByItemId[id]?.trim() || '0');
                return qty <= 0 || qty > pending + 0.0001;
              });
              if (missing) {
                enqueueSnackbar('Please enter assign quantity, expected boxes and delivery date for each line.', {
                  variant: 'warning',
                });
                return;
              }
              if (invalidQty) {
                enqueueSnackbar('Assign quantity must be greater than 0 and not exceed pending quantity.', {
                  variant: 'warning',
                });
                return;
              }
              setAssignConfirmOpen(false);
              await performAssignment();
            }}
          >
            {actioning
              ? t('wholesaleOrderDetail:assigning')
              : Object.keys(assignWarningByItemId).length > 0
                ? t('wholesaleOrderDetail:assignAnyway')
                : t('wholesaleOrderDetail:ok')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={emailDialogOpen}
        onClose={() => !emailSending && closeEmailDialog()}
        onKeyDown={handleEmailDialogKeyDown}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>
          {emailResendSummary && !emailResendSummary.skipped
            ? t('wholesaleOrderDetail:emailResendTitle')
            : isShipmentDocumentsEmail && order
              ? t('wholesaleOrderDetail:emailShipmentDocumentsTitle', {
                  selected: emailShipmentIds?.length ?? selectedShipmentIdsForEmail.size,
                  total: order.shipments?.length ?? 0,
                })
              : emailKind === 'order_confirm'
                ? t('wholesaleOrderDetail:emailOrderConfirmTitle')
                : emailKind === 'shipments_delivered'
                  ? t('wholesaleOrderDetail:emailShipmentsDeliveredTitle')
                  : emailKind === 'invoice'
                    ? t('wholesaleOrderDetail:emailInvoiceTitle')
                    : t('wholesaleOrderDetail:emailOrderTitle')}
        </DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ pt: 0.5 }}>
            {isShipmentDocumentsEmail && !emailResendSummary && (
              <DialogContentText>
                {t('wholesaleOrderDetail:askSendShipmentDocumentsEmail', {
                  count: emailShipmentIds?.length ?? selectedShipmentIdsForEmail.size,
                })}
              </DialogContentText>
            )}
            {emailKind && !emailResendSummary && !isShipmentDocumentsEmail && (
              <DialogContentText>
                {emailKind === 'order_confirm'
                  ? t('wholesaleOrderDetail:askSendOrderConfirmEmail')
                  : emailKind === 'shipments_delivered'
                    ? t('wholesaleOrderDetail:askSendShipmentsDeliveredEmail')
                    : emailKind === 'invoice'
                      ? t('wholesaleOrderDetail:askSendInvoiceEmail')
                      : ''}
              </DialogContentText>
            )}
            {emailResendSummary && (
              <Alert severity={emailResendSummary.skipped ? 'warning' : 'info'}>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {emailResendSummary.typeLabel}
                </Typography>
                {emailResendSummary.skipped && emailResendSummary.skippedAt && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailStatusSkippedAt', {
                      date: format(new Date(emailResendSummary.skippedAt), 'dd MMM yyyy HH:mm'),
                    })}
                  </Typography>
                )}
                {emailResendSummary.skipped && emailResendSummary.skippedBy ? (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailSkippedBy', { name: emailResendSummary.skippedBy })}
                  </Typography>
                ) : null}
                {emailResendSummary.skipped && emailResendSummary.skipRemark ? (
                  <Typography variant="body2" color="text.secondary" sx={{ fontStyle: 'italic' }}>
                    {t('wholesaleOrderDetail:emailSkipRemark', { remark: emailResendSummary.skipRemark })}
                  </Typography>
                ) : null}
                {!emailResendSummary.skipped && emailResendSummary.sentAt && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailResendSentAt')}:{' '}
                    {format(new Date(emailResendSummary.sentAt), 'dd MMM yyyy HH:mm')}
                  </Typography>
                )}
                {emailResendSummary.skipped && (
                  <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                    {t('wholesaleOrderDetail:emailResendAfterSkipHint')}
                  </Typography>
                )}
                {!emailResendSummary.skipped && emailResendSummary.attachmentTypeLabels.length > 0 && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailResendAttachmentTypes')}:{' '}
                    {emailResendSummary.attachmentTypeLabels.join(', ')}
                  </Typography>
                )}
                {!emailResendSummary.skipped && emailResendSummary.filenames.length > 0 && (
                  <Typography variant="body2" color="text.secondary">
                    {t('wholesaleOrderDetail:emailResendFiles')}: {emailResendSummary.filenames.join(', ')}
                  </Typography>
                )}
              </Alert>
            )}
            {renderEmailChipInput(
              'to',
              t('wholesaleOrderDetail:emailTo'),
              emailTo,
              setEmailTo,
              emailToInput,
              setEmailToInput,
              t('wholesaleOrderDetail:emailAddressListHint'),
              t('wholesaleOrderDetail:emailChipPlaceholder', { defaultValue: 'Type email and press Enter' }),
              true,
            )}
            {renderEmailChipInput(
              'cc',
              t('wholesaleOrderDetail:emailCc'),
              emailCc,
              setEmailCc,
              emailCcInput,
              setEmailCcInput,
              t('wholesaleOrderDetail:emailCcHint'),
            )}
            {renderEmailChipInput(
              'bcc',
              t('wholesaleOrderDetail:emailBcc'),
              emailBcc,
              setEmailBcc,
              emailBccInput,
              setEmailBccInput,
            )}
            <TextField
              label={t('wholesaleOrderDetail:emailSubject')}
              fullWidth
              size="small"
              value={emailSubject}
              onFocus={() => setEmailChipSelection({ field: null, indices: [] })}
              onChange={(e) => {
                setEmailSubject(e.target.value);
                setEmailSubjectLocked(false);
              }}
              helperText={
                emailKind
                  ? t('wholesaleOrderDetail:emailStructuredSubjectHelper')
                  : t('wholesaleOrderDetail:emailSubjectHelper')
              }
            />
            <TextField
              label={t('wholesaleOrderDetail:emailMessage')}
              fullWidth
              size="small"
              multiline
              minRows={6}
              value={emailMessage}
              onFocus={() => setEmailChipSelection({ field: null, indices: [] })}
              onChange={(e) => setEmailMessage(e.target.value)}
              placeholder={t('wholesaleOrderDetail:emailMessagePlaceholder')}
              helperText={t('wholesaleOrderDetail:emailMessageHelper')}
            />
            <Box>
              <Typography variant="subtitle2" sx={{ mb: 1 }}>
                {t('wholesaleOrderDetail:emailAttachments')}
              </Typography>
              {emailKind === 'invoice' &&
                !isShipmentDocumentsEmail &&
                emailAttachmentOptions.some(
                  (opt) =>
                    (opt.key === 'delivery_note' || opt.key === 'signed_delivery_note') && opt.available,
                ) && (
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                    {t('wholesaleOrderDetail:emailInvoiceOptionalAttachmentsHint')}
                  </Typography>
                )}
              {isShipmentDocumentsEmail ? (
                <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                  {t('wholesaleOrderDetail:emailShipmentDocumentsHint')}
                </Typography>
              ) : null}
              <FormGroup>
                {emailAttachmentOptionsForDialog
                  .filter((opt) =>
                    isShipmentDocumentsEmail
                      ? opt.key === 'delivery_note' || opt.key === 'signed_delivery_note'
                      : !emailKind || WHOLESALE_ORDER_EMAIL_ATTACHMENT_KINDS[emailKind].includes(opt.key),
                  )
                  .map((opt) => (
                    <FormControlLabel
                      key={opt.key}
                      control={
                        <Checkbox
                          checked={!!emailAttachments[opt.key]}
                          disabled={
                            !opt.available || isWholesaleOrderEmailAttachmentRequired(emailKind, opt.key)
                          }
                          onChange={(e) =>
                            setEmailAttachments((prev) => ({ ...prev, [opt.key]: e.target.checked }))
                          }
                        />
                      }
                      label={
                        opt.hint
                          ? `${opt.label} ${opt.hint}${opt.available ? '' : ` (${t('wholesaleOrderDetail:emailAttachUnavailable')})`}`
                          : `${opt.label}${opt.available ? '' : ` (${t('wholesaleOrderDetail:emailAttachUnavailable')})`}`
                      }
                    />
                  ))}
              </FormGroup>
            </Box>
          </Stack>
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          {emailKind && !emailResendSummary ? (
            <>
              <Button onClick={handleEmailDialogSkip} disabled={emailSending}>
                {t('wholesaleOrderDetail:emailPromptSkip')}
              </Button>
              <Button onClick={handleEmailDialogLater} disabled={emailSending}>
                {t('wholesaleOrderDetail:emailPromptLater')}
              </Button>
              <Button
                variant="contained"
                startIcon={emailSending ? <CircularProgress size={16} color="inherit" /> : <EmailIcon />}
                disabled={!canSendEmail}
                onClick={() => void sendEmailOrder()}
              >
                {emailSending ? t('wholesaleOrderDetail:sendingEmail') : t('wholesaleOrderDetail:emailSend')}
              </Button>
            </>
          ) : (
            <>
              <Button onClick={handleEmailDialogLater} disabled={emailSending}>
                {t('wholesaleOrderDetail:cancel')}
              </Button>
              <Button
                variant="contained"
                startIcon={emailSending ? <CircularProgress size={16} color="inherit" /> : <EmailIcon />}
                disabled={!canSendEmail}
                onClick={() => void sendEmailOrder()}
              >
                {emailSending ? t('wholesaleOrderDetail:sendingEmail') : t('wholesaleOrderDetail:emailSend')}
              </Button>
            </>
          )}
        </DialogActions>
      </Dialog>

      <Dialog
        open={skipEmailDialogOpen}
        onClose={() => !actioning && setSkipEmailDialogOpen(false)}
        maxWidth={false}
        PaperProps={{
          sx: {
            overflowX: 'hidden',
            width: '100%',
            maxWidth: 440,
            mx: 2,
          },
        }}
      >
        <DialogTitle sx={{ overflowWrap: 'anywhere' }}>
          {skipEmailKind === 'order_confirm'
            ? t('wholesaleOrderDetail:emailSkipDialogTitleOrderConfirm')
            : skipEmailKind === 'shipments_delivered'
              ? t('wholesaleOrderDetail:emailSkipDialogTitleShipmentsDelivered')
              : t('wholesaleOrderDetail:emailSkipDialogTitleInvoice')}
        </DialogTitle>
        <DialogContent
          dividers
          sx={{
            overflowX: 'hidden',
            minWidth: 0,
            boxSizing: 'border-box',
          }}
        >
          <Stack spacing={2} sx={{ width: '100%', minWidth: 0, overflow: 'hidden' }}>
            <DialogContentText component="div" sx={{ m: 0 }}>
              {t('wholesaleOrderDetail:emailSkipDialogHint')}
            </DialogContentText>
            <TextField
              autoFocus
              fullWidth
              multiline
              minRows={2}
              label={t('wholesaleOrderDetail:emailSkipRemarkLabel')}
              placeholder={t('wholesaleOrderDetail:emailSkipRemarkPlaceholder')}
              value={skipEmailRemark}
              onChange={(e) => setSkipEmailRemark(e.target.value)}
              disabled={actioning}
              sx={{
                minWidth: 0,
                '& .MuiInputBase-root': {
                  boxSizing: 'border-box',
                },
                '& textarea': {
                  boxSizing: 'border-box',
                },
              }}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSkipEmailDialogOpen(false)} disabled={actioning}>
            {t('wholesaleOrderDetail:cancel')}
          </Button>
          <Button variant="contained" onClick={() => void handleConfirmSkipEmail()} disabled={actioning}>
            {actioning ? t('wholesaleOrderDetail:saving') : t('wholesaleOrderDetail:emailPromptSkip')}
          </Button>
        </DialogActions>
      </Dialog>

      <DeliveryProofCourierWarningDialog
        open={!!courierPickupWarnShipment}
        onClose={() => setCourierPickupWarnShipment(null)}
        onConfirm={proceedDeliveryProofUpload}
        t={t}
      />
    </Box>
  );
}
