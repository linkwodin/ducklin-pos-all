import { useState } from 'react';
import {
  Box, Button, TextField, Typography, Chip, Dialog, DialogTitle,
  DialogContent, DialogActions, Select, MenuItem, Divider, Stack,
} from '@mui/material';
import { CalendarMonth as CalendarIcon } from '@mui/icons-material';

export type DateRangeMode = 'quarter' | 'custom' | 'current';

export interface DateRangeValue {
  effectiveFrom: string;
  effectiveTo: string;
  mode: DateRangeMode;
}

interface Props {
  value: DateRangeValue;
  onChange: (v: DateRangeValue) => void;
}

function quarterDates(year: number, q: number): [string, string] {
  const startMonths = [1, 4, 7, 10];
  const endMonths = [3, 6, 9, 12];
  const lastDay = new Date(year, endMonths[q - 1], 0).getDate();
  const pad = (n: number) => String(n).padStart(2, '0');
  return [`${year}-${pad(startMonths[q - 1])}-01`, `${year}-${pad(endMonths[q - 1])}-${pad(lastDay)}`];
}

function fullYearDates(year: number): [string, string] {
  return [`${year}-01-01`, `${year}-12-31`];
}

function today(): string {
  return new Date().toISOString().substring(0, 10);
}

function formatLabel(v: DateRangeValue): string {
  if (v.mode === 'current') return `From ${today()}`;
  if (!v.effectiveFrom || !v.effectiveTo) return 'Select period';
  const f = v.effectiveFrom;
  const t = v.effectiveTo;
  const fy = f.substring(0, 4);
  if (f === `${fy}-01-01` && t === `${fy}-12-31`) return `Full Year ${fy}`;
  for (let q = 1; q <= 4; q++) {
    const [qf, qt] = quarterDates(Number(fy), q);
    if (f === qf && t === qt) return `${fy} Q${q}`;
  }
  return `${f} → ${t}`;
}

export default function DateRangeSelector({ value, onChange }: Props) {
  const currentYear = new Date().getFullYear();
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<DateRangeValue>(value);
  const [selectedYear, setSelectedYear] = useState(currentYear);
  const yearOptions = Array.from({ length: 7 }, (_, i) => currentYear - 3 + i);

  const handleOpen = () => {
    setDraft(value);
    if (value.mode === 'quarter' && value.effectiveFrom) {
      setSelectedYear(Number(value.effectiveFrom.substring(0, 4)));
    }
    setOpen(true);
  };

  const handleApply = () => {
    onChange(draft);
    setOpen(false);
  };

  const isActive = (f: string, t: string) =>
    draft.effectiveFrom === f && draft.effectiveTo === t && draft.mode !== 'current';

  const pick = (f: string, t: string) => setDraft({ effectiveFrom: f, effectiveTo: t, mode: 'quarter' });

  return (
    <>
      <Chip
        icon={<CalendarIcon sx={{ fontSize: 16 }} />}
        label={formatLabel(value)}
        onClick={handleOpen}
        variant="outlined"
        sx={{ fontSize: 13, height: 32, cursor: 'pointer' }}
      />

      <Dialog open={open} onClose={() => setOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ pb: 0.5 }}>Effective Period</DialogTitle>
        <DialogContent sx={{ pt: '12px !important' }}>
          {/* Custom date range */}
          <Stack direction="row" spacing={2} sx={{ mb: 3 }}>
            <TextField
              fullWidth
              size="small"
              type="date"
              label="From"
              value={draft.effectiveFrom}
              onChange={(e) => setDraft({ effectiveFrom: e.target.value, effectiveTo: draft.effectiveTo, mode: 'custom' })}
              InputLabelProps={{ shrink: true }}
            />
            <TextField
              fullWidth
              size="small"
              type="date"
              label="To"
              value={draft.effectiveTo}
              onChange={(e) => setDraft({ effectiveFrom: draft.effectiveFrom, effectiveTo: e.target.value, mode: 'custom' })}
              InputLabelProps={{ shrink: true }}
            />
          </Stack>

          <Divider textAlign="left" sx={{ mb: 2 }}>
            <Typography variant="caption" color="text.secondary">Quick select</Typography>
          </Divider>

          {/* Year + quarters */}
          <Stack spacing={1.5}>
            {/* Year selector row */}
            <Stack direction="row" spacing={1} alignItems="center">
              <Typography variant="body2" color="text.secondary" sx={{ minWidth: 36 }}>Year</Typography>
              <Select
                size="small"
                value={selectedYear}
                onChange={(e) => setSelectedYear(e.target.value as number)}
                sx={{ minWidth: 85, height: 32 }}
              >
                {yearOptions.map((yr) => (
                  <MenuItem key={yr} value={yr}>{yr}</MenuItem>
                ))}
              </Select>
              <Chip
                label={`Full ${selectedYear}`}
                size="small"
                onClick={() => pick(...fullYearDates(selectedYear))}
                color={isActive(...fullYearDates(selectedYear)) ? 'primary' : 'default'}
                variant={isActive(...fullYearDates(selectedYear)) ? 'filled' : 'outlined'}
                sx={{ ml: 1 }}
              />
            </Stack>

            {/* Quarter row */}
            <Stack direction="row" spacing={1} alignItems="center">
              <Typography variant="body2" color="text.secondary" sx={{ minWidth: 36 }}>Qtr</Typography>
              {[1, 2, 3, 4].map((q) => {
                const [f, t] = quarterDates(selectedYear, q);
                const active = isActive(f, t);
                return (
                  <Chip
                    key={q}
                    label={`Q${q}`}
                    size="small"
                    onClick={() => pick(f, t)}
                    color={active ? 'primary' : 'default'}
                    variant={active ? 'filled' : 'outlined'}
                    sx={{ minWidth: 44 }}
                  />
                );
              })}
            </Stack>

            <Divider sx={{ my: 0.5 }} />

            {/* From today */}
            <Chip
              label={`From today (${today()})`}
              size="small"
              onClick={() => setDraft({ effectiveFrom: today(), effectiveTo: '', mode: 'current' })}
              color={draft.mode === 'current' ? 'success' : 'default'}
              variant={draft.mode === 'current' ? 'filled' : 'outlined'}
              sx={{ alignSelf: 'flex-start' }}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleApply}>Apply</Button>
        </DialogActions>
      </Dialog>
    </>
  );
}
