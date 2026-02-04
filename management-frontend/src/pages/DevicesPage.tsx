import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  MenuItem,
  Chip,
  IconButton,
  Select,
  FormControl,
  InputLabel,
  Checkbox,
  ListItemText,
  OutlinedInput,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  People as PeopleIcon,
} from '@mui/icons-material';
import { devicesAPI, storesAPI, usersAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { POSDevice, Store, User } from '../types';

export default function DevicesPage() {
  const [devices, setDevices] = useState<POSDevice[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [userDialogOpen, setUserDialogOpen] = useState(false);
  const [selectedDevice, setSelectedDevice] = useState<POSDevice | null>(null);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [devicesData, storesData, usersData] = await Promise.all([
        devicesAPI.list(),
        storesAPI.list(),
        usersAPI.list(),
      ]);
      setDevices(devicesData);
      setStores(storesData);
      setUsers(usersData.filter(u => u.role === 'pos_user' || u.role === 'supervisor' || u.role === 'management'));
    } catch (error) {
      enqueueSnackbar('Failed to fetch data', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleRegisterDevice = async (deviceData: {
    device_code: string;
    store_id: number;
    device_name?: string;
  }) => {
    try {
      await devicesAPI.register(deviceData);
      enqueueSnackbar('Device registered successfully', { variant: 'success' });
      setOpen(false);
      fetchData();
    } catch (error: any) {
      enqueueSnackbar(
        error.response?.data?.error || 'Failed to register device',
        { variant: 'error' }
      );
    }
  };

  const handleAssignUsers = async (device: POSDevice, userIds: number[]) => {
    try {
      // Update users to include this device's store
      for (const userId of userIds) {
        const user = users.find(u => u.id === userId);
        if (user) {
          const currentStoreIds = user.stores?.map(s => s.id) || [];
          if (!currentStoreIds.includes(device.store_id)) {
            await usersAPI.updateStores(userId, [...currentStoreIds, device.store_id]);
          }
        }
      }
      enqueueSnackbar('Users assigned successfully', { variant: 'success' });
      setUserDialogOpen(false);
      setSelectedDevice(null);
      fetchData();
    } catch (error: any) {
      enqueueSnackbar(
        error.response?.data?.error || 'Failed to assign users',
        { variant: 'error' }
      );
    }
  };

  const getUsersForDevice = (device: POSDevice): User[] => {
    return users.filter(user => 
      user.stores?.some(store => store.id === device.store_id)
    );
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">Devices</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => setOpen(true)}
        >
          Register Device
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Device Code</TableCell>
              <TableCell>Device Name</TableCell>
              <TableCell>Store</TableCell>
              <TableCell>Assigned Users</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={6} align="center">
                  Loading...
                </TableCell>
              </TableRow>
            ) : devices.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} align="center">
                  No devices found
                </TableCell>
              </TableRow>
            ) : (
              devices.map((device) => {
                const deviceUsers = getUsersForDevice(device);
                return (
                  <TableRow key={device.id}>
                    <TableCell>
                      <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>
                        {device.device_code}
                      </Typography>
                    </TableCell>
                    <TableCell>{device.device_name || '-'}</TableCell>
                    <TableCell>
                      {device.store?.name || `Store ${device.store_id}`}
                    </TableCell>
                    <TableCell>
                      {deviceUsers.length > 0 ? (
                        <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap' }}>
                          {deviceUsers.slice(0, 3).map((user) => (
                            <Chip
                              key={user.id}
                              label={`${user.first_name} ${user.last_name}`}
                              size="small"
                            />
                          ))}
                          {deviceUsers.length > 3 && (
                            <Chip
                              label={`+${deviceUsers.length - 3}`}
                              size="small"
                              variant="outlined"
                            />
                          )}
                        </Box>
                      ) : (
                        <Typography variant="body2" color="text.secondary">
                          No users assigned
                        </Typography>
                      )}
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={device.is_active ? 'Active' : 'Inactive'}
                        size="small"
                        color={device.is_active ? 'success' : 'default'}
                      />
                    </TableCell>
                    <TableCell>
                      <IconButton
                        size="small"
                        onClick={() => {
                          setSelectedDevice(device);
                          setUserDialogOpen(true);
                        }}
                        title="Assign Users"
                      >
                        <PeopleIcon />
                      </IconButton>
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <RegisterDeviceDialog
        open={open}
        onClose={() => setOpen(false)}
        onSave={handleRegisterDevice}
        stores={stores}
      />

      <AssignUsersDialog
        open={userDialogOpen}
        onClose={() => {
          setUserDialogOpen(false);
          setSelectedDevice(null);
        }}
        device={selectedDevice}
        users={users}
        onSave={handleAssignUsers}
      />
    </Box>
  );
}

function RegisterDeviceDialog({
  open,
  onClose,
  onSave,
  stores,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: { device_code: string; store_id: number; device_name?: string }) => void;
  stores: Store[];
}) {
  const [formData, setFormData] = useState({
    device_code: '',
    store_id: '',
    device_name: '',
  });

  useEffect(() => {
    if (!open) {
      setFormData({ device_code: '', store_id: '', device_name: '' });
    }
  }, [open]);

  const handleSubmit = () => {
    if (!formData.device_code || !formData.store_id) {
      return;
    }
    onSave({
      device_code: formData.device_code,
      store_id: parseInt(formData.store_id),
      device_name: formData.device_name || undefined,
    });
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Register Device</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label="Device Code"
            required
            fullWidth
            value={formData.device_code}
            onChange={(e) => setFormData({ ...formData, device_code: e.target.value })}
            helperText="Enter the device code from the POS app"
            inputProps={{ style: { fontFamily: 'monospace' } }}
          />
          <TextField
            select
            label="Store"
            required
            fullWidth
            value={formData.store_id}
            onChange={(e) => setFormData({ ...formData, store_id: e.target.value })}
          >
            {stores.map((store) => (
              <MenuItem key={store.id} value={store.id.toString()}>
                {store.name}
              </MenuItem>
            ))}
          </TextField>
          <TextField
            label="Device Name (Optional)"
            fullWidth
            value={formData.device_name}
            onChange={(e) => setFormData({ ...formData, device_name: e.target.value })}
            helperText="e.g., 'Front Counter', 'Back Office'"
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          onClick={handleSubmit}
          variant="contained"
          disabled={!formData.device_code || !formData.store_id}
        >
          Register
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function AssignUsersDialog({
  open,
  onClose,
  device,
  users,
  onSave,
}: {
  open: boolean;
  onClose: () => void;
  device: POSDevice | null;
  users: User[];
  onSave: (device: POSDevice, userIds: number[]) => void;
}) {
  const [selectedUserIds, setSelectedUserIds] = useState<number[]>([]);

  useEffect(() => {
    if (device && open) {
      // Pre-select users already assigned to this device's store
      const assignedUserIds = users
        .filter(user => user.stores?.some(store => store.id === device.store_id))
        .map(user => user.id);
      setSelectedUserIds(assignedUserIds);
    } else if (!open) {
      setSelectedUserIds([]);
    }
  }, [device, open, users]);

  const handleSubmit = () => {
    if (device) {
      onSave(device, selectedUserIds);
    }
  };

  const availableUsers = users.filter(user => 
    user.role === 'pos_user' || user.role === 'supervisor' || user.role === 'management'
  );

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>
        Assign Users to Device
        {device && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {device.device_name || device.device_code} - {device.store?.name}
          </Typography>
        )}
      </DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <FormControl fullWidth>
            <InputLabel>Select Users</InputLabel>
            <Select
              multiple
              value={selectedUserIds}
              onChange={(e) => setSelectedUserIds(e.target.value as number[])}
              input={<OutlinedInput label="Select Users" />}
              renderValue={(selected) => {
                const selectedUsers = availableUsers.filter(u => 
                  (selected as number[]).includes(u.id)
                );
                return selectedUsers.map(u => `${u.first_name} ${u.last_name}`).join(', ');
              }}
            >
              {availableUsers.map((user) => (
                <MenuItem key={user.id} value={user.id}>
                  <Checkbox checked={selectedUserIds.indexOf(user.id) > -1} />
                  <ListItemText
                    primary={`${user.first_name} ${user.last_name}`}
                    secondary={`${user.username} (${user.role})`}
                  />
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          <Typography variant="body2" color="text.secondary">
            Selected users will be assigned to the store this device belongs to.
          </Typography>
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          onClick={handleSubmit}
          variant="contained"
          disabled={!device}
        >
          Assign Users
        </Button>
      </DialogActions>
    </Dialog>
  );
}

