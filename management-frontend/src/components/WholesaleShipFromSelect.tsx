import { FormControl, MenuItem, Select, Typography } from '@mui/material';
import { useTranslation } from 'react-i18next';
import type { Stock, Store } from '../types';

type Props = {
  assignments: Stock[];
  stores: Store[];
  value: number | '';
  readOnly?: boolean;
  disabled?: boolean;
  onChange?: (storeId: number | '') => void;
};

export default function WholesaleShipFromSelect({
  assignments,
  stores,
  value,
  readOnly = false,
  disabled,
  onChange,
}: Props) {
  const { t } = useTranslation(['productLineDetail', 'storeDetail']);

  const storeLabel = (storeId: number) => {
    const row = assignments.find((r) => r.store_id === storeId);
    return row?.store?.name ?? stores.find((s) => s.id === storeId)?.name ?? `Store #${storeId}`;
  };

  const displayValue = value === '' ? t('productLineDetail.wholesaleShipStoreNone', 'Not set') : storeLabel(value);

  if (assignments.length === 0) {
    return (
      <Typography variant="body2" color="text.secondary" noWrap>
        {t('storeDetail.notAssignedToStore', 'Not at any store')}
      </Typography>
    );
  }

  if (readOnly) {
    return (
      <Typography variant="body2" noWrap title={value === '' ? undefined : displayValue}>
        {displayValue}
      </Typography>
    );
  }

  return (
    <FormControl size="small" fullWidth disabled={disabled}>
      <Select<number | ''>
        value={value}
        displayEmpty
        onChange={(e) => onChange?.(e.target.value === '' ? '' : Number(e.target.value))}
        renderValue={(selected) => {
          if (selected === '') {
            return (
              <Typography variant="body2" color="text.secondary" component="span">
                {t('productLineDetail.wholesaleShipStoreNone', 'Not set')}
              </Typography>
            );
          }
          return storeLabel(selected);
        }}
      >
        <MenuItem value="">
          <em>{t('productLineDetail.wholesaleShipStoreNone', 'Not set')}</em>
        </MenuItem>
        {assignments.map((row) => (
          <MenuItem key={row.store_id} value={row.store_id}>
            {storeLabel(row.store_id)}
          </MenuItem>
        ))}
      </Select>
    </FormControl>
  );
}
