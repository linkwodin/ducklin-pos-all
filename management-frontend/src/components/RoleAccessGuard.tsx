import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import Dashboard from '../pages/Dashboard';
import {
  canAccessCostEditor,
  defaultPathForRole,
  isCostEditorPath,
  isPathAllowedForRole,
} from '../utils/permissions';

export default function RoleAccessGuard() {
  const { user } = useAuth();
  const location = useLocation();
  const role = user?.role;

  if (!isPathAllowedForRole(location.pathname, role)) {
    return <Navigate to={defaultPathForRole(role)} replace />;
  }

  if (!canAccessCostEditor(role) && isCostEditorPath(location.pathname)) {
    return <Navigate to={defaultPathForRole(role)} replace />;
  }

  return <Outlet />;
}

export function RoleHomeRedirect() {
  return <Dashboard />;
}
