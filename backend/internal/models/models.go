package models

import (
	"time"
)

// User represents a system user
type User struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	Username      string    `gorm:"type:varchar(100);uniqueIndex;not null" json:"username"`
	PasswordHash  string    `gorm:"type:varchar(255);not null" json:"-"`
	PINHash       string    `json:"-"`
	FirstName     string    `gorm:"not null" json:"first_name"`
	LastName      string    `gorm:"not null" json:"last_name"`
	Email         string    `json:"email"`
	Role          string `gorm:"type:enum('management','pos_user','supervisor','hq_staff');not null" json:"role"`
	IconURL       string    `json:"icon_url"`
	IconColor     string    `json:"icon_color"`
	IconBgColor   string    `json:"icon_bg_color"`   // Last selected background color for icon generation
	IconTextColor string    `json:"icon_text_color"` // Last selected text color for icon generation
	IsActive      bool      `gorm:"default:true" json:"is_active"`
	DefaultStoreID              *uint `gorm:"index" json:"default_store_id,omitempty"`
	DefaultWholesaleClientID    *uint `gorm:"index" json:"default_wholesale_client_id,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`

	// Relationships
	Stores           []Store           `gorm:"many2many:user_stores;" json:"stores,omitempty"`
	WholesaleClients []WholesaleClient `gorm:"many2many:user_wholesale_clients;" json:"wholesale_clients,omitempty"`
}

// Store represents a physical store location
type Store struct {
	ID                       uint      `gorm:"primaryKey" json:"id"`
	Name                     string    `gorm:"not null" json:"name"`
	Address                  string    `json:"address"`
	IsWarehouseOnly          bool      `gorm:"default:false" json:"is_warehouse_only"`
	IsActive                 bool      `gorm:"default:true" json:"is_active"`
	PosReceiptTypes              []string  `gorm:"serializer:json;type:text" json:"pos_receipt_types"`
	PosAutoPrintReceiptTypes     []string  `gorm:"serializer:json;type:text" json:"pos_auto_print_receipt_types"`
	PosReceiptSettingsConfigured bool      `gorm:"default:false" json:"pos_receipt_settings_configured"`
	CreatedAt                time.Time `json:"created_at"`
	UpdatedAt                time.Time `json:"updated_at"`

	// Relationships
	Users      []User      `gorm:"many2many:user_stores;" json:"users,omitempty"`
	POSDevices []POSDevice `json:"pos_devices,omitempty"`
	Stock      []Stock     `json:"stock,omitempty"`
}

// POSDevice represents a POS device/computer
type POSDevice struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	DeviceCode string    `gorm:"type:varchar(100);uniqueIndex;not null" json:"device_code"`
	StoreID    uint      `gorm:"not null" json:"store_id"`
	DeviceName string    `gorm:"type:varchar(255)" json:"device_name"`
	IsActive   bool      `gorm:"default:true" json:"is_active"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`

	// Relationships
	Store Store `gorm:"foreignKey:StoreID" json:"store,omitempty"`
}

// Sector represents a customer sector (wholesaler, restaurant, etc.)
type Sector struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `gorm:"type:varchar(255);uniqueIndex;not null" json:"name"`
	Description  string    `gorm:"type:text" json:"description"`
	DiscountRate float64   `gorm:"type:decimal(5,2);default:0" json:"discount_rate"` // Base discount rate for this sector (%)
	IsActive     bool      `gorm:"default:true" json:"is_active"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// ProductLine is the shared catalog identity (name, category, image).
// Sellable SKUs (qty box sizes, weight variants) are Product rows linked via ProductLineID.
type ProductLine struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	Name        string    `gorm:"type:varchar(255);not null" json:"name"`
	NameChinese string    `gorm:"type:varchar(255)" json:"name_chinese"`
	Category    string    `gorm:"type:varchar(255)" json:"category"`
	ImageURL    string    `gorm:"type:varchar(500)" json:"image_url"`
	IsActive    bool      `gorm:"default:true" json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`

	Variants []Product `gorm:"foreignKey:ProductLineID" json:"variants,omitempty"`
}

// Product represents a sellable variant (qty box or weight SKU) under a ProductLine.
type Product struct {
	ID          uint   `gorm:"primaryKey" json:"id"`
	ProductLineID uint `gorm:"index" json:"product_line_id"`
	Name        string `gorm:"type:varchar(255);not null" json:"name"`
	NameChinese string `gorm:"type:varchar(255)" json:"name_chinese"`
	Barcode     string `gorm:"type:varchar(100);uniqueIndex" json:"barcode"`
	SKU         string `gorm:"type:varchar(100);uniqueIndex" json:"sku"`
	Category    string `gorm:"type:varchar(255)" json:"category"`
	ImageURL    string `gorm:"type:varchar(500)" json:"image_url"`
	// VariantLabel: e.g. "3 pcs box", "6 pcs box", "Loose weight".
	VariantLabel string `gorm:"type:varchar(255)" json:"variant_label,omitempty"`
	// UnitsPerPack: pieces per pack for quantity variants (e.g. 3, 6).
	UnitsPerPack float64 `gorm:"type:decimal(10,3);default:0" json:"units_per_pack,omitempty"`
	UnitType    string `gorm:"type:enum('quantity','weight');default:'quantity'" json:"unit_type"`
	// SellByQty: product can be sold and stocked by unit count (uses Barcode).
	SellByQty bool `gorm:"default:true" json:"sell_by_qty"`
	// SellByWeight: product can be sold and stocked by weight (uses WeightBarcode).
	SellByWeight bool `gorm:"default:false" json:"sell_by_weight"`
	// WeightBarcode: barcode scanned at POS/stocktake for weight sales.
	WeightBarcode string `gorm:"type:varchar(100);uniqueIndex" json:"weight_barcode,omitempty"`
	// WeightBarcodePrefix: up to 8 digits; receipt barcodes = prefix + weight (4 digits, 0.01 kg) + check digit (0).
	WeightBarcodePrefix string `gorm:"type:varchar(8)" json:"weight_barcode_prefix,omitempty"`
	// PriceWeightG: retail price applies to this weight in grams (weight products only). 0 = default 1000 g (1 kg).
	PriceWeightG float64 `gorm:"type:decimal(10,3);default:0" json:"price_weight_g,omitempty"`
	// CanSellByWeight: product supports weight-based sales and dual inventory (prepacked + loose weight).
	CanSellByWeight bool `gorm:"default:false" json:"can_sell_by_weight"`
	// PrepackWeightG: grams per prepacked unit (for pack/unpack between prepacked and weight inventory).
	PrepackWeightG float64 `gorm:"type:decimal(10,3);default:0" json:"prepack_weight_g,omitempty"`
	// For wholesale orders: how many units (quantity) typically go into one box.
	WholesaleUnitsPerBox float64   `gorm:"type:decimal(10,3);default:0" json:"wholesale_units_per_box,omitempty"`
	IsActive             bool      `gorm:"default:true" json:"is_active"`
	CreatedAt            time.Time `json:"created_at"`
	UpdatedAt            time.Time `json:"updated_at"`

	// Relationships
	ProductLine *ProductLine            `gorm:"foreignKey:ProductLineID" json:"product_line,omitempty"`
	CurrentCost *ProductCost            `gorm:"-" json:"current_cost,omitempty"`
	Discounts   []ProductSectorDiscount `json:"discounts,omitempty"`
	// Aggregated across all store locations (not persisted).
	TotalStockQuantity *float64 `gorm:"-" json:"total_stock_quantity,omitempty"`
	TotalStockWeightG  *float64 `gorm:"-" json:"total_stock_weight_g,omitempty"`
}

// ProductCost represents the cost configuration for a product
type ProductCost struct {
	ID                              uint       `gorm:"primaryKey" json:"id"`
	ProductID                       uint       `gorm:"not null;index" json:"product_id"`
	ExchangeRate                    float64    `gorm:"type:decimal(10,4);not null" json:"exchange_rate"`
	PurchasingCostHKD               float64    `gorm:"type:decimal(10,2)" json:"purchasing_cost_hkd"`
	PurchasingCostGBP               float64    `gorm:"type:decimal(10,2)" json:"purchasing_cost_gbp"`
	UnitWeightG                     int        `gorm:"not null" json:"unit_weight_g"`
	PurchasingCostBufferPercent     float64    `gorm:"type:decimal(5,2);default:0" json:"purchasing_cost_buffer_percent"`
	CostBufferGBP                   float64    `gorm:"type:decimal(10,2);default:0" json:"cost_buffer_gbp"`
	AdjustedPurchasingCostGBP       float64    `gorm:"type:decimal(10,2)" json:"adjusted_purchasing_cost_gbp"`
	WeightG                         int        `gorm:"not null" json:"weight_g"`
	WeightBufferPercent             float64    `gorm:"type:decimal(5,2);default:0" json:"weight_buffer_percent"`
	FreightRateHKDPerKG             float64    `gorm:"type:decimal(10,2);not null" json:"freight_rate_hkd_per_kg"`
	FreightBufferHKD                float64    `gorm:"type:decimal(10,2);default:0" json:"freight_buffer_hkd"`
	FreightHKD                      float64    `gorm:"type:decimal(10,2)" json:"freight_hkd"`
	FreightGBP                      float64    `gorm:"type:decimal(10,2)" json:"freight_gbp"`
	ImportDutyPercent               float64    `gorm:"type:decimal(5,2);default:0" json:"import_duty_percent"`
	ImportDutyGBP                   float64    `gorm:"type:decimal(10,2);default:0" json:"import_duty_gbp"`
	PackagingGBP                    float64    `gorm:"type:decimal(10,2);default:0" json:"packaging_gbp"`
	WholesaleCostGBP                float64    `gorm:"type:decimal(10,2);not null" json:"wholesale_cost_gbp"`
	DirectRetailOnlineStorePriceGBP float64    `gorm:"type:decimal(10,2);default:0" json:"direct_retail_online_store_price_gbp"` // Direct Retail Online Store price
	EffectiveFrom                   *time.Time `gorm:"type:date" json:"effective_from,omitempty"`
	EffectiveTo                     *time.Time `gorm:"type:date" json:"effective_to,omitempty"`
	CreatedAt                       time.Time  `json:"created_at"`

	// Relationships
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// ProductSectorDiscount represents discount rates for products by sector
type ProductSectorDiscount struct {
	ID              uint       `gorm:"primaryKey" json:"id"`
	ProductID       uint       `gorm:"not null;index" json:"product_id"`
	SectorID        uint       `gorm:"not null;index" json:"sector_id"`
	DiscountPercent float64    `gorm:"type:decimal(5,2);not null;default:0" json:"discount_percent"`
	SectorPriceGBP  float64    `gorm:"type:decimal(10,2);not null;default:0" json:"sector_price_gbp"`
	EffectiveFrom   time.Time  `gorm:"type:date" json:"effective_from"`
	EffectiveTo     *time.Time `gorm:"type:date" json:"effective_to,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`

	// Relationships
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
	Sector  Sector  `gorm:"foreignKey:SectorID" json:"sector,omitempty"`
}

// Stock represents inventory at a store
type Stock struct {
	ID                uint      `gorm:"primaryKey" json:"id"`
	ProductID         uint      `gorm:"not null;index" json:"product_id"`
	StoreID           uint      `gorm:"not null;index" json:"store_id"`
	Quantity          float64   `gorm:"type:decimal(10,3);not null;default:0" json:"quantity"`
	WeightQuantityG   float64   `gorm:"type:decimal(10,3);not null;default:0" json:"weight_quantity_g"`
	TrackPrepacked    bool      `gorm:"not null;default:true" json:"track_prepacked"`
	TrackWeight       bool      `gorm:"not null;default:false" json:"track_weight"`
	// WholesaleShipFrom: wholesale orders for this product always ship from this store.
	WholesaleShipFrom bool      `gorm:"not null;default:false" json:"wholesale_ship_from"`
	LowStockThreshold float64   `gorm:"type:decimal(10,3);default:0" json:"low_stock_threshold"`
	LastUpdated       time.Time `gorm:"type:datetime" json:"last_updated"`

	// Relationships
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
	Store   Store   `gorm:"foreignKey:StoreID" json:"store,omitempty"`
}

// RestockOrder represents a re-stock order
type RestockOrder struct {
	ID             uint       `gorm:"primaryKey" json:"id"`
	StoreID        uint       `gorm:"not null;index" json:"store_id"`
	InitiatedBy    uint       `gorm:"not null" json:"initiated_by"`
	TrackingNumber string     `json:"tracking_number"`
	Status         string     `gorm:"type:enum('initiated','in_transit','received','cancelled');default:'initiated'" json:"status"`
	InitiatedAt    time.Time  `gorm:"type:datetime" json:"initiated_at"`
	ReceivedAt     *time.Time `gorm:"type:datetime" json:"received_at,omitempty"`
	Notes          string     `json:"notes"`

	// Relationships
	Store     Store              `gorm:"foreignKey:StoreID" json:"store,omitempty"`
	Initiator User               `gorm:"foreignKey:InitiatedBy" json:"initiator,omitempty"`
	Items     []RestockOrderItem `json:"items,omitempty"`
}

// RestockOrderItem represents items in a re-stock order
type RestockOrderItem struct {
	ID             uint    `gorm:"primaryKey" json:"id"`
	RestockOrderID uint    `gorm:"not null;index" json:"restock_order_id"`
	ProductID      uint    `gorm:"not null" json:"product_id"`
	Quantity       float64 `gorm:"type:decimal(10,3);not null" json:"quantity"`

	// Relationships
	RestockOrder RestockOrder `gorm:"foreignKey:RestockOrderID" json:"restock_order,omitempty"`
	Product      Product      `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// Order represents a POS order
type Order struct {
	ID               uint       `gorm:"primaryKey" json:"id"`
	OrderNumber      string     `gorm:"type:varchar(100);uniqueIndex;not null" json:"order_number"`
	StoreID          uint       `gorm:"not null;index" json:"store_id"`
	UserID           uint       `gorm:"not null;index" json:"user_id"`
	DeviceCode       string     `json:"device_code"`
	SectorID         *uint      `json:"sector_id,omitempty"`
	Subtotal         float64    `gorm:"type:decimal(10,2);not null" json:"subtotal"`
	DiscountAmount   float64    `gorm:"type:decimal(10,2);default:0" json:"discount_amount"`
	TotalAmount      float64    `gorm:"type:decimal(10,2);not null" json:"total_amount"`
	Status           string     `gorm:"type:enum('pending','paid','completed','cancelled','picked_up');default:'pending'" json:"status"`
	QRCodeData       string     `gorm:"type:text" json:"qr_code_data"`
	InvoiceCheckCode string     `gorm:"type:varchar(4)" json:"invoice_check_code,omitempty"`
	ReceiptCheckCode string     `gorm:"type:varchar(4)" json:"receipt_check_code,omitempty"`
	CreatedAt        time.Time  `gorm:"type:datetime" json:"created_at"`
	PaidAt           *time.Time `gorm:"type:datetime" json:"paid_at,omitempty"`
	CompletedAt      *time.Time `gorm:"type:datetime" json:"completed_at,omitempty"`
	PickedUpAt       *time.Time `gorm:"type:datetime" json:"picked_up_at,omitempty"`

	// Relationships
	Store  Store       `gorm:"foreignKey:StoreID" json:"store,omitempty"`
	User   User        `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Sector *Sector     `gorm:"foreignKey:SectorID" json:"sector,omitempty"`
	Items  []OrderItem `json:"items,omitempty"`
}

// OrderItem represents an item in an order
type OrderItem struct {
	ID              uint    `gorm:"primaryKey" json:"id"`
	OrderID         uint    `gorm:"not null;index" json:"order_id"`
	ProductID       uint    `gorm:"not null" json:"product_id"`
	Quantity        float64 `gorm:"type:decimal(10,3);not null" json:"quantity"`
	UnitPrice       float64 `gorm:"type:decimal(10,2);not null" json:"unit_price"`
	DiscountPercent float64 `gorm:"type:decimal(5,2);default:0" json:"discount_percent"`
	DiscountAmount  float64 `gorm:"type:decimal(10,2);default:0" json:"discount_amount"`
	LineTotal       float64 `gorm:"type:decimal(10,2);not null" json:"line_total"`

	// Relationships
	Order   Order   `gorm:"foreignKey:OrderID" json:"order,omitempty"`
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// PriceHistory represents historical price data for trend graphs
type PriceHistory struct {
	ID               uint      `gorm:"primaryKey" json:"id"`
	ProductID        uint      `gorm:"not null;index" json:"product_id"`
	SectorID         *uint     `gorm:"index" json:"sector_id,omitempty"`
	WholesaleCostGBP float64   `gorm:"type:decimal(10,2);not null" json:"wholesale_cost_gbp"`
	DiscountPercent  float64   `gorm:"type:decimal(5,2);default:0" json:"discount_percent"`
	FinalPriceGBP    float64   `gorm:"type:decimal(10,2);not null" json:"final_price_gbp"`
	RecordedAt       time.Time `gorm:"type:datetime;index" json:"recorded_at"`

	// Relationships
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
	Sector  *Sector `gorm:"foreignKey:SectorID" json:"sector,omitempty"`
}

// CurrencyRate represents exchange rates for different currencies
type CurrencyRate struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	CurrencyCode string    `gorm:"uniqueIndex;not null;size:3" json:"currency_code"` // ISO 4217 code (e.g., USD, EUR, HKD, GBP)
	RateToGBP    float64   `gorm:"type:decimal(10,6);not null" json:"rate_to_gbp"`   // Rate to convert to GBP (base currency)
	IsPinned     bool      `gorm:"default:false" json:"is_pinned"`                   // Pin currency to show at top (for main purchasing currencies: CNY, USD, HKD, JPY)
	LastUpdated  time.Time `gorm:"type:datetime" json:"last_updated"`
	UpdatedBy    string    `json:"updated_by"` // "manual" or "api_sync"
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// AuditLog represents system audit logs
type AuditLog struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     *uint     `gorm:"index" json:"user_id,omitempty"`
	Action     string    `gorm:"not null;index" json:"action"`
	EntityType string    `json:"entity_type"`
	EntityID   *uint     `json:"entity_id,omitempty"`
	Changes    string    `gorm:"type:json" json:"changes"`
	IPAddress  string    `json:"ip_address"`
	UserAgent  string    `json:"user_agent"`
	CreatedAt  time.Time `gorm:"type:datetime;index" json:"created_at"`

	// Relationships
	User *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

// StocktakeInventorySnapshot records inventory quantity per product per store after a stocktake.
// One row per (store_id, product_id, snapshot_date, snapshot_type). Used for day-start/day-end stock report.
type StocktakeInventorySnapshot struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	StoreID      uint      `gorm:"not null;uniqueIndex:idx_stocktake_snapshot_store_product_date_type" json:"store_id"`
	ProductID    uint      `gorm:"not null;uniqueIndex:idx_stocktake_snapshot_store_product_date_type" json:"product_id"`
	Quantity     float64   `gorm:"type:decimal(10,3);not null" json:"quantity"`
	SnapshotDate string    `gorm:"type:date;not null;uniqueIndex:idx_stocktake_snapshot_store_product_date_type" json:"snapshot_date"`        // yyyy-MM-dd
	SnapshotType string    `gorm:"type:varchar(20);not null;uniqueIndex:idx_stocktake_snapshot_store_product_date_type" json:"snapshot_type"` // day_start, day_end
	CreatedAt    time.Time `gorm:"type:datetime;not null" json:"created_at"`

	Store   Store   `gorm:"foreignKey:StoreID" json:"store,omitempty"`
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// StocktakeDayStartRecord records first login of the day and day-start stocktake result (done or skipped with reason).
// One record per user per store per calendar day (user may work in multiple stores). Used for management timetable.
type StocktakeDayStartRecord struct {
	ID           uint       `gorm:"primaryKey" json:"id"`
	UserID       uint       `gorm:"not null;uniqueIndex:idx_stocktake_day_start_user_date_store" json:"user_id"`
	StoreID      *uint      `gorm:"uniqueIndex:idx_stocktake_day_start_user_date_store" json:"store_id,omitempty"`      // store where user did first login / stocktake
	Date         string     `gorm:"type:date;not null;uniqueIndex:idx_stocktake_day_start_user_date_store" json:"date"` // yyyy-MM-dd
	FirstLoginAt time.Time  `gorm:"type:datetime;not null" json:"first_login_at"`
	Status       string     `gorm:"type:varchar(20);not null;default:'pending'" json:"status"` // pending, done, skipped
	DoneAt       *time.Time `gorm:"type:datetime" json:"done_at,omitempty"`
	SkipReason   string     `gorm:"type:text" json:"skip_reason,omitempty"`
	CreatedAt    time.Time  `gorm:"type:datetime" json:"created_at"`
	UpdatedAt    time.Time  `gorm:"type:datetime" json:"updated_at"`

	// Relationships
	User  User   `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Store *Store `gorm:"foreignKey:StoreID" json:"store,omitempty"`
}

// UserActivityEvent stores login, logout, and stocktake events for history/audit.
// Used for timetable and for login/logout timeline.
const (
	EventFirstLogin               = "first_login"
	EventLogout                   = "logout"
	EventStocktakeDayStartDone    = "stocktake_day_start_done"
	EventStocktakeDayStartSkipped = "stocktake_day_start_skipped"
	EventStocktakeDayEndSkipped   = "stocktake_day_end_skipped"
)

type UserActivityEvent struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"not null;index" json:"user_id"`
	StoreID    *uint     `gorm:"index" json:"store_id,omitempty"`
	EventType  string    `gorm:"type:varchar(50);not null;index" json:"event_type"` // first_login, logout, stocktake_day_start_done, stocktake_day_start_skipped
	OccurredAt time.Time `gorm:"type:datetime;not null" json:"occurred_at"`
	SkipReason string    `gorm:"type:text" json:"skip_reason,omitempty"` // for stocktake_day_start_skipped
	CreatedAt  time.Time `gorm:"type:datetime" json:"created_at"`

	User  User   `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Store *Store `gorm:"foreignKey:StoreID" json:"store,omitempty"`
}

// WholesaleClient is a wholesale customer; required when creating a wholesale order.
type WholesaleClient struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	Name          string    `gorm:"type:varchar(200);not null;index" json:"name"`
	ContactName   string    `gorm:"type:varchar(200)" json:"contact_name,omitempty"`
	Email         string    `gorm:"type:varchar(255)" json:"email,omitempty"`
	Phone         string    `gorm:"type:varchar(100)" json:"phone,omitempty"`
	Address       string    `gorm:"type:text" json:"address,omitempty"`
	AddressLine1  string    `gorm:"type:varchar(255)" json:"address_line1,omitempty"`
	AddressLine2  string    `gorm:"type:varchar(255)" json:"address_line2,omitempty"`
	Postcode      string    `gorm:"type:varchar(50)" json:"postcode,omitempty"`
	VATNumber     string    `gorm:"type:varchar(50)" json:"vat_number,omitempty"`
	CompanyNumber string    `gorm:"type:varchar(50)" json:"company_number,omitempty"`
	Terms         string    `gorm:"type:varchar(500)" json:"terms,omitempty"` // Payment/order terms; shown in PDF headers
	AccountCode   string    `gorm:"type:varchar(50)" json:"account_code,omitempty"`
	SectorID      *uint     `gorm:"index" json:"sector_id,omitempty"`
	IsActive      bool      `gorm:"default:true" json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`

	Sector *Sector                `gorm:"foreignKey:SectorID" json:"sector,omitempty"`
	Stores []WholesaleClientStore `gorm:"foreignKey:WholesaleClientID" json:"stores,omitempty"`
}

// WholesaleClientStore is a delivery location belonging to a wholesale client.
type WholesaleClientStore struct {
	ID                uint      `gorm:"primaryKey" json:"id"`
	WholesaleClientID uint      `gorm:"not null;index" json:"wholesale_client_id"`
	Name              string    `gorm:"type:varchar(200);not null" json:"name"`
	AddressLine1      string    `gorm:"type:varchar(255)" json:"address_line1,omitempty"`
	AddressLine2      string    `gorm:"type:varchar(255)" json:"address_line2,omitempty"`
	City              string    `gorm:"type:varchar(100)" json:"city,omitempty"`
	Postcode          string    `gorm:"type:varchar(50)" json:"postcode,omitempty"`
	ContactName       string    `gorm:"type:varchar(200)" json:"contact_name,omitempty"`
	Email             string    `gorm:"type:varchar(255)" json:"email,omitempty"`
	Phone             string    `gorm:"type:varchar(100)" json:"phone,omitempty"`
	IsActive          bool      `gorm:"default:true" json:"is_active"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

// TableName overrides the default to avoid conflict with the old many2many join table.
func (WholesaleClientStore) TableName() string {
	return "wholesale_client_delivery_locations"
}

// WholesaleOrder is created by pos_user/admin and must be approved by management/supervisor.
const (
	WholesaleOrderStatusPending        = "pending_approval"
	WholesaleOrderStatusAssignShipment = "assign_shipment" // after endorse; assign stores then complete → approved
	WholesaleOrderStatusApproved       = "approved"
	WholesaleOrderStatusRejected       = "rejected"
	WholesaleOrderStatusDeleted        = "deleted" // soft-delete; excluded from default list unless filtered
)

type WholesaleOrder struct {
	ID                     uint       `gorm:"primaryKey" json:"id"`
	OrderNumber            string     `gorm:"type:varchar(100);uniqueIndex;not null" json:"order_number"`
	WholesaleClientID      uint       `gorm:"not null;index" json:"wholesale_client_id"`
	WholesaleClientStoreID *uint      `gorm:"index" json:"wholesale_client_store_id,omitempty"` // shipping/delivery address
	StoreID                uint       `gorm:"not null;index" json:"store_id"`
	UserID                 uint       `gorm:"not null;index" json:"user_id"` // creator
	SectorID               *uint      `gorm:"index" json:"sector_id,omitempty"`
	Status                 string     `gorm:"type:varchar(20);not null;default:'pending_approval';index" json:"status"`
	Subtotal               float64    `gorm:"type:decimal(10,2);not null;default:0" json:"subtotal"`
	DiscountAmount         float64    `gorm:"type:decimal(10,2);not null;default:0" json:"discount_amount"`
	TotalNet               float64    `gorm:"type:decimal(10,2);not null;default:0" json:"total_net"`
	VATTotal               float64    `gorm:"type:decimal(10,2);not null;default:0" json:"vat_total"`
	AmountDue              float64    `gorm:"type:decimal(10,2);not null;default:0" json:"amount_due"`
	ShippingFee            float64    `gorm:"type:decimal(10,2);default:0" json:"shipping_fee,omitempty"` // order-level shipping fee (invoice total)
	PONumber               string     `gorm:"type:varchar(100)" json:"po_number"`
	OrderChannel           string     `gorm:"type:varchar(80)" json:"order_channel,omitempty"` // "po" = client PO; "whatsapp", "email" or free text
	RefNo                  string     `gorm:"type:varchar(100);uniqueIndex" json:"ref_no"`     // OC Number: D1, D2, D2.1...
	PODate                 *time.Time `gorm:"type:date" json:"po_date,omitempty"`
	OrderDate              *time.Time `gorm:"type:date" json:"order_date,omitempty"`            // used on OC "Date:"
	InvoiceDate            *time.Time `gorm:"type:date" json:"invoice_date,omitempty"`          // used on invoice "Date:"; editable, default to current date when empty
	InvoiceSentAt          *time.Time `gorm:"type:date" json:"invoice_sent_at,omitempty"`       // optional: when invoice was sent to client (operational)
	PaymentTerms           string     `gorm:"type:varchar(500)" json:"payment_terms,omitempty"` // shown on OC, invoice, delivery note; defaults from client
	Notes                  string     `gorm:"type:text" json:"notes"`
	RejectionReason        string     `gorm:"type:text" json:"rejection_reason,omitempty"`
	CreatedAt              time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	ReviewedAt             *time.Time `gorm:"type:datetime" json:"reviewed_at,omitempty"`
	ReviewedBy             *uint      `gorm:"index" json:"reviewed_by,omitempty"`
	PaymentConfirmedAt     *time.Time `gorm:"type:datetime" json:"payment_confirmed_at,omitempty"` // when money received confirmed
	PaymentProofURL        string     `gorm:"type:text" json:"payment_proof_url,omitempty"`        // uploaded image/PDF (or bank API later)

	WholesaleClient      WholesaleClient          `gorm:"foreignKey:WholesaleClientID" json:"wholesale_client,omitempty"`
	WholesaleClientStore *WholesaleClientStore    `gorm:"foreignKey:WholesaleClientStoreID" json:"wholesale_client_store,omitempty"`
	Store                Store                    `gorm:"foreignKey:StoreID" json:"store,omitempty"`
	User                 User                     `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Sector               *Sector                  `gorm:"foreignKey:SectorID" json:"sector,omitempty"`
	Reviewer             *User                    `gorm:"foreignKey:ReviewedBy" json:"reviewer,omitempty"`
	Items                []WholesaleOrderItem     `json:"items,omitempty"`
	Documents            []WholesaleOrderDocument `json:"documents,omitempty"`
	Shipments            []Shipment               `json:"shipments,omitempty"`

	// IsCompleted is computed server-side for list views; true when all shipments done and payment confirmed
	IsCompleted bool `json:"is_completed,omitempty" gorm:"-"`

	// Workflow fields are computed server-side for list/detail status alignment (not persisted).
	WorkflowInvoiceEmailDone  bool     `json:"workflow_invoice_email_done,omitempty" gorm:"-"`
	WorkflowPaymentProofTotal *float64 `json:"workflow_payment_proof_total,omitempty" gorm:"-"`
}

type WholesaleOrderItem struct {
	ID                 uint    `gorm:"primaryKey" json:"id"`
	WholesaleOrderID   uint    `gorm:"not null;index" json:"wholesale_order_id"`
	ProductID          uint    `gorm:"not null" json:"product_id"`
	Quantity           float64 `gorm:"type:decimal(10,3);not null" json:"quantity"`
	UnitPrice          float64 `gorm:"type:decimal(10,2);not null" json:"unit_price"` // fixed from product cost
	LineDiscountType   string  `gorm:"type:varchar(32);not null;default:'order_entry'" json:"line_discount_type"`
	LineDiscountUnit   float64 `gorm:"type:decimal(10,2);not null;default:0" json:"line_discount_unit"`
	LineDiscountAmount float64 `gorm:"type:decimal(10,2);not null;default:0" json:"line_discount_amount"`
	LineTotal          float64 `gorm:"type:decimal(10,2);not null" json:"line_total"` // UnitPrice*Quantity - LineDiscountAmount
	AssignedStoreID    *uint   `gorm:"index" json:"assigned_store_id,omitempty"`      // nil = no store assigned (any store can pack)

	WholesaleOrder WholesaleOrder `gorm:"foreignKey:WholesaleOrderID" json:"-"`
	Product        Product        `gorm:"foreignKey:ProductID" json:"product,omitempty"`
	AssignedStore  *Store         `gorm:"foreignKey:AssignedStoreID" json:"assigned_store,omitempty"`
}

// WholesaleOrderDocument stores generated PDFs (order confirmation, delivery notes, invoices) and user-uploaded PO attachments.
type WholesaleOrderDocument struct {
	ID               uint      `gorm:"primaryKey" json:"id"`
	WholesaleOrderID uint      `gorm:"not null;index" json:"wholesale_order_id"`
	Type             string    `gorm:"type:varchar(50);not null;index" json:"type"` // order_confirmation, delivery_note, invoice, po_attachment
	FileURL          string    `gorm:"type:text;not null" json:"file_url"`
	OriginalFilename string    `gorm:"type:varchar(255)" json:"original_filename,omitempty"` // display name for po_attachment (user's file name)
	CreatedAt        time.Time `gorm:"type:datetime;not null" json:"created_at"`

	WholesaleOrder WholesaleOrder `gorm:"foreignKey:WholesaleOrderID" json:"-"`
}

// Shipment groups assigned order lines for one store; created when assigning lines to a store.
const (
	ShipmentStatusAssigned  = "assigned"
	ShipmentStatusPacked    = "packed"
	ShipmentStatusShipped   = "shipped"
	ShipmentStatusCompleted = "completed"
	// ShipmentStatusPacking is legacy; treat as assigned when reading.
	ShipmentStatusPacking = "packing"
)

func ShipmentStatusIsCompleted(status string) bool {
	return status == ShipmentStatusCompleted
}

func ShipmentStatusAllowsPacking(status string) bool {
	return status == ShipmentStatusAssigned || status == ShipmentStatusPacking
}

func ShipmentStatusAllowsDeliveryProofUpload(status string) bool {
	return status == ShipmentStatusPacked || status == ShipmentStatusShipped
}

type Shipment struct {
	ID                       uint       `gorm:"primaryKey" json:"id"`
	WholesaleOrderID         uint       `gorm:"not null;index" json:"wholesale_order_id"`
	StoreID                  uint       `gorm:"not null;index" json:"store_id"`
	Courier                  string     `gorm:"type:varchar(100)" json:"courier,omitempty"`
	TrackingNumber           string     `gorm:"type:varchar(200)" json:"tracking_number,omitempty"`
	ShipmentFee              float64    `gorm:"type:decimal(10,2);default:0" json:"shipment_fee,omitempty"`
	DeliveryNotePDFURL       string     `gorm:"type:text" json:"delivery_note_pdf_url,omitempty"`
	SignedDeliveryNotePDFURL string     `gorm:"type:text" json:"signed_delivery_note_pdf_url,omitempty"` // uploaded when completing without courier tracking
	DeliveryDate             *time.Time `gorm:"type:date" json:"delivery_date,omitempty"`                // set when completing shipment (used on delivery note PDF)
	Status                   string     `gorm:"type:varchar(20);not null;default:'assigned';index" json:"status"`
	CreatedAt                time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt                time.Time  `gorm:"type:datetime;not null" json:"updated_at"`

	WholesaleOrder WholesaleOrder `gorm:"foreignKey:WholesaleOrderID" json:"wholesale_order,omitempty"`
	Store          Store          `gorm:"foreignKey:StoreID" json:"store,omitempty"`
	Items          []ShipmentItem `json:"items,omitempty"`
}

// ShipmentItem links a shipment to one wholesale order item (for packing and delivery note).
type ShipmentItem struct {
	ID                   uint      `gorm:"primaryKey" json:"id"`
	ShipmentID           uint      `gorm:"not null;uniqueIndex:idx_shipment_wo_item" json:"shipment_id"`
	WholesaleOrderItemID uint      `gorm:"not null;uniqueIndex:idx_shipment_wo_item" json:"wholesale_order_item_id"`
	Quantity             float64   `gorm:"type:decimal(10,3);default:0" json:"quantity,omitempty"`   // units in this shipment; 0 = legacy full line qty
	CaseQty              float64   `gorm:"type:decimal(10,2);default:0" json:"case_qty,omitempty"` // number of cases/boxes (0 = show '-' on delivery note)
	CreatedAt            time.Time `gorm:"type:datetime;not null" json:"created_at"`

	Shipment           Shipment           `gorm:"foreignKey:ShipmentID" json:"-"`
	WholesaleOrderItem WholesaleOrderItem `gorm:"foreignKey:WholesaleOrderItemID" json:"wholesale_order_item,omitempty"`
}

// CompanySettings stores configurable company address, contact and bank details for PDFs (singleton, ID=1).
type CompanySettings struct {
	ID                    uint      `gorm:"primaryKey" json:"id"`
	CompanyName           string    `gorm:"type:varchar(255)" json:"company_name"`
	LogoURL               string    `gorm:"type:text" json:"logo_url"` // legacy; use pdf/web/pos fields
	PdfLogoURL            string    `gorm:"type:text" json:"pdf_logo_url"`
	WebLogoURL            string    `gorm:"type:text" json:"web_logo_url"`
	PosLogoURL            string    `gorm:"type:text" json:"pos_logo_url"`
	AddressLine1          string    `gorm:"type:varchar(255)" json:"address_line1"`
	AddressLine2          string    `gorm:"type:varchar(255)" json:"address_line2"`
	City                  string    `gorm:"type:varchar(100)" json:"city"`
	Postcode              string    `gorm:"type:varchar(20)" json:"postcode"`
	Telephone             string    `gorm:"type:varchar(50)" json:"telephone"`
	Email                 string    `gorm:"type:varchar(255)" json:"email"`
	BankAccountName       string    `gorm:"type:varchar(255)" json:"bank_account_name"`
	BankAccountNumber     string    `gorm:"type:varchar(50)" json:"bank_account_number"`
	BankSortCode          string    `gorm:"type:varchar(20)" json:"bank_sort_code"`
	BankAddress           string    `gorm:"type:varchar(255)" json:"bank_address"`
	BankIBAN              string    `gorm:"type:varchar(50)" json:"bank_iban"`
	PaymentInfo           string    `gorm:"type:text" json:"payment_info"`             // Free-form payment details (max 5 lines), shown on invoice
	PaymentTransferToInfo string    `gorm:"type:text" json:"payment_transfer_to_info"` // Transfer destination options (first line skipped), used for payment confirmation
	ShipmentCouriers      string    `gorm:"type:text" json:"shipment_couriers"`        // One courier per line; start-shipment autocomplete in management UI
	// Placeholders: {ref}, {status}, {order_number}, {client_name}. Empty = built-in default.
	WholesaleOrderEmailSubjectTemplate string `gorm:"type:varchar(500)" json:"wholesale_order_email_subject_template"`
	// Default Cc when sending wholesale order emails from management UI. Empty = company email.
	WholesaleOrderEmailDefaultCC string `gorm:"type:text" json:"wholesale_order_email_default_cc"` // One email per line; empty = no default Cc on wholesale order emails
	// Default Bcc when sending wholesale order emails from management UI.
	WholesaleOrderEmailDefaultBCC string `gorm:"type:text" json:"wholesale_order_email_default_bcc"`
	WholesaleOrderEnabled    bool   `gorm:"default:true" json:"wholesale_order_enabled"`
	WholesaleSerialActivated bool   `gorm:"default:false" json:"wholesale_serial_activated"`
	PosModuleEnabled         bool   `gorm:"default:true" json:"pos_module_enabled"`
	PosDlcActivated          bool   `gorm:"default:false" json:"pos_dlc_activated"`
	InstallationID             string `gorm:"type:varchar(64)" json:"installation_id"`
	SystemFingerprint          string `gorm:"type:varchar(128)" json:"-"` // legacy; migrated to installation_id
	UpdatedAt                    time.Time `json:"updated_at"`
}
