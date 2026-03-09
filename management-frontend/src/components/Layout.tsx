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
  ExpandLess as ExpandLessIcon,
  ExpandMore as ExpandMoreIcon,
  Business as BusinessIcon,
  TableChart as TableChartIcon,
} from '@mui/icons-material';
import Collapse from '@mui/material/Collapse';
import { useAuth } from '../context/AuthContext';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import LanguageSelector from './LanguageSelector';

const drawerWidth = 260;

type MenuItemLeaf = { text: string; icon: React.ReactNode; path: string };
type MenuItemGroup = { text: string; icon: React.ReactNode; children: MenuItemLeaf[] };
type MenuItem = MenuItemLeaf | MenuItemGroup;

function isGroup(item: MenuItem): item is MenuItemGroup {
  return 'children' in item && Array.isArray((item as MenuItemGroup).children);
}

export default function Layout() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const { user, logout } = useAuth();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({});

  const menuStructure: MenuItem[] = [
    { text: t('layout.dashboard'), icon: <DashboardIcon />, path: '/' },
    {
      text: t('layout.menuCatalog'),
      icon: <MenuBookIcon />,
      children: [
        { text: t('layout.products'), icon: <InventoryIcon />, path: '/products' },
        { text: t('layout.categories'), icon: <LabelIcon />, path: '/categories' },
        { text: t('layout.sectors'), icon: <CategoryIcon />, path: '/sectors' },
        { text: t('layout.catalogs'), icon: <MenuBookIcon />, path: '/catalogs' },
        { text: 'Cost Editor', icon: <TableChartIcon />, path: '/product-cost-editor' },
        { text: 'Cost Editor v2', icon: <TableChartIcon />, path: '/product-cost-editor-v2' },
      ],
    },
    {
      text: t('layout.menuInventory'),
      icon: <WarehouseIcon />,
      children: [
        { text: t('layout.stock'), icon: <WarehouseIcon />, path: '/stock' },
        { text: t('layout.assignProductToStore'), icon: <StoreIcon />, path: '/assign-product-to-store' },
        { text: t('layout.shipment'), icon: <LocalShippingIcon />, path: '/restock-orders' },
        { text: t('layout.stockReport'), icon: <AssessmentIcon />, path: '/stock-report' },
      ],
    },
    {
      text: t('layout.menuStocktakeReports'),
      icon: <AssignmentIcon />,
      children: [
        { text: t('layout.stocktake'), icon: <AssignmentIcon />, path: '/stocktake' },
        { text: t('layout.timetable'), icon: <EventIcon />, path: '/timetable' },
      ],
    },
    {
      text: t('layout.menuOrders'),
      icon: <ShoppingCartIcon />,
      children: [
        { text: t('layout.orders'), icon: <ShoppingCartIcon />, path: '/orders' },
        { text: t('layout.wholesaleOrders'), icon: <ShoppingCartIcon />, path: '/wholesale-orders' },
        { text: t('layout.wholesaleClients'), icon: <ShoppingCartIcon />, path: '/wholesale-clients' },
      ],
    },
    {
      text: t('layout.menuSettings'),
      icon: <StoreIcon />,
      children: [
        { text: t('layout.users'), icon: <PeopleIcon />, path: '/users' },
        { text: t('layout.stores'), icon: <StoreIcon />, path: '/stores' },
        { text: t('layout.devices'), icon: <DevicesIcon />, path: '/devices' },
        { text: t('layout.currencyRates'), icon: <CurrencyExchangeIcon />, path: '/currency-rates' },
        { text: t('layout.companySettings'), icon: <BusinessIcon />, path: '/company-settings' },
      ],
    },
  ];

  const toggleGroup = (key: string) => {
    setOpenGroups((prev) => ({ ...prev, [key]: !prev[key] }));
  };

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
          <Box
            component="img"
            src="/logo.png"
            alt="Logo"
            sx={{ height: 32, width: 'auto', objectFit: 'contain', mr: 1.5 }}
          />
          <Typography variant="h6" noWrap component="div" sx={{ flexGrow: 1 }}>
            {t('layout.title')}
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <LanguageSelector />
            <Typography variant="body2">{user?.first_name} {user?.last_name}</Typography>
            <Avatar
              src={user?.icon_url || undefined}
              sx={{
                bgcolor: user?.icon_bg_color || 'primary.main',
                color: user?.icon_text_color || '#fff',
                cursor: 'pointer',
                width: 34,
                height: 34,
                fontSize: '0.85rem',
              }}
              onClick={handleMenuOpen}
            >
              {!user?.icon_url && getInitials()}
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
          <List disablePadding>
            {menuStructure.map((item, index) => {
              const key = isGroup(item) ? `group-${index}-${item.text}` : `leaf-${item.path}`;
              const isOpen = openGroups[key] ?? (isGroup(item) && item.children.some((c) => location.pathname === c.path || location.pathname.startsWith(c.path + '/')));
              if (isGroup(item)) {
                return (
                  <Box key={key}>
                    <ListItem disablePadding>
                      <ListItemButton
                        onClick={() => toggleGroup(key)}
                        sx={{ py: 0.75 }}
                      >
                        <ListItemIcon sx={{ minWidth: 40 }}>{item.icon}</ListItemIcon>
                        <ListItemText primary={item.text} primaryTypographyProps={{ variant: 'body2', fontWeight: 500 }} />
                        {isOpen ? <ExpandLessIcon /> : <ExpandMoreIcon />}
                      </ListItemButton>
                    </ListItem>
                    <Collapse in={isOpen} timeout="auto" unmountOnExit>
                      <List component="div" disablePadding sx={{ pl: 2, borderLeft: 1, borderColor: 'divider', ml: 2.5 }}>
                        {item.children.map((child) => (
                          <ListItem key={child.path} disablePadding>
                            <ListItemButton
                              selected={location.pathname === child.path || location.pathname.startsWith(child.path + '/')}
                              onClick={() => navigate(child.path)}
                              sx={{ py: 0.5, minHeight: 36 }}
                            >
                              <ListItemIcon sx={{ minWidth: 36 }}>{child.icon}</ListItemIcon>
                              <ListItemText primary={child.text} primaryTypographyProps={{ variant: 'body2' }} />
                            </ListItemButton>
                          </ListItem>
                        ))}
                      </List>
                    </Collapse>
                  </Box>
                );
              }
              return (
                <ListItem key={key} disablePadding>
                  <ListItemButton
                    selected={location.pathname === item.path}
                    onClick={() => navigate(item.path)}
                    sx={{ py: 0.75 }}
                  >
                    <ListItemIcon sx={{ minWidth: 40 }}>{item.icon}</ListItemIcon>
                    <ListItemText primary={item.text} primaryTypographyProps={{ variant: 'body2' }} />
                  </ListItemButton>
                </ListItem>
              );
            })}
          </List>
        </Box>
      </Drawer>
      <Box
        component="main"
        sx={{
          flexGrow: 1,
          minWidth: 0,
          overflow: 'hidden',
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

