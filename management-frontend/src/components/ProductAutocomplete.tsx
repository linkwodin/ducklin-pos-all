import { useMemo } from 'react';
import { Autocomplete, TextField, Box, Typography } from '@mui/material';
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
      renderInput={(params) => (
        <TextField
          {...params}
          placeholder={placeholder}
          label={label}
          error={error}
        />
      )}
      renderOption={(props, option) => (
        <li {...props} key={option.id}>
          <Box>
            <Typography variant="body2">{option.name}</Typography>
            {option.name_chinese && (
              <Typography variant="caption" color="text.secondary">
                {option.name_chinese}
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
