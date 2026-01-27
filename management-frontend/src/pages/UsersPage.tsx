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
  Alert,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Lock as LockIcon,
  Image as ImageIcon,
} from '@mui/icons-material';
import { usersAPI, storesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { User, Store } from '../types';

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const [pinDialogOpen, setPinDialogOpen] = useState(false);
  const [iconDialogOpen, setIconDialogOpen] = useState(false);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
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

  const handleChangeUserPIN = (user: User) => {
    setSelectedUser(user);
    setPinDialogOpen(true);
  };

  const handleChangeUserIcon = (user: User) => {
    setSelectedUser(user);
    setIconDialogOpen(true);
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
                      src={user.icon_url}
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
                    <Box sx={{ display: 'flex', gap: 1 }}>
                      <IconButton
                        size="small"
                        onClick={() => {
                          setEditingUser(user);
                          setOpen(true);
                        }}
                        title="Edit User"
                      >
                        <EditIcon />
                      </IconButton>
                      <IconButton
                        size="small"
                        onClick={() => handleChangeUserPIN(user)}
                        title="Change PIN"
                      >
                        <LockIcon />
                      </IconButton>
                      <IconButton
                        size="small"
                        onClick={() => handleChangeUserIcon(user)}
                        title="Change Icon"
                      >
                        <ImageIcon />
                      </IconButton>
                    </Box>
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
      <UserPINDialog
        open={pinDialogOpen}
        onClose={() => {
          setPinDialogOpen(false);
          setSelectedUser(null);
        }}
        user={selectedUser}
        onSave={async (newPin: string) => {
          if (selectedUser) {
            try {
              await usersAPI.updatePIN(selectedUser.id, '', newPin); // Empty current PIN for admin
              enqueueSnackbar('PIN updated successfully', { variant: 'success' });
              setPinDialogOpen(false);
              setSelectedUser(null);
              fetchUsers();
            } catch (error: any) {
              enqueueSnackbar(error.response?.data?.error || 'Failed to update PIN', { variant: 'error' });
            }
          }
        }}
      />
      <UserIconDialog
        open={iconDialogOpen}
        onClose={() => {
          setIconDialogOpen(false);
          setSelectedUser(null);
        }}
        user={selectedUser}
        onSave={async (iconUrl: string, formData: FormData | null, bgColor: string, textColor: string) => {
          if (selectedUser) {
            try {
              if (formData) {
                await usersAPI.updateIconFile(selectedUser.id, formData);
              } else if (bgColor && textColor) {
                await usersAPI.updateIconColors(selectedUser.id, bgColor, textColor);
              } else if (iconUrl) {
                await usersAPI.updateIcon(selectedUser.id, iconUrl);
              }
              enqueueSnackbar('Icon updated successfully', { variant: 'success' });
              setIconDialogOpen(false);
              setSelectedUser(null);
              fetchUsers();
            } catch (error: any) {
              enqueueSnackbar(error.response?.data?.error || 'Failed to update icon', { variant: 'error' });
            }
          }
        }}
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

function UserPINDialog({
  open,
  onClose,
  user,
  onSave,
}: {
  open: boolean;
  onClose: () => void;
  user: User | null;
  onSave: (pin: string) => void;
}) {
  const [pin, setPin] = useState('');
  const [confirmPin, setConfirmPin] = useState('');

  useEffect(() => {
    if (open) {
      setPin('');
      setConfirmPin('');
    }
  }, [open]);

  const handleSubmit = () => {
    if (pin.length < 4) {
      return;
    }
    if (pin !== confirmPin) {
      return;
    }
    onSave(pin);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Change PIN for {user?.first_name} {user?.last_name}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <Alert severity="info">Enter a new PIN for this user. No current PIN verification required for admin.</Alert>
          <TextField
            label="New PIN"
            type="password"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            inputProps={{ maxLength: 10 }}
            fullWidth
          />
          <TextField
            label="Confirm PIN"
            type="password"
            value={confirmPin}
            onChange={(e) => setConfirmPin(e.target.value)}
            inputProps={{ maxLength: 10 }}
            fullWidth
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          onClick={handleSubmit}
          variant="contained"
          disabled={!pin || !confirmPin || pin.length < 4 || pin !== confirmPin}
        >
          Update PIN
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function UserIconDialog({
  open,
  onClose,
  user,
  onSave,
}: {
  open: boolean;
  onClose: () => void;
  user: User | null;
  onSave: (iconUrl: string, formData: FormData | null, bgColor: string, textColor: string) => void;
}) {
  const [iconMode, setIconMode] = useState<'upload' | 'color'>('color');
  const [iconFile, setIconFile] = useState<File | null>(null);
  const [bgColor, setBgColor] = useState('#1976d2');
  const [textColor, setTextColor] = useState('#ffffff');
  const [iconUrl, setIconUrl] = useState('');

  useEffect(() => {
    if (open) {
      setIconFile(null);
      setIconUrl('');
      // Pre-select saved colors if available, otherwise use defaults
      setBgColor(user?.icon_bg_color || '#1976d2');
      setTextColor(user?.icon_text_color || '#ffffff');
      setIconMode('color');
    }
  }, [open, user]);

  const getInitials = () => {
    if (user?.first_name && user?.last_name) {
      return `${user.first_name[0]}${user.last_name[0]}`.toUpperCase();
    }
    return user?.username?.[0]?.toUpperCase() || '?';
  };

  const getPreviewIcon = () => {
    if (iconMode === 'color') {
      const svgContent = '<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="' + bgColor + '"/><text x="50" y="50" font-family="monospace" font-size="40" fill="' + textColor + '" text-anchor="middle" dominant-baseline="central">' + getInitials() + '</text></svg>';
      return 'data:image/svg+xml;base64,' + btoa(svgContent);
    }
    if (iconFile) {
      return URL.createObjectURL(iconFile);
    }
    return user?.icon_url || '';
  };

  const handleSubmit = () => {
    if (iconMode === 'upload' && iconFile) {
      const formData = new FormData();
      formData.append('icon', iconFile);
      onSave('', formData, '', '');
    } else if (iconMode === 'color') {
      onSave('', null, bgColor, textColor);
    } else if (iconUrl) {
      onSave(iconUrl, null, '', '');
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Change Icon for {user?.first_name} {user?.last_name}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 3, mt: 2 }}>
          <Box>
            <Button
              variant={iconMode === 'color' ? 'contained' : 'outlined'}
              onClick={() => setIconMode('color')}
              sx={{ mr: 2 }}
            >
              Generate from Colors
            </Button>
            <Button
              variant={iconMode === 'upload' ? 'contained' : 'outlined'}
              onClick={() => setIconMode('upload')}
            >
              Upload Image
            </Button>
          </Box>

          <Box sx={{ display: 'flex', justifyContent: 'center' }}>
            <Avatar
              src={getPreviewIcon()}
              sx={{
                width: 100,
                height: 100,
                bgcolor: iconMode === 'color' ? bgColor : 'primary.main',
                fontSize: '2rem',
              }}
            >
              {getInitials()}
            </Avatar>
          </Box>

          {iconMode === 'color' && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <TextField
                label="Background Color"
                type="color"
                value={bgColor}
                onChange={(e) => setBgColor(e.target.value)}
                InputLabelProps={{ shrink: true }}
                fullWidth
              />
              <TextField
                label="Text Color"
                type="color"
                value={textColor}
                onChange={(e) => setTextColor(e.target.value)}
                InputLabelProps={{ shrink: true }}
                fullWidth
              />
            </Box>
          )}

          {iconMode === 'upload' && (
            <Box>
              <input
                accept="image/*"
                style={{ display: 'none' }}
                id="icon-upload"
                type="file"
                onChange={(e) => {
                  if (e.target.files && e.target.files[0]) {
                    setIconFile(e.target.files[0]);
                  }
                }}
              />
              <label htmlFor="icon-upload">
                <Button variant="outlined" component="span" fullWidth>
                  Select Image
                </Button>
              </label>
              {iconFile && (
                <Typography variant="body2" sx={{ mt: 1, textAlign: 'center' }}>
                  {iconFile.name}
                </Typography>
              )}
            </Box>
          )}
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          onClick={handleSubmit}
          variant="contained"
          disabled={iconMode === 'upload' && !iconFile}
        >
          Save
        </Button>
      </DialogActions>
    </Dialog>
  );
}

