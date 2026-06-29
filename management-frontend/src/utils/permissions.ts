import type { User } from '../types';

export type UserRole = User['role'];

const POS_USER_ALLOWED_PREFIXES = [
  '/',
  '/orders',
  '/product-lines',
  '/product-barcode-reference',
  '/wholesale-orders',
  '/wholesale-shipments',
  '/profile',
  '/work-settings',
];

const COST_EDITOR_PATHS = ['/product-cost-editor', '/product-cost-editor-v2'];

export function isPosUser(role: string | undefined): boolean {
  return role === 'pos_user';
}

export function isHQStaff(role: string | undefined): boolean {
  return role === 'hq_staff';
}

export function canAccessCostEditor(role: string | undefined): boolean {
  return !!role && role !== 'hq_staff';
}

export function canDeleteProduct(role: string | undefined): boolean {
  return !!role && role !== 'hq_staff';
}

export function canEditProductCost(role: string | undefined): boolean {
  return canAccessCostEditor(role);
}

export function isPathAllowedForRole(pathname: string, role: string | undefined): boolean {
  if (!role || role !== 'pos_user') return true;
  if (pathname === '/' || pathname === '') return true;
  return POS_USER_ALLOWED_PREFIXES.some(
    (prefix) => prefix !== '/' && (pathname === prefix || pathname.startsWith(`${prefix}/`)),
  );
}

export function canViewDashboardSalesAndCharts(role: string | undefined): boolean {
  return !isPosUser(role);
}

export function defaultPathForRole(role: string | undefined): string {
  return '/';
}

export function isCostEditorPath(pathname: string): boolean {
  return COST_EDITOR_PATHS.some(
    (path) => pathname === path || pathname.startsWith(`${path}/`),
  );
}

export function canManageUserWorkAssignments(role: string | undefined): boolean {
  return role === 'management' || role === 'supervisor';
}

export function shouldHideCostEditorMenu(role: string | undefined): boolean {
  return !canAccessCostEditor(role);
}
