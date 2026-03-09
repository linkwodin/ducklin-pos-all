import { useState } from 'react';
import { Box, Popover } from '@mui/material';

interface ProductImageWithPopoverProps {
  imageUrl?: string | null;
  productName?: string;
  size?: number;
}

export default function ProductImageWithPopover({
  imageUrl,
  productName = '',
  size = 40,
}: ProductImageWithPopoverProps) {
  const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);

  const handleClick = (event: React.MouseEvent<HTMLElement>) => {
    event.stopPropagation();
    if (!imageUrl) return;
    setAnchorEl((prev) => (prev ? null : event.currentTarget));
  };

  const handleClose = () => setAnchorEl(null);

  const open = Boolean(anchorEl);

  if (!imageUrl?.trim()) {
    return (
      <Box
        sx={{
          width: size,
          height: size,
          bgcolor: 'grey.200',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          borderRadius: 1,
          color: 'grey.500',
          fontSize: size * 0.5,
        }}
      >
        ?
      </Box>
    );
  }

  return (
    <>
      <Box
        component="img"
        src={imageUrl}
        alt={productName}
        onClick={handleClick}
        sx={{
          width: size,
          height: size,
          objectFit: 'cover',
          borderRadius: 1,
          border: '1px solid',
          borderColor: 'divider',
          cursor: imageUrl ? 'pointer' : 'default',
        }}
      />
      <Popover
        open={open}
        anchorEl={anchorEl}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'left' }}
        transformOrigin={{ vertical: 'top', horizontal: 'left' }}
        onClose={handleClose}
        disableRestoreFocus
      >
        <Box
          component="img"
          src={imageUrl}
          alt={productName}
          sx={{
            maxWidth: 320,
            maxHeight: 320,
            objectFit: 'contain',
            display: 'block',
          }}
        />
      </Popover>
    </>
  );
}
