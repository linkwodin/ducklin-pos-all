package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
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

	// Generate check codes for invoice and receipt
	invoiceCheckCode := h.generateCheckCode(orderNumber, totalAmount, "invoice")
	receiptCheckCode := h.generateCheckCode(orderNumber, totalAmount, "receipt")

	// Generate QR code data
	qrData := map[string]interface{}{
		"order_number": orderNumber,
		"subtotal":     subtotal,
		"discount":     discountAmount,
		"total":        totalAmount,
		"created_at":   now.Format(time.RFC3339),
	}

	order := models.Order{
		OrderNumber:      orderNumber,
		StoreID:          req.StoreID,
		UserID:           userID,
		DeviceCode:       req.DeviceCode,
		SectorID:         req.SectorID,
		Subtotal:         subtotal,
		DiscountAmount:   discountAmount,
		TotalAmount:      totalAmount,
		Status:           "pending",
		QRCodeData:       fmt.Sprintf("%v", qrData),
		InvoiceCheckCode: invoiceCheckCode,
		ReceiptCheckCode: receiptCheckCode,
		CreatedAt:        now,
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

	// Reduce stock immediately when order is created
	for _, item := range orderItems {
		var stock models.Stock
		if err := h.db.Where("product_id = ? AND store_id = ?", item.ProductID, order.StoreID).
			First(&stock).Error; err != nil {
			// Stock not found - log warning but don't fail the order creation
			fmt.Printf("Warning: Stock not found for product %d in store %d, skipping stock reduction\n", item.ProductID, order.StoreID)
			continue
		}

		stock.Quantity -= item.Quantity
		if stock.Quantity < 0 {
			stock.Quantity = 0
		}
		stock.LastUpdated = time.Now()
		if err := h.db.Save(&stock).Error; err != nil {
			fmt.Printf("Warning: Failed to update stock for product %d: %v\n", item.ProductID, err)
			// Continue with other items even if one fails
		}
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

func (h *OrderHandler) ListOrders(c *gin.Context) {
	var orders []models.Order
	query := h.db.Preload("Store").Preload("User").Preload("Sector").Preload("Items.Product")

	// Filter by store_id if provided
	if storeID := c.Query("store_id"); storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}

	// Filter by status if provided
	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}

	// Filter by staff (user_id) if provided
	if userID := c.Query("user_id"); userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	// Filter by date range if provided
	if startDate := c.Query("start_date"); startDate != "" {
		query = query.Where("created_at >= ?", startDate)
	}
	if endDate := c.Query("end_date"); endDate != "" {
		query = query.Where("created_at <= ?", endDate)
	}

	// Order by created_at descending (newest first)
	query = query.Order("created_at DESC")

	// Limit results (default 100, max 1000)
	limit := 100
	if limitStr := c.Query("limit"); limitStr != "" {
		var parsedLimit int
		if _, err := fmt.Sscanf(limitStr, "%d", &parsedLimit); err == nil && parsedLimit > 0 && parsedLimit <= 1000 {
			limit = parsedLimit
		}
	}
	query = query.Limit(limit)

	if err := query.Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, orders)
}

func (h *OrderHandler) GetOrder(c *gin.Context) {
	var order models.Order
	orderID := c.Param("id")

	// Try to get by ID first
	if err := h.db.Preload("Store").Preload("User").Preload("Sector").
		Preload("Items.Product").First(&order, orderID).Error; err != nil {
		// If not found by ID, try by order number
		if err2 := h.db.Preload("Store").Preload("User").Preload("Sector").
			Preload("Items.Product").Where("order_number = ?", orderID).First(&order).Error; err2 != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
			return
		}
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

	// Note: Stock is already deducted when order is created, so no need to deduct again here

	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) MarkCancelled(c *gin.Context) {
	var order models.Order
	if err := h.db.Preload("Items").First(&order, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}

	if order.Status != "pending" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only pending orders can be cancelled"})
		return
	}

	// Restore stock for cancelled orders
	for _, item := range order.Items {
		var stock models.Stock
		if err := h.db.Where("product_id = ? AND store_id = ?", item.ProductID, order.StoreID).
			First(&stock).Error; err == nil {
			stock.Quantity += item.Quantity
			stock.LastUpdated = time.Now()
			h.db.Save(&stock)
		}
	}

	order.Status = "cancelled"

	if err := h.db.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Reload order with all relationships
	h.db.Preload("Store").Preload("User").Preload("Sector").
		Preload("Items.Product").First(&order, order.ID)

	c.JSON(http.StatusOK, order)
}

// generateCheckCode generates a 4-digit check code from order number, total amount, and receipt type
// This matches the Flutter implementation in ReceiptPrinterHelpers.generateCheckCode
// receiptType should be "receipt" or "invoice" to generate different codes
func (h *OrderHandler) generateCheckCode(orderNumber string, totalAmount float64, receiptType string) string {
	// Create a deterministic hash from order number, total amount, and receipt type
	// Format: "ORDER-123.45-receipt" or "ORDER-123.45-invoice" (matching Flutter's format)
	combined := fmt.Sprintf("%s-%.2f-%s", orderNumber, totalAmount, receiptType)

	// Simple hash function matching Dart's hashCode behavior
	hash := int64(0)
	for _, char := range combined {
		hash = hash*31 + int64(char)
	}

	// Ensure positive and get last 4 digits
	code := hash % 10000
	if code < 0 {
		code = -code
	}

	return fmt.Sprintf("%04d", code)
}

// MarkPickedUp marks an order as picked up by scanning QR code
func (h *OrderHandler) MarkPickedUp(c *gin.Context) {
	var order models.Order
	orderNumber := c.Param("order_number")

	// Get check codes from query parameter or request body
	var invoiceCheckCode string
	var receiptCheckCode string

	if c.Query("invoice_check_code") != "" || c.Query("receipt_check_code") != "" {
		// Both check codes provided via query parameters
		invoiceCheckCode = c.Query("invoice_check_code")
		receiptCheckCode = c.Query("receipt_check_code")
	} else {
		// Try request body
		var reqBody map[string]interface{}
		if err := c.ShouldBindJSON(&reqBody); err == nil {
			if invCode, ok := reqBody["invoice_check_code"].(string); ok {
				invoiceCheckCode = invCode
			}
			if recCode, ok := reqBody["receipt_check_code"].(string); ok {
				receiptCheckCode = recCode
			}
		}
	}

	// Normalize order number to uppercase for case-insensitive lookup
	// Order numbers are generated as "ORD-YYYYMMDD-XXXX" but QR codes might be lowercase
	orderNumberUpper := strings.ToUpper(orderNumber)

	// Try case-insensitive lookup
	if err := h.db.Where("UPPER(order_number) = ?", orderNumberUpper).First(&order).Error; err != nil {
		// If UPPER() doesn't work, try direct lookup with uppercase
		if err2 := h.db.Where("order_number = ?", orderNumberUpper).First(&order).Error; err2 != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": fmt.Sprintf("Order not found: %s (tried: %s)", orderNumber, orderNumberUpper)})
			return
		}
	}

	// Verify check codes against database values if provided (optional)
	if invoiceCheckCode != "" && receiptCheckCode != "" {
		// Validate both check codes against stored values in database
		if order.InvoiceCheckCode == "" || order.ReceiptCheckCode == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Order check codes not found in database. Please ensure order was created properly.",
			})
			return
		}

		if invoiceCheckCode != order.InvoiceCheckCode {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": fmt.Sprintf("Invalid invoice check code. Expected: %s, Got: %s", order.InvoiceCheckCode, invoiceCheckCode),
			})
			return
		}

		if receiptCheckCode != order.ReceiptCheckCode {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": fmt.Sprintf("Invalid receipt check code. Expected: %s, Got: %s", order.ReceiptCheckCode, receiptCheckCode),
			})
			return
		}
	}
	// If check codes are not provided, allow pickup without validation (for backward compatibility)

	// Log order details for debugging
	fmt.Printf("Order found: ID=%d, Status=%s, PaidAt=%v, PickedUpAt=%v\n", order.ID, order.Status, order.PaidAt, order.PickedUpAt)

	// Allow pickup if order is paid, completed, or has PaidAt timestamp (even if status is still pending)
	if order.Status != "pending" && order.Status != "paid" && order.Status != "completed" && order.PaidAt == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("Order must be paid before pickup. Current status: %s, PaidAt: %v", order.Status, order.PaidAt),
		})
		return
	}

	if order.PickedUpAt != nil {
		// Return order details including pickup time for better error handling
		c.JSON(http.StatusBadRequest, gin.H{
			"error":        "Order already picked up",
			"picked_up_at": order.PickedUpAt.Format(time.RFC3339),
			"order_number": order.OrderNumber,
		})
		return
	}

	// Get user ID from context (set by auth middleware)
	userIDInterface, exists := c.Get("user_id")
	var userID *uint
	if exists {
		uid := userIDInterface.(uint)
		userID = &uid
	}

	now := time.Now()
	order.Status = "completed"
	order.PickedUpAt = &now

	if err := h.db.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Record audit log for order pickup
	changes := map[string]interface{}{
		"order_id":     order.ID,
		"order_number": order.OrderNumber,
		"status":       "picked_up",
		"picked_up_at": now.Format(time.RFC3339),
	}
	changesJSON, _ := json.Marshal(changes)
	auditLog := models.AuditLog{
		UserID:     userID,
		Action:     "order_pickup",
		EntityType: "order",
		EntityID:   &order.ID,
		Changes:    string(changesJSON),
		IPAddress:  c.ClientIP(),
		UserAgent:  c.GetHeader("User-Agent"),
	}
	h.db.Create(&auditLog)

	// Reload order with all relationships
	h.db.Preload("Store").Preload("User").Preload("Sector").
		Preload("Items.Product").First(&order, order.ID)

	c.JSON(http.StatusOK, order)
}

type DailyRevenueStat struct {
	Date       string  `json:"date"`
	Revenue    float64 `json:"revenue"`
	OrderCount int     `json:"order_count"`
}

type DailyProductSalesStat struct {
	Date               string  `json:"date"`
	ProductID          uint    `json:"product_id"`
	ProductName        string  `json:"product_name"`
	ProductNameChinese string  `json:"product_name_chinese"`
	Quantity           float64 `json:"quantity"`
	Revenue            float64 `json:"revenue"`
}

func parseInt(s string) int {
	var result int
	fmt.Sscanf(s, "%d", &result)
	return result
}

func (h *OrderHandler) GetDailyRevenueStats(c *gin.Context) {
	var stats []DailyRevenueStat

	var startDate, endDate time.Time
	startStr := c.Query("start_date")
	endStr := c.Query("end_date")
	if startStr != "" && endStr != "" {
		if s, err := time.Parse("2006-01-02", startStr); err == nil {
			startDate = s
		} else {
			startDate = time.Now().AddDate(0, 0, -30)
		}
		if e, err := time.Parse("2006-01-02", endStr); err == nil {
			endDate = e
		} else {
			endDate = time.Now()
		}
		if endDate.Before(startDate) {
			startDate, endDate = endDate, startDate
		}
	} else {
		days := 30
		if daysStr := c.Query("days"); daysStr != "" {
			if parsedDays := parseInt(daysStr); parsedDays > 0 && parsedDays <= 365 {
				days = parsedDays
			}
		}
		endDate = time.Now()
		startDate = endDate.AddDate(0, 0, -days)
	}

	// Get store filter if provided
	storeID := c.Query("store_id")

	// Build query
	query := h.db.Model(&models.Order{}).
		Select("DATE(created_at) as date, SUM(total_amount) as revenue, COUNT(*) as order_count").
		Where("created_at >= ? AND created_at < ? AND status IN (?, ?, ?)", startDate, endDate.AddDate(0, 0, 1), "paid", "completed", "picked_up").
		Group("DATE(created_at)")

	if storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}

	query = query.Order("date ASC")

	rows, err := query.Rows()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	for rows.Next() {
		var stat DailyRevenueStat
		var date time.Time
		if err := rows.Scan(&date, &stat.Revenue, &stat.OrderCount); err != nil {
			continue
		}
		stat.Date = date.Format("2006-01-02")
		stats = append(stats, stat)
	}

	c.JSON(http.StatusOK, stats)
}

func (h *OrderHandler) GetDailyProductSalesStats(c *gin.Context) {
	var stats []DailyProductSalesStat

	var startDate, endDate time.Time
	startStr := c.Query("start_date")
	endStr := c.Query("end_date")
	if startStr != "" && endStr != "" {
		if s, err := time.Parse("2006-01-02", startStr); err == nil {
			startDate = s
		} else {
			startDate = time.Now().AddDate(0, 0, -30)
		}
		if e, err := time.Parse("2006-01-02", endStr); err == nil {
			endDate = e
		} else {
			endDate = time.Now()
		}
		if endDate.Before(startDate) {
			startDate, endDate = endDate, startDate
		}
	} else {
		days := 30
		if daysStr := c.Query("days"); daysStr != "" {
			if parsedDays := parseInt(daysStr); parsedDays > 0 && parsedDays <= 365 {
				days = parsedDays
			}
		}
		endDate = time.Now()
		startDate = endDate.AddDate(0, 0, -days)
	}

	// Get store filter if provided
	storeID := c.Query("store_id")

	// Build query to join orders and order_items
	query := h.db.Table("orders").
		Select("DATE(orders.created_at) as date, order_items.product_id, SUM(order_items.quantity) as quantity, SUM(order_items.line_total) as revenue").
		Joins("INNER JOIN order_items ON orders.id = order_items.order_id").
		Where("orders.created_at >= ? AND orders.created_at < ? AND orders.status IN (?, ?, ?)", startDate, endDate.AddDate(0, 0, 1), "paid", "completed", "picked_up").
		Group("DATE(orders.created_at), order_items.product_id")

	if storeID != "" {
		query = query.Where("orders.store_id = ?", storeID)
	}

	query = query.Order("date ASC, order_items.product_id ASC")

	rows, err := query.Rows()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	// Map to store product names
	productMap := make(map[uint]models.Product)

	for rows.Next() {
		var stat DailyProductSalesStat
		var date time.Time
		var productID uint
		if err := rows.Scan(&date, &productID, &stat.Quantity, &stat.Revenue); err != nil {
			continue
		}
		stat.Date = date.Format("2006-01-02")
		stat.ProductID = productID

		// Get product name if not cached
		if product, ok := productMap[productID]; !ok {
			var product models.Product
			if err := h.db.First(&product, productID).Error; err == nil {
				productMap[productID] = product
				stat.ProductName = product.Name
				stat.ProductNameChinese = product.NameChinese
			}
		} else {
			stat.ProductName = product.Name
			stat.ProductNameChinese = product.NameChinese
		}

		stats = append(stats, stat)
	}

	c.JSON(http.StatusOK, stats)
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
