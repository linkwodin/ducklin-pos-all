import { useState } from 'react';
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  TextField,
  Typography,
} from '@mui/material';
import type { Product } from '../types';
import { productDisplayName } from '../utils/productDisplay';
import ProductImageWithPopover from './ProductImageWithPopover';

type WeightInputDialogProps = {
  open: boolean;
  product: Product | null;
  initialWeightG?: number | null;
  onClose: () => void;
  onConfirm: (weightG: number) => void;
  lang: string;
  title: string;
  confirmLabel: string;
  cancelLabel: string;
  weightLabel: string;
  /** Raise above a parent fullscreen dialog (e.g. packing queue). */
  modalZIndex?: number;
};

export default function WeightInputDialog({
  open,
  product,
  initialWeightG,
  onClose,
  onConfirm,
  lang,
  title,
  confirmLabel,
  cancelLabel,
  weightLabel,
  modalZIndex,
}: WeightInputDialogProps) {
  const [weight, setWeight] = useState(
    initialWeightG != null && initialWeightG > 0 ? String(initialWeightG) : '',
  );

  const handleOpen = () => {
    setWeight(initialWeightG != null && initialWeightG > 0 ? String(initialWeightG) : '');
  };

  const submit = () => {
    const parsed = parseFloat(weight);
    if (parsed > 0) onConfirm(parsed);
  };

  return (
    <Dialog
      open={open}
      onClose={onClose}
      maxWidth="xs"
      fullWidth
      TransitionProps={{ onEnter: handleOpen }}
      sx={modalZIndex != null ? { zIndex: modalZIndex } : undefined}
    >
      <DialogTitle>{title}</DialogTitle>
      <DialogContent>
        {product ? (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
            <ProductImageWithPopover
              imageUrl={product.image_url}
              productName={productDisplayName(product, lang)}
              size={56}
            />
            <Typography variant="subtitle2">{productDisplayName(product, lang)}</Typography>
          </Box>
        ) : null}
        <TextField
          autoFocus
          fullWidth
          type="number"
          label={weightLabel}
          value={weight}
          onChange={(e) => setWeight(e.target.value)}
          inputProps={{ min: 0, step: 0.01 }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit();
          }}
        />
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{cancelLabel}</Button>
        <Button variant="contained" onClick={submit}>
          {confirmLabel}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
