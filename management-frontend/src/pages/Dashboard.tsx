import { useEffect, useState } from 'react';
import {
  Grid,
  Paper,
  Typography,
  Box,
  Card,
  CardContent,
} from '@mui/material';
import {
  Inventory as InventoryIcon,
  Warning as WarningIcon,
  LocalShipping as LocalShippingIcon,
  People as PeopleIcon,
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
import { productsAPI, stockAPI, restockAPI, usersAPI, ordersAPI } from '../services/api';
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

export default function Dashboard() {
  const { t } = useTranslation();
  const [stats, setStats] = useState({
    totalProducts: 0,
    lowStockItems: 0,
    pendingRestocks: 0,
    totalUsers: 0,
  });
  const [revenueStats, setRevenueStats] = useState<RevenueStat[]>([]);
  const [productSalesStats, setProductSalesStats] = useState<ProductSalesStat[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        setLoading(true);
        const [products, lowStock, restocks, users, revenue, productSales] = await Promise.all([
          productsAPI.list(),
          stockAPI.getLowStock(),
          restockAPI.list(undefined, 'initiated'),
          usersAPI.list(),
          ordersAPI.getDailyRevenueStats({ days: 30 }),
          ordersAPI.getDailyProductSalesStats({ days: 30 }),
        ]);

        setStats({
          totalProducts: products.length,
          lowStockItems: lowStock.length,
          pendingRestocks: restocks.length,
          totalUsers: users.length,
        });
        setRevenueStats(revenue);
        setProductSalesStats(productSales);
      } catch (error) {
        console.error('Failed to fetch stats:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchStats();
  }, []);

  // Aggregate product sales by date and product
  const productSalesByDate = productSalesStats.reduce((acc, stat) => {
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
  const productTotals = productSalesStats.reduce((acc, stat) => {
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
  const revenueChartData = revenueStats.map(stat => ({
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

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        {t('dashboard.title')}
      </Typography>
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

