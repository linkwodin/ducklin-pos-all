import { useEffect, useState } from 'react';
import { useNavigate, useParams, Link as RouterLink } from 'react-router-dom';
import {
  Box,
  Button,
  Paper,
  Typography,
  TextField,
  Grid,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
  Divider,
  IconButton,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Link,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
  AutoFixHigh as AutoGenIcon,
  ChevronRight as ChevronRightIcon,
} from '@mui/icons-material';
import { wholesaleClientsAPI, sectorsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { WholesaleClient, WholesaleClientStore, Sector } from '../types';

const emptyClientForm = {
  name: '',
  contact_name: '',
  email: '',
  phone: '',
  address_line1: '',
  address_line2: '',
  postcode: '',
  vat_number: '',
  company_number: '',
  terms: '',
  account_code: '',
  sector_id: '' as number | '',
};

function generateAccountCode(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return '';
  if (trimmed.length < 8) return trimmed;
  return trimmed
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0])
    .join('')
    .toUpperCase();
}

const emptyStoreForm = {
  name: '',
  address_line1: '',
  address_line2: '',
  city: '',
  postcode: '',
  contact_name: '',
  email: '',
  phone: '',
};

type PendingStore = typeof emptyStoreForm & { _id: number };

export default function WholesaleClientFormPage() {
  const { id } = useParams<{ id: string }>();
  const isEdit = !!id;
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const [loading, setLoading] = useState(isEdit);
  const [saving, setSaving] = useState(false);
  const [sectors, setSectors] = useState<Sector[]>([]);
  const [client, setClient] = useState<WholesaleClient | null>(null);
  const [form, setForm] = useState(emptyClientForm);

  const [storeDialogOpen, setStoreDialogOpen] = useState(false);
  const [editingStore, setEditingStore] = useState<WholesaleClientStore | null>(null);
  const [editingPendingIndex, setEditingPendingIndex] = useState<number>(-1);
  const [pendingStores, setPendingStores] = useState<PendingStore[]>([]);
  const [storeForm, setStoreForm] = useState(emptyStoreForm);
  const [savingStore, setSavingStore] = useState(false);
  const nextPendingId = Math.max(0, ...pendingStores.map((s) => s._id)) + 1;

  useEffect(() => {
    const load = async () => {
      try {
        const sectorList = await sectorsAPI.list();
        setSectors(sectorList.filter((s) => s.is_active));
        if (isEdit) {
          const data = await wholesaleClientsAPI.get(Number(id));
          setClient(data);
          setForm({
            name: data.name,
            contact_name: data.contact_name ?? '',
            email: data.email ?? '',
            phone: data.phone ?? '',
            address_line1: data.address_line1 ?? '',
            address_line2: data.address_line2 ?? '',
            postcode: data.postcode ?? '',
            vat_number: data.vat_number ?? '',
            company_number: data.company_number ?? '',
            terms: data.terms ?? '',
            account_code: data.account_code ?? '',
            sector_id: data.sector_id ?? '',
          });
        }
      } catch {
        enqueueSnackbar('Failed to load data', { variant: 'error' });
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [id]);

  const handleSave = async () => {
    if (!form.name.trim()) {
      enqueueSnackbar('Company name is required', { variant: 'warning' });
      return;
    }
    try {
      setSaving(true);
      const payload = { ...form, sector_id: form.sector_id || undefined };
      if (isEdit) {
        const updated = await wholesaleClientsAPI.update(Number(id), payload);
        setClient(updated);
        enqueueSnackbar('Client updated', { variant: 'success' });
      } else {
        const created = await wholesaleClientsAPI.create(payload);
        for (const s of pendingStores) {
          const name = s.name.trim() || `${created.name} (Shipping)`;
          if (name || s.address_line1.trim()) {
            await wholesaleClientsAPI.createStore(created.id, { ...s, name });
          }
        }
        navigate('/wholesale-clients', { replace: true, state: { createdClientId: created.id } });
      }
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to save', { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

  const refreshClient = async () => {
    if (!client) return;
    const data = await wholesaleClientsAPI.get(client.id);
    setClient(data);
  };

  const openAddStore = () => {
    setEditingStore(null);
    setEditingPendingIndex(-1);
    setStoreForm(emptyStoreForm);
    setStoreDialogOpen(true);
  };

  const addSameAsCompany = () => {
    const same: PendingStore = {
      _id: nextPendingId,
      name: form.name ? `${form.name} (Shipping)` : '',
      address_line1: form.address_line1,
      address_line2: form.address_line2,
      city: '',
      postcode: form.postcode,
      contact_name: form.contact_name,
      email: form.email,
      phone: form.phone,
    };
    setPendingStores((prev) => [...prev, same]);
    enqueueSnackbar('Added shipping address from company', { variant: 'success' });
  };

  const openEditStore = (store: WholesaleClientStore) => {
    setEditingStore(store);
    setEditingPendingIndex(-1);
    setStoreForm({
      name: store.name,
      address_line1: store.address_line1 ?? '',
      address_line2: store.address_line2 ?? '',
      city: store.city ?? '',
      postcode: store.postcode ?? '',
      contact_name: store.contact_name ?? '',
      email: store.email ?? '',
      phone: store.phone ?? '',
    });
    setStoreDialogOpen(true);
  };

  const openEditPendingStore = (idx: number) => {
    setEditingStore(null);
    setEditingPendingIndex(idx);
    const s = pendingStores[idx];
    setStoreForm({
      name: s.name,
      address_line1: s.address_line1,
      address_line2: s.address_line2,
      city: s.city,
      postcode: s.postcode,
      contact_name: s.contact_name,
      email: s.email,
      phone: s.phone,
    });
    setStoreDialogOpen(true);
  };

  const handleSaveStore = async () => {
    if (!storeForm.name.trim()) {
      enqueueSnackbar('Shipping address name is required', { variant: 'warning' });
      return;
    }
    if (client) {
      try {
        setSavingStore(true);
        if (editingStore) {
          await wholesaleClientsAPI.updateStore(client.id, editingStore.id, storeForm);
          enqueueSnackbar('Shipping address updated', { variant: 'success' });
        } else {
          await wholesaleClientsAPI.createStore(client.id, storeForm);
          enqueueSnackbar('Shipping address added', { variant: 'success' });
        }
        setStoreDialogOpen(false);
        refreshClient();
      } catch (e: any) {
        enqueueSnackbar(e.response?.data?.error || 'Failed to save', { variant: 'error' });
      } finally {
        setSavingStore(false);
      }
    } else {
      if (editingPendingIndex >= 0) {
        setPendingStores((prev) =>
          prev.map((s, i) => (i === editingPendingIndex ? { ...storeForm, _id: s._id } : s))
        );
      } else {
        setPendingStores((prev) => [...prev, { ...storeForm, _id: nextPendingId }]);
      }
      setStoreDialogOpen(false);
    }
  };

  const handleDeleteStore = async (store: WholesaleClientStore) => {
    if (!client) return;
    if (!window.confirm(`Remove shipping address "${store.name}"?`)) return;
    try {
      await wholesaleClientsAPI.deleteStore(client.id, store.id);
      enqueueSnackbar('Shipping address removed', { variant: 'success' });
      refreshClient();
    } catch (e: any) {
      enqueueSnackbar(e.response?.data?.error || 'Failed to remove', { variant: 'error' });
    }
  };

  const removePendingStore = (idx: number) => {
    setPendingStores((prev) => prev.filter((_, i) => i !== idx));
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', mt: 8 }}>
        <CircularProgress />
      </Box>
    );
  }

  const stores = (client?.stores ?? []).filter((s) => s.is_active);

  return (
    <Box sx={{ p: 3, width: '100%' }}>
      <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2 }}>
        <Link component={RouterLink} to="/" color="primary" underline="none">Home</Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <Link component={RouterLink} to="/wholesale-clients" color="primary" underline="none">
          Wholesale clients
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        {isEdit && client ? (
          <Link component={RouterLink} to={`/wholesale-clients/${client.id}`} color="primary" underline="none">{client.name}</Link>
        ) : (
          <span>{isEdit ? (client?.name ?? '') : 'New wholesale client'}</span>
        )}
        {isEdit && (
          <>
            <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
            <span>Edit</span>
          </>
        )}
      </Typography>
      <Typography variant="h5" sx={{ mb: 3 }}>
        {isEdit ? `Edit: ${client?.name ?? ''}` : 'New wholesale client'}
      </Typography>

      {/* Company details */}
      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h6" sx={{ mb: 2 }}>Company details</Typography>
        <Grid container spacing={2}>
          <Grid item xs={12} sm={6}>
            <TextField label="Company name" required fullWidth value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={6}>
            <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
              <TextField
                label="Account code"
                fullWidth
                value={form.account_code}
                onChange={(e) => setForm((f) => ({ ...f, account_code: e.target.value }))}
              />
              <Button
                variant="outlined"
                size="small"
                startIcon={<AutoGenIcon />}
                onClick={() => setForm((f) => ({ ...f, account_code: generateAccountCode(f.name) }))}
                sx={{ mt: 1, flexShrink: 0 }}
              >
                Auto
              </Button>
            </Box>
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField label="VAT number" fullWidth value={form.vat_number} onChange={(e) => setForm((f) => ({ ...f, vat_number: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField label="Company number" fullWidth value={form.company_number} onChange={(e) => setForm((f) => ({ ...f, company_number: e.target.value }))} />
          </Grid>
          <Grid item xs={12}>
            <TextField label="Terms (shown on order confirmation, invoice & delivery note)" fullWidth value={form.terms} onChange={(e) => setForm((f) => ({ ...f, terms: e.target.value }))} placeholder="e.g. Net 30, Payment on delivery" />
          </Grid>
          <Grid item xs={12}>
            <TextField label="Company address line 1" fullWidth value={form.address_line1} onChange={(e) => setForm((f) => ({ ...f, address_line1: e.target.value }))} />
          </Grid>
          <Grid item xs={12}>
            <TextField label="Company address line 2" fullWidth value={form.address_line2} onChange={(e) => setForm((f) => ({ ...f, address_line2: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={4}>
            <TextField label="Postcode" fullWidth value={form.postcode} onChange={(e) => setForm((f) => ({ ...f, postcode: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={4}>
            <TextField label="Contact name" fullWidth value={form.contact_name} onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={4}>
            <TextField label="Contact email" type="email" fullWidth value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={6}>
            <TextField label="Contact phone" fullWidth value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
          </Grid>
          <Grid item xs={12} sm={6}>
            <FormControl fullWidth>
              <InputLabel>Sector</InputLabel>
              <Select
                value={form.sector_id}
                label="Sector"
                onChange={(e) => setForm((f) => ({ ...f, sector_id: e.target.value as number | '' }))}
              >
                <MenuItem value="">None</MenuItem>
                {sectors.map((s) => (
                  <MenuItem key={s.id} value={s.id}>{s.name}</MenuItem>
                ))}
              </Select>
            </FormControl>
          </Grid>
        </Grid>
        <Box sx={{ mt: 3, display: 'flex', justifyContent: 'flex-end' }}>
          <Button variant="contained" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving…' : isEdit ? 'Update client' : 'Create client'}
          </Button>
        </Box>
      </Paper>

      {/* Shipping addresses — for new create form */}
      {!isEdit && (
        <Paper sx={{ p: 3, mb: 3 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 1 }}>
            <Typography variant="h6">Shipping addresses</Typography>
            <Box sx={{ display: 'flex', gap: 1 }}>
              <Button variant="outlined" size="small" onClick={addSameAsCompany}>
                Same as company address
              </Button>
              <Button variant="outlined" size="small" startIcon={<AddIcon />} onClick={openAddStore}>
                Add shipping address
              </Button>
            </Box>
          </Box>
          <Divider sx={{ mb: 2 }} />
          {pendingStores.length === 0 ? (
            <Typography variant="body2" color="text.secondary" sx={{ py: 2, textAlign: 'center' }}>
              No shipping addresses yet. Add one using the buttons above.
            </Typography>
          ) : (
            <TableContainer>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Name</TableCell>
                    <TableCell>Address</TableCell>
                    <TableCell>Postcode</TableCell>
                    <TableCell>Contact</TableCell>
                    <TableCell>Email</TableCell>
                    <TableCell>Phone</TableCell>
                    <TableCell width={100}>Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {pendingStores.map((s, idx) => (
                    <TableRow key={s._id}>
                      <TableCell>{s.name || '—'}</TableCell>
                      <TableCell>{[s.address_line1, s.address_line2].filter(Boolean).join(', ') || '—'}</TableCell>
                      <TableCell>{s.postcode || '—'}</TableCell>
                      <TableCell>{s.contact_name || '—'}</TableCell>
                      <TableCell>{s.email || '—'}</TableCell>
                      <TableCell>{s.phone || '—'}</TableCell>
                      <TableCell>
                        <IconButton size="small" onClick={() => openEditPendingStore(idx)}><EditIcon fontSize="small" /></IconButton>
                        <IconButton size="small" color="error" onClick={() => removePendingStore(idx)}><DeleteIcon fontSize="small" /></IconButton>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </Paper>
      )}

      {/* Delivery locations — only show after client is created */}
      {isEdit && client && (
        <Paper sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
            <Typography variant="h6">Shipping addresses</Typography>
            <Button variant="outlined" size="small" startIcon={<AddIcon />} onClick={openAddStore}>
              Add shipping address
            </Button>
          </Box>
          <Divider sx={{ mb: 2 }} />
          {stores.length === 0 ? (
            <Typography variant="body2" color="text.secondary" sx={{ py: 2, textAlign: 'center' }}>
              No shipping addresses yet. Add one to use on wholesale orders.
            </Typography>
          ) : (
            <TableContainer>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Name</TableCell>
                    <TableCell>Address</TableCell>
                    <TableCell>Postcode</TableCell>
                    <TableCell>Contact</TableCell>
                    <TableCell>Email</TableCell>
                    <TableCell>Phone</TableCell>
                    <TableCell width={100}>Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {stores.map((store) => (
                    <TableRow key={store.id}>
                      <TableCell>{store.name}</TableCell>
                      <TableCell>
                        {[store.address_line1, store.address_line2].filter(Boolean).join(', ') || '—'}
                      </TableCell>
                      <TableCell>{store.postcode || '—'}</TableCell>
                      <TableCell>{store.contact_name || '—'}</TableCell>
                      <TableCell>{store.email || '—'}</TableCell>
                      <TableCell>{store.phone || '—'}</TableCell>
                      <TableCell>
                        <IconButton size="small" onClick={() => openEditStore(store)}><EditIcon fontSize="small" /></IconButton>
                        <IconButton size="small" color="error" onClick={() => handleDeleteStore(store)}><DeleteIcon fontSize="small" /></IconButton>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </Paper>
      )}

      {/* Store dialog */}
      <Dialog open={storeDialogOpen} onClose={() => setStoreDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{editingStore ? 'Edit shipping address' : 'Add shipping address'}</DialogTitle>
        <DialogContent>
          <TextField autoFocus margin="dense" label="Shipping address name" required fullWidth value={storeForm.name} onChange={(e) => setStoreForm((f) => ({ ...f, name: e.target.value }))} />
          <TextField margin="dense" label="Address line 1" fullWidth value={storeForm.address_line1} onChange={(e) => setStoreForm((f) => ({ ...f, address_line1: e.target.value }))} />
          <TextField margin="dense" label="Address line 2" fullWidth value={storeForm.address_line2} onChange={(e) => setStoreForm((f) => ({ ...f, address_line2: e.target.value }))} />
          <TextField margin="dense" label="Postcode" fullWidth value={storeForm.postcode} onChange={(e) => setStoreForm((f) => ({ ...f, postcode: e.target.value }))} />
          <TextField margin="dense" label="Contact name" fullWidth value={storeForm.contact_name} onChange={(e) => setStoreForm((f) => ({ ...f, contact_name: e.target.value }))} />
          <TextField margin="dense" label="Contact email" type="email" fullWidth value={storeForm.email} onChange={(e) => setStoreForm((f) => ({ ...f, email: e.target.value }))} />
          <TextField margin="dense" label="Contact phone" fullWidth value={storeForm.phone} onChange={(e) => setStoreForm((f) => ({ ...f, phone: e.target.value }))} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setStoreDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleSaveStore} disabled={savingStore}>
            {savingStore ? 'Saving…' : 'Save'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
