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
  IconButton,
  useMediaQuery,
} from '@mui/material';
import { useTheme } from '@mui/material/styles';
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
  QrCode2 as BarcodeReferenceIcon,
  SmartToy as SmartToyIcon,
  Menu as MenuIcon,
} from '@mui/icons-material';
import Collapse from '@mui/material/Collapse';
import { useAuth } from '../context/AuthContext';
import { useEffect, useState } from 'react';
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
  const theme = useTheme();
  const isDesktop = useMediaQuery(theme.breakpoints.up('md'));
  const navigate = useNavigate();
  const location = useLocation();
  const { user, logout } = useAuth();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({});
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  useEffect(() => {
    setMobileNavOpen(false);
  }, [location.pathname]);

  const closeMobileNav = () => {
    if (!isDesktop) setMobileNavOpen(false);
  };

  const menuStructure: MenuItem[] = [
    { text: t('layout.menuHome'), icon: <DashboardIcon />, path: '/' },
    { text: t('layout.report'), icon: <TableChartIcon />, path: '/reports' },
    {
      text: t('layout.menuProducts'),
      icon: <MenuBookIcon />,
      children: [
        { text: t('layout.products'), icon: <InventoryIcon />, path: '/products' },
        { text: t('layout.productLines'), icon: <MenuBookIcon />, path: '/product-lines' },
        { text: t('layout.productBarcodeReference'), icon: <BarcodeReferenceIcon />, path: '/product-barcode-reference' },
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
        { text: t('layout.stocktake'), icon: <AssignmentIcon />, path: '/stocktake' },
        { text: t('layout.timetable'), icon: <EventIcon />, path: '/timetable' },
      ],
    },
    { text: t('layout.menuPos'), icon: <ShoppingCartIcon />, path: '/orders' },
    {
      text: t('layout.menuWholesale'),
      icon: <LocalShippingIcon />,
      children: [
        { text: t('layout.wholesaleOrders'), icon: <ShoppingCartIcon />, path: '/wholesale-orders' },
        { text: t('layout.wholesaleShipments'), icon: <LocalShippingIcon />, path: '/wholesale-shipments' },
        { text: t('layout.wholesaleClients'), icon: <PeopleIcon />, path: '/wholesale-clients' },
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
        { text: t('layout.internalAiPlaybook'), icon: <SmartToyIcon />, path: '/internal-ai-playbook' },
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

  const drawerScrollArea = (
    <Box sx={{ overflow: 'auto', flex: 1, minHeight: 0 }}>
      <List disablePadding>
        {menuStructure.map((item, index) => {
          const key = isGroup(item) ? `group-${index}-${item.text}` : `leaf-${item.path}`;
          const isOpen =
            openGroups[key] ??
            (isGroup(item) &&
              item.children.some(
                (c) => location.pathname === c.path || location.pathname.startsWith(`${c.path}/`)
              ));
          if (isGroup(item)) {
            return (
              <Box key={key}>
                <ListItem disablePadding>
                  <ListItemButton onClick={() => toggleGroup(key)} sx={{ py: { xs: 1, md: 0.75 } }}>
                    <ListItemIcon sx={{ minWidth: 40 }}>{item.icon}</ListItemIcon>
                    <ListItemText
                      primary={item.text}
                      primaryTypographyProps={{ variant: 'body2', fontWeight: 500 }}
                    />
                    {isOpen ? <ExpandLessIcon /> : <ExpandMoreIcon />}
                  </ListItemButton>
                </ListItem>
                <Collapse in={isOpen} timeout="auto" unmountOnExit>
                  <List component="div" disablePadding sx={{ pl: 2, ml: 2.5 }}>
                    {item.children.map((child) => (
                      <ListItem key={child.path} disablePadding>
                        <ListItemButton
                          selected={
                            location.pathname === child.path ||
                            location.pathname.startsWith(`${child.path}/`)
                          }
                          onClick={() => {
                            navigate(child.path);
                            closeMobileNav();
                          }}
                          sx={{ py: { xs: 0.75, md: 0.5 }, minHeight: { xs: 48, md: 36 } }}
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
                onClick={() => {
                  navigate(item.path);
                  closeMobileNav();
                }}
                sx={{ py: { xs: 1, md: 0.75 } }}
              >
                <ListItemIcon sx={{ minWidth: 40 }}>{item.icon}</ListItemIcon>
                <ListItemText primary={item.text} primaryTypographyProps={{ variant: 'body2' }} />
              </ListItemButton>
            </ListItem>
          );
        })}
      </List>
    </Box>
  );

  const drawerPaperSx = {
    width: { xs: 'min(100%, 300px)', md: drawerWidth },
    maxWidth: '100vw',
    boxSizing: 'border-box' as const,
  };

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        height: '100dvh',
        overflow: 'hidden',
        minHeight: 0,
      }}
    >
      <AppBar
        position="fixed"
        sx={{
          zIndex: (zTheme) => zTheme.zIndex.drawer + 1,
          pt: 'env(safe-area-inset-top, 0px)',
        }}
      >
        <Toolbar
          sx={{
            minHeight: { xs: 56, sm: 64 },
            pr: { xs: 1, sm: 2 },
          }}
        >
          <IconButton
            color="inherit"
            aria-label={t('layout.openMenu')}
            edge="start"
            onClick={() => setMobileNavOpen(true)}
            sx={{ mr: 1, display: { md: 'none' } }}
          >
            <MenuIcon />
          </IconButton>
          <Box
            component="img"
            src="/logo.png"
            alt="Logo"
            sx={{
              height: { xs: 28, sm: 32 },
              width: 'auto',
              objectFit: 'contain',
              mr: { xs: 1, sm: 1.5 },
              flexShrink: 0,
            }}
          />
          <Typography
            variant="h6"
            noWrap
            component="div"
            sx={{
              flexGrow: 1,
              fontSize: { xs: '1rem', sm: undefined },
              minWidth: 0,
            }}
          >
            {t('layout.title')}
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: { xs: 0.5, sm: 1 }, flexShrink: 0 }}>
            <LanguageSelector />
            <Typography
              variant="body2"
              noWrap
              sx={{
                display: { xs: 'none', sm: 'block' },
                maxWidth: { sm: 120, md: 200 },
              }}
            >
              {user?.first_name} {user?.last_name}
            </Typography>
            <Avatar
              src={user?.icon_url || undefined}
              sx={{
                bgcolor: user?.icon_bg_color || 'primary.main',
                color: user?.icon_text_color || '#fff',
                cursor: 'pointer',
                width: { xs: 36, sm: 34 },
                height: { xs: 36, sm: 34 },
                fontSize: '0.85rem',
              }}
              onClick={handleMenuOpen}
            >
              {!user?.icon_url && getInitials()}
            </Avatar>
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose}>
              <MenuItem
                onClick={() => {
                  navigate('/profile');
                  handleMenuClose();
                }}
              >
                <ListItemIcon>
                  <PersonIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText
                  primary={t('layout.profile')}
                  secondary={
                    !isDesktop && user
                      ? `${user.first_name} ${user.last_name}`.trim()
                      : undefined
                  }
                />
              </MenuItem>
              <Divider />
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

      <Box
        sx={{
          display: 'flex',
          flex: 1,
          minHeight: 0,
          minWidth: 0,
          overflow: 'hidden',
        }}
      >
        {isDesktop && (
          <Drawer
            variant="permanent"
            sx={{
              width: drawerWidth,
              flexShrink: 0,
              '& .MuiDrawer-paper': {
                ...drawerPaperSx,
                borderRight: 1,
                borderColor: 'divider',
              },
            }}
            open
          >
            <Toolbar />
            {drawerScrollArea}
          </Drawer>
        )}

        <Box
          component="main"
          sx={{
            flexGrow: 1,
            minWidth: 0,
            minHeight: 0,
            overflow: 'auto',
            WebkitOverflowScrolling: 'touch',
            bgcolor: 'background.default',
            p: { xs: 1.5, sm: 2, md: 3 },
            pb: { xs: `calc(12px + env(safe-area-inset-bottom, 0px))`, sm: 2, md: 3 },
          }}
        >
          <Toolbar />
          <Outlet />
        </Box>
      </Box>

      {!isDesktop && (
        <Drawer
          variant="temporary"
          open={mobileNavOpen}
          onClose={() => setMobileNavOpen(false)}
          ModalProps={{ keepMounted: true }}
          sx={{
            display: { md: 'none' },
            '& .MuiDrawer-paper': {
              ...drawerPaperSx,
              pt: 'env(safe-area-inset-top, 0px)',
              pb: 'env(safe-area-inset-bottom, 0px)',
              height: '100%',
              display: 'flex',
              flexDirection: 'column',
            },
          }}
        >
          <Toolbar />
          {drawerScrollArea}
        </Drawer>
      )}
    </Box>
  );
}
