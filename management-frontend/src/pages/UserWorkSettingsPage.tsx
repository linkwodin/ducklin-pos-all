import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Autocomplete,
  Box,
  Button,
  FormControl,
  InputLabel,
  MenuItem,
  Paper,
  Select,
  TextField,
  Typography,
} from '@mui/material';
import { Save as SaveIcon } from '@mui/icons-material';
import { useSearchParams } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import { storesAPI, usersAPI, wholesaleClientsAPI } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { canManageUserWorkAssignments } from '../utils/permissions';
import { usePosModuleEnabled, useWholesaleOrderEnabled } from '../hooks/useWholesaleOrderEnabled';
import type { Store, User, WholesaleClient } from '../types';

export default function UserWorkSettingsPage() {
  const { t } = useTranslation();
  const { enqueueSnackbar } = useSnackbar();
  const { user: authUser } = useAuth();
  const [searchParams] = useSearchParams();
  const manageAssignments = canManageUserWorkAssignments(authUser?.role);
  const { enabled: posEnabled, loaded: posLoaded } = usePosModuleEnabled();
  const { enabled: wholesaleEnabled, loaded: wholesaleLoaded } = useWholesaleOrderEnabled();

  const [allUsers, setAllUsers] = useState<User[]>([]);
  const [selectedUserId, setSelectedUserId] = useState<number | ''>('');
  const [user, setUser] = useState<User | null>(null);
  const [allStores, setAllStores] = useState<Store[]>([]);
  const [allClients, setAllClients] = useState<WholesaleClient[]>([]);
  const [storeIds, setStoreIds] = useState<number[]>([]);
  const [clientIds, setClientIds] = useState<number[]>([]);
  const [defaultStoreId, setDefaultStoreId] = useState<number | ''>('');
  const [defaultClientId, setDefaultClientId] = useState<number | ''>('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const modulesLoaded = posLoaded && wholesaleLoaded;
  const showPosSettings = posEnabled;
  const showWholesaleSettings = wholesaleEnabled;
  const hasModuleSettings = showPosSettings || showWholesaleSettings;

  const targetUserId = useMemo(() => {
    if (manageAssignments && selectedUserId !== '') return selectedUserId;
    return authUser?.id ?? '';
  }, [authUser?.id, manageAssignments, selectedUserId]);

  const loadCatalogs = useCallback(async () => {
    const [stores, clients] = await Promise.all([
      showPosSettings ? storesAPI.list() : Promise.resolve([] as Store[]),
      showWholesaleSettings
        ? wholesaleClientsAPI.list({ active_only: true })
        : Promise.resolve([] as WholesaleClient[]),
    ]);
    setAllStores(stores.filter((s) => s.is_active));
    setAllClients(clients.filter((c) => c.is_active));
  }, [showPosSettings, showWholesaleSettings]);

  const applyUserToForm = useCallback((u: User) => {
    setUser(u);
    setStoreIds(u.stores?.map((s) => s.id) ?? []);
    setClientIds(u.wholesale_clients?.map((c) => c.id) ?? []);
    setDefaultStoreId(u.default_store_id ?? '');
    setDefaultClientId(u.default_wholesale_client_id ?? '');
  }, []);

  const loadUser = useCallback(async (id: number) => {
    const data = await usersAPI.get(id);
    applyUserToForm(data);
  }, [applyUserToForm]);

  useEffect(() => {
    if (!modulesLoaded) return;
    const init = async () => {
      try {
        setLoading(true);
        await loadCatalogs();
        if (manageAssignments) {
          const users = await usersAPI.list();
          setAllUsers(users.filter((u) => u.is_active));
          const fromQuery = searchParams.get('user');
          const parsed = fromQuery ? Number(fromQuery) : NaN;
          if (Number.isFinite(parsed) && parsed > 0) {
            setSelectedUserId(parsed);
          } else if (authUser?.id) {
            setSelectedUserId(authUser.id);
          }
        }
      } catch {
        enqueueSnackbar(t('userWorkSettings.failedToLoad'), { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    void init();
  }, [authUser?.id, enqueueSnackbar, loadCatalogs, manageAssignments, modulesLoaded, searchParams, t]);

  useEffect(() => {
    if (targetUserId === '' || !Number.isFinite(targetUserId)) return;
    void loadUser(targetUserId).catch(() => {
      enqueueSnackbar(t('userWorkSettings.failedToLoad'), { variant: 'error' });
    });
  }, [enqueueSnackbar, loadUser, targetUserId, t]);

  const assignedStores = useMemo(
    () => allStores.filter((s) => storeIds.includes(s.id)),
    [allStores, storeIds],
  );

  const allowedClients = useMemo(() => {
    if (clientIds.length === 0) return allClients;
    return allClients.filter((c) => clientIds.includes(c.id));
  }, [allClients, clientIds]);

  const handleSave = async () => {
    if (targetUserId === '' || !Number.isFinite(targetUserId)) return;
    try {
      setSaving(true);
      const body: Parameters<typeof usersAPI.updateWorkSettings>[1] = {};
      if (manageAssignments) {
        if (showPosSettings) {
          body.store_ids = storeIds;
        }
        if (showWholesaleSettings) {
          body.wholesale_client_ids = clientIds;
        }
      }
      if (showPosSettings) {
        if (defaultStoreId === '') {
          body.clear_default_store = true;
        } else {
          body.default_store_id = defaultStoreId;
        }
      }
      if (showWholesaleSettings) {
        if (defaultClientId === '') {
          body.clear_default_wholesale_client = true;
        } else {
          body.default_wholesale_client_id = defaultClientId;
        }
      }
      const updated = await usersAPI.updateWorkSettings(targetUserId, body);
      applyUserToForm(updated);
      enqueueSnackbar(t('userWorkSettings.saved'), { variant: 'success' });
    } catch (error: unknown) {
      const err = error as { response?: { data?: { error?: string } } };
      enqueueSnackbar(err.response?.data?.error || t('userWorkSettings.saveFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

  if (loading || !modulesLoaded) {
    return (
      <Box sx={{ p: 3 }}>
        <Typography>{t('common.loading')}</Typography>
      </Box>
    );
  }

  return (
    <Box sx={{ p: { xs: 2, md: 3 }, maxWidth: 900 }}>
      <Typography variant="h4" gutterBottom>
        {t('userWorkSettings.title')}
      </Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
        {t('userWorkSettings.subtitle')}
      </Typography>

      {!hasModuleSettings ? (
        <Alert severity="info">{t('userWorkSettings.noModulesEnabled')}</Alert>
      ) : null}

      {manageAssignments && hasModuleSettings && (
        <Paper sx={{ p: 2.5, mb: 3 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('userWorkSettings.selectUser')}</InputLabel>
            <Select
              label={t('userWorkSettings.selectUser')}
              value={selectedUserId === '' ? '' : selectedUserId}
              onChange={(e) => setSelectedUserId(e.target.value === '' ? '' : Number(e.target.value))}
            >
              {allUsers.map((u) => (
                <MenuItem key={u.id} value={u.id}>
                  {u.first_name} {u.last_name} ({u.username})
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        </Paper>
      )}

      {user && hasModuleSettings && (
        <>
          {manageAssignments ? (
            <>
              {showPosSettings ? (
                <Paper sx={{ p: 2.5, mb: 3 }}>
                  <Typography variant="h6" gutterBottom>
                    {t('userWorkSettings.storeAssignments')}
                  </Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    {t('userWorkSettings.storeAssignmentsHint')}
                  </Typography>
                  <Autocomplete
                    multiple
                    options={allStores}
                    getOptionLabel={(s) => s.name}
                    value={assignedStores}
                    onChange={(_, value) => {
                      const ids = value.map((s) => s.id);
                      setStoreIds(ids);
                      if (defaultStoreId !== '' && !ids.includes(defaultStoreId)) {
                        setDefaultStoreId('');
                      }
                    }}
                    renderInput={(params) => (
                      <TextField {...params} label={t('userWorkSettings.assignedStores')} />
                    )}
                  />
                </Paper>
              ) : null}

              {showWholesaleSettings ? (
                <Paper sx={{ p: 2.5, mb: 3 }}>
                  <Typography variant="h6" gutterBottom>
                    {t('userWorkSettings.clientAccess')}
                  </Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    {t('userWorkSettings.clientAccessHint')}
                  </Typography>
                  <Autocomplete
                    multiple
                    options={allClients}
                    getOptionLabel={(c) => c.name}
                    value={allClients.filter((c) => clientIds.includes(c.id))}
                    onChange={(_, value) => {
                      const ids = value.map((c) => c.id);
                      setClientIds(ids);
                      if (defaultClientId !== '' && ids.length > 0 && !ids.includes(defaultClientId)) {
                        setDefaultClientId('');
                      }
                    }}
                    renderInput={(params) => (
                      <TextField {...params} label={t('userWorkSettings.assignedClients')} />
                    )}
                  />
                </Paper>
              ) : null}
            </>
          ) : (
            <Paper sx={{ p: 2.5, mb: 3 }}>
              <Typography variant="h6" gutterBottom>
                {t('userWorkSettings.yourAssignments')}
              </Typography>
              {showPosSettings ? (
                <Typography variant="body2" sx={{ mb: showWholesaleSettings ? 1 : 0 }}>
                  <strong>{t('userWorkSettings.assignedStores')}:</strong>{' '}
                  {user.stores?.length ? user.stores.map((s) => s.name).join(', ') : '—'}
                </Typography>
              ) : null}
              {showWholesaleSettings ? (
                <Typography variant="body2">
                  <strong>{t('userWorkSettings.assignedClients')}:</strong>{' '}
                  {user.wholesale_clients?.length
                    ? user.wholesale_clients.map((c) => c.name).join(', ')
                    : t('userWorkSettings.noClientsAssigned')}
                </Typography>
              ) : null}
              <Alert severity="info" sx={{ mt: 2 }}>
                {t('userWorkSettings.assignmentsReadOnlyHint')}
              </Alert>
            </Paper>
          )}

          {(showPosSettings || showWholesaleSettings) ? (
            <Paper sx={{ p: 2.5, mb: 3 }}>
              <Typography variant="h6" gutterBottom>
                {t('userWorkSettings.defaults')}
              </Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('userWorkSettings.defaultsHint')}
              </Typography>
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                {showPosSettings ? (
                  <FormControl fullWidth size="small">
                    <InputLabel>{t('userWorkSettings.defaultStore')}</InputLabel>
                    <Select
                      label={t('userWorkSettings.defaultStore')}
                      value={defaultStoreId === '' ? '' : defaultStoreId}
                      onChange={(e) =>
                        setDefaultStoreId(e.target.value === '' ? '' : Number(e.target.value))
                      }
                    >
                      <MenuItem value="">
                        <em>{t('userWorkSettings.none')}</em>
                      </MenuItem>
                      {(manageAssignments ? assignedStores : user.stores ?? []).map((s) => (
                        <MenuItem key={s.id} value={s.id}>
                          {s.name}
                        </MenuItem>
                      ))}
                    </Select>
                  </FormControl>
                ) : null}

                {showWholesaleSettings ? (
                  <FormControl fullWidth size="small">
                    <InputLabel>{t('userWorkSettings.defaultClient')}</InputLabel>
                    <Select
                      label={t('userWorkSettings.defaultClient')}
                      value={defaultClientId === '' ? '' : defaultClientId}
                      onChange={(e) =>
                        setDefaultClientId(e.target.value === '' ? '' : Number(e.target.value))
                      }
                    >
                      <MenuItem value="">
                        <em>{t('userWorkSettings.none')}</em>
                      </MenuItem>
                      {allowedClients.map((c) => (
                        <MenuItem key={c.id} value={c.id}>
                          {c.name}
                        </MenuItem>
                      ))}
                    </Select>
                  </FormControl>
                ) : null}
              </Box>
            </Paper>
          ) : null}

          <Button
            variant="contained"
            startIcon={<SaveIcon />}
            onClick={() => void handleSave()}
            disabled={saving}
          >
            {t('common.save')}
          </Button>
        </>
      )}
    </Box>
  );
}
