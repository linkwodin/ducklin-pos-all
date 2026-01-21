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
import { categoriesAPI } from '../services/api';
import { useSnackbar } from 'notistack';

export default function CategoriesPage() {
  const [categories, setCategories] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [renameOpen, setRenameOpen] = useState(false);
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
    if (!window.confirm(`Are you sure you want to delete category "${categoryName}"? This will remove the category from all products.`)) {
      return;
    }
    try {
      await categoriesAPI.delete(categoryName);
      enqueueSnackbar('Category deleted successfully', { variant: 'success' });
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
      enqueueSnackbar('Category renamed successfully', { variant: 'success' });
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
      enqueueSnackbar('Category created. It will appear when used in a product.', {
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

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">Categories</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => {
            setNewCategoryName('');
            setOpen(true);
          }}
        >
          Add Category
        </Button>
      </Box>

      <Alert severity="info" sx={{ mb: 3 }}>
        Categories are automatically created when you assign them to products. 
        Deleting a category will remove it from all products.
      </Alert>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Category Name</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={2} align="center">
                  Loading...
                </TableCell>
              </TableRow>
            ) : categories.length === 0 ? (
              <TableRow>
                <TableCell colSpan={2} align="center">
                  No categories found. Categories are created when you assign them to products.
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
        <DialogTitle>Add Category</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
            <TextField
              label="Category Name"
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
              The category will be created when you assign it to a product.
            </Alert>
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={handleCreate} variant="contained">
            Create
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={renameOpen} onClose={() => setRenameOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Rename Category</DialogTitle>
        <DialogContent>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
            <TextField
              label="New Category Name"
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
              This will rename the category in all products that use it.
            </Alert>
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameOpen(false)}>Cancel</Button>
          <Button
            onClick={() => {
              if (editingCategory) {
                handleRename(editingCategory, newCategoryName);
              }
            }}
            variant="contained"
          >
            Rename
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

