import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme, CssBaseline } from '@mui/material';
import { alpha } from '@mui/material/styles';
import { SnackbarProvider } from 'notistack';
import { AuthProvider, useAuth } from './context/AuthContext';
import LoginPage from './pages/LoginPage';
import Dashboard from './pages/Dashboard';
import ProductsPage from './pages/ProductsPage';
import ProductDetailPage from './pages/ProductDetailPage';
import SectorsPage from './pages/SectorsPage';
import CategoriesPage from './pages/CategoriesPage';
import StockPage from './pages/StockPage';
import AssignProductToStorePage from './pages/AssignProductToStorePage';
import RestockOrdersPage from './pages/RestockOrdersPage';
import UsersPage from './pages/UsersPage';
import StoresPage from './pages/StoresPage';
import StoreDetailPage from './pages/StoreDetailPage';
import DevicesPage from './pages/DevicesPage';
import CatalogPage from './pages/CatalogPage';
import CurrencyRatesPage from './pages/CurrencyRatesPage';
import OrdersPage from './pages/OrdersPage';
import WholesaleOrdersPage from './pages/WholesaleOrdersPage';
import WholesaleOrderCreatePage from './pages/WholesaleOrderCreatePage';
import WholesaleOrderDetailPage from './pages/WholesaleOrderDetailPage';
import WholesaleOrderAuditLogPage from './pages/WholesaleOrderAuditLogPage';
import WholesaleShipmentsPage from './pages/WholesaleShipmentsPage';
import WholesaleShipmentDetailPage from './pages/WholesaleShipmentDetailPage';
import WholesaleClientsPage from './pages/WholesaleClientsPage';
import WholesaleClientDetailPage from './pages/WholesaleClientDetailPage';
import WholesaleClientFormPage from './pages/WholesaleClientFormPage';
import ProductCostEditorPage from './pages/ProductCostEditorPage';
import ProductCostEditorV2Page from './pages/ProductCostEditorV2Page';
import UserProfilePage from './pages/UserProfilePage';
import StocktakeTimetablePage from './pages/StocktakeTimetablePage';
import TimetablePage from './pages/TimetablePage';
import StockReportPage from './pages/StockReportPage';
import ReportsPage from './pages/ReportsPage';
import CompanySettingsPage from './pages/CompanySettingsPage';
import AiPlaybookPage from './pages/AiPlaybookPage';
import ProductBarcodeReferencePage from './pages/ProductBarcodeReferencePage';
import ProductLinesPage from './pages/ProductLinesPage';
import ProductLineDetailPage from './pages/ProductLineDetailPage';
import Layout from './components/Layout';

const theme = createTheme({
  palette: {
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
  },
  components: {
    MuiTableContainer: {
      styleOverrides: {
        root: ({ theme }) => ({
          overflowX: 'auto',
          WebkitOverflowScrolling: 'touch',
          border: `1px solid ${theme.palette.divider}`,
          borderRadius: Number(theme.shape.borderRadius),
          backgroundColor: theme.palette.background.paper,
        }),
      },
    },
    MuiTable: {
      styleOverrides: {
        root: {
          borderCollapse: 'collapse',
        },
      },
    },
    MuiTableCell: {
      styleOverrides: {
        root: ({ theme }) => ({
          borderColor: alpha(theme.palette.text.primary, 0.14),
          padding: '12px 16px',
        }),
        head: ({ theme }) => ({
          fontWeight: 800,
          fontSize: '0.8125rem',
          lineHeight: 1.35,
          letterSpacing: '0.045em',
          textTransform: 'uppercase',
          color: theme.palette.text.primary,
          backgroundColor:
            theme.palette.mode === 'light' ? theme.palette.grey[200] : alpha(theme.palette.common.white, 0.1),
          borderBottom: `3px solid ${theme.palette.primary.main}`,
          verticalAlign: 'bottom',
        }),
        body: ({ theme }) => ({
          fontSize: '0.9375rem',
          lineHeight: 1.5,
          fontWeight: 500,
          color: theme.palette.text.primary,
        }),
        footer: ({ theme }) => ({
          fontWeight: 700,
          fontSize: '0.9375rem',
          borderTop: `2px solid ${theme.palette.divider}`,
          backgroundColor:
            theme.palette.mode === 'light' ? theme.palette.grey[100] : alpha(theme.palette.common.white, 0.06),
        }),
        sizeSmall: {
          padding: '10px 14px',
        },
      },
    },
    MuiTableBody: {
      styleOverrides: {
        root: ({ theme }) => ({
          // Stripe / hover must not override MUI-selected (e.g. checkbox-selected wholesale rows).
          '& .MuiTableRow-root:nth-of-type(even):not(.Mui-selected)': {
            backgroundColor:
              theme.palette.mode === 'light'
                ? alpha(theme.palette.primary.main, 0.04)
                : alpha(theme.palette.common.white, 0.05),
          },
          '& .MuiTableRow-root:hover:not(.Mui-selected)': {
            backgroundColor: alpha(theme.palette.primary.main, 0.1),
          },
        }),
      },
    },
    MuiTableRow: {
      styleOverrides: {
        root: ({ theme }) => ({
          transition: 'background-color 0.12s ease',
          '&.Mui-selected': {
            backgroundColor:
              theme.palette.mode === 'light'
                ? alpha(theme.palette.primary.main, 0.2)
                : alpha(theme.palette.primary.main, 0.3),
            boxShadow: `inset 4px 0 0 ${theme.palette.primary.main}`,
            '&:hover': {
              backgroundColor:
                theme.palette.mode === 'light'
                  ? alpha(theme.palette.primary.main, 0.26)
                  : alpha(theme.palette.primary.main, 0.38),
            },
          },
        }),
      },
    },
    MuiListItemButton: {
      styleOverrides: {
        root: {
          '@media (pointer: coarse)': {
            minHeight: 48,
          },
        },
      },
    },
  },
});

const ProtectedRoute = ({ children }: { children: React.ReactNode }) => {
  const { isAuthenticated, loading } = useAuth();

  if (loading) {
    return <div>Loading...</div>;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
};

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Layout />
          </ProtectedRoute>
        }
      >
        <Route index element={<Dashboard />} />
        <Route path="products" element={<ProductsPage />} />
        <Route path="product-lines" element={<ProductLinesPage />} />
        <Route path="product-lines/:id" element={<ProductLineDetailPage />} />
        <Route path="product-barcode-reference" element={<ProductBarcodeReferencePage />} />
        <Route path="products/:id" element={<ProductDetailPage />} />
        <Route path="product-cost-editor" element={<ProductCostEditorPage />} />
        <Route path="product-cost-editor-v2" element={<ProductCostEditorV2Page />} />
        <Route path="sectors" element={<SectorsPage />} />
        <Route path="categories" element={<CategoriesPage />} />
        <Route path="stock" element={<StockPage />} />
        <Route path="assign-product-to-store" element={<AssignProductToStorePage />} />
        <Route path="restock-orders" element={<RestockOrdersPage />} />
        <Route path="users" element={<UsersPage />} />
        <Route path="stores" element={<StoresPage />} />
        <Route path="stores/:id" element={<StoreDetailPage />} />
        <Route path="devices" element={<DevicesPage />} />
        <Route path="orders" element={<OrdersPage />} />
        <Route path="wholesale-orders" element={<WholesaleOrdersPage />} />
        <Route path="wholesale-orders/new" element={<WholesaleOrderCreatePage />} />
        <Route path="wholesale-orders/:id" element={<WholesaleOrderDetailPage />} />
        <Route path="wholesale-orders/:id/audit-log" element={<WholesaleOrderAuditLogPage />} />
        <Route path="wholesale-shipments" element={<WholesaleShipmentsPage />} />
        <Route path="wholesale-shipments/:id" element={<WholesaleShipmentDetailPage />} />
        <Route path="wholesale-clients" element={<WholesaleClientsPage />} />
        <Route path="wholesale-clients/new" element={<WholesaleClientFormPage />} />
        <Route path="wholesale-clients/:id" element={<WholesaleClientDetailPage />} />
        <Route path="wholesale-clients/:id/edit" element={<WholesaleClientFormPage />} />
        <Route path="catalogs" element={<CatalogPage />} />
        <Route path="currency-rates" element={<CurrencyRatesPage />} />
        <Route path="company-settings" element={<CompanySettingsPage />} />
        <Route path="internal-ai-playbook" element={<AiPlaybookPage />} />
        <Route path="stocktake" element={<StocktakeTimetablePage />} />
        <Route path="stock-report" element={<StockReportPage />} />
        <Route path="timetable" element={<TimetablePage />} />
        <Route path="reports" element={<ReportsPage />} />
        <Route path="profile" element={<UserProfilePage />} />
      </Route>
    </Routes>
  );
}

function App() {
  console.log('App component rendering...');
  
  // Add error boundary
  React.useEffect(() => {
    console.log('App component mounted');
  }, []);
  
  try {
    return (
      <ThemeProvider theme={theme}>
        <CssBaseline />
        <SnackbarProvider maxSnack={3}>
          <AuthProvider>
            <BrowserRouter>
              <AppRoutes />
            </BrowserRouter>
          </AuthProvider>
        </SnackbarProvider>
      </ThemeProvider>
    );
  } catch (error) {
    console.error('Error in App component:', error);
    return (
      <div style={{ padding: '20px', color: 'red' }}>
        Error in App: {String(error)}
      </div>
    );
  }
}

export default App;

