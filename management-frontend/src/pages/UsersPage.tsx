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
  IconButton,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  MenuItem,
  Avatar,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
} from '@mui/icons-material';
import { usersAPI, storesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { User, Store } from '../types';

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      const data = await usersAPI.list();
      setUsers(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch users', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (userData: any) => {
    try {
      if (editingUser) {
        await usersAPI.update(editingUser.id, userData);
        enqueueSnackbar('User updated', { variant: 'success' });
      } else {
        await usersAPI.create(userData);
        enqueueSnackbar('User created', { variant: 'success' });
      }
      setOpen(false);
      setEditingUser(null);
      fetchUsers();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to save user', {
        variant: 'error',
      });
    }
  };

  const getInitials = (user: User) => {
    return `${user.first_name[0]}${user.last_name[0]}`.toUpperCase();
  };

  const getRoleColor = (role: string) => {
    switch (role) {
      case 'management':
        return 'primary';
      case 'supervisor':
        return 'warning';
      default:
        return 'default';
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">Users</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => {
            setEditingUser(null);
            setOpen(true);
          }}
        >
          Add User
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Icon</TableCell>
              <TableCell>Name</TableCell>
              <TableCell>Username</TableCell>
              <TableCell>Email</TableCell>
              <TableCell>Role</TableCell>
              <TableCell>Stores</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={8} align="center">
                  Loading...
                </TableCell>
              </TableRow>
            ) : users.length === 0 ? (
              <TableRow>
                <TableCell colSpan={8} align="center">
                  No users found
                </TableCell>
              </TableRow>
            ) : (
              users.map((user) => (
                <TableRow key={user.id}>
                  <TableCell>
                    <Avatar
                      sx={{
                        bgcolor: user.icon_color || 'primary.main',
                        width: 32,
                        height: 32,
                      }}
                    >
                      {getInitials(user)}
                    </Avatar>
                  </TableCell>
                  <TableCell>
                    {user.first_name} {user.last_name}
                  </TableCell>
                  <TableCell>{user.username}</TableCell>
                  <TableCell>{user.email || '-'}</TableCell>
                  <TableCell>
                    <Chip
                      label={user.role}
                      size="small"
                      color={getRoleColor(user.role) as any}
                    />
                  </TableCell>
                  <TableCell>
                    {user.stores?.map((s) => s.name).join(', ') || '-'}
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={user.is_active ? 'Active' : 'Inactive'}
                      size="small"
                      color={user.is_active ? 'success' : 'default'}
                    />
                  </TableCell>
                  <TableCell>
                    <IconButton
                      size="small"
                      onClick={() => {
                        setEditingUser(user);
                        setOpen(true);
                      }}
                    >
                      <EditIcon />
                    </IconButton>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <UserDialog
        open={open}
        onClose={() => {
          setOpen(false);
          setEditingUser(null);
        }}
        onSave={handleSave}
        user={editingUser}
      />
    </Box>
  );
}

function UserDialog({
  open,
  onClose,
  onSave,
  user,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: any) => void;
  user: User | null;
}) {
  const [formData, setFormData] = useState({
    username: '',
    password: '',
    pin: '',
    first_name: '',
    last_name: '',
    email: '',
    role: 'pos_user',
    store_ids: [] as number[],
  });
  const [stores, setStores] = useState<Store[]>([]);

  useEffect(() => {
    fetchStores();
  }, []);

  useEffect(() => {
    if (user) {
      setFormData({
        username: user.username || '',
        password: '',
        pin: '',
        first_name: user.first_name || '',
        last_name: user.last_name || '',
        email: user.email || '',
        role: user.role || 'pos_user',
        store_ids: user.stores?.map((s) => s.id) || [],
      });
    } else {
      setFormData({
        username: '',
        password: '',
        pin: '',
        first_name: '',
        last_name: '',
        email: '',
        role: 'pos_user',
        store_ids: [],
      });
    }
  }, [user, open]);

  const fetchStores = async () => {
    try {
      const data = await storesAPI.list();
      setStores(data);
    } catch (error) {
      console.error('Failed to fetch stores:', error);
    }
  };

  const handleSubmit = () => {
    if (!user && !formData.password) {
      return;
    }
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{user ? 'Edit User' : 'Add User'}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label="Username"
            required
            fullWidth
            value={formData.username}
            onChange={(e) => setFormData({ ...formData, username: e.target.value })}
            disabled={!!user}
          />
          {!user && (
            <TextField
              label="Password"
              type="password"
              required
              fullWidth
              value={formData.password}
              onChange={(e) => setFormData({ ...formData, password: e.target.value })}
            />
          )}
          <TextField
            label="PIN"
            fullWidth
            value={formData.pin}
            onChange={(e) => setFormData({ ...formData, pin: e.target.value })}
            helperText="4-digit PIN for POS login"
          />
          <TextField
            label="First Name"
            required
            fullWidth
            value={formData.first_name}
            onChange={(e) => setFormData({ ...formData, first_name: e.target.value })}
          />
          <TextField
            label="Last Name"
            required
            fullWidth
            value={formData.last_name}
            onChange={(e) => setFormData({ ...formData, last_name: e.target.value })}
          />
          <TextField
            label="Email"
            type="email"
            fullWidth
            value={formData.email}
            onChange={(e) => setFormData({ ...formData, email: e.target.value })}
          />
          <TextField
            select
            label="Role"
            required
            fullWidth
            value={formData.role}
            onChange={(e) => setFormData({ ...formData, role: e.target.value })}
          >
            <MenuItem value="management">Management</MenuItem>
            <MenuItem value="pos_user">POS User</MenuItem>
            <MenuItem value="supervisor">Supervisor</MenuItem>
          </TextField>
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={handleSubmit} variant="contained">
          Save
        </Button>
      </DialogActions>
    </Dialog>
  );
}

