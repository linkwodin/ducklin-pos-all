package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
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
	query := h.db.Preload("Product.ProductLine").Preload("Store")

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
		IncomingQuantity   float64 `json:"incoming_quantity"`
		PendingPackQuantity float64 `json:"pending_pack_quantity"`
	}

	pendingPackByKey := map[string]float64{}
	type pendingPackRow struct {
		StoreID   uint
		ProductID uint
		Qty       float64
	}
	var pendingRows []pendingPackRow
	if err := h.db.Table("shipment_items si").
		Select(`s.store_id AS store_id, woi.product_id AS product_id,
			SUM(CASE WHEN si.quantity > 0 THEN si.quantity ELSE woi.quantity END) AS qty`).
		Joins("INNER JOIN shipments s ON s.id = si.shipment_id").
		Joins("INNER JOIN wholesale_order_items woi ON woi.id = si.wholesale_order_item_id").
		Joins("INNER JOIN wholesale_orders wo ON wo.id = s.wholesale_order_id AND wo.status != ?", models.WholesaleOrderStatusDeleted).
		Where("s.status IN ?", []string{models.ShipmentStatusAssigned, models.ShipmentStatusPacking}).
		Group("s.store_id, woi.product_id").
		Scan(&pendingRows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	for _, row := range pendingRows {
		key := fmt.Sprintf("%d:%d", row.StoreID, row.ProductID)
		pendingPackByKey[key] = row.Qty
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
			Stock:               s,
			IncomingQuantity:    incomingQty,
			PendingPackQuantity: pendingPackByKey[fmt.Sprintf("%d:%d", s.StoreID, s.ProductID)],
		}
	}

	c.JSON(http.StatusOK, response)
}

// GetWholesaleShipFromMap returns product_id -> store_id for products with a default wholesale ship store.
func (h *StockHandler) GetWholesaleShipFromMap(c *gin.Context) {
	var rows []models.Stock
	if err := h.db.Where("wholesale_ship_from = ?", true).Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	out := make(map[string]uint, len(rows))
	for _, row := range rows {
		out[strconv.FormatUint(uint64(row.ProductID), 10)] = row.StoreID
	}
	c.JSON(http.StatusOK, out)
}

// GetProductStockAssignments returns all store stock rows for one product.
func (h *StockHandler) GetProductStockAssignments(c *gin.Context) {
	productID, err := strconv.ParseUint(c.Param("product_id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product_id"})
		return
	}
	var stock []models.Stock
	if err := h.db.Where("product_id = ?", uint(productID)).
		Preload("Store").Find(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, stock)
}

func (h *StockHandler) GetStoreStock(c *gin.Context) {
	var stock []models.Stock
	if err := h.db.Where("store_id = ?", c.Param("store_id")).
		Preload("Product.ProductLine").Find(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stock)
}

// AssignProductsToStoreRequest is the body for assigning products to a store (creates stock records with quantity 0 if not present).
type AssignProductsToStoreRequest struct {
	StoreID    uint   `json:"store_id" binding:"required"`
	ProductIDs []uint `json:"product_ids" binding:"required,min=1"`
}

func (h *StockHandler) AssignProductsToStore(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var req AssignProductsToStoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var store models.Store
	if err := h.db.First(&store, req.StoreID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Store not found"})
		return
	}
	assigned := 0
	now := time.Now()
	for _, productID := range req.ProductIDs {
		var existing models.Stock
		err := h.db.Where("product_id = ? AND store_id = ?", productID, req.StoreID).First(&existing).Error
		if err == nil {
			continue
		}
		var product models.Product
		if err := h.db.First(&product, productID).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Product not found: " + strconv.FormatUint(uint64(productID), 10)})
			return
		}
		stock := models.Stock{
			ProductID:         productID,
			StoreID:           req.StoreID,
			Quantity:          0,
			WeightQuantityG:   0,
			TrackPrepacked:    true,
			TrackWeight:       productSupportsDualInventory(&product),
			LowStockThreshold: 0,
			LastUpdated:       now,
		}
		if err := h.db.Create(&stock).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		assigned++
	}
	c.JSON(http.StatusOK, gin.H{"assigned": assigned, "store_id": req.StoreID, "product_ids": req.ProductIDs})
}

// UnassignProductsFromStoreRequest removes product stock records from a store (delete stock rows with quantity 0 only, or any).
type UnassignProductsFromStoreRequest struct {
	StoreID    uint   `json:"store_id" binding:"required"`
	ProductIDs []uint `json:"product_ids" binding:"required,min=1"`
}

func (h *StockHandler) UnassignProductsFromStore(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var req UnassignProductsFromStoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	result := h.db.Where("store_id = ? AND product_id IN ?", req.StoreID, req.ProductIDs).Delete(&models.Stock{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": result.Error.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"unassigned": int(result.RowsAffected), "store_id": req.StoreID, "product_ids": req.ProductIDs})
}

type StockAssignmentItem struct {
	ProductID         uint `json:"product_id" binding:"required"`
	TrackPrepacked    bool `json:"track_prepacked"`
	TrackWeight       bool `json:"track_weight"`
	WholesaleShipFrom bool `json:"wholesale_ship_from"`
}

type SetStockAssignmentsRequest struct {
	StoreID     uint                  `json:"store_id" binding:"required"`
	Assignments []StockAssignmentItem `json:"assignments" binding:"required"`
}

// SetStockAssignments upserts store stock rows with prepacked/weight tracking flags.
func (h *StockHandler) SetStockAssignments(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var req SetStockAssignmentsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var store models.Store
	if err := h.db.First(&store, req.StoreID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Store not found"})
		return
	}

	now := time.Now()
	updated := 0
	for _, item := range req.Assignments {
		var product models.Product
		if err := h.db.First(&product, item.ProductID).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Product not found: " + strconv.FormatUint(uint64(item.ProductID), 10)})
			return
		}
		dual := productSupportsDualInventory(&product)
		trackPrepacked := item.TrackPrepacked
		trackWeight := item.TrackWeight
		if !dual {
			trackPrepacked = item.TrackPrepacked || item.TrackWeight
			trackWeight = false
		}

		var stock models.Stock
		err := h.db.Where("product_id = ? AND store_id = ?", item.ProductID, req.StoreID).First(&stock).Error
		if !trackPrepacked && !trackWeight {
			if err == nil {
				if stock.Quantity != 0 || stock.WeightQuantityG != 0 {
					c.JSON(http.StatusBadRequest, gin.H{
						"error": fmt.Sprintf("Cannot unassign product %d from store %d while stock quantities remain", item.ProductID, req.StoreID),
					})
					return
				}
				if delErr := h.db.Delete(&stock).Error; delErr != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": delErr.Error()})
					return
				}
				updated++
			}
			continue
		}

		if err != nil {
			stock = models.Stock{
				ProductID:       item.ProductID,
				StoreID:         req.StoreID,
				Quantity:        0,
				WeightQuantityG: 0,
				LastUpdated:     now,
			}
		}
		stock.TrackPrepacked = trackPrepacked
		stock.TrackWeight = trackWeight
		if item.WholesaleShipFrom {
			if !trackPrepacked && !trackWeight {
				c.JSON(http.StatusBadRequest, gin.H{
					"error": fmt.Sprintf("Product %d must be assigned to store %d before marking as wholesale ship-from store", item.ProductID, req.StoreID),
				})
				return
			}
			if err := h.db.Model(&models.Stock{}).
				Where("product_id = ? AND store_id != ?", item.ProductID, req.StoreID).
				Update("wholesale_ship_from", false).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			stock.WholesaleShipFrom = true
		} else if err == nil {
			stock.WholesaleShipFrom = false
		}
		stock.LastUpdated = now
		if err != nil {
			if createErr := h.db.Create(&stock).Error; createErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": createErr.Error()})
				return
			}
		} else if saveErr := h.db.Save(&stock).Error; saveErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": saveErr.Error()})
			return
		}
		updated++
	}

	c.JSON(http.StatusOK, gin.H{"updated": updated, "store_id": req.StoreID})
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
	oldWeightG := 0.0
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
		oldWeightG = stock.WeightQuantityG
	}

	var req struct {
		Quantity          float64 `json:"quantity"`
		WeightQuantityG   *float64 `json:"weight_quantity_g"`
		LowStockThreshold float64 `json:"low_stock_threshold"`
		Reason            string  `json:"reason"` // Reason for the update (e.g., "manual adjustment", "received stock", etc.)
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stock.Quantity = req.Quantity
	if req.WeightQuantityG != nil {
		stock.WeightQuantityG = *req.WeightQuantityG
	}
	stock.LowStockThreshold = req.LowStockThreshold
	stock.LastUpdated = time.Now()

	if err := h.db.Save(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Record audit log
	changes := map[string]interface{}{
		"product_id":        stock.ProductID,
		"store_id":          stock.StoreID,
		"old_quantity":      oldQuantity,
		"new_quantity":      stock.Quantity,
		"old_weight_quantity_g": oldWeightG,
		"new_weight_quantity_g": stock.WeightQuantityG,
		"reason":            req.Reason,
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

	// Record inventory snapshot when update is from stocktake (day_start or day_end).
	// Frontend may send reason with suffix e.g. "stocktake_day_start | remark".
	snapshotType := ""
	if strings.HasPrefix(req.Reason, "stocktake_day_start") {
		snapshotType = "stocktake_day_start"
	} else if strings.HasPrefix(req.Reason, "stocktake_day_end") {
		snapshotType = "stocktake_day_end"
	}
	if snapshotType != "" {
		snapshotDate := time.Now().Format("2006-01-02")
		var snap models.StocktakeInventorySnapshot
		err := h.db.Where("store_id = ? AND product_id = ? AND snapshot_date = ? AND snapshot_type = ?",
			stock.StoreID, stock.ProductID, snapshotDate, snapshotType).First(&snap).Error
		if err != nil {
			h.db.Create(&models.StocktakeInventorySnapshot{
				StoreID:      stock.StoreID,
				ProductID:    stock.ProductID,
				Quantity:     stock.Quantity,
				SnapshotDate: snapshotDate,
				SnapshotType: snapshotType,
			})
		} else {
			snap.Quantity = stock.Quantity
			h.db.Save(&snap)
		}
	}

	c.JSON(http.StatusOK, stock)
}

// GetStockReport returns per-product day-start and day-end quantities for a given date.
// Prefers stocktake_inventory_snapshots; falls back to audit_logs for historical dates.
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

	type key struct {
		ProductID uint
		StoreID   uint
	}
	dayStart := make(map[key]float64)
	dayEnd := make(map[key]float64)

	// 1) Try snapshot table first
	var snapshots []models.StocktakeInventorySnapshot
	snapQuery := h.db.Where("snapshot_date = ?", dateStr)
	if storeIDStr != "" {
		snapQuery = snapQuery.Where("store_id = ?", storeIDStr)
	}
	if err := snapQuery.Find(&snapshots).Error; err == nil && len(snapshots) > 0 {
		for _, s := range snapshots {
			k := key{ProductID: s.ProductID, StoreID: s.StoreID}
			switch s.SnapshotType {
			case "stocktake_day_start":
				dayStart[k] = s.Quantity
			case "stocktake_day_end":
				dayEnd[k] = s.Quantity
			}
		}
	} else {
		// 2) Fall back to audit logs
		var logs []models.AuditLog
		query := h.db.Where("action = ? AND entity_type = ?", "stock_update", "stock").
			Where("DATE(created_at) = ?", date.Format("2006-01-02")).
			Order("created_at ASC")
		if storeIDStr != "" {
			query = query.Joins("INNER JOIN stocks ON audit_logs.entity_id = stocks.id AND stocks.store_id = ?", storeIDStr)
		}
		if err := query.Find(&logs).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		type changeSet struct {
			ProductID   uint    `json:"product_id"`
			StoreID     uint    `json:"store_id"`
			NewQuantity float64 `json:"new_quantity"`
			Reason      string  `json:"reason"`
		}
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
	}

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
	query := h.db.Where("is_active = ?", true)
	if c.Query("exclude_warehouse_only") == "true" {
		query = query.Where("is_warehouse_only = ?", false)
	}
	if err := query.Find(&stores).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stores)
}

func (h *StockHandler) CreateStore(c *gin.Context) {
	var req struct {
		Name            string `json:"name" binding:"required"`
		Address         string `json:"address"`
		IsWarehouseOnly bool   `json:"is_warehouse_only"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	store := models.Store{
		Name:            req.Name,
		Address:         req.Address,
		IsWarehouseOnly: req.IsWarehouseOnly,
		IsActive:        true,
	}

	if err := h.db.Create(&store).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, store)
}

// ConvertStockInventory moves inventory between prepacked units and loose weight (grams).
func (h *StockHandler) ConvertStockInventory(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uint)

	var req struct {
		Direction string  `json:"direction" binding:"required,oneof=unpack pack"`
		Amount    float64 `json:"amount" binding:"required,gt=0"`
		Reason    string  `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var stock models.Stock
	if err := h.db.Preload("Product").Where("product_id = ? AND store_id = ?",
		c.Param("product_id"), c.Param("store_id")).First(&stock).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock record not found"})
		return
	}
	product := stock.Product
	if !productSupportsDualInventory(&product) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Product does not support prepacked/weight inventory"})
		return
	}
	prepackG := effectivePrepackWeightG(&product)
	if prepackG <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Set prepack weight (g) on the product before pack/unpack"})
		return
	}

	prepacked := effectivePrepackedQuantity(&stock, &product)
	weightG := effectiveWeightQuantityG(&stock, &product)
	oldPrepacked := prepacked
	oldWeightG := weightG

	switch req.Direction {
	case "unpack":
		if prepacked+1e-9 < req.Amount {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient prepacked inventory"})
			return
		}
		prepacked -= req.Amount
		weightG += req.Amount * prepackG
	case "pack":
		if weightG+1e-9 < req.Amount {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient weight inventory"})
			return
		}
		units := req.Amount / prepackG
		weightG -= req.Amount
		prepacked += units
	}

	stock.Quantity = prepacked
	stock.WeightQuantityG = weightG
	stock.LastUpdated = time.Now()
	if err := h.db.Save(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	changes := map[string]interface{}{
		"product_id":              stock.ProductID,
		"store_id":                stock.StoreID,
		"direction":               req.Direction,
		"amount":                  req.Amount,
		"prepack_weight_g":        prepackG,
		"old_prepacked_quantity":  oldPrepacked,
		"new_prepacked_quantity":  prepacked,
		"old_weight_quantity_g":   oldWeightG,
		"new_weight_quantity_g":   weightG,
		"reason":                  strings.TrimSpace(req.Reason),
	}
	changesJSON, _ := json.Marshal(changes)
	auditLog := models.AuditLog{
		UserID:     &userID,
		Action:     "stock_convert_inventory",
		EntityType: "stock",
		EntityID:   &stock.ID,
		Changes:    string(changesJSON),
		IPAddress:  c.ClientIP(),
		UserAgent:  c.GetHeader("User-Agent"),
	}
	h.db.Create(&auditLog)

	h.db.Preload("Product").Preload("Store").First(&stock, stock.ID)
	c.JSON(http.StatusOK, stock)
}
