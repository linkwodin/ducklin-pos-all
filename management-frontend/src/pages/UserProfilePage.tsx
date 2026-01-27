import { useEffect, useState } from 'react';
import {
  Box,
  Paper,
  Typography,
  TextField,
  Button,
  Avatar,
  Grid,
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  IconButton,
  Tooltip,
} from '@mui/material';
import {
  Save as SaveIcon,
  ColorLens as ColorLensIcon,
  Upload as UploadIcon,
} from '@mui/icons-material';
import { usersAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import { useAuth } from '../context/AuthContext';

export default function UserProfilePage() {
  const { t } = useTranslation();
  const { user: currentUser } = useAuth();
  const { enqueueSnackbar } = useSnackbar();
  const [user, setUser] = useState<any>(null);
  const [currentPin, setCurrentPin] = useState('');
  const [pin, setPin] = useState('');
  const [confirmPin, setConfirmPin] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [iconDialogOpen, setIconDialogOpen] = useState(false);
  const [iconFile, setIconFile] = useState<File | null>(null);
  const [bgColor, setBgColor] = useState('#1976d2');
  const [textColor, setTextColor] = useState('#ffffff');
  const [iconMode, setIconMode] = useState<'upload' | 'color'>('color');

  useEffect(() => {
    if (currentUser?.id) {
      fetchUser();
    }
  }, [currentUser]);

  const fetchUser = async () => {
    try {
      setLoading(true);
      const data = await usersAPI.get(currentUser!.id);
      setUser(data);
      // Pre-select saved colors if available
      if (data.icon_bg_color) {
        setBgColor(data.icon_bg_color);
      }
      if (data.icon_text_color) {
        setTextColor(data.icon_text_color);
      }
    } catch (error) {
      enqueueSnackbar(t('profile.failedToLoad'), { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleUpdatePIN = async () => {
    if (!currentPin) {
      enqueueSnackbar(t('profile.currentPIN') + ' is required', { variant: 'error' });
      return;
    }
    if (pin.length < 4) {
      enqueueSnackbar(t('profile.pinMinLength'), { variant: 'error' });
      return;
    }
    if (pin !== confirmPin) {
      enqueueSnackbar(t('profile.pinMismatch'), { variant: 'error' });
      return;
    }

    try {
      setSaving(true);
      await usersAPI.updatePIN(currentUser!.id, currentPin, pin);
      enqueueSnackbar(t('profile.pinUpdated'), { variant: 'success' });
      setCurrentPin('');
      setPin('');
      setConfirmPin('');
      await fetchUser();
    } catch (error: any) {
      const errorMsg = error.response?.data?.error || t('profile.updateFailed');
      if (errorMsg.includes('current') || errorMsg.includes('Current') || errorMsg.includes('incorrect')) {
        enqueueSnackbar(t('profile.invalidCurrentPIN'), { variant: 'error' });
      } else {
        enqueueSnackbar(errorMsg, { variant: 'error' });
      }
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateIcon = async () => {
    try {
      setSaving(true);
      if (iconMode === 'upload' && iconFile) {
        // Upload file
        const formData = new FormData();
        formData.append('icon', iconFile);
        await usersAPI.updateIconFile(currentUser!.id, formData);
      } else {
        // Generate from colors
        await usersAPI.updateIconColors(currentUser!.id, bgColor, textColor);
      }
      enqueueSnackbar(t('profile.iconUpdated'), { variant: 'success' });
      setIconDialogOpen(false);
      setIconFile(null);
      await fetchUser();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || t('profile.updateFailed'), { variant: 'error' });
    } finally {
      setSaving(false);
    }
  };

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
    return user?.icon_url;
  };
  const previewIcon = getPreviewIcon(); 
  
  if (loading) {
    return (
      <Box sx={{ p: 3 }}>
        <Typography>{t('common.loading')}</Typography>
      </Box>
    );
  }

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" gutterBottom>
        {t('profile.title')}
      </Typography>

      <Grid container spacing={3} sx={{ mt: 2 }}>
        {/* User Info */}
        <Grid item xs={12} md={6}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              {t('profile.userInfo')}
            </Typography>
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <TextField
                label={t('profile.username')}
                value={user?.username || ''}
                disabled
                fullWidth
              />
              <TextField
                label={t('profile.firstName')}
                value={user?.first_name || ''}
                disabled
                fullWidth
              />
              <TextField
                label={t('profile.lastName')}
                value={user?.last_name || ''}
                disabled
                fullWidth
              />
              <TextField
                label={t('profile.email')}
                value={user?.email || ''}
                disabled
                fullWidth
              />
              <TextField
                label={t('profile.role')}
                value={user?.role || ''}
                disabled
                fullWidth
              />
            </Box>
          </Paper>
        </Grid>

        {/* Icon Settings */}
        <Grid item xs={12} md={6}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              {t('profile.icon')}
            </Typography>
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'center' }}>
              <Avatar
                src={user?.icon_url}
                sx={{
                  width: 100,
                  height: 100,
                  bgcolor: 'primary.main',
                  fontSize: '2rem',
                }}
              >
                {getInitials()}
              </Avatar>
              <Button
                variant="outlined"
                startIcon={<ColorLensIcon />}
                onClick={() => setIconDialogOpen(true)}
              >
                {t('profile.changeIcon')}
              </Button>
            </Box>
          </Paper>
        </Grid>

        {/* PIN Settings */}
        <Grid item xs={12}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              {t('profile.changePIN')}
            </Typography>
            <Alert severity="info" sx={{ mb: 2 }}>
              {t('profile.pinInfo')}
            </Alert>
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, maxWidth: 400 }}>
              <TextField
                label={t('profile.currentPIN')}
                type="password"
                value={currentPin}
                onChange={(e) => setCurrentPin(e.target.value)}
                inputProps={{ maxLength: 10 }}
                fullWidth
              />
              <TextField
                label={t('profile.newPIN')}
                type="password"
                value={pin}
                onChange={(e) => setPin(e.target.value)}
                inputProps={{ maxLength: 10 }}
                fullWidth
              />
              <TextField
                label={t('profile.confirmPIN')}
                type="password"
                value={confirmPin}
                onChange={(e) => setConfirmPin(e.target.value)}
                inputProps={{ maxLength: 10 }}
                fullWidth
              />
              <Button
                variant="contained"
                startIcon={<SaveIcon />}
                onClick={handleUpdatePIN}
                disabled={saving || !pin || !confirmPin}
              >
                {t('profile.updatePIN')}
              </Button>
            </Box>
          </Paper>
        </Grid>
      </Grid>

      {/* Icon Dialog */}
      <Dialog open={iconDialogOpen} onClose={() => setIconDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{t('profile.changeIcon')}</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 3, mt: 2 }}>
            {/* Mode Selection */}
            <Box>
              <Button
                variant={iconMode === 'color' ? 'contained' : 'outlined'}
                onClick={() => setIconMode('color')}
                sx={{ mr: 2 }}
              >
                {t('profile.generateFromColors')}
              </Button>
              <Button
                variant={iconMode === 'upload' ? 'contained' : 'outlined'}
                onClick={() => setIconMode('upload')}
              >
                {t('profile.uploadImage')}
              </Button>
            </Box>

            {/* Preview */}
            <Box sx={{ display: 'flex', justifyContent: 'center' }}>
              <Avatar
                src={previewIcon}
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

            {/* Color Picker */}
            {iconMode === 'color' && (
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <TextField
                  label={t('profile.backgroundColor')}
                  type="color"
                  value={bgColor}
                  onChange={(e) => setBgColor(e.target.value)}
                  InputLabelProps={{ shrink: true }}
                  fullWidth
                />
                <TextField
                  label={t('profile.textColor')}
                  type="color"
                  value={textColor}
                  onChange={(e) => setTextColor(e.target.value)}
                  InputLabelProps={{ shrink: true }}
                  fullWidth
                />
              </Box>
            )}

            {/* File Upload */}
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
                  <Button
                    variant="outlined"
                    component="span"
                    startIcon={<UploadIcon />}
                    fullWidth
                  >
                    {t('profile.selectImage')}
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
          <Button onClick={() => setIconDialogOpen(false)}>{t('common.cancel')}</Button>
          <Button
            onClick={handleUpdateIcon}
            variant="contained"
            disabled={saving || (iconMode === 'upload' && !iconFile)}
          >
            {t('common.save')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

