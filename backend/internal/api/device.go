package api

import (
	"net/http"
	"strings"
	"time"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type DeviceHandler struct {
	db *gorm.DB
}

func NewDeviceHandler(db *gorm.DB) *DeviceHandler {
	return &DeviceHandler{db: db}
}

// normalizeDeviceCodeForStorage wraps device code with braces for database storage
// Input: "xxxxx" -> Output: "{xxxxx}"
// If already wrapped, returns as-is
func normalizeDeviceCodeForStorage(deviceCode string) string {
	deviceCode = strings.TrimSpace(deviceCode)
	if strings.HasPrefix(deviceCode, "{") && strings.HasSuffix(deviceCode, "}") {
		return deviceCode
	}
	return "{" + deviceCode + "}"
}

// normalizeDeviceCodeForLookup strips braces from device code for URL parameter
// Input: "{xxxxx}" or "xxxxx" -> Output: "xxxxx"
func normalizeDeviceCodeForLookup(deviceCode string) string {
	deviceCode = strings.TrimSpace(deviceCode)
	if strings.HasPrefix(deviceCode, "{") && strings.HasSuffix(deviceCode, "}") {
		return deviceCode[1 : len(deviceCode)-1]
	}
	return deviceCode
}

type RegisterDeviceRequest struct {
	DeviceCode string `json:"device_code" binding:"required"`
	StoreID    uint   `json:"store_id" binding:"required"`
	DeviceName string `json:"device_name"`
}

func (h *DeviceHandler) RegisterDevice(c *gin.Context) {
	var req RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Normalize device code for storage (wrap with braces)
	normalizedDeviceCode := normalizeDeviceCodeForStorage(req.DeviceCode)

	// Check if device already exists
	var device models.POSDevice
	if err := h.db.Where("device_code = ?", normalizedDeviceCode).First(&device).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Device already registered"})
		return
	}

	device = models.POSDevice{
		DeviceCode: normalizedDeviceCode,
		StoreID:    req.StoreID,
		DeviceName: req.DeviceName,
		IsActive:   true,
	}

	if err := h.db.Create(&device).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, device)
}

// ConfigureDeviceRequest is the body for PUT /device/configure (add or update device store)
type ConfigureDeviceRequest struct {
	DeviceCode string `json:"device_code" binding:"required"`
	StoreID    uint   `json:"store_id" binding:"required"`
	DeviceName string `json:"device_name"`
}

// ConfigureDevice adds this device to a store or updates its store (management only).
func (h *DeviceHandler) ConfigureDevice(c *gin.Context) {
	role, _ := c.Get("role")
	if role != "management" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only management can configure devices"})
		return
	}

	var req ConfigureDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	normalizedDeviceCode := normalizeDeviceCodeForStorage(req.DeviceCode)

	var device models.POSDevice
	err := h.db.Where("device_code = ?", normalizedDeviceCode).First(&device).Error
	if err != nil {
		// Create new device
		device = models.POSDevice{
			DeviceCode: normalizedDeviceCode,
			StoreID:    req.StoreID,
			DeviceName: req.DeviceName,
			IsActive:   true,
		}
		if err := h.db.Create(&device).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusCreated, device)
		return
	}

	// Update existing device
	updates := map[string]interface{}{"store_id": req.StoreID}
	if req.DeviceName != "" {
		updates["device_name"] = req.DeviceName
	}
	if err := h.db.Model(&device).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := h.db.Preload("Store").First(&device, device.ID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, device)
}

func (h *DeviceHandler) GetUsersForDevice(c *gin.Context) {
	// Get device code from URL parameter and normalize it (strip braces if present)
	rawDeviceCode := c.Param("device_code")
	// Normalize for lookup: strip braces from URL parameter, then wrap for database lookup
	normalizedDeviceCode := normalizeDeviceCodeForStorage(normalizeDeviceCodeForLookup(rawDeviceCode))

	var device models.POSDevice
	if err := h.db.Where("device_code = ? AND is_active = ?", normalizedDeviceCode, true).
		Preload("Store").First(&device).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		return
	}

	// Get users assigned to this store
	var users []models.User
	if err := h.db.Table("users").
		Joins("JOIN user_stores ON users.id = user_stores.user_id").
		Where("user_stores.store_id = ? AND users.is_active = ? AND users.role IN (?, ?, ?)",
			device.StoreID, true, "pos_user", "supervisor", "management").
		Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Clear sensitive data
	for i := range users {
		users[i].PasswordHash = ""
		users[i].PINHash = ""
	}

	c.JSON(http.StatusOK, users)
}

// GetDeviceInfo returns device info including last_stocktake_at for the device's store (public).
// last_stocktake_at is the latest occurred_at for event_type = stocktake_day_start_done only (skip does not clear reminder).
func (h *DeviceHandler) GetDeviceInfo(c *gin.Context) {
	rawDeviceCode := c.Param("device_code")
	normalizedDeviceCode := normalizeDeviceCodeForStorage(normalizeDeviceCodeForLookup(rawDeviceCode))

	var device models.POSDevice
	if err := h.db.Where("device_code = ? AND is_active = ?", normalizedDeviceCode, true).
		Preload("Store").First(&device).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		return
	}

	var lastAt *time.Time
	var out struct {
		MaxAt *time.Time `gorm:"column:max_at"`
	}
	err := h.db.Model(&models.UserActivityEvent{}).
		Select("MAX(occurred_at) AS max_at").
		Where("store_id = ? AND event_type = ?", device.StoreID, models.EventStocktakeDayStartDone).
		Scan(&out).Error
	if err == nil && out.MaxAt != nil {
		lastAt = out.MaxAt
	}

	deviceCodeDisplay := normalizeDeviceCodeForLookup(device.DeviceCode)
	resp := gin.H{
		"device_code": deviceCodeDisplay,
		"store_id":    device.StoreID,
		"device_name": device.DeviceName,
	}
	if lastAt != nil {
		resp["last_stocktake_at"] = lastAt.Format(time.RFC3339)
	} else {
		resp["last_stocktake_at"] = nil
	}
	c.JSON(http.StatusOK, resp)
}

func (h *DeviceHandler) GetProductsForDevice(c *gin.Context) {
	// Get device code from URL parameter and normalize it (strip braces if present)
	rawDeviceCode := c.Param("device_code")
	// Normalize for lookup: strip braces from URL parameter, then wrap for database lookup
	normalizedDeviceCode := normalizeDeviceCodeForStorage(normalizeDeviceCodeForLookup(rawDeviceCode))

	var device models.POSDevice
	if err := h.db.Where("device_code = ? AND is_active = ?", normalizedDeviceCode, true).First(&device).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		return
	}

	// Get all active products with current costs
	var products []models.Product
	if err := h.db.Where("is_active = ?", true).Find(&products).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Get store to potentially get default sector (for now, use 0% discount as default)
	var store models.Store
	var defaultSectorDiscountRate float64 = 0.0
	if err := h.db.First(&store, device.StoreID).Error; err == nil {
		// TODO: If store has a default sector in the future, get its discount rate here
		// For now, default to 0% discount
	}

	// Load current costs and discounts
	now := time.Now()
	for i := range products {
		// Get current cost
		var cost models.ProductCost
		h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", products[i].ID, now).
			Order("effective_from DESC").First(&cost)
		products[i].CurrentCost = &cost

		// Get discounts for all sectors
		var discounts []models.ProductSectorDiscount
		h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", products[i].ID, now).
			Find(&discounts)
		products[i].Discounts = discounts
	}

	// Create response with calculated POS price
	type ProductResponse struct {
		models.Product
		POSPrice float64 `json:"pos_price"` // Calculated price for POS: direct_retail_online_store_price_gbp * (1 - sector_discount_rate)
	}

	var productResponses []ProductResponse
	for _, product := range products {
		posPrice := 0.0
		if product.CurrentCost != nil {
			// Use Direct Retail Online Store Price, fallback to WholesaleCostGBP if not set
			basePrice := product.CurrentCost.DirectRetailOnlineStorePriceGBP
			if basePrice <= 0 {
				basePrice = product.CurrentCost.WholesaleCostGBP
			}
			// Calculate POS price: basePrice * (1 - sector_discount_rate)
			// Default sector discount rate is 0 if not set
			posPrice = basePrice * (1 - defaultSectorDiscountRate/100.0)
		}

		productResponses = append(productResponses, ProductResponse{
			Product:  product,
			POSPrice: posPrice,
		})
	}

	c.JSON(http.StatusOK, productResponses)
}

// ListDevices lists all devices (protected endpoint for management)
func (h *DeviceHandler) ListDevices(c *gin.Context) {
	var devices []models.POSDevice
	if err := h.db.Preload("Store").Find(&devices).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, devices)
}

// GetDevice gets a device by ID (protected endpoint for management)
func (h *DeviceHandler) GetDevice(c *gin.Context) {
	var device models.POSDevice
	if err := h.db.Preload("Store").First(&device, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		return
	}

	c.JSON(http.StatusOK, device)
}

// ListDevicesByStore lists devices for a specific store
func (h *DeviceHandler) ListDevicesByStore(c *gin.Context) {
	storeID := c.Param("store_id")
	var devices []models.POSDevice
	if err := h.db.Where("store_id = ?", storeID).Preload("Store").Find(&devices).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, devices)
}
