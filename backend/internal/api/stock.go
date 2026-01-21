package api

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type StockHandler struct {
	db *gorm.DB
}

func NewStockHandler(db *gorm.DB) *StockHandler {
	return &StockHandler{db: db}
}

func (h *StockHandler) ListStock(c *gin.Context) {
	var stock []models.Stock
	query := h.db.Preload("Product").Preload("Store")

	if storeID := c.Query("store_id"); storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}

	if err := query.Find(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stock)
}

func (h *StockHandler) GetStoreStock(c *gin.Context) {
	var stock []models.Stock
	if err := h.db.Where("store_id = ?", c.Param("store_id")).
		Preload("Product").Find(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stock)
}

func (h *StockHandler) GetLowStock(c *gin.Context) {
	var stock []models.Stock
	if err := h.db.Where("quantity <= low_stock_threshold").
		Preload("Product").Preload("Store").Find(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stock)
}

func (h *StockHandler) UpdateStock(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uint)

	var stock models.Stock
	productIDStr := c.Param("product_id")
	storeIDStr := c.Param("store_id")

	oldQuantity := 0.0
	if err := h.db.Where("product_id = ? AND store_id = ?",
		productIDStr, storeIDStr).First(&stock).Error; err != nil {
		// Create if doesn't exist
		productID, _ := strconv.ParseUint(productIDStr, 10, 32)
		storeID, _ := strconv.ParseUint(storeIDStr, 10, 32)
		stock = models.Stock{
			ProductID: uint(productID),
			StoreID:   uint(storeID),
		}
	} else {
		oldQuantity = stock.Quantity
	}

	var req struct {
		Quantity          float64 `json:"quantity"`
		LowStockThreshold float64 `json:"low_stock_threshold"`
		Reason            string  `json:"reason"` // Reason for the update (e.g., "manual adjustment", "received stock", etc.)
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stock.Quantity = req.Quantity
	stock.LowStockThreshold = req.LowStockThreshold
	stock.LastUpdated = time.Now()

	if err := h.db.Save(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Record audit log
	changes := map[string]interface{}{
		"product_id":   stock.ProductID,
		"store_id":     stock.StoreID,
		"old_quantity": oldQuantity,
		"new_quantity": stock.Quantity,
		"reason":       req.Reason,
	}
	changesJSON, _ := json.Marshal(changes)
	auditLog := models.AuditLog{
		UserID:     &userID,
		Action:     "stock_update",
		EntityType: "stock",
		EntityID:   &stock.ID,
		Changes:    string(changesJSON),
		IPAddress:  c.ClientIP(),
		UserAgent:  c.GetHeader("User-Agent"),
	}
	h.db.Create(&auditLog)

	c.JSON(http.StatusOK, stock)
}

func (h *StockHandler) ListRestockOrders(c *gin.Context) {
	var orders []models.RestockOrder
	query := h.db.Preload("Store").Preload("Initiator").Preload("Items.Product")

	if storeID := c.Query("store_id"); storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}

	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}

	if err := query.Order("initiated_at DESC").Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, orders)
}

// GetIncomingStock returns restock orders that are on the way (initiated or in_transit)
func (h *StockHandler) GetIncomingStock(c *gin.Context) {
	var orders []models.RestockOrder
	query := h.db.Preload("Store").Preload("Initiator").Preload("Items.Product").
		Where("status IN (?, ?)", "initiated", "in_transit")

	if storeID := c.Query("store_id"); storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}

	if err := query.Order("initiated_at DESC").Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, orders)
}

func (h *StockHandler) CreateRestockOrder(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uint)

	var req struct {
		StoreID uint `json:"store_id" binding:"required"`
		Items   []struct {
			ProductID uint    `json:"product_id" binding:"required"`
			Quantity  float64 `json:"quantity" binding:"required"`
		} `json:"items" binding:"required"`
		Notes string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	order := models.RestockOrder{
		StoreID:     req.StoreID,
		InitiatedBy: userID,
		Status:      "initiated",
		Notes:       req.Notes,
		InitiatedAt: time.Now(),
	}

	if err := h.db.Create(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create order items
	for _, item := range req.Items {
		orderItem := models.RestockOrderItem{
			RestockOrderID: order.ID,
			ProductID:      item.ProductID,
			Quantity:       item.Quantity,
		}
		h.db.Create(&orderItem)
	}

	h.db.Preload("Store").Preload("Initiator").Preload("Items.Product").First(&order, order.ID)

	c.JSON(http.StatusCreated, order)
}

func (h *StockHandler) UpdateTrackingNumber(c *gin.Context) {
	var order models.RestockOrder
	if err := h.db.First(&order, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}

	var req struct {
		TrackingNumber string `json:"tracking_number" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	order.TrackingNumber = req.TrackingNumber
	if order.Status == "initiated" {
		order.Status = "in_transit"
	}

	if err := h.db.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, order)
}

func (h *StockHandler) ReceiveRestockOrder(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uint)

	var order models.RestockOrder
	if err := h.db.Preload("Items").First(&order, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}

	now := time.Now()
	order.Status = "received"
	order.ReceivedAt = &now

	if err := h.db.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Update stock and record audit logs
	for _, item := range order.Items {
		var stock models.Stock
		oldQuantity := 0.0
		if err := h.db.Where("product_id = ? AND store_id = ?", item.ProductID, order.StoreID).
			First(&stock).Error; err != nil {
			// Create if doesn't exist
			stock = models.Stock{
				ProductID: item.ProductID,
				StoreID:   order.StoreID,
				Quantity:  0,
			}
		} else {
			oldQuantity = stock.Quantity
		}

		stock.Quantity += item.Quantity
		stock.LastUpdated = time.Now()
		h.db.Save(&stock)

		// Record audit log for stock update
		changes := map[string]interface{}{
			"product_id":       item.ProductID,
			"store_id":         order.StoreID,
			"old_quantity":     oldQuantity,
			"new_quantity":     stock.Quantity,
			"added_quantity":   item.Quantity,
			"reason":           "restock_order_received",
			"restock_order_id": order.ID,
		}
		changesJSON, _ := json.Marshal(changes)
		auditLog := models.AuditLog{
			UserID:     &userID,
			Action:     "stock_update",
			EntityType: "stock",
			EntityID:   &stock.ID,
			Changes:    string(changesJSON),
			IPAddress:  c.ClientIP(),
			UserAgent:  c.GetHeader("User-Agent"),
		}
		h.db.Create(&auditLog)
	}

	c.JSON(http.StatusOK, order)
}

func (h *StockHandler) ListStores(c *gin.Context) {
	var stores []models.Store
	if err := h.db.Where("is_active = ?", true).Find(&stores).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stores)
}

func (h *StockHandler) CreateStore(c *gin.Context) {
	var req struct {
		Name    string `json:"name" binding:"required"`
		Address string `json:"address"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	store := models.Store{
		Name:     req.Name,
		Address:  req.Address,
		IsActive: true,
	}

	if err := h.db.Create(&store).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, store)
}
