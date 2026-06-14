import type { SxProps, Theme } from '@mui/material';

/** Fixed column widths for product lines list variant table (sums to 100%). */
export const VARIANT_TABLE_COLS_LIST = ['20%', '14%', '30%', '16%', '20%'] as const;

/** Fixed column widths for product line detail variant table (sums to 100%). */
export const VARIANT_TABLE_COLS_WITH_PRICE = ['12%', '8%', '7%', '14%', '9%', '9%', '13%', '28%'] as const;

export const productLineVariantTableSx: SxProps<Theme> = {
  tableLayout: 'fixed',
  width: '100%',
  '& .MuiTableCell-root': {
    px: 1.25,
    py: 1,
  },
  '& .MuiInputBase-root': {
    fontSize: '0.8125rem',
  },
};

export const productLineVariantCellSx: SxProps<Theme> = {
  maxWidth: 0,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
  verticalAlign: 'middle',
};

export const productLineVariantActionsCellSx: SxProps<Theme> = {
  whiteSpace: 'nowrap',
  verticalAlign: 'middle',
};

/** Allow variant column to wrap label text in view mode. */
export const productLineVariantLabelCellSx: SxProps<Theme> = {
  maxWidth: 0,
  overflow: 'hidden',
  verticalAlign: 'middle',
  whiteSpace: 'normal',
  wordBreak: 'break-word',
};

/** Edit-mode variant inputs — no word-break on adornments (e.g. "per"). */
export const productLineVariantEditLabelCellSx: SxProps<Theme> = {
  maxWidth: 0,
  overflow: 'hidden',
  verticalAlign: 'middle',
  whiteSpace: 'nowrap',
};
