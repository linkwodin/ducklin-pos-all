import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme, CssBaseline } from '@mui/material';
import { SnackbarProvider } from 'notistack';
import { AuthProvider, useAuth } from './context/AuthContext';
import LoginPage from './pages/LoginPage';
import Dashboard from './pages/Dashboard';
import ProductsPage from './pages/ProductsPage';
import ProductDetailPage from './pages/ProductDetailPage';
import SectorsPage from './pages/SectorsPage';
import CategoriesPage from './pages/CategoriesPage';
import StockPage from './pages/StockPage';
import RestockOrdersPage from './pages/RestockOrdersPage';
import UsersPage from './pages/UsersPage';
import StoresPage from './pages/StoresPage';
import DevicesPage from './pages/DevicesPage';
import CatalogPage from './pages/CatalogPage';
import CurrencyRatesPage from './pages/CurrencyRatesPage';
import OrdersPage from './pages/OrdersPage';
import ProductCostEditorPage from './pages/ProductCostEditorPage';
import UserProfilePage from './pages/UserProfilePage';
import StocktakeTimetablePage from './pages/StocktakeTimetablePage';
import TimetablePage from './pages/TimetablePage';
import StockReportPage from './pages/StockReportPage';
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
        <Route path="products/:id" element={<ProductDetailPage />} />
        <Route path="product-cost-editor" element={<ProductCostEditorPage />} />
        <Route path="sectors" element={<SectorsPage />} />
        <Route path="categories" element={<CategoriesPage />} />
        <Route path="stock" element={<StockPage />} />
        <Route path="restock-orders" element={<RestockOrdersPage />} />
        <Route path="users" element={<UsersPage />} />
        <Route path="stores" element={<StoresPage />} />
        <Route path="devices" element={<DevicesPage />} />
        <Route path="orders" element={<OrdersPage />} />
        <Route path="catalogs" element={<CatalogPage />} />
        <Route path="currency-rates" element={<CurrencyRatesPage />} />
        <Route path="stocktake" element={<StocktakeTimetablePage />} />
        <Route path="stock-report" element={<StockReportPage />} />
        <Route path="timetable" element={<TimetablePage />} />
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

