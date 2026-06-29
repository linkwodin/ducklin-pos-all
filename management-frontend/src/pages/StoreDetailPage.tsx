import { useEffect, useMemo, useState } from 'react';
import { Link as RouterLink, useNavigate, useParams } from 'react-router-dom';
import {
  Avatar,
  Box,
  Button,
  Checkbox,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  IconButton,
  InputLabel,
  Link,
  ListItemText,
  MenuItem,
  OutlinedInput,
  Paper,
  Select,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import {
  Add as AddIcon,
  ChevronRight as ChevronRightIcon,
  LocalShipping as LocalShippingIcon,
  People as PeopleIcon,
  Save as SaveIcon,
  Settings as SettingsIcon,
} from '@mui/icons-material';
import { useTheme, alpha } from '@mui/material/styles';
import { useTranslation } from 'react-i18next';
import { useSnackbar } from 'notistack';
import { productsAPI, stockAPI, storesAPI, usersAPI } from '../services/api';
import type { Product, Stock, Store, User } from '../types';
import ProductImageWithPopover from '../components/ProductImageWithPopover';
import VariantProductPicker from '../components/VariantProductPicker';
import {
  assignmentFlagsForVariant,
  productIsWeight,
  stockLevelInputLabel,
  stockLevelValue,
  stockProductLabel,
} from '../utils/productInventory';
import {
  POS_RECEIPT_TYPE_OPTIONS,
  effectivePosAutoPrintReceiptTypes,
  effectivePosReceiptTypes,
  type PosReceiptTypeId,
} from '../utils/posReceiptTypes';
import { useAuth } from '../context/AuthContext';
import { canManageUserWorkAssignments } from '../utils/permissions';

function userRoleLabel(role: string, t: (key: string) => string): string {
  switch (role) {
    case 'management':
      return t('users:roleManagement');
    case 'supervisor':
      return t('users:roleSupervisor');
    case 'hq_staff':
      return t('users:roleHQStaff');
    case 'pos_user':
      return t('users:rolePosUser');
    default:
      return role;
  }
}

function userRoleColor(role: string): 'primary' | 'warning' | 'info' | 'default' {
  switch (role) {
    case 'management':
      return 'primary';
    case 'supervisor':
      return 'warning';
    case 'hq_staff':
      return 'info';
    default:
      return 'default';
  }
}

export default function StoreDetailPage() {
  const { id } = useParams<{ id: string }>();
  const storeId = Number(id);
  const navigate = useNavigate();
  const { user: currentUser } = useAuth();
  const canManageUsers = canManageUserWorkAssignments(currentUser?.role);
  const { t, i18n } = useTranslation(['storeDetail', 'assignProductToStore', 'storesPage', 'stores', 'stock', 'common', 'usersPage', 'users']);
  const theme = useTheme();
  const lang = i18n.language || 'en';
  const { enqueueSnackbar } = useSnackbar();
  const [store, setStore] = useState<Store | null>(null);
  const [stockRows, setStockRows] = useState<Stock[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [stockDrafts, setStockDrafts] = useState<Record<number, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingProductId, setSavingProductId] = useState<number | null>(null);
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [addProductId, setAddProductId] = useState<number | null>(null);
  const [addLevel, setAddLevel] = useState('0');
  const [addingProduct, setAddingProduct] = useState(false);
  const [enabledReceiptTypes, setEnabledReceiptTypes] = useState<PosReceiptTypeId[]>([]);
  const [autoPrintReceiptTypes, setAutoPrintReceiptTypes] = useState<PosReceiptTypeId[]>([]);
  const [savingReceiptSettings, setSavingReceiptSettings] = useState(false);
  const [users, setUsers] = useState<User[]>([]);
  const [usersDialogOpen, setUsersDialogOpen] = useState(false);
  const [selectedUserIds, setSelectedUserIds] = useState<number[]>([]);
  const [savingUsers, setSavingUsers] = useState(false);
  const shipCheckboxSx = {
    color: theme.palette.success.dark,
    '&.Mui-checked': { color: theme.palette.success.dark },
  };
  const shipHeaderBg = alpha(theme.palette.success.main, 0.16);

  const load = async () => {
    if (!id || Number.isNaN(storeId)) {
      setLoading(false);
      return;
    }
    try {
      setLoading(true);
      const [storeData, stock, productList, userList] = await Promise.all([
        storesAPI.get(storeId),
        stockAPI.getStoreStock(storeId),
        productsAPI.list(),
        usersAPI.list(),
      ]);
      const rows = stock.filter((row) => row.track_prepacked !== false || row.track_weight);
      setStore(storeData);
      setEnabledReceiptTypes(effectivePosReceiptTypes(storeData));
      setAutoPrintReceiptTypes(effectivePosAutoPrintReceiptTypes(storeData));
      setProducts(productList);
      setUsers(userList);
      setStockRows(rows);
      setStockDrafts(
        Object.fromEntries(rows.map((row) => [row.product_id, String(stockLevelValue(row, row.product))])),
      );
    } catch {
      enqueueSnackbar(t('storeDetail:loadFailed'), { variant: 'error' });
      setStore(null);
      setStockRows([]);
      setStockDrafts({});
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, [id, storeId]);

  const assignedProductIds = new Set(stockRows.map((row) => row.product_id));
  const addableProducts = products.filter((p) => !assignedProductIds.has(p.id));
  const storeUsers = useMemo(
    () => users.filter((user) => user.stores?.some((s) => s.id === storeId)),
    [users, storeId],
  );
  const assignableUsers = useMemo(
    () => users.filter((user) => user.is_active),
    [users],
  );

  const openUsersDialog = () => {
    setSelectedUserIds(storeUsers.map((user) => user.id));
    setUsersDialogOpen(true);
  };

  const saveStoreUsers = async () => {
    const previouslyAssigned = storeUsers;
    const toAddIds = selectedUserIds.filter((id) => !previouslyAssigned.some((user) => user.id === id));
    const toRemove = previouslyAssigned.filter((user) => !selectedUserIds.includes(user.id));

    try {
      setSavingUsers(true);
      for (const userId of toAddIds) {
        const user = users.find((u) => u.id === userId);
        if (!user) continue;
        const currentStoreIds = user.stores?.map((s) => s.id) ?? [];
        if (!currentStoreIds.includes(storeId)) {
          await usersAPI.updateStores(user.id, [...currentStoreIds, storeId]);
        }
      }
      for (const user of toRemove) {
        const currentStoreIds = user.stores?.map((s) => s.id) ?? [];
        await usersAPI.updateStores(
          user.id,
          currentStoreIds.filter((id) => id !== storeId),
        );
      }
      enqueueSnackbar(t('storeDetail:usersSaved'), { variant: 'success' });
      setUsersDialogOpen(false);
      await load();
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:usersSaveFailed'), { variant: 'error' });
    } finally {
      setSavingUsers(false);
    }
  };

  const userInitials = (user: User) =>
    `${user.first_name?.[0] ?? ''}${user.last_name?.[0] ?? ''}`.toUpperCase();

  const toggleShipFrom = async (row: Stock) => {
    const enabling = !row.wholesale_ship_from;
    try {
      setSavingProductId(row.product_id);
      await stockAPI.setAssignments(storeId, [
        {
          product_id: row.product_id,
          ...assignmentFlagsForVariant(row.product),
          wholesale_ship_from: enabling,
        },
      ]);
      await load();
      enqueueSnackbar(t('storeDetail:shipFromSaved'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:shipFromSaveFailed'), { variant: 'error' });
    } finally {
      setSavingProductId(null);
    }
  };

  const saveStock = async (row: Stock) => {
    const draft = stockDrafts[row.product_id];
    if (draft == null) return;
    const product = row.product;
    const level = parseFloat(draft);
    if (Number.isNaN(level) || level < 0) {
      enqueueSnackbar(t('storeDetail:invalidQuantity'), { variant: 'warning' });
      return;
    }
    try {
      setSavingProductId(row.product_id);
      await stockAPI.update(row.product_id, storeId, {
        quantity: productIsWeight(product) ? 0 : level,
        weight_quantity_g: productIsWeight(product) ? level : undefined,
        low_stock_threshold: row.low_stock_threshold,
        reason: 'manual adjustment',
      });
      await load();
      enqueueSnackbar(t('storeDetail:stockSaved'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:stockSaveFailed'), { variant: 'error' });
    } finally {
      setSavingProductId(null);
    }
  };

  const toggleReceiptEnabled = (typeId: PosReceiptTypeId, checked: boolean) => {
    setEnabledReceiptTypes((prev) => {
      const next = checked
        ? [...prev, typeId]
        : prev.filter((id) => id !== typeId);
      const unique = POS_RECEIPT_TYPE_OPTIONS.map((o) => o.id).filter((id) => next.includes(id));
      setAutoPrintReceiptTypes((auto) => auto.filter((id) => unique.includes(id)));
      return unique;
    });
  };

  const toggleReceiptAutoPrint = (typeId: PosReceiptTypeId, checked: boolean) => {
    if (checked && !enabledReceiptTypes.includes(typeId)) return;
    setAutoPrintReceiptTypes((prev) => {
      if (checked) return [...prev, typeId];
      return prev.filter((id) => id !== typeId);
    });
  };

  const saveReceiptSettings = async () => {
    if (enabledReceiptTypes.length === 0) {
      enqueueSnackbar(t('storeDetail:receiptSettingsNeedOne'), { variant: 'warning' });
      return;
    }
    try {
      setSavingReceiptSettings(true);
      const updated = await storesAPI.update(storeId, {
        pos_receipt_types: enabledReceiptTypes,
        pos_auto_print_receipt_types: autoPrintReceiptTypes.filter((id) =>
          enabledReceiptTypes.includes(id),
        ),
      });
      setStore(updated);
      setEnabledReceiptTypes(effectivePosReceiptTypes(updated));
      setAutoPrintReceiptTypes(effectivePosAutoPrintReceiptTypes(updated));
      enqueueSnackbar(t('storeDetail:receiptSettingsSaved'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:receiptSettingsSaveFailed'), { variant: 'error' });
    } finally {
      setSavingReceiptSettings(false);
    }
  };

  const handleAddProduct = async () => {
    if (!addProductId) return;
    const product = products.find((p) => p.id === addProductId);
    if (!product) return;
    const level = parseFloat(addLevel);
    if (Number.isNaN(level) || level < 0) {
      enqueueSnackbar(t('storeDetail:invalidQuantity'), { variant: 'warning' });
      return;
    }
    try {
      setAddingProduct(true);
      await stockAPI.setAssignments(storeId, [
        {
          product_id: addProductId,
          ...assignmentFlagsForVariant(product),
          wholesale_ship_from: false,
        },
      ]);
      await stockAPI.update(addProductId, storeId, {
        quantity: productIsWeight(product) ? 0 : level,
        weight_quantity_g: productIsWeight(product) ? level : undefined,
        low_stock_threshold: 0,
        reason: 'manual adjustment',
      });
      setAddDialogOpen(false);
      setAddProductId(null);
      setAddLevel('0');
      await load();
      enqueueSnackbar(t('storeDetail:productAdded'), { variant: 'success' });
    } catch (error: unknown) {
      const msg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error;
      enqueueSnackbar(msg || t('storeDetail:productAddFailed'), { variant: 'error' });
    } finally {
      setAddingProduct(false);
    }
  };

  if (loading) {
    return (
      <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!store) {
    return (
      <Box sx={{ p: 3 }}>
        <Typography color="text.secondary">{t('storeDetail:notFound')}</Typography>
      </Box>
    );
  }

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2, md: 3 } }}>
      <Typography variant="body2" component="span" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 2, flexWrap: 'wrap' }}>
        <Link component={RouterLink} to="/" color="primary" underline="none">
          Home
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <Link component={RouterLink} to="/stores" color="primary" underline="none">
          {t('storesPage:title')}
        </Link>
        <ChevronRightIcon sx={{ fontSize: 18, mx: 0.5, color: 'text.secondary' }} />
        <span>{store.name}</span>
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h4" sx={{ mb: 2, typography: { xs: 'h5', md: 'h4' } }}>
          {store.name}
        </Typography>
        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 1 }}>
          <Chip
            size="small"
            label={store.is_active ? t('storesPage:active') : t('storesPage:inactive')}
            color={store.is_active ? 'success' : 'default'}
            variant="outlined"
          />
          {store.is_warehouse_only ? (
            <Chip size="small" label={t('stores:warehouseOnly')} variant="outlined" />
          ) : null}
        </Box>
        <Typography variant="body2" color="text.secondary">
          {store.address || '—'}
        </Typography>
      </Paper>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 2, flexWrap: 'wrap', mb: 2 }}>
          <Box>
            <Typography variant="h6">{t('storeDetail:usersSection')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {t('storeDetail:usersHint')}
            </Typography>
          </Box>
          {canManageUsers ? (
            <Button variant="contained" startIcon={<PeopleIcon />} onClick={openUsersDialog}>
              {t('storeDetail:manageUsers')}
            </Button>
          ) : null}
        </Box>
        <TableContainer>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 52 }} />
                <TableCell>{t('usersPage:name')}</TableCell>
                <TableCell>{t('usersPage:username')}</TableCell>
                <TableCell>{t('usersPage:role')}</TableCell>
                <TableCell>{t('usersPage:status')}</TableCell>
                <TableCell align="center" sx={{ width: 72 }}>
                  {t('common:actions')}
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {storeUsers.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={6} align="center" sx={{ color: 'text.secondary' }}>
                    {t('storeDetail:noUsers')}
                  </TableCell>
                </TableRow>
              ) : (
                storeUsers.map((user) => (
                  <TableRow key={user.id} hover>
                    <TableCell>
                      <Avatar
                        src={user.icon_url}
                        sx={{
                          bgcolor: user.icon_color || 'primary.main',
                          width: 32,
                          height: 32,
                          fontSize: 14,
                        }}
                      >
                        {userInitials(user)}
                      </Avatar>
                    </TableCell>
                    <TableCell>
                      {user.first_name} {user.last_name}
                    </TableCell>
                    <TableCell>{user.username}</TableCell>
                    <TableCell>
                      <Chip
                        size="small"
                        label={userRoleLabel(user.role, t)}
                        color={userRoleColor(user.role)}
                      />
                    </TableCell>
                    <TableCell>
                      <Chip
                        size="small"
                        label={user.is_active ? t('storesPage:active') : t('storesPage:inactive')}
                        color={user.is_active ? 'success' : 'default'}
                        variant="outlined"
                      />
                    </TableCell>
                    <TableCell align="center">
                      <Tooltip title={t('usersPage:workSettings')}>
                        <IconButton
                          size="small"
                          onClick={() => navigate(`/work-settings?user=${user.id}`)}
                        >
                          <SettingsIcon fontSize="small" />
                        </IconButton>
                      </Tooltip>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h6" sx={{ mb: 1 }}>
          {t('storeDetail:receiptSettingsSection')}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          {t('storeDetail:receiptSettingsHint')}
        </Typography>
        <TableContainer>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>{t('storeDetail:receiptTypeColumn')}</TableCell>
                <TableCell align="center">{t('storeDetail:receiptEnabledColumn')}</TableCell>
                <TableCell align="center">{t('storeDetail:receiptAutoPrintColumn')}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {POS_RECEIPT_TYPE_OPTIONS.map((option) => {
                const enabled = enabledReceiptTypes.includes(option.id);
                const autoPrint = autoPrintReceiptTypes.includes(option.id);
                return (
                  <TableRow key={option.id}>
                    <TableCell>{t(option.labelKey)}</TableCell>
                    <TableCell align="center">
                      <Checkbox
                        checked={enabled}
                        onChange={(e) => toggleReceiptEnabled(option.id, e.target.checked)}
                        disabled={savingReceiptSettings}
                      />
                    </TableCell>
                    <TableCell align="center">
                      <Checkbox
                        checked={autoPrint}
                        disabled={!enabled || savingReceiptSettings}
                        onChange={(e) => toggleReceiptAutoPrint(option.id, e.target.checked)}
                      />
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>
        <Box sx={{ mt: 2, display: 'flex', justifyContent: 'flex-end' }}>
          <Button
            variant="contained"
            startIcon={savingReceiptSettings ? <CircularProgress size={18} color="inherit" /> : <SaveIcon />}
            onClick={saveReceiptSettings}
            disabled={savingReceiptSettings}
          >
            {t('storeDetail:saveReceiptSettings')}
          </Button>
        </Box>
      </Paper>

      <Paper sx={{ p: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 2, flexWrap: 'wrap', mb: 2 }}>
          <Box>
            <Typography variant="h6">{t('storeDetail:productsSection')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              {t('storeDetail:productsHint')}
            </Typography>
          </Box>
          <Button variant="contained" startIcon={<AddIcon />} onClick={() => setAddDialogOpen(true)}>
            {t('storeDetail:addProduct')}
          </Button>
        </Box>
        <TableContainer>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 52 }} />
                <TableCell>{t('assignProductToStore:product')}</TableCell>
                <TableCell align="right" sx={{ minWidth: 120 }}>
                  {t('stock:stockLevel')}
                </TableCell>
                <TableCell align="center" sx={{ bgcolor: shipHeaderBg, color: 'success.dark', fontWeight: 600 }}>
                  {t('assignProductToStore:shipFromShort')}
                </TableCell>
                <TableCell align="center" sx={{ width: 72 }}>
                  {t('common:actions')}
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {stockRows.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={5} align="center" sx={{ color: 'text.secondary' }}>
                    {t('storeDetail:noProducts')}
                  </TableCell>
                </TableRow>
              ) : (
                stockRows.map((row) => {
                  const product = row.product;
                  return (
                    <TableRow key={row.id} hover>
                      <TableCell>
                        <ProductImageWithPopover
                          imageUrl={product?.image_url}
                          productName={stockProductLabel(product, lang, t)}
                          size={40}
                        />
                      </TableCell>
                      <TableCell>{stockProductLabel(product, lang, t)}</TableCell>
                      <TableCell align="right">
                        <TextField
                          size="small"
                          type="number"
                          value={stockDrafts[row.product_id] ?? '0'}
                          onChange={(e) =>
                            setStockDrafts((prev) => ({ ...prev, [row.product_id]: e.target.value }))
                          }
                          inputProps={{ min: 0, step: 0.001 }}
                          sx={{ width: 112 }}
                        />
                      </TableCell>
                      <TableCell align="center">
                        <Tooltip title={t('assignProductToStore:shipFrom')}>
                          <span>
                            <Checkbox
                              checked={!!row.wholesale_ship_from}
                              size="small"
                              disabled={savingProductId === row.product_id}
                              sx={shipCheckboxSx}
                              icon={<LocalShippingIcon fontSize="small" />}
                              checkedIcon={<LocalShippingIcon fontSize="small" />}
                              onChange={() => toggleShipFrom(row)}
                            />
                          </span>
                        </Tooltip>
                      </TableCell>
                      <TableCell align="center">
                        <Tooltip title={t('storeDetail:saveStock')}>
                          <span>
                            <IconButton
                              size="small"
                              color="primary"
                              disabled={savingProductId === row.product_id}
                              onClick={() => saveStock(row)}
                            >
                              {savingProductId === row.product_id ? (
                                <CircularProgress size={18} />
                              ) : (
                                <SaveIcon fontSize="small" />
                              )}
                            </IconButton>
                          </span>
                        </Tooltip>
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>

      <Dialog open={addDialogOpen} onClose={() => !addingProduct && setAddDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{t('storeDetail:addProduct')}</DialogTitle>
        <DialogContent>
          <Box sx={{ mt: 1, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <VariantProductPicker
              products={addableProducts}
              productId={addProductId}
              onProductIdChange={setAddProductId}
              disabled={addingProduct}
            />
            <TextField
              label={stockLevelInputLabel(products.find((p) => p.id === addProductId), t)}
              type="number"
              size="small"
              fullWidth
              value={addLevel}
              onChange={(e) => setAddLevel(e.target.value)}
              inputProps={{ min: 0, step: 0.001 }}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAddDialogOpen(false)} disabled={addingProduct}>
            {t('common:cancel')}
          </Button>
          <Button variant="contained" onClick={handleAddProduct} disabled={addingProduct || !addProductId}>
            {addingProduct ? t('storeDetail:addingProduct') : t('storeDetail:addProduct')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={usersDialogOpen}
        onClose={() => !savingUsers && setUsersDialogOpen(false)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>{t('storeDetail:manageUsersTitle')}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, mb: 2 }}>
            {t('storeDetail:manageUsersHint')}
          </Typography>
          <FormControl fullWidth>
            <InputLabel>{t('storeDetail:selectUsers')}</InputLabel>
            <Select
              multiple
              value={selectedUserIds}
              onChange={(e) => setSelectedUserIds(e.target.value as number[])}
              input={<OutlinedInput label={t('storeDetail:selectUsers')} />}
              renderValue={(selected) => {
                const picked = assignableUsers.filter((user) => (selected as number[]).includes(user.id));
                return picked.map((user) => `${user.first_name} ${user.last_name}`).join(', ');
              }}
            >
              {assignableUsers.map((user) => (
                <MenuItem key={user.id} value={user.id}>
                  <Checkbox checked={selectedUserIds.includes(user.id)} />
                  <ListItemText
                    primary={`${user.first_name} ${user.last_name}`}
                    secondary={`${user.username} (${userRoleLabel(user.role, t)})`}
                  />
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setUsersDialogOpen(false)} disabled={savingUsers}>
            {t('common:cancel')}
          </Button>
          <Button variant="contained" onClick={saveStoreUsers} disabled={savingUsers}>
            {savingUsers ? t('storeDetail:savingUsers') : t('storeDetail:saveUsers')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
