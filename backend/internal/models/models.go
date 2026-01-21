package models

import (
	"time"
)

// User represents a system user
type User struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Username     string    `gorm:"uniqueIndex;not null" json:"username"`
	PasswordHash string    `gorm:"not null" json:"-"`
	PINHash      string    `json:"-"`
	FirstName    string    `gorm:"not null" json:"first_name"`
	LastName     string    `gorm:"not null" json:"last_name"`
	Email        string    `json:"email"`
	Role         string    `gorm:"type:enum('management','pos_user','supervisor');not null" json:"role"`
	IconURL      string    `json:"icon_url"`
	IconColor    string    `json:"icon_color"`
	IsActive     bool      `gorm:"default:true" json:"is_active"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Relationships
	Stores []Store `gorm:"many2many:user_stores;" json:"stores,omitempty"`
}

// Store represents a physical store location
type Store struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"not null" json:"name"`
	Address   string    `json:"address"`
	IsActive  bool      `gorm:"default:true" json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`

	// Relationships
	Users      []User      `gorm:"many2many:user_stores;" json:"users,omitempty"`
	POSDevices []POSDevice `json:"pos_devices,omitempty"`
	Stock      []Stock     `json:"stock,omitempty"`
}

// POSDevice represents a POS device/computer
type POSDevice struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	DeviceCode string    `gorm:"uniqueIndex;not null" json:"device_code"`
	StoreID    uint      `gorm:"not null" json:"store_id"`
	DeviceName string    `json:"device_name"`
	IsActive   bool      `gorm:"default:true" json:"is_active"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`

	// Relationships
	Store Store `gorm:"foreignKey:StoreID" json:"store,omitempty"`
}

// Sector represents a customer sector (wholesaler, restaurant, etc.)
type Sector struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `gorm:"uniqueIndex;not null" json:"name"`
	Description  string    `json:"description"`
	DiscountRate float64   `gorm:"type:decimal(5,2);default:0" json:"discount_rate"` // Base discount rate for this sector (%)
	IsActive     bool      `gorm:"default:true" json:"is_active"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Product represents a product/item
type Product struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	Name        string    `gorm:"not null" json:"name"`
	NameChinese string    `json:"name_chinese"`
	Barcode     string    `gorm:"uniqueIndex" json:"barcode"`
	SKU         string    `gorm:"uniqueIndex" json:"sku"`
	Category    string    `json:"category"`
	ImageURL    string    `json:"image_url"`
	UnitType    string    `gorm:"type:enum('quantity','weight');default:'quantity'" json:"unit_type"`
	IsActive    bool      `gorm:"default:true" json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`

	// Relationships
	CurrentCost *ProductCost            `gorm:"-" json:"current_cost,omitempty"`
	Discounts   []ProductSectorDiscount `json:"discounts,omitempty"`
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
	EffectiveFrom                   time.Time  `gorm:"default:CURRENT_TIMESTAMP" json:"effective_from"`
	EffectiveTo                     *time.Time `json:"effective_to,omitempty"`
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
	EffectiveFrom   time.Time  `gorm:"default:CURRENT_TIMESTAMP" json:"effective_from"`
	EffectiveTo     *time.Time `json:"effective_to,omitempty"`
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
	LowStockThreshold float64   `gorm:"type:decimal(10,3);default:0" json:"low_stock_threshold"`
	LastUpdated       time.Time `gorm:"default:CURRENT_TIMESTAMP" json:"last_updated"`

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
	InitiatedAt    time.Time  `gorm:"default:CURRENT_TIMESTAMP" json:"initiated_at"`
	ReceivedAt     *time.Time `json:"received_at,omitempty"`
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
	ID             uint       `gorm:"primaryKey" json:"id"`
	OrderNumber    string     `gorm:"uniqueIndex;not null" json:"order_number"`
	StoreID        uint       `gorm:"not null;index" json:"store_id"`
	UserID         uint       `gorm:"not null;index" json:"user_id"`
	DeviceCode     string     `json:"device_code"`
	SectorID       *uint      `json:"sector_id,omitempty"`
	Subtotal       float64    `gorm:"type:decimal(10,2);not null" json:"subtotal"`
	DiscountAmount float64    `gorm:"type:decimal(10,2);default:0" json:"discount_amount"`
	TotalAmount    float64    `gorm:"type:decimal(10,2);not null" json:"total_amount"`
	Status         string     `gorm:"type:enum('pending','paid','completed','cancelled');default:'pending'" json:"status"`
	QRCodeData     string     `gorm:"type:text" json:"qr_code_data"`
	CreatedAt      time.Time  `gorm:"default:CURRENT_TIMESTAMP" json:"created_at"`
	PaidAt         *time.Time `json:"paid_at,omitempty"`
	CompletedAt    *time.Time `json:"completed_at,omitempty"`

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
	RecordedAt       time.Time `gorm:"default:CURRENT_TIMESTAMP;index" json:"recorded_at"`

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
	LastUpdated  time.Time `gorm:"default:CURRENT_TIMESTAMP" json:"last_updated"`
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
	CreatedAt  time.Time `gorm:"default:CURRENT_TIMESTAMP;index" json:"created_at"`

	// Relationships
	User *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}
