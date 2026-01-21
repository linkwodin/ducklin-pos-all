package api

import (
	"net/http"
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

	// Check if device already exists
	var device models.POSDevice
	if err := h.db.Where("device_code = ?", req.DeviceCode).First(&device).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Device already registered"})
		return
	}

	device = models.POSDevice{
		DeviceCode: req.DeviceCode,
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

func (h *DeviceHandler) GetUsersForDevice(c *gin.Context) {
	deviceCode := c.Param("device_code")

	var device models.POSDevice
	if err := h.db.Where("device_code = ? AND is_active = ?", deviceCode, true).
		Preload("Store").First(&device).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		return
	}

	// Get users assigned to this store
	var users []models.User
	if err := h.db.Table("users").
		Joins("JOIN user_stores ON users.id = user_stores.user_id").
		Where("user_stores.store_id = ? AND users.is_active = ? AND users.role IN (?, ?)",
			device.StoreID, true, "pos_user", "supervisor").
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

func (h *DeviceHandler) GetProductsForDevice(c *gin.Context) {
	deviceCode := c.Param("device_code")

	var device models.POSDevice
	if err := h.db.Where("device_code = ? AND is_active = ?", deviceCode, true).First(&device).Error; err != nil {
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
