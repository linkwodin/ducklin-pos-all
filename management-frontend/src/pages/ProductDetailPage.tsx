import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Box,
  Paper,
  Typography,
  Button,
  Grid,
  Card,
  CardContent,
  Tabs,
  Tab,
  TextField,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
} from '@mui/material';
import {
  ArrowBack as ArrowBackIcon,
  AttachMoney as AttachMoneyIcon,
  TrendingUp as TrendingUpIcon,
  LocalOffer as LocalOfferIcon,
} from '@mui/icons-material';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { productsAPI, sectorsAPI, currencyRatesAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Product, ProductCost, PriceHistory, CurrencyRate } from '../types';
import { format } from 'date-fns';
import {
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  CircularProgress,
} from '@mui/material';

export default function ProductDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const [product, setProduct] = useState<Product | null>(null);
  const [priceHistory, setPriceHistory] = useState<PriceHistory[]>([]);
  const [tabValue, setTabValue] = useState(0);
  const [costDialogOpen, setCostDialogOpen] = useState(false);

  useEffect(() => {
    if (id) {
      fetchProduct();
      fetchPriceHistory();
    }
  }, [id]);

  const fetchProduct = async () => {
    try {
      const data = await productsAPI.get(Number(id));
      setProduct(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch product', { variant: 'error' });
    }
  };

  const fetchPriceHistory = async () => {
    try {
      const data = await productsAPI.getPriceHistory(Number(id));
      setPriceHistory(data);
    } catch (error) {
      console.error('Failed to fetch price history:', error);
    }
  };

  const handleSetCost = async (costData: Partial<ProductCost>) => {
    try {
      await productsAPI.setCost(Number(id), costData);
      enqueueSnackbar('Cost updated successfully', { variant: 'success' });
      setCostDialogOpen(false);
      fetchProduct();
      fetchPriceHistory();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to set cost', {
        variant: 'error',
      });
    }
  };

  const chartData = priceHistory
    .slice()
    .reverse()
    .map((h) => ({
      date: format(new Date(h.recorded_at), 'MMM dd, yyyy'),
      wholesale: h.wholesale_cost_gbp,
      final: h.final_price_gbp,
    }));

  if (!product) {
    return <Typography>Loading...</Typography>;
  }

  return (
    <Box>
      <Button
        startIcon={<ArrowBackIcon />}
        onClick={() => navigate('/products')}
        sx={{ mb: 2 }}
      >
        Back to Products
      </Button>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Grid container spacing={3}>
          <Grid item xs={12} md={6}>
            <Typography variant="h4" gutterBottom>
              {product.name}
            </Typography>
            {product.name_chinese && (
              <Typography variant="h6" color="text.secondary" gutterBottom>
                {product.name_chinese}
              </Typography>
            )}
            <Box sx={{ mt: 2 }}>
              <Typography variant="body2">
                <strong>SKU:</strong> {product.sku || '-'}
              </Typography>
              <Typography variant="body2">
                <strong>Barcode:</strong> {product.barcode || '-'}
              </Typography>
              <Typography variant="body2">
                <strong>Category:</strong> {product.category || '-'}
              </Typography>
              <Typography variant="body2">
                <strong>Unit Type:</strong> {product.unit_type}
              </Typography>
            </Box>
          </Grid>
          <Grid item xs={12} md={6}>
            {product.image_url && (
              <Box
                component="img"
                src={product.image_url}
                alt={product.name}
                sx={{ maxWidth: '100%', maxHeight: 300, borderRadius: 2 }}
              />
            )}
          </Grid>
        </Grid>
      </Paper>

      <Paper sx={{ p: 2 }}>
        <Tabs value={tabValue} onChange={(_, v) => setTabValue(v)}>
          <Tab icon={<AttachMoneyIcon />} label="Cost Configuration" />
          <Tab icon={<TrendingUpIcon />} label="Price History" />
          <Tab icon={<LocalOfferIcon />} label="Discounts" />
        </Tabs>

        {tabValue === 0 && (
          <Box sx={{ mt: 3 }}>
            {product.current_cost ? (
              <Card>
                <CardContent>
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                    <Typography variant="h6">Current Cost Configuration</Typography>
                    <Button
                      variant="outlined"
                      onClick={() => setCostDialogOpen(true)}
                    >
                      Update Cost
                    </Button>
                  </Box>
                  <Grid container spacing={2}>
                    <Grid item xs={6}>
                      <Typography variant="body2" color="text.secondary">
                        Exchange Rate
                      </Typography>
                      <Typography variant="body1">
                        {product.current_cost.exchange_rate}
                      </Typography>
                    </Grid>
                    <Grid item xs={6}>
                      <Typography variant="body2" color="text.secondary">
                        Wholesale Cost (GBP)
                      </Typography>
                      <Typography variant="h6" color="primary">
                        £{product.current_cost.wholesale_cost_gbp.toFixed(2)}
                      </Typography>
                    </Grid>
                    <Grid item xs={6}>
                      <Typography variant="body2" color="text.secondary">
                        Unit Weight (g)
                      </Typography>
                      <Typography variant="body1">
                        {product.current_cost.unit_weight_g}g
                      </Typography>
                    </Grid>
                    <Grid item xs={6}>
                      <Typography variant="body2" color="text.secondary">
                        Weight (g)
                      </Typography>
                      <Typography variant="body1">
                        {product.current_cost.weight_g}g
                      </Typography>
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>
            ) : (
              <Box>
                <Typography variant="body1" gutterBottom>
                  No cost configuration set
                </Typography>
                <Button
                  variant="contained"
                  onClick={() => setCostDialogOpen(true)}
                >
                  Set Cost
                </Button>
              </Box>
            )}
          </Box>
        )}

        {tabValue === 1 && (
          <Box sx={{ mt: 3 }}>
            {chartData.length > 0 ? (
              <ResponsiveContainer width="100%" height={400}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="wholesale"
                    stroke="#8884d8"
                    name="Wholesale Cost (GBP)"
                  />
                  <Line
                    type="monotone"
                    dataKey="final"
                    stroke="#82ca9d"
                    name="Final Price (GBP)"
                  />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <Typography>No price history available</Typography>
            )}
          </Box>
        )}

        {tabValue === 2 && (
          <Box sx={{ mt: 3 }}>
            <DiscountManagement
              productId={product.id}
              onUpdate={fetchProduct}
            />
          </Box>
        )}
      </Paper>

      <CostDialog
        open={costDialogOpen}
        onClose={() => setCostDialogOpen(false)}
        onSave={handleSetCost}
        currentCost={product.current_cost || undefined}
      />
    </Box>
  );
}

function CostDialog({
  open,
  onClose,
  onSave,
  currentCost,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: Partial<ProductCost>) => void;
  currentCost?: ProductCost;
}) {
  const [formData, setFormData] = useState({
    currency_code: 'HKD',
    exchange_rate: 0,
    purchasing_cost_hkd: 0,
    unit_weight_g: 0,
    purchasing_cost_buffer_percent: 0,
    weight_g: 0,
    weight_buffer_percent: 0,
    freight_rate_hkd_per_kg: 0,
    freight_buffer_hkd: 0,
    import_duty_percent: 0,
    packaging_gbp: 0,
    direct_retail_online_store_price_gbp: 0,
  });
  const [currencyRates, setCurrencyRates] = useState<CurrencyRate[]>([]);
  const [loadingRates, setLoadingRates] = useState(false);

  useEffect(() => {
    if (open) {
      fetchCurrencyRates();
    }
  }, [open]);

  // Pre-populate form with current cost data when dialog opens or currentCost changes
  useEffect(() => {
    if (open && currentCost && currencyRates.length > 0) {
      // Find currency by matching exchange rate (with small tolerance for floating point)
      const matchedCurrency = currencyRates.find(
        (r) => Math.abs(r.rate_to_gbp - currentCost.exchange_rate) < 0.000001
      );
      
      setFormData({
        currency_code: matchedCurrency?.currency_code || 'HKD',
        exchange_rate: currentCost.exchange_rate,
        purchasing_cost_hkd: currentCost.purchasing_cost_hkd || 0,
        unit_weight_g: currentCost.unit_weight_g,
        purchasing_cost_buffer_percent: currentCost.purchasing_cost_buffer_percent || 0,
        weight_g: currentCost.weight_g,
        weight_buffer_percent: currentCost.weight_buffer_percent || 0,
        freight_rate_hkd_per_kg: currentCost.freight_rate_hkd_per_kg || 0,
        freight_buffer_hkd: currentCost.freight_buffer_hkd || 0,
        import_duty_percent: currentCost.import_duty_percent || 0,
        packaging_gbp: currentCost.packaging_gbp || 0,
        direct_retail_online_store_price_gbp: currentCost.direct_retail_online_store_price_gbp || 0,
      });
    } else if (open && !currentCost && currencyRates.length > 0) {
      // Set default to HKD (most commonly used for purchasing) or first pinned currency
      const hkdRate = currencyRates.find((r) => r.currency_code === 'HKD');
      const firstPinned = currencyRates.find((r) => r.is_pinned);
      const defaultRate = hkdRate || firstPinned || currencyRates[0];
      
      if (defaultRate) {
        setFormData((prev) => ({
          ...prev,
          currency_code: defaultRate.currency_code,
          exchange_rate: defaultRate.rate_to_gbp,
        }));
      }
    }
  }, [open, currentCost, currencyRates]);

  const fetchCurrencyRates = async () => {
    try {
      setLoadingRates(true);
      const rates = await currencyRatesAPI.list();
      // Rates are already sorted with pinned first from the API
      setCurrencyRates(rates);
    } catch (error) {
      console.error('Failed to fetch currency rates:', error);
    } finally {
      setLoadingRates(false);
    }
  };

  const handleCurrencyChange = (currencyCode: string) => {
    const selectedRate = currencyRates.find((r) => r.currency_code === currencyCode);
    if (selectedRate) {
      setFormData((prev) => ({
        ...prev,
        currency_code: currencyCode,
        exchange_rate: selectedRate.rate_to_gbp,
      }));
    }
  };

  const handleSubmit = () => {
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>Set Product Cost</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <FormControl fullWidth required>
            <InputLabel>Currency</InputLabel>
            <Select
              value={formData.currency_code}
              label="Currency"
              onChange={(e) => handleCurrencyChange(e.target.value)}
              disabled={loadingRates}
            >
              {loadingRates ? (
                <MenuItem disabled>
                  <CircularProgress size={20} sx={{ mr: 1 }} />
                  Loading currencies...
                </MenuItem>
              ) : currencyRates.length === 0 ? (
                <MenuItem disabled>No currency rates available. Please add currencies first.</MenuItem>
              ) : (
                currencyRates.map((rate) => (
                  <MenuItem key={rate.currency_code} value={rate.currency_code}>
                    {rate.currency_code}
                    {rate.is_pinned && (
                      <Typography component="span" variant="caption" color="primary" sx={{ ml: 1 }}>
                        📌
                      </Typography>
                    )}
                    {' - '}
                    {rate.rate_to_gbp.toFixed(6)} GBP
                  </MenuItem>
                ))
              )}
            </Select>
          </FormControl>
          <TextField
            label="Exchange Rate (to GBP)"
            type="number"
            required
            fullWidth
            disabled
            value={formData.exchange_rate}
            helperText="Automatically set based on selected currency"
          />
          <TextField
            label="Purchasing Cost (HKD)"
            type="number"
            fullWidth
            value={formData.purchasing_cost_hkd}
            onChange={(e) =>
              setFormData({
                ...formData,
                purchasing_cost_hkd: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Unit Weight (g)"
            type="number"
            required
            fullWidth
            value={formData.unit_weight_g}
            onChange={(e) =>
              setFormData({ ...formData, unit_weight_g: parseInt(e.target.value) })
            }
          />
          <TextField
            label="Purchasing Cost Buffer (%)"
            type="number"
            fullWidth
            value={formData.purchasing_cost_buffer_percent}
            onChange={(e) =>
              setFormData({
                ...formData,
                purchasing_cost_buffer_percent: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Weight (g)"
            type="number"
            required
            fullWidth
            value={formData.weight_g}
            onChange={(e) =>
              setFormData({ ...formData, weight_g: parseInt(e.target.value) })
            }
          />
          <TextField
            label="Weight Buffer (%)"
            type="number"
            fullWidth
            value={formData.weight_buffer_percent}
            onChange={(e) =>
              setFormData({
                ...formData,
                weight_buffer_percent: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Freight Rate (HKD per KG)"
            type="number"
            required
            fullWidth
            value={formData.freight_rate_hkd_per_kg}
            onChange={(e) =>
              setFormData({
                ...formData,
                freight_rate_hkd_per_kg: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Freight Buffer (HKD)"
            type="number"
            fullWidth
            value={formData.freight_buffer_hkd}
            onChange={(e) =>
              setFormData({
                ...formData,
                freight_buffer_hkd: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Import Duty (%)"
            type="number"
            fullWidth
            value={formData.import_duty_percent}
            onChange={(e) =>
              setFormData({
                ...formData,
                import_duty_percent: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Packaging (GBP)"
            type="number"
            fullWidth
            value={formData.packaging_gbp}
            onChange={(e) =>
              setFormData({
                ...formData,
                packaging_gbp: parseFloat(e.target.value),
              })
            }
          />
          <TextField
            label="Direct Retail Online Store Price (GBP)"
            type="number"
            fullWidth
            inputProps={{ min: 0, step: 0.01 }}
            value={formData.direct_retail_online_store_price_gbp}
            onChange={(e) =>
              setFormData({
                ...formData,
                direct_retail_online_store_price_gbp: parseFloat(e.target.value) || 0,
              })
            }
            helperText="Used for e-catalog price calculation with sector discount"
          />
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

function DiscountManagement({
  productId,
  onUpdate,
}: {
  productId: number;
  onUpdate: () => void;
}) {
  const [discounts, setDiscounts] = useState<any[]>([]);
  const [sectors, setSectors] = useState<any[]>([]);
  const [open, setOpen] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [discountsData, sectorsData] = await Promise.all([
        productsAPI.getDiscounts(productId),
        sectorsAPI.list(),
      ]);
      setDiscounts(discountsData);
      setSectors(sectorsData);
    } catch (error) {
      console.error('Failed to fetch discounts:', error);
    }
  };

  const handleSetDiscount = async (sectorId: number, discountPercent: number) => {
    try {
      await productsAPI.setDiscount(productId, sectorId, discountPercent);
      enqueueSnackbar('Discount set successfully', { variant: 'success' });
      setOpen(false);
      fetchData();
      onUpdate();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to set discount', {
        variant: 'error',
      });
    }
  };

  return (
    <Box>
      <Button variant="contained" onClick={() => setOpen(true)} sx={{ mb: 2 }}>
        Set Discount
      </Button>
      <TableContainer>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Sector</TableCell>
              <TableCell>Discount %</TableCell>
              <TableCell>Effective From</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {discounts.length === 0 ? (
              <TableRow>
                <TableCell colSpan={3} align="center">
                  No discounts set
                </TableCell>
              </TableRow>
            ) : (
              discounts.map((discount) => (
                <TableRow key={discount.id}>
                  <TableCell>{discount.sector?.name || '-'}</TableCell>
                  <TableCell>{discount.discount_percent}%</TableCell>
                  <TableCell>
                    {format(new Date(discount.effective_from), 'MMM dd, yyyy')}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <DiscountDialog
        open={open}
        onClose={() => setOpen(false)}
        onSave={handleSetDiscount}
        sectors={sectors}
      />
    </Box>
  );
}

function DiscountDialog({
  open,
  onClose,
  onSave,
  sectors,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (sectorId: number, discountPercent: number) => void;
  sectors: any[];
}) {
  const [sectorId, setSectorId] = useState<number | ''>('');
  const [discountPercent, setDiscountPercent] = useState(0);

  const handleSubmit = () => {
    if (sectorId && discountPercent >= 0) {
      onSave(Number(sectorId), discountPercent);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Set Discount</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            select
            label="Sector"
            required
            fullWidth
            value={sectorId}
            onChange={(e) => setSectorId(Number(e.target.value))}
          >
            {sectors.map((sector) => (
              <MenuItem key={sector.id} value={sector.id}>
                {sector.name}
              </MenuItem>
            ))}
          </TextField>
          <TextField
            label="Discount Percent"
            type="number"
            required
            fullWidth
            value={discountPercent}
            onChange={(e) => setDiscountPercent(parseFloat(e.target.value))}
            inputProps={{ min: 0, max: 100, step: 0.01 }}
          />
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

