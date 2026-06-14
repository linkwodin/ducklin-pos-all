import { useMemo } from 'react';
import { Box, Typography } from '@mui/material';
import { renderBarcodeSvg, type RenderBarcodeOptions } from '../utils/barcodeImage';

type BarcodeSvgProps = {
  value: string;
  label?: string;
  maxWidth?: number;
  renderOptions?: RenderBarcodeOptions;
};

export default function BarcodeSvg({ value, label, maxWidth = 200, renderOptions }: BarcodeSvgProps) {
  const html = useMemo(() => renderBarcodeSvg(value, renderOptions), [value, renderOptions]);

  if (!html) {
    return (
      <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>
        {value || '—'}
      </Typography>
    );
  }

  return (
    <Box sx={{ mb: label ? 0.5 : 0 }}>
      {label ? (
        <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.25 }}>
          {label}
        </Typography>
      ) : null}
      <Box
        sx={{ maxWidth, '& svg': { maxWidth: '100%', height: 'auto', display: 'block' } }}
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </Box>
  );
}
