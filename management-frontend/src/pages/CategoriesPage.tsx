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
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { categoriesAPI } from '../services/api';
import { useSnackbar } from 'notistack';

export default function CategoriesPage() {
  const { t } = useTranslation('categories');
  const [categories, setCategories] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [renameOpen, setRenameOpen] = useState(false);
  const [normalizing, setNormalizing] = useState(false);
  const [editingCategory, setEditingCategory] = useState<string | null>(null);
  const [newCategoryName, setNewCategoryName] = useState('');
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchCategories();
  }, []);

  const fetchCategories = async () => {
    try {
      setLoading(true);
      const data = await categoriesAPI.list();
      setCategories(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch categories', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (categoryName: string) => {
    if (!window.confirm(t('confirmDelete', { name: categoryName }))) {
      return;
    }
    try {
      await categoriesAPI.delete(categoryName);
      enqueueSnackbar(t('deleteSuccess'), { variant: 'success' });
      fetchCategories();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to delete category', {
        variant: 'error',
      });
    }
  };

  const handleRename = async (oldName: string, newName: string) => {
    if (!newName.trim()) {
      enqueueSnackbar('Category name cannot be empty', { variant: 'error' });
      return;
    }
    if (newName === oldName) {
      setRenameOpen(false);
      return;
    }
    try {
      await categoriesAPI.rename(oldName, newName);
      enqueueSnackbar(t('renameSuccess'), { variant: 'success' });
      setRenameOpen(false);
      setEditingCategory(null);
      setNewCategoryName('');
      fetchCategories();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to rename category', {
        variant: 'error',
      });
    }
  };

  const handleCreate = async () => {
    if (!newCategoryName.trim()) {
      enqueueSnackbar('Category name cannot be empty', { variant: 'error' });
      return;
    }
    try {
      await categoriesAPI.create(newCategoryName);
      enqueueSnackbar(t('addSuccess'), {
        variant: 'success',
      });
      setOpen(false);
      setNewCategoryName('');
      fetchCategories();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to create category', {
        variant: 'error',
      });
    }
  };

  const handleNormalize = async () => {
    try {
      setNormalizing(true);
      const { products_updated } = await categoriesAPI.normalize();
      enqueueSnackbar(
        products_updated > 0
          ? t('normalizeSuccess', { count: products_updated })
          : t('normalizeAlready'),
        { variant: 'success' }
      );
      fetchCategories();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to normalize categories', {
        variant: 'error',
      });
    } finally {
      setNormalizing(false);
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 1, mb: 3 }}>
        <Typography variant="h4">{t('title')}</Typography>
        <Box sx={{ display: 'flex', gap: 1 }}>
          <Button
            variant="outlined"
            onClick={handleNormalize}
            disabled={normalizing}
          >
            {normalizing ? t('normalizeBusy') : t('normalize')}
          </Button>
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={() => {
              setNewCategoryName('');
            setOpen(true);
          }}
          >
            {t('addCategory')}
          </Button>
        </Box>
      </Box>

      <Alert severity="info" sx={{ mb: 3 }}>
        {t('infoMessage')}
      </Alert>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>{t('categoryName')}</TableCell>
              <TableCell>{t('actions')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={2} align="center">
                  {t('loading')}
                </TableCell>
              </TableRow>
            ) : categories.length === 0 ? (
              <TableRow>
                <TableCell colSpan={2} align="center">
                  {t('noCategories')}
                </TableCell>
              </TableRow>
            ) : (
              categories.map((category) => (
                <TableRow key={category}>
                  <TableCell>{category}</TableCell>
                  <TableCell>
                    <IconButton
                      size="small"
                      onClick={() => {
                        setEditingCategory(category);
                        setNewCategoryName(category);
                        setRenameOpen(true);
                      }}
                    >
                      <EditIcon />
                    </IconButton>
                    <IconButton
                      size="small"
                      onClick={() => handleDelete(category)}
                      color="error"
                    >
                      <DeleteIcon />
                    </IconButton>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <Dialog open={open} onClose={() => setOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{t('addCategory')}</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
            <TextField
              label={t('categoryName')}
              required
              fullWidth
              value={newCategoryName}
              onChange={(e) => setNewCategoryName(e.target.value)}
              onKeyPress={(e) => {
                if (e.key === 'Enter') {
                  handleCreate();
                }
              }}
            />
            <Alert severity="info">
              {t('createInfo')}
            </Alert>
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpen(false)}>{t('cancel')}</Button>
          <Button onClick={handleCreate} variant="contained">
            {t('create')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={renameOpen} onClose={() => setRenameOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{t('renameCategory')}</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
            <TextField
              label={t('newCategoryName')}
              required
              fullWidth
              value={newCategoryName}
              onChange={(e) => setNewCategoryName(e.target.value)}
              onKeyPress={(e) => {
                if (e.key === 'Enter' && editingCategory) {
                  handleRename(editingCategory, newCategoryName);
                }
              }}
            />
            <Alert severity="warning">
              {t('renameWarning')}
            </Alert>
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameOpen(false)}>{t('cancel')}</Button>
          <Button
            onClick={() => {
              if (editingCategory) {
                handleRename(editingCategory, newCategoryName);
              }
            }}
            variant="contained"
          >
            {t('rename')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

