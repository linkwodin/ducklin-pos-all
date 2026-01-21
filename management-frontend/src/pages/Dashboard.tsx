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
import { productsAPI, stockAPI, restockAPI, usersAPI } from '../services/api';

export default function Dashboard() {
  const [stats, setStats] = useState({
    totalProducts: 0,
    lowStockItems: 0,
    pendingRestocks: 0,
    totalUsers: 0,
  });

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const [products, lowStock, restocks, users] = await Promise.all([
          productsAPI.list(),
          stockAPI.getLowStock(),
          restockAPI.list(undefined, 'initiated'),
          usersAPI.list(),
        ]);

        setStats({
          totalProducts: products.length,
          lowStockItems: lowStock.length,
          pendingRestocks: restocks.length,
          totalUsers: users.length,
        });
      } catch (error) {
        console.error('Failed to fetch stats:', error);
      }
    };

    fetchStats();
  }, []);

  const statCards = [
    {
      title: 'Total Products',
      value: stats.totalProducts,
      icon: <InventoryIcon sx={{ fontSize: 40 }} />,
      color: '#1976d2',
    },
    {
      title: 'Low Stock Items',
      value: stats.lowStockItems,
      icon: <WarningIcon sx={{ fontSize: 40 }} />,
      color: '#d32f2f',
    },
    {
      title: 'Pending Shipments',
      value: stats.pendingRestocks,
      icon: <LocalShippingIcon sx={{ fontSize: 40 }} />,
      color: '#ed6c02',
    },
    {
      title: 'Total Users',
      value: stats.totalUsers,
      icon: <PeopleIcon sx={{ fontSize: 40 }} />,
      color: '#2e7d32',
    },
  ];

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        Dashboard
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
      </Grid>
    </Box>
  );
}

