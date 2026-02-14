import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import {
  Box,
  Drawer,
  AppBar,
  Toolbar,
  List,
  Typography,
  Divider,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Avatar,
  Menu,
  MenuItem,
} from '@mui/material';
import {
  Dashboard as DashboardIcon,
  Inventory as InventoryIcon,
  Category as CategoryIcon,
  Label as LabelIcon,
  Warehouse as WarehouseIcon,
  LocalShipping as LocalShippingIcon,
  People as PeopleIcon,
  Store as StoreIcon,
  PhoneAndroid as DevicesIcon,
  ShoppingCart as ShoppingCartIcon,
  MenuBook as MenuBookIcon,
  CurrencyExchange as CurrencyExchangeIcon,
  Assignment as AssignmentIcon,
  Event as EventIcon,
  Assessment as AssessmentIcon,
  Person as PersonIcon,
  Logout as LogoutIcon,
} from '@mui/icons-material';
import { useAuth } from '../context/AuthContext';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import LanguageSelector from './LanguageSelector';

const drawerWidth = 240;

export default function Layout() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const { user, logout } = useAuth();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);

  const menuItems = [
    { text: t('layout.dashboard'), icon: <DashboardIcon />, path: '/' },
    { text: t('layout.products'), icon: <InventoryIcon />, path: '/products' },
    { text: t('layout.categories'), icon: <LabelIcon />, path: '/categories' },
    { text: t('layout.sectors'), icon: <CategoryIcon />, path: '/sectors' },
    { text: t('layout.stock'), icon: <WarehouseIcon />, path: '/stock' },
    { text: t('layout.shipment'), icon: <LocalShippingIcon />, path: '/restock-orders' },
    { text: t('layout.users'), icon: <PeopleIcon />, path: '/users' },
    { text: t('layout.stores'), icon: <StoreIcon />, path: '/stores' },
    { text: t('layout.devices'), icon: <DevicesIcon />, path: '/devices' },
    { text: t('layout.orders'), icon: <ShoppingCartIcon />, path: '/orders' },
    { text: t('layout.catalogs'), icon: <MenuBookIcon />, path: '/catalogs' },
    { text: t('layout.currencyRates'), icon: <CurrencyExchangeIcon />, path: '/currency-rates' },
    { text: t('layout.stocktake'), icon: <AssignmentIcon />, path: '/stocktake' },
    { text: t('layout.stockReport'), icon: <AssessmentIcon />, path: '/stock-report' },
    { text: t('layout.timetable'), icon: <EventIcon />, path: '/timetable' },
  ];

  const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
    setAnchorEl(event.currentTarget);
  };

  const handleMenuClose = () => {
    setAnchorEl(null);
  };

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const getInitials = () => {
    if (user) {
      return `${user.first_name[0]}${user.last_name[0]}`.toUpperCase();
    }
    return 'U';
  };

  return (
    <Box sx={{ display: 'flex' }}>
      <AppBar
        position="fixed"
        sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }}
      >
        <Toolbar>
          <Typography variant="h6" noWrap component="div" sx={{ flexGrow: 1 }}>
            {t('layout.title')}
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <LanguageSelector />
            <Typography variant="body2">{user?.first_name} {user?.last_name}</Typography>
            <Avatar
              sx={{
                bgcolor: user?.icon_color || 'primary.main',
                cursor: 'pointer',
              }}
              onClick={handleMenuOpen}
            >
              {getInitials()}
            </Avatar>
            <Menu
              anchorEl={anchorEl}
              open={Boolean(anchorEl)}
              onClose={handleMenuClose}
            >
              <MenuItem onClick={() => { navigate('/profile'); handleMenuClose(); }}>
                <ListItemIcon>
                  <PersonIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>{t('layout.profile')}</ListItemText>
              </MenuItem>
              <MenuItem onClick={handleLogout}>
                <ListItemIcon>
                  <LogoutIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>{t('layout.logout')}</ListItemText>
              </MenuItem>
            </Menu>
          </Box>
        </Toolbar>
      </AppBar>
      <Drawer
        variant="permanent"
        sx={{
          width: drawerWidth,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: drawerWidth,
            boxSizing: 'border-box',
          },
        }}
      >
        <Toolbar />
        <Box sx={{ overflow: 'auto' }}>
          <List>
            {menuItems.map((item) => (
              <ListItem key={item.path} disablePadding>
                <ListItemButton
                  selected={location.pathname === item.path}
                  onClick={() => navigate(item.path)}
                >
                  <ListItemIcon>{item.icon}</ListItemIcon>
                  <ListItemText primary={item.text} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Box>
      </Drawer>
      <Box
        component="main"
        sx={{
          flexGrow: 1,
          bgcolor: 'background.default',
          p: 3,
          minHeight: '100vh',
        }}
      >
        <Toolbar />
        <Outlet />
      </Box>
    </Box>
  );
}

