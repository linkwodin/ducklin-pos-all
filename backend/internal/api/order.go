package api

import (
	"fmt"
	"net/http"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type OrderHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewOrderHandler(db *gorm.DB, cfg *config.Config) *OrderHandler {
	return &OrderHandler{db: db, cfg: cfg}
}

type CreateOrderRequest struct {
	StoreID    uint   `json:"store_id" binding:"required"`
	DeviceCode string `json:"device_code"`
	SectorID   *uint  `json:"sector_id"`
	Items      []struct {
		ProductID uint    `json:"product_id" binding:"required"`
		Quantity  float64 `json:"quantity" binding:"required"`
		UnitType  string  `json:"unit_type"` // "quantity" or "weight" (gram)
	} `json:"items" binding:"required"`
}

func (h *OrderHandler) CreateOrder(c *gin.Context) {
	userIDInterface, _ := c.Get("user_id")
	userID := userIDInterface.(uint)

	var req CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Generate order number
	orderNumber := fmt.Sprintf("ORD-%s-%d", time.Now().Format("20060102"), time.Now().Unix()%10000)

	// Calculate totals
	var subtotal float64
	var discountAmount float64
	var orderItems []models.OrderItem

	now := time.Now()
	for _, item := range req.Items {
		// Get product with current cost
		var product models.Product
		if err := h.db.First(&product, item.ProductID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": fmt.Sprintf("Product %d not found", item.ProductID)})
			return
		}

		// Get current cost
		var cost models.ProductCost
		if err := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, now).
			Order("effective_from DESC").First(&cost).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Cost not found for product %d", product.ID)})
			return
		}

		// Use Direct Retail Online Store Price as base, fallback to WholesaleCostGBP if not set
		basePrice := cost.DirectRetailOnlineStorePriceGBP
		if basePrice <= 0 {
			basePrice = cost.WholesaleCostGBP
		}

		// Get sector discount rate if sector is provided
		var sectorDiscountRate float64
		if req.SectorID != nil {
			var sector models.Sector
			if err := h.db.First(&sector, *req.SectorID).Error; err == nil {
				sectorDiscountRate = sector.DiscountRate
			}
		}

		// Get product-specific discount for sector if provided
		var productDiscountPercent float64
		if req.SectorID != nil {
			var discount models.ProductSectorDiscount
			if err := h.db.Where("product_id = ? AND sector_id = ? AND (effective_to IS NULL OR effective_to > ?)",
				product.ID, *req.SectorID, now).Order("effective_from DESC").First(&discount).Error; err == nil {
				productDiscountPercent = discount.DiscountPercent
			}
		}

		// Apply discounts: base price * (1 - sector discount / 100) * (1 - product discount / 100)
		priceAfterSectorDiscount := basePrice * (1 - sectorDiscountRate/100.0)
		unitPrice := priceAfterSectorDiscount * (1 - productDiscountPercent/100.0)
		totalDiscountPercent := sectorDiscountRate + productDiscountPercent

		lineDiscount := basePrice * (totalDiscountPercent / 100.0) * item.Quantity
		lineTotal := (unitPrice * item.Quantity)

		subtotal += basePrice * item.Quantity
		discountAmount += lineDiscount

		orderItems = append(orderItems, models.OrderItem{
			ProductID:       item.ProductID,
			Quantity:        item.Quantity,
			UnitPrice:       unitPrice,
			DiscountPercent: totalDiscountPercent,
			DiscountAmount:  lineDiscount,
			LineTotal:       lineTotal,
		})
	}

	totalAmount := subtotal - discountAmount

	// Generate QR code data
	qrData := map[string]interface{}{
		"order_number": orderNumber,
		"subtotal":     subtotal,
		"discount":     discountAmount,
		"total":        totalAmount,
		"created_at":   now.Format(time.RFC3339),
	}

	order := models.Order{
		OrderNumber:    orderNumber,
		StoreID:        req.StoreID,
		UserID:         userID,
		DeviceCode:     req.DeviceCode,
		SectorID:       req.SectorID,
		Subtotal:       subtotal,
		DiscountAmount: discountAmount,
		TotalAmount:    totalAmount,
		Status:         "pending",
		QRCodeData:     fmt.Sprintf("%v", qrData),
		CreatedAt:      now,
	}

	if err := h.db.Create(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create order items
	for i := range orderItems {
		orderItems[i].OrderID = order.ID
		h.db.Create(&orderItems[i])
	}

	// Record price history for each product
	for _, item := range orderItems {
		var cost models.ProductCost
		h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", item.ProductID, now).
			Order("effective_from DESC").First(&cost)

		// Use Direct Retail Online Store Price for price history, fallback to WholesaleCostGBP
		basePriceForHistory := cost.DirectRetailOnlineStorePriceGBP
		if basePriceForHistory <= 0 {
			basePriceForHistory = cost.WholesaleCostGBP
		}
		finalPrice := item.UnitPrice
		h.recordPriceHistory(item.ProductID, req.SectorID, basePriceForHistory, item.DiscountPercent, finalPrice)
	}

	h.db.Preload("Store").Preload("User").Preload("Sector").Preload("Items.Product").First(&order, order.ID)

	c.JSON(http.StatusCreated, order)
}

func (h *OrderHandler) GetOrder(c *gin.Context) {
	var order models.Order
	if err := h.db.Preload("Store").Preload("User").Preload("Sector").
		Preload("Items.Product").First(&order, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}

	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) MarkPaid(c *gin.Context) {
	var order models.Order
	if err := h.db.First(&order, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}

	now := time.Now()
	order.Status = "paid"
	order.PaidAt = &now

	if err := h.db.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) MarkComplete(c *gin.Context) {
	var order models.Order
	if err := h.db.Preload("Items").First(&order, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}

	if order.Status != "paid" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be paid before completion"})
		return
	}

	now := time.Now()
	order.Status = "completed"
	order.CompletedAt = &now

	if err := h.db.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Reduce stock
	for _, item := range order.Items {
		var stock models.Stock
		if err := h.db.Where("product_id = ? AND store_id = ?", item.ProductID, order.StoreID).
			First(&stock).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Stock not found for product %d", item.ProductID)})
			return
		}

		stock.Quantity -= item.Quantity
		if stock.Quantity < 0 {
			stock.Quantity = 0
		}
		stock.LastUpdated = time.Now()
		h.db.Save(&stock)
	}

	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) recordPriceHistory(productID uint, sectorID *uint, wholesaleCost, discountPercent, finalPrice float64) {
	history := models.PriceHistory{
		ProductID:        productID,
		SectorID:         sectorID,
		WholesaleCostGBP: wholesaleCost,
		DiscountPercent:  discountPercent,
		FinalPriceGBP:    finalPrice,
		RecordedAt:       time.Now(),
	}
	h.db.Create(&history)
}
