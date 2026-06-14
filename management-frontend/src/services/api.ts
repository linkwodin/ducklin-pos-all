import axios, { type InternalAxiosRequestConfig } from 'axios';
import { isTokenExpired, tokenExpiresWithin } from '../utils/jwt';
import type {
  User,
  Store,
  POSDevice,
  Sector,
  Product,
  ProductCost,
  ProductSectorDiscount,
  Stock,
  StockReportRow,
  RestockOrder,
  PriceHistory,
  CurrencyRate,
  AuditLog,
  LoginResponse,
  Order,
  StocktakeDayStartRecord,
  UserActivityEvent,
  WholesaleOrder,
  EndorseAllocationPreview,
  WholesaleClient,
  WholesaleClientStore,
  CompanySettings,
  Shipment,
} from '../types';

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api/v1';
const REFRESH_WITHIN_MS = 30 * 60 * 1000;

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

let refreshInFlight: Promise<string | null> | null = null;

function notifyTokenRefreshed(token: string, user?: User) {
  window.dispatchEvent(new CustomEvent('auth:token-refreshed', { detail: { token, user } }));
}

async function refreshAuthToken(): Promise<string | null> {
  if (refreshInFlight) return refreshInFlight;

  refreshInFlight = (async () => {
    const token = localStorage.getItem('token');
    if (!token) return null;
    try {
      const { data } = await axios.post<LoginResponse>(
        `${API_BASE_URL}/auth/refresh`,
        {},
        { headers: { Authorization: `Bearer ${token}` } },
      );
      localStorage.setItem('token', data.token);
      if (data.user) {
        localStorage.setItem('user', JSON.stringify(data.user));
      }
      notifyTokenRefreshed(data.token, data.user);
      return data.token;
    } catch {
      return null;
    } finally {
      refreshInFlight = null;
    }
  })();

  return refreshInFlight;
}

function shouldRefreshForUrl(url?: string): boolean {
  if (!url) return true;
  return !url.includes('/auth/login') && !url.includes('/auth/refresh');
}

// Add token to requests; refresh proactively before expiry while the user is active.
api.interceptors.request.use(async (config) => {
  let token = localStorage.getItem('token');
  if (token && shouldRefreshForUrl(config.url) && tokenExpiresWithin(token, REFRESH_WITHIN_MS)) {
    const refreshed = await refreshAuthToken();
    if (refreshed) token = refreshed;
  }
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  // Don't set Content-Type for FormData — axios must add multipart boundary
  if (config.data instanceof FormData && config.headers) {
    const h = config.headers as Record<string, unknown> & { set?: (k: string, v: unknown) => void; delete?: (k: string) => void };
    if (typeof h.set === 'function') {
      h.set('Content-Type', undefined);
    } else {
      delete h['Content-Type'];
      delete h['content-type'];
    }
  }
  return config;
});

// Handle 401 errors — try refresh once, then redirect to login.
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const config = error.config as (InternalAxiosRequestConfig & { _authRetry?: boolean }) | undefined;
    const isLoginRequest = config?.url?.includes('/auth/login');
    const isRefreshRequest = config?.url?.includes('/auth/refresh');

    if (
      error.response?.status === 401 &&
      config &&
      !isLoginRequest &&
      !isRefreshRequest &&
      !config._authRetry
    ) {
      config._authRetry = true;
      const refreshed = await refreshAuthToken();
      if (refreshed) {
        config.headers.Authorization = `Bearer ${refreshed}`;
        return api.request(config);
      }
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  },
);

// Company settings (for PDF/document header)
export const settingsAPI = {
  getCompany: async (): Promise<CompanySettings> => {
    const { data } = await api.get('/settings/company');
    return data;
  },
  updateCompany: async (body: Partial<CompanySettings>): Promise<CompanySettings> => {
    const { data } = await api.put('/settings/company', body);
    return data;
  },
};

// Auth API
export const authAPI = {
  login: async (username: string, password: string): Promise<LoginResponse> => {
    const { data } = await api.post('/auth/login', { username, password });
    return data;
  },
  refresh: refreshAuthToken,
};

// Product lines API (catalog grouping)
export const productLinesAPI = {
  list: async (category?: string): Promise<import('../types').ProductLine[]> => {
    const { data } = await api.get('/product-lines', { params: { category } });
    return data;
  },
  get: async (id: number): Promise<import('../types').ProductLine> => {
    const { data } = await api.get(`/product-lines/${id}`);
    return data;
  },
  create: async (body: Partial<import('../types').ProductLine>): Promise<import('../types').ProductLine> => {
    const { data } = await api.post('/product-lines', body);
    return data;
  },
  update: async (
    id: number,
    body: Partial<import('../types').ProductLine> | FormData,
  ): Promise<import('../types').ProductLine> => {
    const config = body instanceof FormData ? {} : {};
    const { data } = await api.put(`/product-lines/${id}`, body, config);
    return data;
  },
  delete: async (id: number): Promise<void> => {
    await api.delete(`/product-lines/${id}`);
  },
};

// Products API
export const productsAPI = {
  list: async (category?: string, effectiveFrom?: string, effectiveTo?: string): Promise<Product[]> => {
    const { data } = await api.get('/products', { params: { category, effective_from: effectiveFrom, effective_to: effectiveTo } });
    return data;
  },
  get: async (id: number): Promise<Product> => {
    const { data } = await api.get(`/products/${id}`);
    return data;
  },
  create: async (product: Partial<Product> | FormData): Promise<Product> => {
    // For FormData, let axios set Content-Type automatically (with boundary)
    const config = product instanceof FormData
      ? {}
      : {};
    const { data } = await api.post('/products', product, config);
    return data;
  },
  update: async (id: number, product: Partial<Product> | FormData): Promise<Product> => {
    // For FormData, let axios set Content-Type automatically (with boundary)
    const config = product instanceof FormData
      ? {}
      : {};
    const { data } = await api.put(`/products/${id}`, product, config);
    return data;
  },
  delete: async (id: number): Promise<void> => {
    await api.delete(`/products/${id}`);
  },
  setCost: async (id: number, cost: Partial<ProductCost>): Promise<ProductCost> => {
    const { data } = await api.post(`/products/${id}/cost`, cost);
    return data;
  },
  updateCostSimple: async (id: number, cost: {
    wholesale_cost_gbp?: number;
    direct_retail_online_store_price_gbp?: number;
    effective_from?: string;
    effective_to?: string;
  }): Promise<ProductCost> => {
    const { data } = await api.put(`/products/${id}/cost`, cost);
    return data;
  },
  getPriceHistory: async (id: number, sectorId?: number): Promise<PriceHistory[]> => {
    const { data } = await api.get(`/products/${id}/price-history`, {
      params: { sector_id: sectorId },
    });
    return data;
  },
  getDiscounts: async (productId: number): Promise<ProductSectorDiscount[]> => {
    const { data } = await api.get(`/products/${productId}/discounts`);
    return data;
  },
  setDiscount: async (
    productId: number,
    sectorId: number,
    discountPercent: number,
    sectorPriceGbp?: number,
    effectiveFrom?: string,
    effectiveTo?: string,
  ): Promise<ProductSectorDiscount> => {
    const body: Record<string, unknown> = {
      discount_percent: discountPercent,
      sector_price_gbp: sectorPriceGbp ?? 0,
    };
    if (effectiveFrom) body.effective_from = effectiveFrom;
    if (effectiveTo) body.effective_to = effectiveTo;
    const { data } = await api.post(`/products/${productId}/discounts/${sectorId}`, body);
    return data;
  },
  importExcel: async (
    file: File
  ): Promise<{ imported: number; updated: number; errors: string[] }> => {
    const formData = new FormData();
    formData.append('file', file);
    const { data } = await api.post('/products/import-excel', formData);
    return data;
  },
};

// Categories API
export const categoriesAPI = {
  list: async (): Promise<string[]> => {
    const { data } = await api.get('/categories');
    return data.categories || [];
  },
  create: async (name: string): Promise<void> => {
    await api.post('/categories', { name });
  },
  delete: async (name: string): Promise<void> => {
    await api.delete(`/categories/${encodeURIComponent(name)}`);
  },
  rename: async (oldName: string, newName: string): Promise<void> => {
    await api.put(`/categories/${encodeURIComponent(oldName)}/rename`, {
      new_name: newName,
    });
  },
  /** Trim leading/trailing spaces from all product categories to merge duplicates */
  normalize: async (): Promise<{ products_updated: number }> => {
    const { data } = await api.post('/categories/normalize');
    return data;
  },
};

// Sectors API
export const sectorsAPI = {
  list: async (): Promise<Sector[]> => {
    const { data } = await api.get('/sectors');
    return data;
  },
  create: async (sector: Partial<Sector>): Promise<Sector> => {
    const { data } = await api.post('/sectors', sector);
    return data;
  },
  update: async (id: number, sector: Partial<Sector>): Promise<Sector> => {
    const { data } = await api.put(`/sectors/${id}`, sector);
    return data;
  },
  delete: async (id: number): Promise<void> => {
    await api.delete(`/sectors/${id}`);
  },
};

// Stock API
export const stockAPI = {
  list: async (storeId?: number): Promise<Stock[]> => {
    const { data } = await api.get('/stock', { params: { store_id: storeId } });
    return data;
  },
  getStoreStock: async (storeId: number): Promise<Stock[]> => {
    const { data } = await api.get(`/stock/${storeId}`);
    return data;
  },
  assignProductsToStore: async (storeId: number, productIds: number[]): Promise<{ assigned: number; store_id: number; product_ids: number[] }> => {
    const { data } = await api.post('/stock/assign', { store_id: storeId, product_ids: productIds });
    return data;
  },
  unassignProductsFromStore: async (storeId: number, productIds: number[]): Promise<{ unassigned: number; store_id: number; product_ids: number[] }> => {
    const { data } = await api.post('/stock/unassign', { store_id: storeId, product_ids: productIds });
    return data;
  },
  setAssignments: async (
    storeId: number,
    assignments: {
      product_id: number;
      track_prepacked: boolean;
      track_weight: boolean;
      wholesale_ship_from?: boolean;
    }[],
  ): Promise<{ updated: number; store_id: number }> => {
    const { data } = await api.post('/stock/set-assignments', { store_id: storeId, assignments });
    return data;
  },
  getWholesaleShipFromMap: async (): Promise<Record<string, number>> => {
    const { data } = await api.get('/stock/wholesale-ship-from');
    return data;
  },
  getProductStockAssignments: async (productId: number): Promise<Stock[]> => {
    const { data } = await api.get(`/stock/by-product/${productId}`);
    return data;
  },
  getLowStock: async (): Promise<Stock[]> => {
    const { data } = await api.get('/stock/low-stock');
    return data;
  },
  update: async (
    productId: number,
    storeId: number,
    stock: Partial<Stock> & { reason?: string },
  ): Promise<Stock> => {
    const { data } = await api.put(`/stock/${productId}/${storeId}`, stock);
    return data;
  },
  convertInventory: async (
    productId: number,
    storeId: number,
    body: { direction: 'unpack' | 'pack'; amount: number; reason?: string },
  ): Promise<Stock> => {
    const { data } = await api.post(`/stock/${productId}/${storeId}/convert`, body);
    return data;
  },
  getStockReport: async (params: { date: string; store_id?: number }): Promise<StockReportRow[]> => {
    const p: Record<string, string | number> = { date: params.date };
    if (params.store_id != null) p.store_id = params.store_id;
    // Cache-bust so browser doesn't return 304 and user always gets fresh data
    p._t = Date.now();
    const { data } = await api.get('/stock/report', {
      params: p,
      headers: { 'Cache-Control': 'no-cache', Pragma: 'no-cache' },
    });
    return data;
  },
};

// Restock Orders API
export const restockAPI = {
  list: async (storeId?: number, status?: string): Promise<RestockOrder[]> => {
    const { data } = await api.get('/restock-orders', {
      params: { store_id: storeId, status },
    });
    return data;
  },
  create: async (order: {
    store_id: number;
    items: { product_id: number; quantity: number }[];
    notes?: string;
  }): Promise<RestockOrder> => {
    const { data } = await api.post('/restock-orders', order);
    return data;
  },
  updateTracking: async (id: number, trackingNumber: string): Promise<RestockOrder> => {
    const { data } = await api.put(`/restock-orders/${id}/tracking`, {
      tracking_number: trackingNumber,
    });
    return data;
  },
  receive: async (id: number): Promise<RestockOrder> => {
    const { data } = await api.put(`/restock-orders/${id}/receive`);
    return data;
  },
};

// Stores API
export const storesAPI = {
  list: async (params?: { exclude_warehouse_only?: boolean }): Promise<Store[]> => {
    const { data } = await api.get('/stores', { params });
    return data;
  },
  create: async (store: Partial<Store>): Promise<Store> => {
    const { data } = await api.post('/stores', store);
    return data;
  },
};

// Users API
export const usersAPI = {
  list: async (): Promise<User[]> => {
    const { data } = await api.get('/users');
    return data;
  },
  get: async (id: number): Promise<User> => {
    const { data } = await api.get(`/users/${id}`);
    return data;
  },
  create: async (user: {
    username: string;
    password: string;
    pin?: string;
    first_name: string;
    last_name: string;
    email?: string;
    role: string;
    store_ids?: number[];
  }): Promise<User> => {
    const { data } = await api.post('/users', user);
    return data;
  },
  update: async (id: number, user: Partial<User>): Promise<User> => {
    const { data } = await api.put(`/users/${id}`, user);
    return data;
  },
  updatePIN: async (id: number, currentPin: string, newPin: string): Promise<void> => {
    await api.put(`/users/${id}/pin`, { current_pin: currentPin, pin: newPin });
  },
  updateIcon: async (id: number, iconUrl: string): Promise<void> => {
    await api.put(`/users/${id}/icon`, { icon_url: iconUrl });
  },
  updateIconFile: async (id: number, formData: FormData): Promise<{ icon_url: string }> => {
    const { data } = await api.put(`/users/${id}/icon`, formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });
    return data;
  },
  updateIconColors: async (id: number, bgColor: string, textColor: string): Promise<{ icon_url: string }> => {
    const { data } = await api.put(`/users/${id}/icon`, {
      bg_color: bgColor,
      text_color: textColor,
    });
    return data;
  },
  updateStores: async (id: number, storeIds: number[]): Promise<User> => {
    const { data } = await api.put(`/users/${id}/stores`, { store_ids: storeIds });
    return data;
  },
};

// Devices API
export const devicesAPI = {
  register: async (device: {
    device_code: string;
    store_id: number;
    device_name?: string;
  }): Promise<POSDevice> => {
    const { data } = await api.post('/device/register', device);
    return data;
  },
  list: async (): Promise<POSDevice[]> => {
    const { data } = await api.get('/devices');
    return data;
  },
  get: async (id: number): Promise<POSDevice> => {
    const { data } = await api.get(`/devices/${id}`);
    return data;
  },
  listByStore: async (storeId: number): Promise<POSDevice[]> => {
    const { data } = await api.get(`/stores/${storeId}/devices`);
    return data;
  },
  getUsers: async (deviceCode: string): Promise<User[]> => {
    const { data } = await api.get(`/device/${deviceCode}/users`);
    return data;
  },
};

// Catalog API
export const catalogAPI = {
  generate: async (sectorId: number): Promise<any> => {
    const { data } = await api.get(`/catalogs/${sectorId}`);
    return data;
  },
  download: async (sectorId: number): Promise<Blob> => {
    const { data } = await api.get(`/catalogs/${sectorId}/download`, {
      responseType: 'blob',
    });
    return data;
  },
};

// Currency Rates API
export const currencyRatesAPI = {
  list: async (): Promise<CurrencyRate[]> => {
    const { data } = await api.get('/currency-rates');
    return data;
  },
  get: async (code: string): Promise<CurrencyRate> => {
    const { data } = await api.get(`/currency-rates/${code}`);
    return data;
  },
  create: async (rate: { currency_code: string; rate_to_gbp: number; is_pinned?: boolean }): Promise<CurrencyRate> => {
    const { data } = await api.post('/currency-rates', rate);
    return data;
  },
  update: async (code: string, rate: { rate_to_gbp: number; is_pinned?: boolean }): Promise<CurrencyRate> => {
    const { data } = await api.put(`/currency-rates/${code}`, rate);
    return data;
  },
  togglePin: async (code: string, isPinned: boolean): Promise<CurrencyRate> => {
    const { data } = await api.put(`/currency-rates/${code}/pin`, { is_pinned: isPinned });
    return data;
  },
  delete: async (code: string): Promise<void> => {
    await api.delete(`/currency-rates/${code}`);
  },
  sync: async (): Promise<{ message: string; updated_count: number; sync_date: string }> => {
    const { data } = await api.post('/currency-rates/sync');
    return data;
  },
};

// Audit Logs API
export const auditAPI = {
  getStockAuditLogs: async (params: {
    product_id?: number;
    store_id?: number;
    entity_id?: number;
  }): Promise<AuditLog[]> => {
    const { data } = await api.get('/audit/stock', { params });
    return data;
  },
  getOrderAuditLogs: async (params: {
    order_id?: number;
    entity_id?: number;
  }): Promise<AuditLog[]> => {
    const { data } = await api.get('/audit/order', { params });
    return data;
  },
};

// Orders API
export const ordersAPI = {
  list: async (params?: {
    store_id?: number;
    status?: string;
    user_id?: number;
    start_date?: string;
    end_date?: string;
    limit?: number;
  }): Promise<Order[]> => {
    const { data } = await api.get('/orders', { params });
    return data;
  },
  get: async (id: number | string): Promise<Order> => {
    const { data } = await api.get(`/orders/${id}`);
    return data;
  },
  markPaid: async (id: number): Promise<Order> => {
    const { data } = await api.put(`/orders/${id}/pay`);
    return data;
  },
  markComplete: async (id: number): Promise<Order> => {
    const { data } = await api.put(`/orders/${id}/complete`);
    return data;
  },
  cancel: async (id: number): Promise<Order> => {
    const { data } = await api.put(`/orders/${id}/cancel`);
    return data;
  },
  getDailyRevenueStats: async (params?: {
    days?: number;
    start_date?: string;
    end_date?: string;
    store_id?: number;
    store_ids?: number[];
  }): Promise<Array<{ date: string; revenue: number; order_count: number }>> => {
    const p: Record<string, string | number> = { ...(params ?? {}) } as any;
    if (params?.store_ids?.length) {
      p.store_ids = params.store_ids.join(',');
    }
    delete (p as any).store_ids_array;
    const { data } = await api.get('/orders/stats/revenue', { params: p });
    return data;
  },
  getDailyProductSalesStats: async (params?: {
    days?: number;
    start_date?: string;
    end_date?: string;
    store_id?: number;
    store_ids?: number[];
  }): Promise<Array<{ date: string; product_id: number; product_name: string; product_name_chinese: string; quantity: number; revenue: number }>> => {
    const p: Record<string, string | number> = { ...(params ?? {}) } as any;
    if (params?.store_ids?.length) {
      p.store_ids = params.store_ids.join(',');
    }
    delete (p as any).store_ids_array;
    const { data } = await api.get('/orders/stats/product-sales', { params: p });
    return data;
  },
};

// Wholesale clients (management CRUD; list used when creating wholesale orders)
export const wholesaleClientsAPI = {
  list: async (params?: { active_only?: boolean }): Promise<WholesaleClient[]> => {
    const { data } = await api.get('/wholesale-clients', {
      params: params?.active_only ? { active_only: 1 } : undefined,
    });
    return data;
  },
  get: async (id: number): Promise<WholesaleClient> => {
    const { data } = await api.get(`/wholesale-clients/${id}`);
    return data;
  },
  create: async (body: Partial<WholesaleClient>): Promise<WholesaleClient> => {
    const { data } = await api.post('/wholesale-clients', body);
    return data;
  },
  update: async (id: number, body: Partial<WholesaleClient>): Promise<WholesaleClient> => {
    const { data } = await api.put(`/wholesale-clients/${id}`, body);
    return data;
  },
  delete: async (id: number): Promise<void> => {
    await api.delete(`/wholesale-clients/${id}`);
  },
  createStore: async (clientId: number, body: Partial<WholesaleClientStore>): Promise<WholesaleClientStore> => {
    const { data } = await api.post(`/wholesale-clients/${clientId}/stores`, body);
    return data;
  },
  updateStore: async (clientId: number, storeId: number, body: Partial<WholesaleClientStore>): Promise<WholesaleClientStore> => {
    const { data } = await api.put(`/wholesale-clients/${clientId}/stores/${storeId}`, body);
    return data;
  },
  deleteStore: async (clientId: number, storeId: number): Promise<void> => {
    await api.delete(`/wholesale-clients/${clientId}/stores/${storeId}`);
  },
};

// Wholesale orders (pos_user/admin create; management/supervisor approve/reject; admin assigns stores)
export const wholesaleOrdersAPI = {
  create: async (body: {
    wholesale_client_id: number;
    wholesale_client_store_id?: number;
    store_id: number;
    sector_id?: number;
    po_number?: string;
    order_channel?: string;
    po_date?: string;
    order_date?: string;
    payment_terms?: string;
    notes?: string;
    total_discount?: number;
    shipping_fee?: number;
    items: {
      product_id: number;
      quantity: number;
      line_discount_amount?: number;
      line_discount_type?: 'order_entry' | 'order_entry_unit';
      line_discount_unit?: number;
    }[];
  }): Promise<WholesaleOrder> => {
    const { data } = await api.post('/wholesale-orders', body);
    return data;
  },
  uploadPoAttachments: async (
    orderId: number,
    files: File[],
    opts?: { unlock_after_completion?: boolean },
  ): Promise<{ saved: number }> => {
    const form = new FormData();
    files.forEach((f) => form.append('po_attachments', f));
    const { data } = await api.post(`/wholesale-orders/${orderId}/po-attachments`, form, {
      params: opts?.unlock_after_completion ? { unlock_after_completion: 'true' } : undefined,
    });
    return data;
  },
  deletePoAttachment: async (
    orderId: number,
    docId: number,
    opts?: { unlock_after_completion?: boolean },
  ): Promise<void> => {
    await api.delete(`/wholesale-orders/${orderId}/documents/${docId}`, {
      params: opts?.unlock_after_completion ? { unlock_after_completion: 'true' } : undefined,
    });
  },
  list: async (params?: {
    status?: string;
    store_id?: string;
    client?: string;
    delivery_location?: string;
    po_number?: string;
    order_number?: string;
    ref_no?: string;
    order_date_from?: string;
    order_date_to?: string;
    sort_by?: 'ref_no' | 'po_number' | 'total' | 'order_date';
    sort_dir?: 'asc' | 'desc';
  }): Promise<WholesaleOrder[]> => {
    const { data } = await api.get('/wholesale-orders', {
      params: params as Record<string, string>,
    });
    return data;
  },
  getRecentOrderChannels: async (): Promise<string[]> => {
    const { data } = await api.get<{ channels: string[] }>('/wholesale-orders/recent-order-channels');
    return data?.channels ?? [];
  },
  get: async (id: number, options?: { cacheBust?: boolean }): Promise<WholesaleOrder> => {
    const params = options?.cacheBust ? { _t: Date.now() } : undefined;
    const { data } = await api.get(`/wholesale-orders/${id}`, { params });
    return data;
  },
  update: async (id: number, body: {
    po_number?: string;
    order_channel?: string;
    ref_no?: string;
    po_date?: string;
    order_date?: string;
    invoice_date?: string;
    shipping_fee?: number;
    discount_amount?: number;
    wholesale_client_store_id?: number | null;
    clear_wholesale_client_store_id?: boolean;
    items?: { id: number; unit_price?: number; line_discount_amount?: number }[];
  }): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}`, body);
    return data;
  },
  approve: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/approve`);
    return data;
  },
  getEndorseAllocationPreview: async (id: number): Promise<EndorseAllocationPreview> => {
    const { data } = await api.get(`/wholesale-orders/${id}/endorse-allocation-preview`);
    return data;
  },
  reject: async (id: number, reason?: string): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/reject`, { reason: reason ?? '' });
    return data;
  },
  archive: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/archive`);
    return data;
  },
  resubmit: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/resubmit`);
    return data;
  },
  assignStores: async (
    id: number,
    assignments: {
      wholesale_order_item_id: number;
      store_id: number | null;
      quantity?: number;
      case_qty?: number;
    }[],
  ): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/assign`, { assignments });
    return data;
  },
  unassignStores: async (
    id: number,
    assignments: {
      wholesale_order_item_id: number;
      store_id: number;
      quantity?: number;
    }[],
  ): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/unassign`, { assignments });
    return data;
  },
  assignByDefaults: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/assign-by-defaults`);
    return data;
  },
  completeAssignment: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/complete-assignment`);
    return data;
  },
  regenerateOrderConfirmation: async (
    id: number,
    body?: { unlock_after_email?: boolean },
  ): Promise<WholesaleOrder> => {
    const { data } = await api.post(`/wholesale-orders/${id}/regenerate-order-confirmation`, body ?? {});
    return data;
  },
  generateInvoice: async (id: number, body?: { unlock_after_email?: boolean }): Promise<WholesaleOrder> => {
    const { data } = await api.post(`/wholesale-orders/${id}/generate-invoice`, body ?? {});
    return data;
  },
  setInvoiceSentAt: async (id: number, body: { invoice_sent_at: string }): Promise<WholesaleOrder> => {
    const { data } = await api.patch(`/wholesale-orders/${id}/invoice-sent`, body);
    return data;
  },
  bulkAttachmentsZipEmail: async (body: {
    order_ids: number[];
    kind:
      | 'all'
      | 'order_confirmation'
      | 'po_attachment'
      | 'delivery_note'
      | 'signed_delivery_note'
      | 'invoice'
      | 'payment_proof';
    recipient_email: string;
  }): Promise<{ message: string; download_url?: string }> => {
    const { data } = await api.post('/wholesale-orders/bulk-attachments-zip-email', body, {
      timeout: 600_000,
    });
    return data;
  },
  getAuditLogs: async (id: number): Promise<AuditLog[]> => {
    const { data } = await api.get(`/wholesale-orders/${id}/audit-logs`);
    return data;
  },
  restoreDocumentFromAudit: async (
    orderId: number,
    auditLogId: number,
    body?: { unlock_after_email?: boolean },
  ): Promise<WholesaleOrder> => {
    const { data } = await api.post(
      `/wholesale-orders/${orderId}/audit-logs/${auditLogId}/restore-document`,
      body ?? {},
    );
    return data;
  },
  emailOrder: async (
    id: number,
    body: {
      recipient?: string;
      to?: string[];
      cc?: string;
      cc_list?: string[];
      bcc?: string;
      bcc_list?: string[];
      subject?: string;
      message?: string;
      attachments: string[];
      signed_delivery_shipment_id?: number;
      shipment_ids?: number[];
      email_type?: 'order_confirm' | 'shipments_delivered' | 'invoice';
    },
  ): Promise<{
    message: string;
    recipient: string;
    to?: string[];
    cc?: string;
    cc_list?: string[];
    bcc?: string;
    bcc_list?: string[];
    sent_at: string;
    initiated_by?: string;
    attachment_count: number;
    order?: WholesaleOrder;
  }> => {
    const { data } = await api.post(`/wholesale-orders/${id}/email`, body, { timeout: 120_000 });
    return data;
  },
  skipOrderEmail: async (
    id: number,
    body: { email_type: 'order_confirm' | 'shipments_delivered' | 'invoice'; remark: string },
  ): Promise<{
    message: string;
    email_type: string;
    skipped_at: string;
    initiated_by?: string;
    skip_remark?: string;
  }> => {
    const { data } = await api.post(`/wholesale-orders/${id}/skip-email`, body);
    return data;
  },
  emailDocument: async (
    id: number,
    body: {
      document_type: string;
      recipient?: string;
      to?: string[];
      cc?: string;
      cc_list?: string[];
      bcc?: string;
      bcc_list?: string[];
      shipment_id?: number;
    },
  ): Promise<{
    message: string;
    recipient: string;
    to?: string[];
    cc?: string;
    cc_list?: string[];
    bcc?: string;
    bcc_list?: string[];
    sent_at: string;
    initiated_by?: string;
    order?: WholesaleOrder;
  }> => {
    const { data } = await api.post(`/wholesale-orders/${id}/email-document`, body);
    return data;
  },
  uploadPaymentProofs: async (
    id: number,
    files: File[],
    meta?: { amount?: number; transfer_date?: string; transferred_to?: string },
    opts?: { unlock_after_completion?: boolean },
  ): Promise<WholesaleOrder> => {
    const form = new FormData();
    files.forEach((f) => form.append('payment_proofs', f));
    if (meta?.amount != null) form.append('amount', String(meta.amount));
    if (meta?.transfer_date) form.append('transfer_date', meta.transfer_date);
    if (meta?.transferred_to) form.append('transferred_to', meta.transferred_to);
    const { data } = await api.post(`/wholesale-orders/${id}/upload-payment-proof`, form, {
      params: opts?.unlock_after_completion ? { unlock_after_completion: 'true' } : undefined,
    });
    return data;
  },
  deletePaymentProof: async (
    orderId: number,
    docId: number,
    opts?: { unlock_after_completion?: boolean },
  ): Promise<void> => {
    await api.delete(`/wholesale-orders/${orderId}/documents/${docId}`, {
      params: opts?.unlock_after_completion ? { unlock_after_completion: 'true' } : undefined,
    });
  },
  downloadDocument: async (orderId: number, docId: number, preview = false): Promise<Blob> => {
    const url = `/wholesale-orders/${orderId}/documents/${docId}/download${preview ? '?preview=1' : ''}`;
    const { data } = await api.get(url, { responseType: 'blob' });
    return data;
  },
  downloadDocumentWithFilename: async (
    orderId: number,
    docId: number,
    preview = false,
    fallbackFilename?: string,
  ): Promise<{ blob: Blob; filename: string }> => {
    const url = `/wholesale-orders/${orderId}/documents/${docId}/download${preview ? '?preview=1' : ''}`;
    const res = await api.get(url, { responseType: 'blob' });
    const cd = (res.headers?.['content-disposition'] ?? res.headers?.['Content-Disposition']) as string | undefined;
    const parseFilename = (v?: string): string | null => {
      if (!v) return null;
      // filename*=UTF-8''...
      const star = v.match(/filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i);
      if (star?.[1]) {
        try {
          return decodeURIComponent(star[1].trim().replace(/^"|"$/g, ''));
        } catch {
          return star[1].trim().replace(/^"|"$/g, '');
        }
      }
      // filename="..."
      const simple = v.match(/filename\s*=\s*([^;]+)/i);
      if (simple?.[1]) {
        return simple[1].trim().replace(/^"|"$/g, '');
      }
      return null;
    };
    const parsed = parseFilename(cd);
    const filename = parsed || fallbackFilename || 'download';
    return { blob: res.data as Blob, filename };
  },
  downloadLegacyPaymentProof: async (orderId: number): Promise<Blob> => {
    const { data } = await api.get(`/wholesale-orders/${orderId}/legacy-payment-proof/download`, {
      responseType: 'blob',
    });
    return data;
  },
  confirmPayment: async (id: number, body?: { amount?: number; transfer_date?: string; transferred_to?: string }): Promise<WholesaleOrder> => {
    const { data } = await api.post(`/wholesale-orders/${id}/confirm-payment`, body ?? {});
    return data;
  },
};

// Shipments (wholesale outbound)
export const shipmentsAPI = {
  list: async (params?: {
    store_id?: number;
    status?: string;
    include_old_completed?: boolean;
  }): Promise<Shipment[]> => {
    const { data } = await api.get('/shipments', {
      params: {
        ...params,
        include_old_completed: params?.include_old_completed ? 'true' : undefined,
      },
    });
    return data;
  },
  get: async (id: number): Promise<Shipment> => {
    const { data } = await api.get(`/shipments/${id}`);
    return data;
  },
  update: async (
    id: number,
    body: { courier?: string; tracking_number?: string; delivery_date?: string },
  ): Promise<Shipment> => {
    const { data } = await api.put(`/shipments/${id}`, body);
    return data;
  },
  updateStatus: async (id: number, status: string): Promise<Shipment> => {
    const { data } = await api.patch(`/shipments/${id}/status`, { status });
    return data;
  },
  regenerateDeliveryNote: async (id: number, body?: { unlock_after_email?: boolean }): Promise<Shipment> => {
    const { data } = await api.post(`/shipments/${id}/regenerate-delivery-note`, body ?? {});
    return data;
  },
  startShipment: async (
    id: number,
    body: {
      case_qty: { wholesale_order_item_id: number; case_qty: number }[];
      delivery_date?: string;
      courier?: string;
      tracking_number?: string;
    },
  ): Promise<Shipment> => {
    const { data } = await api.post(`/shipments/${id}/start-shipment`, body);
    return data;
  },
  uploadSignedDeliveryNote: async (
    id: number,
    file: File,
    opts?: { unlock_after_completion?: boolean },
  ): Promise<Shipment> => {
    const form = new FormData();
    form.append('signed_delivery_note', file);
    const { data } = await api.post(`/shipments/${id}/upload-signed-delivery-note`, form, {
      params: opts?.unlock_after_completion ? { unlock_after_completion: 'true' } : undefined,
    });
    return data;
  },
  completePacking: async (
    id: number,
    body?: {
      case_qty?: { wholesale_order_item_id: number; case_qty: number }[];
      delivery_date?: string; // YYYY-MM-DD
      force_complete?: boolean;
    },
  ): Promise<Shipment> => {
    const { data } = await api.post(`/shipments/${id}/complete-packing`, body ?? {});
    return data;
  },
  updateCaseQty: async (
    id: number,
    body: {
      case_qty: { wholesale_order_item_id: number; case_qty: number }[];
      delivery_date?: string; // YYYY-MM-DD
      unlock_after_email?: boolean;
    },
  ): Promise<Shipment> => {
    const { data } = await api.put(`/shipments/${id}/case-qty`, body);
    return data;
  },
};

// Stocktake day-start (management)
export const stocktakeAPI = {
  listDayStart: async (params?: {
    from?: string;
    to?: string;
    user_id?: number;
    store_ids?: number[];
  }): Promise<StocktakeDayStartRecord[]> => {
    const p: Record<string, string | number> = {};
    if (params?.from) p.from = params.from;
    if (params?.to) p.to = params.to;
    if (params?.user_id != null) p.user_id = params.user_id;
    if (params?.store_ids?.length) p.store_ids = params.store_ids.join(',');
    const { data } = await api.get('/stocktake-day-start', { params: p });
    return data;
  },
};

// User activity events (for timetable: login, logout, stocktake)
export const userActivityAPI = {
  list: async (params?: {
    from?: string;
    to?: string;
    user_id?: number;
    store_ids?: number[];
    event_type?: string[];
  }): Promise<UserActivityEvent[]> => {
    const p: Record<string, string | number> = {};
    if (params?.from) p.from = params.from;
    if (params?.to) p.to = params.to;
    if (params?.user_id != null) p.user_id = params.user_id;
    if (params?.store_ids?.length) p.store_ids = params.store_ids.join(',');
    if (params?.event_type?.length) p.event_type = params.event_type.join(',');
    const { data } = await api.get('/user-activity-events', { params: p });
    return data;
  },
};

// Reporting / aggregated stats (used by the Report page)
export const reportsAPI = {
  getWholesaleRevenueSummary: async (params: { start_date: string; end_date: string; store_id?: number; store_ids?: number[] }): Promise<
    { total_revenue: number }
  > => {
    const p: Record<string, string | number> = { start_date: params.start_date, end_date: params.end_date };
    if (params.store_ids?.length) {
      p.store_ids = params.store_ids.join(',');
    } else if (params.store_id != null) {
      p.store_id = params.store_id;
    }
    const { data } = await api.get('/wholesale-orders/stats/revenue-summary', { params: p });
    return data;
  },
  getWholesaleProductSales: async (params: { start_date: string; end_date: string; store_id?: number; store_ids?: number[] }): Promise<
    Array<{ product_id: number; product_name: string; product_name_chinese: string; quantity: number; revenue: number }>
  > => {
    const p: Record<string, string | number> = { start_date: params.start_date, end_date: params.end_date };
    if (params.store_ids?.length) {
      p.store_ids = params.store_ids.join(',');
    } else if (params.store_id != null) {
      p.store_id = params.store_id;
    }
    const { data } = await api.get('/wholesale-orders/stats/product-sales', { params: p });
    return data ?? [];
  },
  getWholesaleClientSales: async (params: { start_date: string; end_date: string; store_id?: number; store_ids?: number[] }): Promise<
    Array<{ client_id: number; client_name: string; revenue: number }>
  > => {
    const p: Record<string, string | number> = { start_date: params.start_date, end_date: params.end_date };
    if (params.store_ids?.length) {
      p.store_ids = params.store_ids.join(',');
    } else if (params.store_id != null) {
      p.store_id = params.store_id;
    }
    const { data } = await api.get('/wholesale-orders/stats/client-sales', { params: p });
    return data ?? [];
  },
};

export default api;

