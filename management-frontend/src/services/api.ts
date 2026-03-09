import axios from 'axios';
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
  WholesaleClient,
  WholesaleClientStore,
  CompanySettings,
  Shipment,
} from '../types';

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api/v1';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Add token to requests
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  // Don't set Content-Type for FormData - let axios set it with boundary
  if (config.data instanceof FormData) {
    delete config.headers['Content-Type'];
  }
  return config;
});

// Handle 401 errors — skip redirect for the login endpoint itself
api.interceptors.response.use(
  (response) => response,
  (error) => {
    const isLoginRequest = error.config?.url?.includes('/auth/login');
    if (error.response?.status === 401 && !isLoginRequest) {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
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
  getLowStock: async (): Promise<Stock[]> => {
    const { data } = await api.get('/stock/low-stock');
    return data;
  },
  update: async (productId: number, storeId: number, stock: Partial<Stock>): Promise<Stock> => {
    const { data } = await api.put(`/stock/${productId}/${storeId}`, stock);
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
  list: async (): Promise<Store[]> => {
    const { data } = await api.get('/stores');
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
  }): Promise<Array<{ date: string; revenue: number; order_count: number }>> => {
    const { data } = await api.get('/orders/stats/revenue', { params });
    return data;
  },
  getDailyProductSalesStats: async (params?: {
    days?: number;
    start_date?: string;
    end_date?: string;
    store_id?: number;
  }): Promise<Array<{ date: string; product_id: number; product_name: string; product_name_chinese: string; quantity: number; revenue: number }>> => {
    const { data } = await api.get('/orders/stats/product-sales', { params });
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
    payment_terms?: string;
    notes?: string;
    total_discount?: number;
    shipping_fee?: number;
    items: { product_id: number; quantity: number; line_discount_amount?: number }[];
  }): Promise<WholesaleOrder> => {
    const { data } = await api.post('/wholesale-orders', body);
    return data;
  },
  list: async (params?: { status?: string; store_id?: string; client?: string; po_number?: string; order_number?: string; ref_no?: string }): Promise<WholesaleOrder[]> => {
    const { data } = await api.get('/wholesale-orders', { params });
    return data;
  },
  getRecentOrderChannels: async (): Promise<string[]> => {
    const { data } = await api.get<{ channels: string[] }>('/wholesale-orders/recent-order-channels');
    return data?.channels ?? [];
  },
  get: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.get(`/wholesale-orders/${id}`);
    return data;
  },
  update: async (id: number, body: { po_number?: string; order_channel?: string; ref_no?: string; po_date?: string; shipping_fee?: number; items?: { id: number; unit_price: number }[] }): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}`, body);
    return data;
  },
  approve: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/approve`);
    return data;
  },
  reject: async (id: number, reason?: string): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/reject`, { reason: reason ?? '' });
    return data;
  },
  assignStores: async (
    id: number,
    assignments: { wholesale_order_item_id: number; store_id: number | null }[],
  ): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/assign`, { assignments });
    return data;
  },
  completeAssignment: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.put(`/wholesale-orders/${id}/complete-assignment`);
    return data;
  },
  regenerateOrderConfirmation: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.post(`/wholesale-orders/${id}/regenerate-order-confirmation`);
    return data;
  },
  generateInvoice: async (id: number): Promise<WholesaleOrder> => {
    const { data } = await api.post(`/wholesale-orders/${id}/generate-invoice`);
    return data;
  },
  getAuditLogs: async (id: number): Promise<AuditLog[]> => {
    const { data } = await api.get(`/wholesale-orders/${id}/audit-logs`);
    return data;
  },
  emailDocument: async (id: number, body: { document_type: string; recipient?: string; shipment_id?: number }): Promise<{ message: string; recipient: string }> => {
    const { data } = await api.post(`/wholesale-orders/${id}/email-document`, body);
    return data;
  },
};

// Shipments (for order detail: list is on order; update courier/tracking)
export const shipmentsAPI = {
  get: async (id: number): Promise<Shipment> => {
    const { data } = await api.get(`/shipments/${id}`);
    return data;
  },
  update: async (
    id: number,
    body: { courier?: string; tracking_number?: string },
  ): Promise<Shipment> => {
    const { data } = await api.put(`/shipments/${id}`, body);
    return data;
  },
  regenerateDeliveryNote: async (id: number): Promise<Shipment> => {
    const { data } = await api.post(`/shipments/${id}/regenerate-delivery-note`);
    return data;
  },
  completePacking: async (
    id: number,
    body?: { case_qty?: { wholesale_order_item_id: number; case_qty: number }[] },
  ): Promise<Shipment> => {
    const { data } = await api.post(`/shipments/${id}/complete-packing`, body ?? {});
    return data;
  },
  updateCaseQty: async (
    id: number,
    body: { case_qty: { wholesale_order_item_id: number; case_qty: number }[] },
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

export default api;

