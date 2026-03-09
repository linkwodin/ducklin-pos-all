export interface User {
  id: number;
  username: string;
  first_name: string;
  last_name: string;
  email?: string;
  role: 'management' | 'pos_user' | 'supervisor';
  icon_url?: string;
  icon_color?: string;
  icon_bg_color?: string;
  icon_text_color?: string;
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
  sector_price_gbp: number;
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
  incoming_quantity?: number;
  product?: Product;
  store?: Store;
}

/** One row of the day-start / day-end stock report */
export interface StockReportRow {
  product_id: number;
  product_name: string;
  store_id: number;
  store_name: string;
  day_start_quantity: number;
  day_end_quantity: number;
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

export interface StocktakeDayStartRecord {
  id: number;
  user_id: number;
  store_id?: number; // store where user did first login / stocktake
  date: string; // yyyy-MM-dd
  first_login_at: string;
  status: 'pending' | 'done' | 'skipped';
  done_at?: string;
  skip_reason?: string;
  created_at: string;
  updated_at: string;
  user?: User;
  store?: Store;
}

export interface UserActivityEvent {
  id: number;
  user_id: number;
  store_id?: number;
  event_type: string; // first_login, logout, stocktake_day_start_done, stocktake_day_start_skipped, stocktake_day_end_skipped
  occurred_at: string;
  skip_reason?: string;
  created_at: string;
  user?: User;
  store?: Store;
}

export interface WholesaleOrderItem {
  id: number;
  wholesale_order_id: number;
  product_id: number;
  quantity: number;
  unit_price: number;
  line_discount_amount?: number;
  line_total: number;
  assigned_store_id?: number | null;
  assigned_store?: Store | null;
  product?: Product;
}

export interface WholesaleClientStore {
  id: number;
  wholesale_client_id: number;
  name: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  postcode?: string;
  contact_name?: string;
  email?: string;
  phone?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface WholesaleClient {
  id: number;
  name: string;
  contact_name?: string;
  email?: string;
  phone?: string;
  address?: string;
  address_line1?: string;
  address_line2?: string;
  postcode?: string;
  vat_number?: string;
  company_number?: string;
  terms?: string;
  account_code?: string;
  sector_id?: number;
  sector?: Sector;
  stores?: WholesaleClientStore[];
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface WholesaleOrder {
  id: number;
  order_number: string;
  po_number: string;
  order_channel?: string;
  ref_no: string;
  po_date?: string;
  payment_terms?: string;
  wholesale_client_id: number;
  wholesale_client_store_id?: number; // shipping address
  store_id: number;
  user_id: number;
  sector_id?: number;
  status: 'pending_approval' | 'assign_shipment' | 'approved' | 'rejected';
  subtotal?: number;
  discount_amount?: number;
  total_net?: number;
  vat_total?: number;
  amount_due?: number;
  shipping_fee?: number;
  notes?: string;
  rejection_reason?: string;
  created_at: string;
  reviewed_at?: string;
  reviewed_by?: number;
  wholesale_client?: WholesaleClient;
  store?: Store;
  user?: User;
  sector?: Sector;
  reviewer?: User;
  items?: WholesaleOrderItem[];
  documents?: WholesaleOrderDocument[];
  shipments?: Shipment[];
}

export interface Shipment {
  id: number;
  wholesale_order_id: number;
  store_id: number;
  courier?: string;
  tracking_number?: string;
  shipment_fee?: number;
  delivery_note_pdf_url?: string;
  status: 'packing' | 'completed';
  created_at: string;
  updated_at: string;
  store?: Store;
  wholesale_order?: WholesaleOrder;
  items?: ShipmentItem[];
}

export interface ShipmentItem {
  id: number;
  shipment_id: number;
  wholesale_order_item_id: number;
  case_qty?: number;
  wholesale_order_item?: WholesaleOrderItem;
}

export interface WholesaleOrderDocument {
  id: number;
  wholesale_order_id: number;
  type: 'order_confirmation' | 'delivery_note' | 'invoice';
  file_url: string;
  created_at: string;
}

export interface CompanySettings {
  id: number;
  company_name: string;
  address_line1: string;
  address_line2: string;
  city: string;
  postcode: string;
  telephone: string;
  email: string;
  bank_account_name: string;
  bank_account_number: string;
  bank_sort_code: string;
  bank_address: string;
  bank_iban: string;
  payment_info: string;
  updated_at: string;
}

