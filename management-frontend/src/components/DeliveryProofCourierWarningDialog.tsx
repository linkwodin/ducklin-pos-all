import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
} from '@mui/material';
import type { TFunction } from 'i18next';

type DeliveryProofCourierWarningDialogProps = {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  t: TFunction;
};

export default function DeliveryProofCourierWarningDialog({
  open,
  onClose,
  onConfirm,
  t,
}: DeliveryProofCourierWarningDialogProps) {
  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{t('wholesaleOrderDetail:uploadSignedDeliveryNoteAwaitingCourier')}</DialogTitle>
      <DialogContent>
        <DialogContentText>{t('wholesaleOrderDetail:uploadSignedDeliveryNoteAwaitingCourierConfirm')}</DialogContentText>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('wholesaleOrderDetail:cancel')}</Button>
        <Button color="warning" variant="contained" onClick={onConfirm}>
          {t('wholesaleOrderDetail:uploadSignedDeliveryNoteAwaitingCourierProceed')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
