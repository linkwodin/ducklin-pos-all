import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
  TextField,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  MenuItem,
  Autocomplete,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
  Visibility as VisibilityIcon,
  EditNote as EditNoteIcon,
} from '@mui/icons-material';
import { productsAPI, categoriesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Product } from '../types';

export default function ProductsPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [categoryFilter, setCategoryFilter] = useState('');
  const [importDialogOpen, setImportDialogOpen] = useState(false);
  const [importFile, setImportFile] = useState<File | null>(null);
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchProducts();
    fetchCategories();
  }, [categoryFilter]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const data = await productsAPI.list(categoryFilter || undefined);
      setProducts(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch products', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const fetchCategories = async () => {
    try {
      const data = await categoriesAPI.list();
      setCategories(data);
    } catch (error) {
      // Silently fail - categories are optional
      console.error('Failed to fetch categories:', error);
    }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm('Are you sure you want to deactivate this product?')) {
      return;
    }
    try {
      await productsAPI.delete(id);
      enqueueSnackbar('Product deactivated', { variant: 'success' });
      fetchProducts();
    } catch (error) {
      enqueueSnackbar('Failed to deactivate product', { variant: 'error' });
    }
  };

  const handleSave = async (productData: Partial<Product> | FormData) => {
    try {
      if (editingProduct) {
        await productsAPI.update(editingProduct.id, productData);
        enqueueSnackbar('Product updated', { variant: 'success' });
      } else {
        await productsAPI.create(productData);
        enqueueSnackbar('Product created', { variant: 'success' });
      }
      setOpen(false);
      setEditingProduct(null);
      fetchProducts();
      fetchCategories(); // Refresh categories after adding/updating product
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to save product', {
        variant: 'error',
      });
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">Products</Typography>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <Button
            variant="outlined"
            onClick={() => setImportDialogOpen(true)}
          >
            Import from Excel
          </Button>
          <Button
            variant="outlined"
            startIcon={<EditNoteIcon />}
            onClick={() => navigate('/product-cost-editor')}
          >
            Cost & Price Editor
          </Button>
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={() => {
              setEditingProduct(null);
              setOpen(true);
            }}
          >
            Add Product
          </Button>
        </Box>
      </Box>

      <Box sx={{ mb: 2 }}>
        <TextField
          select
          label="Filter by Category"
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          sx={{ minWidth: 200 }}
          size="small"
        >
          <MenuItem value="">All Categories</MenuItem>
          {categories.map((cat) => (
            <MenuItem key={cat} value={cat}>
              {cat}
            </MenuItem>
          ))}
        </TextField>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Name</TableCell>
              <TableCell>SKU</TableCell>
              <TableCell>Barcode</TableCell>
              <TableCell>Category</TableCell>
              <TableCell>Unit Type</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Price (GBP)</TableCell>
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
            ) : products.length === 0 ? (
              <TableRow>
                <TableCell colSpan={8} align="center">
                  No products found
                </TableCell>
              </TableRow>
            ) : (
              products.map((product) => (
                <TableRow key={product.id}>
                  <TableCell>{product.name}</TableCell>
                  <TableCell>{product.sku || '-'}</TableCell>
                  <TableCell>{product.barcode || '-'}</TableCell>
                  <TableCell>{product.category || '-'}</TableCell>
                  <TableCell>
                    <Chip
                      label={product.unit_type}
                      size="small"
                      color={product.unit_type === 'weight' ? 'primary' : 'default'}
                    />
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={product.is_active ? 'Active' : 'Inactive'}
                      size="small"
                      color={product.is_active ? 'success' : 'default'}
                    />
                  </TableCell>
                  <TableCell>
                    £{product.current_cost?.wholesale_cost_gbp?.toFixed(2) || '-'}
                  </TableCell>
                  <TableCell>
                    <IconButton
                      size="small"
                      onClick={() => navigate(`/products/${product.id}`)}
                    >
                      <VisibilityIcon />
                    </IconButton>
                    <IconButton
                      size="small"
                      onClick={() => {
                        setEditingProduct(product);
                        setOpen(true);
                      }}
                    >
                      <EditIcon />
                    </IconButton>
                    <IconButton
                      size="small"
                      onClick={() => handleDelete(product.id)}
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

      <ProductDialog
        open={open}
        onClose={() => {
          setOpen(false);
          setEditingProduct(null);
        }}
        onSave={handleSave}
        product={editingProduct}
        existingCategories={categories}
      />

      <Dialog
        open={importDialogOpen}
        onClose={() => {
          setImportDialogOpen(false);
          setImportFile(null);
        }}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Import Products from Excel</DialogTitle>
        <DialogContent>
          <Typography variant="body2" sx={{ mb: 2 }}>
            Upload an Excel file (.xlsx) with the following headers in the first row:
          </Typography>
          <Box sx={{ mb: 2, pl: 2 }}>
            <Typography variant="body2">• Chinese Name</Typography>
            <Typography variant="body2">• English name</Typography>
            <Typography variant="body2">• Unit ("weight" or leave blank for quantity)</Typography>
            <Typography variant="body2">• Barcode</Typography>
            <Typography variant="body2">• Retail Price (Direct Retail Price)</Typography>
            <Typography variant="body2">• Sector - Loog Fung Retail (optional)</Typography>
          </Box>
          <Button
            variant="outlined"
            component="label"
            sx={{ mt: 1 }}
          >
            Choose Excel File
            <input
              type="file"
              accept=".xlsx"
              hidden
              onChange={(e) => {
                const file = e.target.files?.[0] || null;
                setImportFile(file);
              }}
            />
          </Button>
          <Typography variant="body2" sx={{ mt: 1 }}>
            {importFile ? importFile.name : 'No file selected'}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button
            onClick={() => {
              setImportDialogOpen(false);
              setImportFile(null);
            }}
          >
            Cancel
          </Button>
          <Button
            variant="contained"
            disabled={!importFile}
            onClick={async () => {
              if (!importFile) return;
              try {
                const result = await productsAPI.importExcel(importFile);
                enqueueSnackbar(
                  `Imported: ${result.imported}, Updated: ${result.updated}`,
                  { variant: 'success' }
                );
                if (result.errors && result.errors.length > 0) {
                  console.error('Import errors:', result.errors);
                  enqueueSnackbar(
                    `${result.errors.length} errors occurred. Check console for details.`,
                    { variant: 'warning' }
                  );
                }
                setImportDialogOpen(false);
                setImportFile(null);
                fetchProducts();
              } catch (error: any) {
                enqueueSnackbar(
                  error.response?.data?.error || 'Failed to import products',
                  { variant: 'error' }
                );
              }
            }}
          >
            Import
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

function ProductDialog({
  open,
  onClose,
  onSave,
  product,
  existingCategories,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: Partial<Product> | FormData) => void;
  product: Product | null;
  existingCategories: string[];
}) {
  const [formData, setFormData] = useState({
    name: '',
    name_chinese: '',
    barcode: '',
    sku: '',
    category: '',
    unit_type: 'quantity' as 'quantity' | 'weight',
  });
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);

  useEffect(() => {
    if (product) {
      setFormData({
        name: product.name || '',
        name_chinese: product.name_chinese || '',
        barcode: product.barcode || '',
        sku: product.sku || '',
        category: product.category || '',
        unit_type: product.unit_type || 'quantity',
      });
      // Show existing image as preview if available
      if (product.image_url) {
        setImagePreview(product.image_url);
      } else {
        setImagePreview(null);
      }
      setImageFile(null);
    } else {
      setFormData({
        name: '',
        name_chinese: '',
        barcode: '',
        sku: '',
        category: '',
        unit_type: 'quantity',
      });
      setImagePreview(null);
      setImageFile(null);
    }
  }, [product, open]);

  const validateAndSetImage = (file: File) => {
    // Validate file type
    const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
    if (!validTypes.includes(file.type)) {
      alert('Invalid file type. Please upload a JPEG, PNG, GIF, or WebP image.');
      return false;
    }
    
    // No file size limit - backend will resize if needed

    setImageFile(file);
    const reader = new FileReader();
    reader.onloadend = () => {
      setImagePreview(reader.result as string);
    };
    reader.readAsDataURL(file);
    return true;
  };

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      validateAndSetImage(file);
    }
  };

  // Handle clipboard paste
  useEffect(() => {
    const handlePasteGlobal = (e: ClipboardEvent) => {
      if (!open) return;
      const items = e.clipboardData?.items;
      if (!items) return;
      
      for (let i = 0; i < items.length; i++) {
        if (items[i].type.indexOf('image') !== -1) {
          const blob = items[i].getAsFile();
          if (blob) {
            // Create a File object from the blob
            const file = new File([blob], `pasted-image-${Date.now()}.png`, {
              type: blob.type || 'image/png',
            });
            if (validateAndSetImage(file)) {
              e.preventDefault();
            }
            break;
          }
        }
      }
    };

    if (open) {
      document.addEventListener('paste', handlePasteGlobal);
      return () => {
        document.removeEventListener('paste', handlePasteGlobal);
      };
    }
  }, [open]);

  const handleSubmit = () => {
    // If image file is selected, we need to send FormData
    if (imageFile) {
      const formDataToSend = new FormData();
      formDataToSend.append('name', formData.name);
      formDataToSend.append('name_chinese', formData.name_chinese);
      formDataToSend.append('barcode', formData.barcode);
      formDataToSend.append('sku', formData.sku);
      formDataToSend.append('category', formData.category);
      formDataToSend.append('unit_type', formData.unit_type);
      formDataToSend.append('image', imageFile);
      
      // Call onSave with FormData
      onSave(formDataToSend as any);
    } else {
      // Use regular JSON if no file
      onSave(formData);
    }
  };

  return (
    <Dialog 
      open={open} 
      onClose={onClose} 
      maxWidth="sm" 
      fullWidth
    >
      <DialogTitle>{product ? 'Edit Product' : 'Add Product'}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label="Name"
            required
            fullWidth
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          />
          <TextField
            label="Name (Chinese)"
            fullWidth
            value={formData.name_chinese}
            onChange={(e) =>
              setFormData({ ...formData, name_chinese: e.target.value })
            }
          />
          <TextField
            label="SKU"
            fullWidth
            value={formData.sku}
            onChange={(e) => setFormData({ ...formData, sku: e.target.value })}
          />
          <TextField
            label="Barcode"
            fullWidth
            value={formData.barcode}
            onChange={(e) =>
              setFormData({ ...formData, barcode: e.target.value })
            }
          />
          <Autocomplete
            freeSolo
            options={existingCategories}
            value={formData.category || null}
            onChange={(_, newValue) => {
              // Handle both string selection and new input
              const categoryValue = typeof newValue === 'string' ? newValue : (newValue || '');
              setFormData({ ...formData, category: categoryValue });
            }}
            onInputChange={(_, newInputValue) => {
              // Update as user types
              setFormData({ ...formData, category: newInputValue });
            }}
            renderInput={(params) => (
              <TextField
                {...params}
                label="Category"
                placeholder="Select existing or type new category"
              />
            )}
          />
          <Box>
            <Typography variant="body2" sx={{ mb: 1 }}>
              Product Image
            </Typography>
            <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
              Upload an image file or paste from clipboard (Ctrl+V / Cmd+V)
            </Typography>
            <input
              accept="image/*"
              style={{ display: 'none' }}
              id="image-upload"
              type="file"
              onChange={handleImageChange}
            />
            <label htmlFor="image-upload">
              <Button variant="outlined" component="span" fullWidth sx={{ mb: 1 }}>
                {imageFile ? 'Change Image' : 'Upload Image'}
              </Button>
            </label>
            {imagePreview && (
              <Box
                component="img"
                src={imagePreview}
                alt="Preview"
                sx={{
                  width: '100%',
                  maxHeight: 200,
                  objectFit: 'contain',
                  borderRadius: 1,
                  mb: 1,
                  border: '1px solid #e0e0e0',
                }}
              />
            )}
          </Box>
          <TextField
            select
            label="Unit Type"
            required
            fullWidth
            value={formData.unit_type}
            onChange={(e) =>
              setFormData({
                ...formData,
                unit_type: e.target.value as 'quantity' | 'weight',
              })
            }
          >
            <MenuItem value="quantity">Quantity</MenuItem>
            <MenuItem value="weight">Weight</MenuItem>
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

