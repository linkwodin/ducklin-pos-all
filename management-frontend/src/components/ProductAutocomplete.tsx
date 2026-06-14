import { useMemo } from 'react';
import { Autocomplete, TextField, Box, Typography, ListSubheader, useMediaQuery } from '@mui/material';
import { useTheme } from '@mui/material/styles';
import type { Product } from '../types';
import { normalizeCategory } from '../utils/category';

interface Props {
  products: Product[];
  value: number | '' | null;
  onChange: (productId: number | null) => void;
  size?: 'small' | 'medium';
  placeholder?: string;
  error?: boolean;
  fullWidth?: boolean;
  label?: string;
}

export default function ProductAutocomplete({
  products,
  value,
  onChange,
  size = 'small',
  placeholder = 'Search product...',
  error = false,
  fullWidth = true,
  label,
}: Props) {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  const selected = products.find((p) => p.id === value) || null;
  // Sort by normalized category so same-category options are adjacent and group under one header
  const optionsSorted = useMemo(
    () =>
      [...products].sort(
        (a, b) =>
          normalizeCategory(a.category || '').localeCompare(normalizeCategory(b.category || '')) ||
          (a.name || '').localeCompare(b.name || '')
      ),
    [products]
  );

  return (
    <Autocomplete
      size={size}
      fullWidth={fullWidth}
      options={optionsSorted}
      groupBy={(option) => normalizeCategory(option.category || '') || 'Uncategorized'}
      getOptionLabel={(option) =>
        `${option.name}${option.name_chinese ? ` (${option.name_chinese})` : ''}`
      }
      value={selected}
      onChange={(_, newVal) => onChange(newVal?.id ?? null)}
      filterOptions={(options, { inputValue }) => {
        const q = inputValue.toLowerCase();
        return options.filter(
          (o) =>
            o.name.toLowerCase().includes(q) ||
            (o.name_chinese && o.name_chinese.includes(inputValue)) ||
            (o.barcode && o.barcode.includes(inputValue)) ||
            (o.sku && o.sku.toLowerCase().includes(q))
        );
      }}
      ListboxProps={{
        sx: {
          maxHeight: isMobile ? 'min(60vh, 360px)' : 320,
          '& .MuiAutocomplete-option': {
            alignItems: 'flex-start',
            py: isMobile ? 1.25 : 0.75,
            whiteSpace: 'normal',
          },
        },
      }}
      componentsProps={{
        popper: {
          placement: 'bottom-start',
          sx: isMobile
            ? {
                width: 'min(calc(100vw - 24px), 480px) !important',
                maxWidth: 'min(calc(100vw - 24px), 480px) !important',
              }
            : undefined,
        },
        paper: {
          sx: isMobile ? { width: '100%' } : undefined,
        },
      }}
      renderInput={(params) => (
        <TextField
          {...params}
          placeholder={placeholder}
          label={label}
          error={error}
          inputProps={{
            ...params.inputProps,
            style: {
              ...params.inputProps?.style,
              ...(isMobile ? { whiteSpace: 'normal', overflow: 'visible', textOverflow: 'clip' } : {}),
            },
          }}
          sx={
            isMobile
              ? {
                  '& .MuiInputBase-root': { alignItems: 'flex-start', py: 0.75 },
                  '& .MuiInputBase-input': { whiteSpace: 'normal', overflow: 'visible', textOverflow: 'clip' },
                }
              : undefined
          }
        />
      )}
      renderGroup={(params) => (
        <li key={params.key}>
          <ListSubheader
            component="div"
            disableSticky={false}
            sx={{
              bgcolor: 'grey.100',
              lineHeight: 2,
              fontWeight: 700,
              fontSize: '0.75rem',
            }}
          >
            {params.group}
          </ListSubheader>
          <ul style={{ padding: 0 }}>{params.children}</ul>
        </li>
      )}
      renderOption={(props, option) => (
        <li {...props} key={option.id}>
          <Box sx={{ minWidth: 0, width: '100%' }}>
            <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
              {option.name}
            </Typography>
            {option.name_chinese && (
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', wordBreak: 'break-word' }}>
                {option.name_chinese}
              </Typography>
            )}
            {(option.sku || option.barcode) && (
              <Typography variant="caption" color="text.disabled" sx={{ display: 'block' }}>
                {[option.sku, option.barcode].filter(Boolean).join(' · ')}
              </Typography>
            )}
          </Box>
        </li>
      )}
      isOptionEqualToValue={(option, val) => option.id === val.id}
      clearOnBlur
      blurOnSelect
      noOptionsText="No products found"
    />
  );
}
