import { useEffect, useState, useMemo } from 'react';
import {
  Grid,
  Paper,
  Typography,
  Box,
  Card,
  CardContent,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  TextField,
} from '@mui/material';
import {
  Inventory as InventoryIcon,
  Warning as WarningIcon,
  LocalShipping as LocalShippingIcon,
  People as PeopleIcon,
  AttachMoney as AttachMoneyIcon,
} from '@mui/icons-material';
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { productsAPI, stockAPI, restockAPI, usersAPI, ordersAPI, storesAPI } from '../services/api';
import type { Store } from '../types';
import { useTranslation } from 'react-i18next';

interface RevenueStat {
  date: string;
  revenue: number;
  order_count: number;
}

interface ProductSalesStat {
  date: string;
  product_id: number;
  product_name: string;
  product_name_chinese: string;
  quantity: number;
  revenue: number;
}

const DAYS = 30;
const todayStr = () => new Date().toISOString().slice(0, 10);
const formatDate = (d: Date) => d.toISOString().slice(0, 10);
const defaultEnd = () => new Date();
const defaultStart = () => {
  const d = new Date();
  d.setDate(d.getDate() - DAYS + 1);
  return d;
};

export default function Dashboard() {
  const { t } = useTranslation();
  const [dateRangeStart, setDateRangeStart] = useState(formatDate(defaultStart()));
  const [dateRangeEnd, setDateRangeEnd] = useState(formatDate(defaultEnd()));
  const [stores, setStores] = useState<Store[]>([]);
  const [selectedStoreId, setSelectedStoreId] = useState<number | ''>('');
  const [stats, setStats] = useState({
    totalProducts: 0,
    lowStockItems: 0,
    pendingRestocks: 0,
    totalUsers: 0,
  });
  const [revenueStats, setRevenueStats] = useState<RevenueStat[]>([]);
  const [productSalesStats, setProductSalesStats] = useState<ProductSalesStat[]>([]);
  const [todayRevenue, setTodayRevenue] = useState<number>(0);
  const [revenueByStore, setRevenueByStore] = useState<Array<{ store: Store; stats: RevenueStat[] }>>([]);
  const [loadingByStore, setLoadingByStore] = useState(false);
  const [loading, setLoading] = useState(true);

  const storeIdParam = selectedStoreId === '' ? undefined : (selectedStoreId as number);

  useEffect(() => {
    const fetchStores = async () => {
      try {
        const list = await storesAPI.list();
        setStores(list || []);
      } catch (e) {
        console.error('Failed to fetch stores:', e);
      }
    };
    fetchStores();
  }, []);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        setLoading(true);
        const [products, lowStock, restocks, users, revenue, productSales] = await Promise.all([
          productsAPI.list(),
          stockAPI.getLowStock(),
          restockAPI.list(undefined, 'initiated'),
          usersAPI.list(),
          ordersAPI.getDailyRevenueStats({ start_date: dateRangeStart, end_date: dateRangeEnd, store_id: storeIdParam }),
          ordersAPI.getDailyProductSalesStats({ start_date: dateRangeStart, end_date: dateRangeEnd, store_id: storeIdParam }),
        ]);

        setStats({
          totalProducts: products?.length || 0,
          lowStockItems: lowStock?.length || 0,
          pendingRestocks: restocks?.length || 0,
          totalUsers: users?.length || 0,
        });
        setRevenueStats(revenue || []);
        setProductSalesStats(productSales || []);
      } catch (error) {
        console.error('Failed to fetch stats:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchStats();
  }, [storeIdParam, dateRangeStart, dateRangeEnd]);

  useEffect(() => {
    const fetchToday = async () => {
      try {
        const all = await ordersAPI.getDailyRevenueStats({ days: 1 });
        const today = todayStr();
        const todayRow = (all || []).find((r: RevenueStat) => r.date === today);
        setTodayRevenue(todayRow ? Number(todayRow.revenue) : 0);
      } catch (e) {
        console.error('Failed to fetch today stats:', e);
      }
    };
    fetchToday();
  }, []);

  useEffect(() => {
    if (stores.length === 0) return;
    const fetchRevenueByStore = async () => {
      try {
        setLoadingByStore(true);
        const results = await Promise.all(
          stores.map(async (store) => {
            const stats = await ordersAPI.getDailyRevenueStats({ start_date: dateRangeStart, end_date: dateRangeEnd, store_id: store.id });
            return { store, stats: stats || [] };
          })
        );
        setRevenueByStore(results);
      } catch (e) {
        console.error('Failed to fetch revenue by store:', e);
      } finally {
        setLoadingByStore(false);
      }
    };
    fetchRevenueByStore();
  }, [stores.length, dateRangeStart, dateRangeEnd]);

  // Aggregate product sales by date and product
  const productSalesByDate = (productSalesStats || []).reduce((acc, stat) => {
    const key = stat.date;
    if (!acc[key]) {
      acc[key] = {};
    }
    const productKey = stat.product_name || stat.product_name_chinese || `Product ${stat.product_id}`;
    if (!acc[key][productKey]) {
      acc[key][productKey] = 0;
    }
    acc[key][productKey] += stat.quantity;
    return acc;
  }, {} as Record<string, Record<string, number>>);

  // Get top products by total sales
  const productTotals = (productSalesStats || []).reduce((acc, stat) => {
    const productKey = stat.product_name || stat.product_name_chinese || `Product ${stat.product_id}`;
    if (!acc[productKey]) {
      acc[productKey] = 0;
    }
    acc[productKey] += stat.quantity;
    return acc;
  }, {} as Record<string, number>);

  const topProducts = Object.entries(productTotals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([name, quantity]) => ({ name, quantity }));

  // Format revenue chart data
  const revenueChartData = (revenueStats || []).map(stat => ({
    date: new Date(stat.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    revenue: parseFloat(stat.revenue.toFixed(2)),
    orders: stat.order_count,
  }));

  // Format product sales chart data (top 5 products)
  const top5Products = topProducts.slice(0, 5).map(p => p.name);
  const productSalesChartData = Object.entries(productSalesByDate).map(([date, products]) => {
    const entry: any = {
      date: new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    };
    top5Products.forEach(productName => {
      entry[productName] = products[productName] || 0;
    });
    return entry;
  });

  const statCards = [
    {
      title: t('dashboard.totalProducts'),
      value: stats.totalProducts,
      icon: <InventoryIcon sx={{ fontSize: 40 }} />,
      color: '#1976d2',
    },
    {
      title: t('dashboard.lowStockItems'),
      value: stats.lowStockItems,
      icon: <WarningIcon sx={{ fontSize: 40 }} />,
      color: '#d32f2f',
    },
    {
      title: t('dashboard.pendingShipments'),
      value: stats.pendingRestocks,
      icon: <LocalShippingIcon sx={{ fontSize: 40 }} />,
      color: '#ed6c02',
    },
    {
      title: t('dashboard.totalUsers'),
      value: stats.totalUsers,
      icon: <PeopleIcon sx={{ fontSize: 40 }} />,
      color: '#2e7d32',
    },
  ];

  const colors = ['#1976d2', '#d32f2f', '#ed6c02', '#2e7d32', '#9c27b0'];

  const storeLineColors = ['#1976d2', '#2e7d32', '#ed6c02', '#9c27b0', '#0288d1', '#c2185b'];

  const dailySalesByStoreChartData = useMemo(() => {
    const dateMap: Record<string, Record<string, number>> = {};
    const add = (date: string, key: string, revenue: number) => {
      if (!dateMap[date]) dateMap[date] = {};
      dateMap[date][key] = parseFloat(Number(revenue).toFixed(2));
    };
    revenueByStore.forEach(({ store, stats }) => {
      const key = `s${store.id}`;
      stats.forEach((s) => add(s.date, key, s.revenue));
    });
    const allDates: string[] = [];
    const start = new Date(dateRangeStart);
    const end = new Date(dateRangeEnd);
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      allDates.push(d.toISOString().slice(0, 10));
    }
    return allDates.map((date) => {
      const row: Record<string, string | number> = {
        date: new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
      };
      revenueByStore.forEach(({ store }) => {
        row[`s${store.id}`] = dateMap[date]?.[`s${store.id}`] ?? 0;
      });
      return row;
    });
  }, [revenueByStore, dateRangeStart, dateRangeEnd]);

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        {t('dashboard.title')}
      </Typography>

      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap', mb: 2 }}>
        <TextField
          size="small"
          label={t('dashboard.dateFrom')}
          type="date"
          value={dateRangeStart}
          onChange={(e) => setDateRangeStart(e.target.value)}
          InputLabelProps={{ shrink: true }}
          inputProps={{ max: dateRangeEnd }}
        />
        <TextField
          size="small"
          label={t('dashboard.dateTo')}
          type="date"
          value={dateRangeEnd}
          onChange={(e) => setDateRangeEnd(e.target.value)}
          InputLabelProps={{ shrink: true }}
          inputProps={{ min: dateRangeStart }}
        />
        <Box sx={{ display: 'flex', gap: 1 }}>
          <Typography
            component="button"
            variant="body2"
            sx={{ px: 1.5, py: 0.75, border: 1, borderColor: 'divider', borderRadius: 1, cursor: 'pointer', background: 'transparent' }}
            onClick={() => {
              const end = new Date();
              const start = new Date();
              start.setDate(start.getDate() - 6);
              setDateRangeStart(formatDate(start));
              setDateRangeEnd(formatDate(end));
            }}
          >
            {t('dashboard.last7Days')}
          </Typography>
          <Typography
            component="button"
            variant="body2"
            sx={{ px: 1.5, py: 0.75, border: 1, borderColor: 'divider', borderRadius: 1, cursor: 'pointer', background: 'transparent' }}
            onClick={() => {
              const end = new Date();
              const start = new Date();
              start.setDate(start.getDate() - 29);
              setDateRangeStart(formatDate(start));
              setDateRangeEnd(formatDate(end));
            }}
          >
            {t('dashboard.last30Days')}
          </Typography>
        </Box>
        <FormControl size="small" sx={{ minWidth: 200 }}>
          <InputLabel>{t('dashboard.filterByStore')}</InputLabel>
          <Select
            value={selectedStoreId === '' ? 'all' : selectedStoreId}
            label={t('dashboard.filterByStore')}
            onChange={(e) => setSelectedStoreId(e.target.value === 'all' ? '' : (e.target.value as number))}
          >
            <MenuItem value="all">{t('dashboard.allStores')}</MenuItem>
            {stores.map((s) => (
              <MenuItem key={s.id} value={s.id}>
                {s.name}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      </Box>

      <Grid container spacing={3} sx={{ mt: 2 }}>
        {statCards.map((card, index) => (
          <Grid item xs={12} sm={6} md={3} key={index}>
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box sx={{ color: card.color }}>{card.icon}</Box>
                  <Box>
                    <Typography variant="h4">{card.value}</Typography>
                    <Typography variant="body2" color="text.secondary">
                      {card.title}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}

        {/* Today's sales (total) */}
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ color: '#2e7d32' }}>
                  <AttachMoneyIcon sx={{ fontSize: 40 }} />
                </Box>
                <Box>
                  <Typography variant="h4">£{todayRevenue.toFixed(2)}</Typography>
                  <Typography variant="body2" color="text.secondary">
                    {t('dashboard.todaySales')}
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Daily sales by store (date on x-axis, sales on y-axis, one line per store) */}
        <Grid item xs={12}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              {t('dashboard.dailySalesByStore')}
            </Typography>
            {loadingByStore ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                <Typography>{t('common.loading')}</Typography>
              </Box>
            ) : dailySalesByStoreChartData.length === 0 ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                <Typography color="text.secondary">{t('dashboard.noRevenueData')}</Typography>
              </Box>
            ) : (
              <ResponsiveContainer width="100%" height={360}>
                <LineChart data={dailySalesByStoreChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis tickFormatter={(v) => `£${v}`} />
                  <Tooltip formatter={(value: number) => [`£${value.toFixed(2)}`, t('dashboard.revenue')]} />
                  <Legend />
                  {revenueByStore.map(({ store }, index) => (
                    <Line
                      key={store.id}
                      type="monotone"
                      dataKey={`s${store.id}`}
                      stroke={storeLineColors[index % storeLineColors.length]}
                      strokeWidth={2}
                      name={store.name}
                      dot={{ r: 3 }}
                      connectNulls
                    />
                  ))}
                </LineChart>
              </ResponsiveContainer>
            )}
          </Paper>
        </Grid>

        {/* Daily Revenue Trend */}
        <Grid item xs={12} md={6}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              {t('dashboard.dailyRevenueTrend')}
            </Typography>
            {loading ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                <Typography>{t('common.loading')}</Typography>
              </Box>
            ) : revenueChartData.length === 0 ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                <Typography color="text.secondary">{t('dashboard.noRevenueData')}</Typography>
              </Box>
            ) : (
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={revenueChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip formatter={(value: number) => `£${value.toFixed(2)}`} />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="revenue"
                    stroke="#1976d2"
                    strokeWidth={2}
                    name={t('dashboard.revenue')}
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
          </Paper>
        </Grid>

        {/* Daily Product Sales Trend */}
        <Grid item xs={12} md={6}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              {t('dashboard.dailyProductSalesTrend')}
            </Typography>
            {loading ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                <Typography>{t('common.loading')}</Typography>
              </Box>
            ) : productSalesChartData.length === 0 ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                <Typography color="text.secondary">{t('dashboard.noSalesData')}</Typography>
              </Box>
            ) : (
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={productSalesChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  {top5Products.map((productName, index) => (
                    <Bar
                      key={productName}
                      dataKey={productName}
                      fill={colors[index % colors.length]}
                      name={productName.length > 20 ? `${productName.substring(0, 20)}...` : productName}
                    />
                  ))}
                </BarChart>
              </ResponsiveContainer>
            )}
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
}

