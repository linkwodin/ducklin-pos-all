package api

import (
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"time"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// StockReportRow is one row of the day-start / day-end stock report
type StockReportRow struct {
	ProductID        uint    `json:"product_id"`
	ProductName      string  `json:"product_name"`
	StoreID          uint    `json:"store_id"`
	StoreName        string  `json:"store_name"`
	DayStartQuantity float64 `json:"day_start_quantity"`
	DayEndQuantity   float64 `json:"day_end_quantity"`
}

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

	// Calculate incoming quantities for each stock item
	type StockResponse struct {
		models.Stock
		IncomingQuantity float64 `json:"incoming_quantity"`
	}

	response := make([]StockResponse, len(stock))
	for i, s := range stock {
		// Get incoming quantity from restock orders (initiated or in_transit status)
		var incomingQty float64
		var results []struct {
			Quantity float64
		}
		h.db.Table("restock_order_items").
			Select("restock_order_items.quantity").
			Joins("INNER JOIN restock_orders ON restock_order_items.restock_order_id = restock_orders.id").
			Where("restock_order_items.product_id = ? AND restock_orders.store_id = ? AND restock_orders.status IN (?, ?)",
				s.ProductID, s.StoreID, "initiated", "in_transit").
			Scan(&results)

		for _, result := range results {
			incomingQty += result.Quantity
		}

		response[i] = StockResponse{
			Stock:            s,
			IncomingQuantity: incomingQty,
		}
	}

	c.JSON(http.StatusOK, response)
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

// GetStockReport returns per-product day-start and day-end quantities for a given date,
// derived from stock_update audit logs with reason stocktake_day_start / stocktake_day_end.
func (h *StockHandler) GetStockReport(c *gin.Context) {
	dateStr := c.Query("date")
	if dateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date is required (YYYY-MM-DD)"})
		return
	}
	date, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid date format (use YYYY-MM-DD)"})
		return
	}
	storeIDStr := c.Query("store_id")

	var logs []models.AuditLog
	query := h.db.Where("action = ? AND entity_type = ?", "stock_update", "stock").
		Where("DATE(created_at) = ?", date.Format("2006-01-02")).
		Order("created_at ASC")
	if storeIDStr != "" {
		// Join to stocks to filter by store_id (GORM table name is "stocks")
		query = query.Joins("INNER JOIN stocks ON audit_logs.entity_id = stocks.id AND stocks.store_id = ?", storeIDStr)
	}
	if err := query.Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// changes: product_id, store_id, old_quantity, new_quantity, reason
	type changeSet struct {
		ProductID   uint    `json:"product_id"`
		StoreID     uint    `json:"store_id"`
		NewQuantity float64 `json:"new_quantity"`
		Reason      string  `json:"reason"`
	}
	type key struct {
		ProductID uint
		StoreID   uint
	}
	dayStart := make(map[key]float64)
	dayEnd := make(map[key]float64)
	for _, log := range logs {
		var c changeSet
		if err := json.Unmarshal([]byte(log.Changes), &c); err != nil {
			continue
		}
		k := key{ProductID: c.ProductID, StoreID: c.StoreID}
		switch c.Reason {
		case "stocktake_day_start":
			dayStart[k] = c.NewQuantity
		case "stocktake_day_end":
			dayEnd[k] = c.NewQuantity
		}
	}

	// Build unique keys and fetch product/store names
	seen := make(map[key]bool)
	for k := range dayStart {
		seen[k] = true
	}
	for k := range dayEnd {
		seen[k] = true
	}
	if len(seen) == 0 {
		c.JSON(http.StatusOK, []StockReportRow{})
		return
	}

	var productIDs, storeIDs []uint
	for k := range seen {
		productIDs = append(productIDs, k.ProductID)
		storeIDs = append(storeIDs, k.StoreID)
	}
	var products []models.Product
	h.db.Where("id IN ?", productIDs).Find(&products)
	var stores []models.Store
	h.db.Where("id IN ?", storeIDs).Find(&stores)
	productNameByID := make(map[uint]string)
	for _, p := range products {
		productNameByID[p.ID] = p.Name
	}
	storeNameByID := make(map[uint]string)
	for _, s := range stores {
		storeNameByID[s.ID] = s.Name
	}

	var rows []StockReportRow
	for k := range seen {
		rows = append(rows, StockReportRow{
			ProductID:        k.ProductID,
			ProductName:      productNameByID[k.ProductID],
			StoreID:          k.StoreID,
			StoreName:        storeNameByID[k.StoreID],
			DayStartQuantity: dayStart[k],
			DayEndQuantity:   dayEnd[k],
		})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].StoreName != rows[j].StoreName {
			return rows[i].StoreName < rows[j].StoreName
		}
		return rows[i].ProductName < rows[j].ProductName
	})
	c.JSON(http.StatusOK, rows)
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
