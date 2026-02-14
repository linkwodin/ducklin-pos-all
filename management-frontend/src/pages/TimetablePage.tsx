import { useEffect, useState, useMemo } from 'react';
import {
  Box,
  Paper,
  Typography,
  TextField,
  FormControl,
  FormControlLabel,
  FormGroup,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Alert,
  Checkbox,
  ListItemText,
  OutlinedInput,
} from '@mui/material';
import { useTranslation } from 'react-i18next';
import { userActivityAPI, usersAPI, storesAPI } from '../services/api';
import type { UserActivityEvent, User, Store } from '../types';

// 8:00–22:00 like calendar day view
const TIME_FIRST = 8;
const TIME_LAST = 22;
const TIME_SLOTS = Array.from({ length: TIME_LAST - TIME_FIRST + 1 }, (_, i) => i + TIME_FIRST);
const SLOT_HEIGHT = 48;
const TIME_COLUMN_WIDTH = 72;
const STORE_COLUMN_MIN_WIDTH = 200;
const BLOCK_MIN_HEIGHT = 44;
const BLOCK_GAP = 4;

function formatTime(iso: string): string {
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed.toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

function timeToSlotMinutes(iso: string): number {
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return 0;
  return parsed.getHours() * 60 + parsed.getMinutes();
}

function getDayViewHeader(dateStr: string): { weekday: string; dayNum: string } {
  if (!dateStr || dateStr.length < 10) return { weekday: '—', dayNum: '—' };
  const d = new Date(dateStr + 'T12:00:00');
  if (Number.isNaN(d.getTime())) return { weekday: '—', dayNum: '—' };
  return {
    weekday: d.toLocaleDateString(undefined, { weekday: 'short' }),
    dayNum: d.getDate().toString(),
  };
}

function getTimezoneLabel(): string {
  const offset = -new Date().getTimezoneOffset();
  const sign = offset >= 0 ? '+' : '-';
  const abs = Math.abs(offset);
  const h = Math.floor(abs / 60);
  const m = abs % 60;
  return m ? `GMT${sign}${h}:${String(m).padStart(2, '0')}` : `GMT${sign}${h}`;
}

/** One row in the day view: derived from events (first_login + done/skipped) for a user+store on a date */
interface TimetableRow {
  id: string;
  user_id: number;
  store_id: number | null;
  first_login_at: string;
  status: 'pending' | 'done' | 'skipped';
  done_at?: string;
  skip_reason?: string;
  user?: User;
  store?: Store | null;
}

/** Aggregate events for a single day into timetable rows.
 * For each user+store on that date we may create up to TWO rows:
 * - one for "login with day-start stocktake skipped" (at first_login time, using skip reason)
 * - one for "day-start stocktake done" (at done time)
 * If there's only done (no skip), we keep the old behaviour: a single row at first_login with "done at" time.
 */
function aggregateEventsToRows(events: UserActivityEvent[], date: string): TimetableRow[] {
  const byKey = new Map<string, { firstLogin?: UserActivityEvent; done?: UserActivityEvent; skipped?: UserActivityEvent }>();
  const dateStr = date.slice(0, 10);

  events.forEach((ev) => {
    const evDate = ev.occurred_at.slice(0, 10);
    if (evDate !== dateStr) return;
    const storeId = ev.store_id ?? 0;
    const key = `${ev.user_id}_${storeId}`;
    if (!byKey.has(key)) byKey.set(key, {});
    const group = byKey.get(key)!;
    if (ev.event_type === 'first_login') group.firstLogin = ev;
    else if (ev.event_type === 'stocktake_day_start_done') group.done = ev;
    else if (ev.event_type === 'stocktake_day_start_skipped') group.skipped = ev;
  });

  const rows: TimetableRow[] = [];
  byKey.forEach((group, key) => {
    const firstLogin = group.firstLogin;
    if (!firstLogin) return;
    const [userId, storeIdStr] = key.split('_');
    const storeId = storeIdStr === '0' ? null : parseInt(storeIdStr, 10);
    const done = group.done;
    const skipped = group.skipped;
    const userIdNum = parseInt(userId, 10);

    // 1) If there's a skipped event, create a row at FIRST LOGIN time with the skip reason.
    if (skipped) {
      rows.push({
        id: `${key}_skipped`,
        user_id: userIdNum,
        store_id: storeId,
        first_login_at: firstLogin.occurred_at,
        status: 'skipped',
        skip_reason: skipped.skip_reason,
        user: firstLogin.user,
        store: firstLogin.store ?? (storeId ? undefined : null),
      });
    }

    // 2) If there's a done event, create a row.
    if (done) {
      const hasSkip = !!skipped;
      const doneAt = done.occurred_at;
      const firstTimeForDone = hasSkip ? doneAt : firstLogin.occurred_at;
      rows.push({
        id: `${key}_done`,
        user_id: userIdNum,
        store_id: storeId,
        first_login_at: firstTimeForDone,
        status: 'done',
        done_at: hasSkip ? undefined : doneAt, // when also skipped, we only show the done time via position, not as extra text
        user: firstLogin.user,
        store: firstLogin.store ?? (storeId ? undefined : null),
      });
    }

    // 3) If no done/skip yet, keep a single pending row.
    if (!done && !skipped) {
      rows.push({
        id: `${key}_pending`,
        user_id: userIdNum,
        store_id: storeId,
        first_login_at: firstLogin.occurred_at,
        status: 'pending',
        user: firstLogin.user,
        store: firstLogin.store ?? (storeId ? undefined : null),
      });
    }
  });
  return rows;
}

export default function TimetablePage() {
  const { t } = useTranslation();
  const [events, setEvents] = useState<UserActivityEvent[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [userId, setUserId] = useState<number | ''>('');
  const [storeIds, setStoreIds] = useState<number[]>([]);
  const [eventFilter, setEventFilter] = useState({
    loginDayStartDone: true,
    loginDayStartSkipped: true,
    logoutDayEndDone: true,
    logoutDayEndSkipped: true,
  });

  const fetchUsers = async () => {
    try {
      const data = await usersAPI.list();
      setUsers(data);
    } catch (_) {}
  };

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list();
      setStores(data);
    } catch (_) {}
  };

  const fetchEvents = async () => {
    try {
      setLoading(true);
      setError(null);
      const params: { from: string; to: string; user_id?: number; store_ids?: number[]; event_type?: string[] } = {
        from: date,
        to: date,
      };
      if (userId !== '') params.user_id = userId;
      if (storeIds.length > 0) params.store_ids = storeIds;
      params.event_type = [
        'first_login',
        'stocktake_day_start_done',
        'stocktake_day_start_skipped',
        'logout',
        'stocktake_day_end_skipped',
      ];
      const data = await userActivityAPI.list(params);
      setEvents(data);
    } catch (e: any) {
      setError(e?.response?.data?.error || 'Failed to load timetable');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchUsers();
    fetchStores();
  }, []);

  useEffect(() => {
    fetchEvents();
  }, [date, userId, storeIds]);

  const rows = useMemo(() => aggregateEventsToRows(events, date), [events, date]);

  /** Logout and day-end skip events for the selected day, grouped by store_id (0 for null) */
  const logoutAndDayEndByStore = useMemo(() => {
    const dateStr = date.slice(0, 10);
    const list = events.filter(
      (ev) =>
        ev.occurred_at.slice(0, 10) === dateStr &&
        (ev.event_type === 'logout' || ev.event_type === 'stocktake_day_end_skipped')
    );
    const map = new Map<number, UserActivityEvent[]>();
    list.forEach((ev) => {
      const sid = ev.store_id ?? 0;
      if (!map.has(sid)) map.set(sid, []);
      map.get(sid)!.push(ev);
    });
    map.forEach((arr) => arr.sort((a, b) => a.occurred_at.localeCompare(b.occurred_at)));
    return map;
  }, [events, date]);

  /** Rows filtered by event type checkboxes */
  const filteredRows = useMemo(() => {
    return rows.filter((r) => {
      if (r.status === 'done') return eventFilter.loginDayStartDone;
      if (r.status === 'skipped') return eventFilter.loginDayStartSkipped;
      return eventFilter.loginDayStartDone || eventFilter.loginDayStartSkipped;
    });
  }, [rows, eventFilter]);

  /** Logout/day-end events filtered by event type checkboxes */
  const filteredLogoutAndDayEndByStore = useMemo(() => {
    const map = new Map<number, UserActivityEvent[]>();
    logoutAndDayEndByStore.forEach((evs, storeId) => {
      const filtered = evs.filter((ev) => {
        if (ev.event_type === 'logout') return eventFilter.logoutDayEndDone;
        if (ev.event_type === 'stocktake_day_end_skipped') return eventFilter.logoutDayEndSkipped;
        return false;
      });
      if (filtered.length > 0) map.set(storeId, filtered);
    });
    return map;
  }, [logoutAndDayEndByStore, eventFilter]);

  /** Columns to show: when stores selected, those; else stores from filtered rows + filtered logout/day-end events */
  const storesToShow = useMemo(() => {
    if (storeIds.length > 0) {
      return storeIds
        .map((id) => {
          const s = stores.find((st) => st.id === id);
          return s ? { id: s.id, name: s.name } : null;
        })
        .filter((s): s is { id: number; name: string } => s != null)
        .sort((a, b) => a.name.localeCompare(b.name));
    }
    const storeIdsFromRows = new Set(
      filteredRows.map((r) => r.store?.id ?? r.store_id ?? 0)
    );
    const storeIdsFromLogout = new Set(filteredLogoutAndDayEndByStore.keys());
    const allIds = new Set([...storeIdsFromRows, ...storeIdsFromLogout]);
    const withNames = Array.from(allIds).map((id) => ({
      id,
      name: id === 0 ? '—' : stores.find((s) => s.id === id)?.name ?? `Store ${id}`,
    }));
    return withNames.sort((a, b) => (a.id === 0 ? 1 : b.id === 0 ? -1 : a.name.localeCompare(b.name)));
  }, [storeIds, stores, filteredRows, filteredLogoutAndDayEndByStore]);

  const recordsByStore = useMemo(() => {
    const map = new Map<number, TimetableRow[]>();
    storesToShow.forEach((s) => map.set(s.id, []));
    filteredRows.forEach((r) => {
      const sid = r.store?.id ?? r.store_id ?? 0;
      const list = map.get(sid);
      if (list) list.push(r);
    });
    return map;
  }, [filteredRows, storesToShow]);

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 2 }}>
        {t('layout.timetable')}
      </Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Day view from activity events (first login and stocktake result per store).
      </Typography>

      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center', mb: 2 }}>
        <TextField
          label="Date"
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          InputLabelProps={{ shrink: true }}
          size="small"
        />
        <FormControl size="small" sx={{ minWidth: 180 }}>
          <InputLabel>User</InputLabel>
          <Select
            value={userId}
            label="User"
            onChange={(e) => setUserId(e.target.value === '' ? '' : Number(e.target.value))}
          >
            <MenuItem value="">All users</MenuItem>
            {users.map((u) => (
              <MenuItem key={u.id} value={u.id}>
                {u.first_name} {u.last_name} ({u.username})
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        <FormControl size="small" sx={{ minWidth: 220 }}>
          <InputLabel>Stores</InputLabel>
          <Select
            multiple
            value={storeIds}
            label="Stores"
            onChange={(e) => setStoreIds(Array.isArray(e.target.value) ? e.target.value : [])}
            input={<OutlinedInput label="Stores" />}
            renderValue={(selected) =>
              selected.length === 0
                ? 'All stores'
                : selected
                    .map((id) => stores.find((s) => s.id === id)?.name ?? id)
                    .join(', ')
            }
          >
            {stores.map((store) => (
              <MenuItem key={store.id} value={store.id}>
                <Checkbox checked={storeIds.indexOf(store.id) > -1} size="small" sx={{ mr: 1 }} />
                <ListItemText primary={store.name} />
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        <FormGroup row sx={{ ml: 1 }}>
          <FormControlLabel
            control={
              <Checkbox
                checked={eventFilter.loginDayStartDone}
                onChange={(_, v) =>
                  setEventFilter((f) => ({ ...f, loginDayStartDone: v }))
                }
              />
            }
            label="Login with day start stocktake done"
          />
          <FormControlLabel
            control={
              <Checkbox
                checked={eventFilter.loginDayStartSkipped}
                onChange={(_, v) =>
                  setEventFilter((f) => ({ ...f, loginDayStartSkipped: v }))
                }
              />
            }
            label="Login with day start stocktake skipped"
          />
          <FormControlLabel
            control={
              <Checkbox
                checked={eventFilter.logoutDayEndDone}
                onChange={(_, v) =>
                  setEventFilter((f) => ({ ...f, logoutDayEndDone: v }))
                }
              />
            }
            label="Logout with day end stocktake done"
          />
          <FormControlLabel
            control={
              <Checkbox
                checked={eventFilter.logoutDayEndSkipped}
                onChange={(_, v) =>
                  setEventFilter((f) => ({ ...f, logoutDayEndSkipped: v }))
                }
              />
            }
            label="Logout with day end stocktake skipped"
          />
        </FormGroup>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
          <CircularProgress />
        </Box>
      ) : (
        <DayView
          date={date}
          storesToShow={storesToShow}
          recordsByStore={recordsByStore}
          logoutAndDayEndByStore={filteredLogoutAndDayEndByStore}
          formatTime={formatTime}
          timeToSlotMinutes={timeToSlotMinutes}
        />
      )}
    </Box>
  );
}

function DayView({
  date,
  storesToShow,
  recordsByStore,
  logoutAndDayEndByStore,
  formatTime,
  timeToSlotMinutes,
}: {
  date: string;
  storesToShow: { id: number; name: string }[];
  recordsByStore: Map<number, TimetableRow[]>;
  logoutAndDayEndByStore: Map<number, UserActivityEvent[]>;
  formatTime: (iso: string) => string;
  timeToSlotMinutes: (iso: string) => number;
}) {
  const { weekday, dayNum } = getDayViewHeader(date);
  const timezoneLabel = getTimezoneLabel();
  const totalHeight = TIME_SLOTS.length * SLOT_HEIGHT;
  const hour0Minutes = TIME_FIRST * 60;

  return (
    <Paper sx={{ overflow: 'hidden' }}>
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          gap: 2,
          px: 2,
          py: 2,
          borderBottom: 1,
          borderColor: 'divider',
        }}
      >
        <Typography variant="h6" color="text.secondary" fontWeight={500}>
          {weekday}
        </Typography>
        <Box
          sx={{
            width: 40,
            height: 40,
            borderRadius: '50%',
            bgcolor: 'primary.main',
            color: 'primary.contrastText',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontWeight: 700,
            fontSize: '1rem',
          }}
        >
          {dayNum}
        </Box>
        <Typography variant="caption" color="text.secondary" sx={{ ml: 1 }}>
          {timezoneLabel}
        </Typography>
      </Box>

      <Box sx={{ display: 'flex', minHeight: 32 + totalHeight }}>
        <Box
          sx={{
            width: TIME_COLUMN_WIDTH,
            flexShrink: 0,
            borderRight: 1,
            borderColor: 'divider',
            bgcolor: 'grey.50',
          }}
        >
          <Box sx={{ height: 32, borderBottom: 1, borderColor: 'divider' }} />
          {TIME_SLOTS.map((hour) => (
            <Box
              key={hour}
              sx={{
                height: SLOT_HEIGHT,
                display: 'flex',
                alignItems: 'flex-start',
                justifyContent: 'flex-end',
                pr: 1.5,
                pt: 0.5,
              }}
            >
              <Typography variant="caption" color="text.secondary">
                {hour.toString().padStart(2, '0')}:00
              </Typography>
            </Box>
          ))}
        </Box>

        {storesToShow.length === 0 ? (
          <Box
            sx={{
              flex: 1,
              minWidth: STORE_COLUMN_MIN_WIDTH,
              height: 32 + totalHeight,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              bgcolor: 'grey.50',
              borderBottom: 1,
              borderColor: 'divider',
            }}
          >
            <Typography variant="body2" color="text.secondary">
              No events for this day.
            </Typography>
          </Box>
        ) : (
          storesToShow.map((store) => {
            const list = recordsByStore.get(store.id) ?? [];
            return (
              <Box
                key={store.id}
                sx={{
                  flex: 1,
                  minWidth: STORE_COLUMN_MIN_WIDTH,
                  borderRight: 1,
                  borderColor: 'divider',
                  position: 'relative',
                  height: 32 + totalHeight,
                }}
              >
                <Box
                  sx={{
                    height: 32,
                    display: 'flex',
                    alignItems: 'center',
                    px: 1.5,
                    borderBottom: 1,
                    borderColor: 'divider',
                    bgcolor: 'grey.100',
                  }}
                >
                  <Typography variant="subtitle2" fontWeight={600}>
                    {store.name}
                  </Typography>
                </Box>
                <Box sx={{ position: 'relative', height: totalHeight }}>
                  {TIME_SLOTS.map((hour) => (
                    <Box
                      key={hour}
                      sx={{
                        height: SLOT_HEIGHT,
                        borderBottom: 1,
                        borderColor: 'divider',
                      }}
                    />
                  ))}
                  {(() => {
                    type SlotItem =
                      | { type: 'row'; time: string; data: TimetableRow }
                      | { type: 'event'; time: string; data: UserActivityEvent };
                    const slotItems: SlotItem[] = [
                      ...list.map((r) => ({ type: 'row' as const, time: r.first_login_at, data: r })),
                      ...(logoutAndDayEndByStore.get(store.id) ?? []).map((ev) => ({
                        type: 'event' as const,
                        time: ev.occurred_at,
                        data: ev,
                      })),
                    ].sort((a, b) => a.time.localeCompare(b.time));

                    let nextTop = 0;
                    return slotItems.map((item) => {
                      const idealTop =
                        ((timeToSlotMinutes(item.time) - hour0Minutes) / 60) * SLOT_HEIGHT + 2;
                      const top = Math.max(0, Math.max(idealTop, nextTop));
                      nextTop = top + BLOCK_MIN_HEIGHT + BLOCK_GAP;

                      if (item.type === 'row') {
                        const r = item.data;
                        const userLabel = r.user
                          ? `${r.user.first_name} ${r.user.last_name}`
                          : `User #${r.user_id}`;
                        return (
                          <Box
                            key={`row-${r.id}`}
                            sx={{
                              position: 'absolute',
                              left: 6,
                              right: 6,
                              top,
                              minHeight: BLOCK_MIN_HEIGHT,
                              bgcolor:
                                r.status === 'done'
                                  ? 'success.light'
                                  : r.status === 'skipped'
                                    ? 'warning.light'
                                    : 'grey.200',
                              borderRadius: 1,
                              p: 1,
                              border: '1px solid',
                              borderColor:
                                r.status === 'done'
                                  ? 'success.main'
                                  : r.status === 'skipped'
                                    ? 'warning.main'
                                    : 'grey.400',
                            }}
                          >
                            <Typography variant="body2" fontWeight={600}>
                              {userLabel}
                            </Typography>
                            <Typography variant="caption" display="block">
                              {r.status === 'done'
                                ? 'Login with day start stocktake done'
                                : r.status === 'skipped'
                                  ? 'Login with day start stocktake skipped'
                                  : 'Login (day start pending)'}
                              {' '}{formatTime(r.first_login_at)}
                            </Typography>
                            {r.status === 'done' && r.done_at && (
                              <Typography variant="caption" color="success.dark">
                                Done at {formatTime(r.done_at)}
                              </Typography>
                            )}
                            {r.status === 'skipped' && (
                              <Typography variant="caption" sx={{ color: 'grey.800' }}>
                                {r.skip_reason ? `Reason: ${r.skip_reason}` : ''}
                              </Typography>
                            )}
                          </Box>
                        );
                      }
                      const ev = item.data;
                      const userLabel = ev.user
                        ? `${ev.user.first_name} ${ev.user.last_name}`
                        : `User #${ev.user_id}`;
                      const isLogout = ev.event_type === 'logout';
                      return (
                        <Box
                          key={`ev-${ev.id}`}
                          sx={{
                            position: 'absolute',
                            left: 6,
                            right: 6,
                            top,
                            minHeight: BLOCK_MIN_HEIGHT,
                            bgcolor: isLogout ? 'info.light' : 'warning.light',
                            borderRadius: 1,
                            p: 1,
                            border: '1px solid',
                            borderColor: isLogout ? 'info.main' : 'warning.main',
                          }}
                        >
                          <Typography variant="body2" fontWeight={600}>
                            {userLabel}
                          </Typography>
                          <Typography variant="caption" display="block">
                            {isLogout
                              ? 'Logout with day end stocktake done'
                              : 'Logout with day end stocktake skipped'}
                            {' '}{formatTime(ev.occurred_at)}
                          </Typography>
                          {!isLogout && ev.skip_reason && (
                            <Typography variant="caption" sx={{ color: 'grey.800' }}>
                              Reason: {ev.skip_reason}
                            </Typography>
                          )}
                        </Box>
                      );
                    });
                  })()}
                </Box>
              </Box>
            );
          })
        )}
      </Box>
    </Paper>
  );
}
