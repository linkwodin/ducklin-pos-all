import { Box, CircularProgress } from '@mui/material';
import { Navigate, Outlet } from 'react-router-dom';
import { useWholesaleOrderEnabled } from '../hooks/useWholesaleOrderEnabled';

export default function WholesaleEnabledGuard() {
  const { enabled, loaded } = useWholesaleOrderEnabled();

  if (!loaded) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: 240 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!enabled) {
    return <Navigate to="/company-settings#wholesale-order" replace />;
  }

  return <Outlet />;
}
