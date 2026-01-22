export interface User {
  id: number;
  username: string;
  first_name: string;
  last_name: string;
  email?: string;
  role: 'management' | 'pos_user' | 'supervisor';
  icon_url?: string;
  icon_color?: string;
  is_active: boolean;
  stores?: Store[];
}

export interface Store {
  id: number;
  name: string;
  address?: string;
  is_active: boolean;
}

export interface POSDevice {
  id: number;
  device_code: string;
  store_id: number;
  device_name?: string;
  is_active: boolean;
  store?: Store;
}

export interface Sector {
  id: number;
  name: string;
  description?: string;
  is_active: boolean;
}

export interface Product {
  id: number;
  name: string;
  name_chinese?: string;
  barcode?: string;
  sku?: string;
  category?: string;
  image_url?: string;
  unit_type: 'quantity' | 'weight';
  is_active: boolean;
  current_cost?: ProductCost;
  discounts?: ProductSectorDiscount[];
}

export interface ProductCost {
  id: number;
  product_id: number;
  exchange_rate: number;
  purchasing_cost_hkd?: number;
  purchasing_cost_gbp?: number;
  unit_weight_g: number;
  purchasing_cost_buffer_percent: number;
  cost_buffer_gbp: number;
  adjusted_purchasing_cost_gbp: number;
  weight_g: number;
  weight_buffer_percent: number;
  freight_rate_hkd_per_kg: number;
  freight_buffer_hkd: number;
  freight_hkd: number;
  freight_gbp: number;
  import_duty_percent: number;
  import_duty_gbp: number;
  packaging_gbp: number;
  wholesale_cost_gbp: number;
  direct_retail_online_store_price_gbp?: number; // Direct Retail Online Store price
  effective_from: string;
  effective_to?: string;
}

export interface ProductSectorDiscount {
  id: number;
  product_id: number;
  sector_id: number;
  discount_percent: number;
  effective_from: string;
  effective_to?: string;
  product?: Product;
  sector?: Sector;
}

export interface Stock {
  id: number;
  product_id: number;
  store_id: number;
  quantity: number;
  low_stock_threshold: number;
  last_updated: string;
  product?: Product;
  store?: Store;
}

export interface RestockOrder {
  id: number;
  store_id: number;
  initiated_by: number;
  tracking_number?: string;
  status: 'initiated' | 'in_transit' | 'received' | 'cancelled';
  initiated_at: string;
  received_at?: string;
  notes?: string;
  store?: Store;
  initiator?: User;
  items?: RestockOrderItem[];
}

export interface RestockOrderItem {
  id: number;
  restock_order_id: number;
  product_id: number;
  quantity: number;
  product?: Product;
}

export interface AuditLog {
  id: number;
  user_id?: number;
  action: string;
  entity_type: string;
  entity_id?: number;
  changes: string; // JSON string
  ip_address: string;
  user_agent: string;
  created_at: string;
  user?: User;
}

export interface PriceHistory {
  id: number;
  product_id: number;
  sector_id?: number;
  wholesale_cost_gbp: number;
  discount_percent: number;
  final_price_gbp: number;
  recorded_at: string;
  product?: Product;
  sector?: Sector;
}

export interface CurrencyRate {
  id: number;
  currency_code: string;
  rate_to_gbp: number;
  is_pinned: boolean;
  last_updated: string;
  updated_by: string;
  created_at: string;
  updated_at: string;
}

export interface LoginResponse {
  token: string;
  user: User;
}

export interface Order {
  id: number;
  order_number: string;
  store_id: number;
  user_id: number;
  device_code?: string;
  sector_id?: number;
  subtotal: number;
  discount_amount: number;
  total_amount: number;
  status: 'pending' | 'paid' | 'completed' | 'cancelled' | 'picked_up';
  qr_code_data?: string;
  created_at: string;
  paid_at?: string;
  completed_at?: string;
  picked_up_at?: string;
  store?: Store;
  user?: User;
  sector?: Sector;
  items?: OrderItem[];
}

export interface OrderItem {
  id: number;
  order_id: number;
  product_id: number;
  quantity: number;
  unit_price: number;
  discount_percent: number;
  discount_amount: number;
  line_total: number;
  product?: Product;
}

