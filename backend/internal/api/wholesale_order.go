package api

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"

	"os"
	"path/filepath"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/gin-gonic/gin"
	"github.com/jung-kurt/gofpdf"
	"golang.org/x/net/context"
	"gorm.io/gorm"
)

type WholesaleOrderHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewWholesaleOrderHandler(db *gorm.DB, cfg *config.Config) *WholesaleOrderHandler {
	return &WholesaleOrderHandler{db: db, cfg: cfg}
}

func (h *WholesaleOrderHandler) audit(c *gin.Context, action string, orderID uint, changes map[string]interface{}) {
	userIDVal, _ := c.Get("user_id")
	var uid *uint
	if id, ok := userIDVal.(uint); ok {
		uid = &id
	}
	changesJSON, _ := json.Marshal(changes)
	h.db.Create(&models.AuditLog{
		UserID:     uid,
		Action:     action,
		EntityType: "wholesale_order",
		EntityID:   &orderID,
		Changes:    string(changesJSON),
		IPAddress:  c.ClientIP(),
		UserAgent:  c.GetHeader("User-Agent"),
	})
}

// requireManagementOrSupervisor aborts with 403 if role is not management or supervisor.
func requireManagementOrSupervisor(c *gin.Context) bool {
	role, _ := c.Get("role")
	r, _ := role.(string)
	if r != "management" && r != "supervisor" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Admin or manager role required"})
		c.Abort()
		return false
	}
	return true
}

// requirePosUserSupervisorOrManagement allows create for pos_user, supervisor, or management (admin).
func requirePosUserSupervisorOrManagement(c *gin.Context) bool {
	role, _ := c.Get("role")
	r, _ := role.(string)
	if r != "pos_user" && r != "supervisor" && r != "management" {
		c.JSON(http.StatusForbidden, gin.H{"error": "POS user, supervisor, or admin role required"})
		c.Abort()
		return false
	}
	return true
}

type CreateWholesaleOrderRequest struct {
	WholesaleClientID      uint   `json:"wholesale_client_id" binding:"required"`
	WholesaleClientStoreID *uint  `json:"wholesale_client_store_id"` // shipping address
	StoreID                uint   `json:"store_id" binding:"required"`
	SectorID               *uint  `json:"sector_id"`
	PONumber               string `json:"po_number"`
	OrderChannel           string `json:"order_channel"` // "po" = client provided PO, "whatsapp" = we generate PO (delivery note shows "Whatsapp")
	PODate                 string `json:"po_date"`
	PaymentTerms           string  `json:"payment_terms"` // defaults from client.Terms if empty
	Notes                  string  `json:"notes"`
	TotalDiscount          float64 `json:"total_discount"`
	ShippingFee            float64 `json:"shipping_fee"` // order-level shipping fee
	Items                  []struct {
		ProductID          uint    `json:"product_id" binding:"required"`
		Quantity           float64 `json:"quantity" binding:"required"`
		LineDiscountAmount float64 `json:"line_discount_amount"` // per-line discount in £
	} `json:"items" binding:"required,min=1"`
}

func (h *WholesaleOrderHandler) Create(c *gin.Context) {
	if !requirePosUserSupervisorOrManagement(c) {
		return
	}
	userIDInterface, _ := c.Get("user_id")
	userID := userIDInterface.(uint)

	var req CreateWholesaleOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	orderNumber := fmt.Sprintf("WO-%s-%d", time.Now().Format("20060102"), time.Now().Unix()%100000)
	now := time.Now()
	priceDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	if pd := parsePODate(req.PODate); pd != nil {
		priceDate = *pd
	}

	var client models.WholesaleClient
	if err := h.db.First(&client, req.WholesaleClientID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Wholesale client not found"})
		return
	}
	if !client.IsActive {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Wholesale client is inactive"})
		return
	}

	// Use client's sector if request doesn't specify one
	sectorID := req.SectorID
	if sectorID == nil && client.SectorID != nil {
		sectorID = client.SectorID
	}

	var subtotal float64
	var items []models.WholesaleOrderItem
	for _, it := range req.Items {
		var product models.Product
		if err := h.db.First(&product, it.ProductID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": fmt.Sprintf("Product %d not found", it.ProductID)})
			return
		}
		var unitPrice float64
		var cost models.ProductCost
		if err := h.db.Where("product_id = ? AND (effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
			product.ID, priceDate, priceDate).
			Order("effective_from DESC").First(&cost).Error; err == nil {
			unitPrice = cost.WholesaleCostGBP
			if unitPrice <= 0 {
				unitPrice = cost.DirectRetailOnlineStorePriceGBP
			}
		}
		// Apply sector pricing if sector is set
		if sectorID != nil && unitPrice > 0 {
			var psd models.ProductSectorDiscount
			if err := h.db.Where("product_id = ? AND sector_id = ? AND (effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
				product.ID, *sectorID, priceDate, priceDate).Order("effective_from DESC").First(&psd).Error; err == nil {
				if psd.SectorPriceGBP > 0 {
					unitPrice = psd.SectorPriceGBP
				} else if psd.DiscountPercent > 0 {
					unitPrice = unitPrice * (1 - psd.DiscountPercent/100)
					unitPrice = math.Round(unitPrice*100) / 100
				}
			}
		}
		lineDiscount := it.LineDiscountAmount
		if lineDiscount < 0 {
			lineDiscount = 0
		}
		lineTotal := unitPrice*it.Quantity - lineDiscount
		if lineTotal < 0 {
			lineTotal = 0
		}
		subtotal += lineTotal
		items = append(items, models.WholesaleOrderItem{
			ProductID:          it.ProductID,
			Quantity:           it.Quantity,
			UnitPrice:          unitPrice,
			LineDiscountAmount: lineDiscount,
			LineTotal:          lineTotal,
		})
	}

	discount := req.TotalDiscount
	if discount < 0 {
		discount = 0
	}
	if discount > subtotal {
		discount = subtotal
	}
	totalNet := subtotal - discount
	vatTotal := 0.0
	amountDue := totalNet + vatTotal

	paymentTerms := strings.TrimSpace(req.PaymentTerms)
	if paymentTerms == "" {
		paymentTerms = client.Terms
	}
	orderChannel := strings.TrimSpace(strings.ToLower(req.OrderChannel))
	poNumber := strings.TrimSpace(req.PONumber)
	if orderChannel == "whatsapp" {
		poNumber = "" // force no client PO when channel is WhatsApp
	}
	shippingFee := req.ShippingFee
	if shippingFee < 0 {
		shippingFee = 0
	}
	wo := models.WholesaleOrder{
		OrderNumber:            orderNumber,
		WholesaleClientID:      req.WholesaleClientID,
		WholesaleClientStoreID: req.WholesaleClientStoreID,
		StoreID:                req.StoreID,
		UserID:                 userID,
		SectorID:               sectorID,
		PONumber:               poNumber,
		PODate:                 parsePODate(req.PODate),
		PaymentTerms:            paymentTerms,
		ShippingFee:            shippingFee,
		Status:                 models.WholesaleOrderStatusPending,
		Subtotal:               subtotal,
		DiscountAmount:         discount,
		TotalNet:               totalNet,
		VATTotal:               vatTotal,
		AmountDue:               amountDue,
		Notes:                  req.Notes,
		CreatedAt:              now,
	}
	if err := h.db.Create(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Default OC Number: D + order_id (user can manually edit to D123.1 etc.)
	wo.RefNo = fmt.Sprintf("D%d", wo.ID)
	h.db.Model(&wo).Update("ref_no", wo.RefNo)

	// If no client PO and channel is not "po": generate PO [003][dd][mm][yy] and store channel (whatsapp, email, or custom)
	if wo.PONumber == "" && orderChannel != "po" {
		loc := wo.CreatedAt.Location()
		startOfDay := time.Date(wo.CreatedAt.Year(), wo.CreatedAt.Month(), wo.CreatedAt.Day(), 0, 0, 0, 0, loc)
		endOfDay := startOfDay.Add(24 * time.Hour)
		var seq int64
		h.db.Model(&models.WholesaleOrder{}).Where("created_at >= ? AND created_at < ? AND id <= ?", startOfDay, endOfDay, wo.ID).Count(&seq)
		generatedPO := fmt.Sprintf("%03d%02d%02d%02d", seq, wo.CreatedAt.Day(), int(wo.CreatedAt.Month()), wo.CreatedAt.Year()%100)
		wo.PONumber = generatedPO
		if orderChannel == "" {
			orderChannel = "whatsapp"
		}
		wo.OrderChannel = orderChannel
		h.db.Model(&wo).Updates(map[string]interface{}{"po_number": wo.PONumber, "order_channel": wo.OrderChannel})
	} else if orderChannel == "po" || (orderChannel == "" && wo.PONumber != "") {
		wo.OrderChannel = "po"
		h.db.Model(&wo).Update("order_channel", "po")
	}

	for i := range items {
		items[i].WholesaleOrderID = wo.ID
	}
	if err := h.db.Create(&items).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	h.audit(c, "wholesale_order_create", wo.ID, map[string]interface{}{
		"order_number": orderNumber, "client_id": req.WholesaleClientID,
		"po_number": req.PONumber, "item_count": len(items), "subtotal": subtotal,
	})

	var created models.WholesaleOrder
	if err := h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("Store").Preload("User").Preload("Sector").
		First(&created, wo.ID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, created)
}

// RecentOrderChannels returns distinct order_channel values from recent orders (most recent first), for autocomplete.
func (h *WholesaleOrderHandler) RecentOrderChannels(c *gin.Context) {
	var channels []string
	var rows []struct {
		OrderChannel string `gorm:"column:order_channel"`
	}
	err := h.db.Model(&models.WholesaleOrder{}).
		Select("order_channel").
		Where("order_channel != ''").
		Order("created_at DESC").
		Limit(300).
		Find(&rows).Error
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	seen := make(map[string]bool)
	for _, r := range rows {
		ch := strings.TrimSpace(r.OrderChannel)
		if ch != "" && !seen[ch] {
			seen[ch] = true
			channels = append(channels, ch)
		}
	}
	if channels == nil {
		channels = []string{}
	}
	c.JSON(http.StatusOK, gin.H{"channels": channels})
}

func (h *WholesaleOrderHandler) List(c *gin.Context) {
	role, _ := c.Get("role")
	r, _ := role.(string)

	status := c.Query("status")
	storeID := c.Query("store_id")
	clientFilter := c.Query("client")
	poNumberFilter := c.Query("po_number")
	orderNumberFilter := c.Query("order_number")
	refNoFilter := c.Query("ref_no")

	// POS user: only approved orders for packing, must pass store_id; returns orders that have at least one item assigned to this store or unassigned
	if r == "pos_user" {
		if status != "" && status != models.WholesaleOrderStatusApproved {
			c.JSON(http.StatusOK, []models.WholesaleOrder{})
			return
		}
		if storeID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "store_id required for packing list"})
			return
		}
		sid, err := strconv.ParseUint(storeID, 10, 32)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid store_id"})
			return
		}
		storeIDUint := uint(sid)
		var orderIDs []uint
		h.db.Model(&models.WholesaleOrderItem{}).Where(
			"assigned_store_id = ? OR assigned_store_id IS NULL", storeIDUint,
		).Distinct("wholesale_order_id").Pluck("wholesale_order_id", &orderIDs)
		if len(orderIDs) == 0 {
			c.JSON(http.StatusOK, []models.WholesaleOrder{})
			return
		}
		var list []models.WholesaleOrder
		if err := h.db.Where("id IN ? AND status = ?", orderIDs, models.WholesaleOrderStatusApproved).
			Preload("WholesaleClient").Preload("Store").Preload("User").Preload("Sector").
			Preload("Items.Product").Preload("Items.AssignedStore").Preload("Documents").
			Order("created_at DESC").Limit(500).Find(&list).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, list)
		return
	}

	if !requireManagementOrSupervisor(c) {
		return
	}

	query := h.db.Model(&models.WholesaleOrder{}).
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Sector").
		Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("Documents")
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}
	if clientFilter != "" {
		query = query.Where("wholesale_client_id IN (SELECT id FROM wholesale_clients WHERE name LIKE ?)", "%"+clientFilter+"%")
	}
	if poNumberFilter != "" {
		query = query.Where("po_number LIKE ?", "%"+poNumberFilter+"%")
	}
	if orderNumberFilter != "" {
		query = query.Where("order_number LIKE ?", "%"+orderNumberFilter+"%")
	}
	if refNoFilter != "" {
		query = query.Where("ref_no LIKE ?", "%"+refNoFilter+"%")
	}
	query = query.Order("created_at DESC").Limit(500)

	var list []models.WholesaleOrder
	if err := query.Find(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, list)
}

func (h *WholesaleOrderHandler) Get(c *gin.Context) {
	role, _ := c.Get("role")
	// pos_user can only get their own; management/supervisor can get any
	var wo models.WholesaleOrder
	q := h.db.Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Sector").
		Preload("Reviewer").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product")
	if err := q.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	r, _ := role.(string)
	userIDInterface, _ := c.Get("user_id")
	userID := userIDInterface.(uint)
	if r == "pos_user" && wo.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not allowed to view this order"})
		return
	}
	c.JSON(http.StatusOK, wo)
}

func (h *WholesaleOrderHandler) Update(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	var req struct {
		PONumber     *string   `json:"po_number"`
		OrderChannel *string   `json:"order_channel"`
		RefNo        *string   `json:"ref_no"`
		PODate       *string   `json:"po_date"`
		ShippingFee  *float64  `json:"shipping_fee"`
		Items        []struct {
			ID        uint     `json:"id"`
			UnitPrice *float64 `json:"unit_price"`
		} `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	changes := map[string]interface{}{}
	if req.PONumber != nil {
		changes["po_number"] = map[string]interface{}{"old": wo.PONumber, "new": *req.PONumber}
		wo.PONumber = *req.PONumber
	}
	if req.OrderChannel != nil {
		newCh := strings.TrimSpace(*req.OrderChannel)
		changes["order_channel"] = map[string]interface{}{"old": wo.OrderChannel, "new": newCh}
		wo.OrderChannel = newCh
	}
	if req.RefNo != nil {
		newRef := strings.TrimSpace(*req.RefNo)
		if newRef == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "OC Number cannot be empty"})
			return
		}
		var existing models.WholesaleOrder
		if err := h.db.Where("ref_no = ? AND id != ?", newRef, wo.ID).First(&existing).Error; err == nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "OC Number already in use"})
			return
		}
		changes["ref_no"] = map[string]interface{}{"old": wo.RefNo, "new": newRef}
		wo.RefNo = newRef
	}
	if req.PODate != nil {
		oldDate := ""
		if wo.PODate != nil {
			oldDate = wo.PODate.Format("2006-01-02")
		}
		changes["po_date"] = map[string]interface{}{"old": oldDate, "new": *req.PODate}
		wo.PODate = parsePODate(*req.PODate)
	}
	if req.ShippingFee != nil {
		fee := *req.ShippingFee
		if fee < 0 {
			fee = 0
		}
		changes["shipping_fee"] = map[string]interface{}{"old": wo.ShippingFee, "new": fee}
		wo.ShippingFee = fee
	}
	if err := h.db.Save(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(req.Items) > 0 {
		var subtotal float64
		var items []models.WholesaleOrderItem
		h.db.Where("wholesale_order_id = ?", wo.ID).Find(&items)
		itemMap := map[uint]*models.WholesaleOrderItem{}
		for i := range items {
			itemMap[items[i].ID] = &items[i]
		}
		itemChanges := []map[string]interface{}{}
		for _, ri := range req.Items {
			if it, ok := itemMap[ri.ID]; ok && ri.UnitPrice != nil {
				oldPrice := it.UnitPrice
				it.UnitPrice = *ri.UnitPrice
				it.LineTotal = it.UnitPrice*it.Quantity - it.LineDiscountAmount
				if it.LineTotal < 0 {
					it.LineTotal = 0
				}
				h.db.Save(it)
				itemChanges = append(itemChanges, map[string]interface{}{
					"item_id": ri.ID, "old_unit_price": oldPrice, "new_unit_price": *ri.UnitPrice,
				})
			}
		}
		if len(itemChanges) > 0 {
			changes["items"] = itemChanges
		}
		h.db.Where("wholesale_order_id = ?", wo.ID).Find(&items)
		for _, it := range items {
			subtotal += it.LineTotal
		}
		wo.Subtotal = subtotal
		wo.TotalNet = subtotal - wo.DiscountAmount
		if wo.TotalNet < 0 {
			wo.TotalNet = 0
		}
		wo.AmountDue = wo.TotalNet + wo.VATTotal
		h.db.Save(&wo)
	}
	// If shipping fee was updated and all shipments are completed, re-generate invoice.
	if req.ShippingFee != nil {
		var shipments []models.Shipment
		if err := h.db.Where("wholesale_order_id = ?", wo.ID).Find(&shipments).Error; err == nil {
			allCompleted := len(shipments) > 0
			for _, sh := range shipments {
				if sh.Status != models.ShipmentStatusCompleted {
					allCompleted = false
					break
				}
			}
			if allCompleted {
				h.db.Where("wholesale_order_id = ? AND type = ?", wo.ID, "invoice").Delete(&models.WholesaleOrderDocument{})
				var woReload models.WholesaleOrder
				if err := h.db.Preload("Items.Product").
					Preload("WholesaleClient").
					Preload("Store").
					Preload("User").
					Preload("Reviewer").
					Preload("Documents").
					First(&woReload, wo.ID).Error; err == nil {
					if invURL, err := h.generateInvoicePDF(&woReload); err == nil && invURL != "" {
						doc := models.WholesaleOrderDocument{
							WholesaleOrderID: wo.ID,
							Type:             "invoice",
							FileURL:          invURL,
							CreatedAt:        time.Now(),
						}
						if err := h.db.Create(&doc).Error; err != nil {
							fmt.Printf("Failed to save wholesale invoice after shipping fee update for order %d: %v\n", wo.ID, err)
						} else {
							h.audit(c, "wholesale_order_generate_invoice", wo.ID, map[string]interface{}{
								"document_type": "invoice", "trigger": "shipping_fee_updated", "file_url": invURL,
							})
						}
					}
				}
			}
		}
	}
	if len(changes) > 0 {
		h.audit(c, "wholesale_order_update", wo.ID, changes)
	}
	h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("Store").Preload("User").Preload("Sector").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Store").Preload("Shipments.Items").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

func (h *WholesaleOrderHandler) Approve(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	reviewerIDInterface, _ := c.Get("user_id")
	reviewerID := reviewerIDInterface.(uint)

	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status != models.WholesaleOrderStatusPending {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order is not pending approval"})
		return
	}

	oldStatus := string(wo.Status)
	now := time.Now()
	wo.Status = models.WholesaleOrderStatusAssignShipment
	wo.ReviewedAt = &now
	wo.ReviewedBy = &reviewerID
	if err := h.db.Save(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_approve", wo.ID, map[string]interface{}{
		"old_status": oldStatus, "new_status": string(wo.Status),
	})
	h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Reviewer").Preload("Documents").First(&wo, wo.ID)

	// Best-effort: generate order confirmation PDF and store document record.
	if url, err := h.generateOrderConfirmationPDF(&wo); err != nil {
		fmt.Printf("Failed to generate wholesale order confirmation PDF for order %d: %v\n", wo.ID, err)
	} else if url != "" {
		doc := models.WholesaleOrderDocument{
			WholesaleOrderID: wo.ID,
			Type:             "order_confirmation",
			FileURL:          url,
			CreatedAt:        time.Now(),
		}
		if err := h.db.Create(&doc).Error; err != nil {
			fmt.Printf("Failed to save wholesale order document record for order %d: %v\n", wo.ID, err)
		} else {
			h.audit(c, "wholesale_order_generate_oc", wo.ID, map[string]interface{}{
				"document_type": "order_confirmation", "trigger": "approve", "file_url": url,
			})
			h.db.Preload("Documents").First(&wo, wo.ID)
		}
	}
	c.JSON(http.StatusOK, wo)
}

func (h *WholesaleOrderHandler) CompleteAssignment(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status != models.WholesaleOrderStatusAssignShipment {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be in assign_shipment status"})
		return
	}
	oldStatus := string(wo.Status)
	wo.Status = models.WholesaleOrderStatusApproved
	if err := h.db.Save(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_complete_assignment", wo.ID, map[string]interface{}{
		"old_status": oldStatus, "new_status": string(wo.Status),
	})
	h.db.Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

type RejectRequest struct {
	Reason string `json:"reason"`
}

func (h *WholesaleOrderHandler) Reject(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	reviewerIDInterface, _ := c.Get("user_id")
	reviewerID := reviewerIDInterface.(uint)

	var req RejectRequest
	_ = c.ShouldBindJSON(&req)

	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status != models.WholesaleOrderStatusPending {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order is not pending approval"})
		return
	}

	oldStatus := string(wo.Status)
	now := time.Now()
	wo.Status = models.WholesaleOrderStatusRejected
	wo.RejectionReason = req.Reason
	wo.ReviewedAt = &now
	wo.ReviewedBy = &reviewerID
	if err := h.db.Save(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_reject", wo.ID, map[string]interface{}{
		"old_status": oldStatus, "new_status": string(wo.Status), "reason": req.Reason,
	})
	h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// RegenerateOrderConfirmation re-generates the order confirmation PDF and replaces the existing one.
func (h *WholesaleOrderHandler) RegenerateOrderConfirmation(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Reviewer").Preload("Documents").
		First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status != models.WholesaleOrderStatusAssignShipment && wo.Status != models.WholesaleOrderStatusApproved {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be endorsed (assign_shipment or approved) to regenerate confirmation"})
		return
	}
	// Remove existing order_confirmation documents
	h.db.Where("wholesale_order_id = ? AND type = ?", wo.ID, "order_confirmation").Delete(&models.WholesaleOrderDocument{})
	// Generate new PDF
	url, err := h.generateOrderConfirmationPDF(&wo)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	doc := models.WholesaleOrderDocument{
		WholesaleOrderID: wo.ID,
		Type:             "order_confirmation",
		FileURL:          url,
		CreatedAt:        time.Now(),
	}
	if err := h.db.Create(&doc).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_regenerate_oc", wo.ID, map[string]interface{}{
		"document_type": "order_confirmation", "file_url": url,
	})
	h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Documents").First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// GenerateInvoice generates (or regenerates) the invoice PDF for a wholesale order,
// but only if all shipments for the order have been completed.
func (h *WholesaleOrderHandler) GenerateInvoice(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Reviewer").
		Preload("Documents").
		First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	// Ensure all shipments for this order are completed
	var shipments []models.Shipment
	if err := h.db.Where("wholesale_order_id = ?", wo.ID).Find(&shipments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(shipments) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No shipments found for this order; cannot generate invoice"})
		return
	}
	for _, sh := range shipments {
		if sh.Status != models.ShipmentStatusCompleted {
			c.JSON(http.StatusBadRequest, gin.H{"error": "All shipments must be completed before generating invoice"})
			return
		}
	}
	// Remove existing invoice documents, then generate a fresh one
	h.db.Where("wholesale_order_id = ? AND type = ?", wo.ID, "invoice").Delete(&models.WholesaleOrderDocument{})
	url, err := h.generateInvoicePDF(&wo)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	doc := models.WholesaleOrderDocument{
		WholesaleOrderID: wo.ID,
		Type:             "invoice",
		FileURL:          url,
		CreatedAt:        time.Now(),
	}
	if err := h.db.Create(&doc).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_generate_invoice", wo.ID, map[string]interface{}{
		"document_type": "invoice", "file_url": url,
	})
	h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// ordinalDay returns "1st", "2nd", "3rd", "18th", etc.
func parsePODate(s string) *time.Time {
	if s == "" {
		return nil
	}
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		return nil
	}
	return &t
}

func accountCodeOrName(code, name string, maxLen int) string {
	s := code
	if s == "" {
		s = name
	}
	if len([]rune(s)) > maxLen {
		return string([]rune(s)[:maxLen]) + "..."
	}
	return s
}

func ordinalDay(day int) string {
	if day < 1 || day > 31 {
		return strconv.Itoa(day)
	}
	s := strconv.Itoa(day)
	switch {
	case day >= 11 && day <= 13:
		return s + "th"
	case day%10 == 1:
		return s + "st"
	case day%10 == 2:
		return s + "nd"
	case day%10 == 3:
		return s + "rd"
	default:
		return s + "th"
	}
}

// generateOrderConfirmationPDF builds an order confirmation PDF and returns its URL.
func (h *WholesaleOrderHandler) generateOrderConfirmationPDF(wo *models.WholesaleOrder) (string, error) {
	return h.generateWholesaleOrderPDF(wo, "order_confirmation")
}

// generateInvoicePDF builds an invoice PDF (green INVOICE bar, INV- ref, no internal-use box) and returns its URL.
func (h *WholesaleOrderHandler) generateInvoicePDF(wo *models.WholesaleOrder) (string, error) {
	return h.generateWholesaleOrderPDF(wo, "invoice")
}

// generateWholesaleOrderPDF builds either an order confirmation or invoice PDF. docType is "order_confirmation" or "invoice".
func (h *WholesaleOrderHandler) generateWholesaleOrderPDF(wo *models.WholesaleOrder, docType string) (string, error) {
	if h.cfg == nil {
		return "", fmt.Errorf("missing config for PDF generation")
	}
	isInvoice := docType == "invoice"
	if wo.RefNo == "" {
		wo.RefNo = fmt.Sprintf("%d", wo.ID)
	}
	pdf := gofpdf.New("P", "mm", "A4", "")
	// UTF-8 font: try Noto (CJK) first so Chinese displays locally, then Arial, else Helvetica.
	fontName, fontBold := "Helvetica", "Helvetica"
	tryFontPaths := func(paths []string) ([]byte, bool) {
		for _, p := range paths {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			if !filepath.IsAbs(p) {
				if abs, err := filepath.Abs(p); err == nil {
					p = abs
				}
			}
			data, err := os.ReadFile(p)
			if err == nil && len(data) > 0 {
				return data, true
			}
		}
		return nil, false
	}
	uploadDir := strings.TrimSuffix(h.cfg.UploadDir, "/")
	if uploadDir == "" {
		uploadDir = "uploads"
	}
	// Noto (CJK) first so Chinese displays; then Arial
	notoPaths := []string{}
	if basePath := strings.TrimSpace(h.cfg.PDFFontPath); basePath != "" && !strings.Contains(strings.ToLower(basePath), "arial") {
		notoPaths = append(notoPaths, basePath)
	}
	notoPaths = append(notoPaths,
		filepath.Join("pdf-assets", "fonts", "NotoSansTC-Regular.ttf"),
		filepath.Join("pdf-assets", "fonts", "NotoSansSC-Regular.ttf"),
		filepath.Join(uploadDir, "assets", "fonts", "NotoSansTC-Regular.ttf"),
		filepath.Join(uploadDir, "assets", "fonts", "NotoSansSC-Regular.ttf"),
	)
	if data, ok := tryFontPaths(notoPaths); ok {
		pdf.AddUTF8FontFromBytes("Uni", "", data)
		boldData := data
		foundBold := false
		tryBoldPath := func(boldPath string) bool {
			boldPath = strings.TrimSpace(boldPath)
			if boldPath == "" {
				return false
			}
			if !filepath.IsAbs(boldPath) {
				if abs, err := filepath.Abs(boldPath); err == nil {
					boldPath = abs
				}
			}
			b, err := os.ReadFile(boldPath)
			if err == nil && len(b) > 0 {
				boldData = b
				return true
			}
			return false
		}
		for _, p := range notoPaths {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			if !filepath.IsAbs(p) {
				if abs, err := filepath.Abs(p); err == nil {
					p = abs
				}
			}
			dir, file := filepath.Dir(p), filepath.Base(p)
			boldFile := strings.Replace(file, "-Regular.", "-Bold.", 1)
			if boldFile == file {
				boldFile = strings.Replace(file, "Regular", "Bold", 1)
			}
			if boldFile != file && tryBoldPath(filepath.Join(dir, boldFile)) {
				foundBold = true
				break
			}
		}
		if !foundBold {
			tryBoldPath(filepath.Join("pdf-assets", "fonts", "NotoSansTC-Bold.ttf"))
			tryBoldPath(filepath.Join("pdf-assets", "fonts", "NotoSansSC-Bold.ttf"))
			tryBoldPath(filepath.Join(uploadDir, "assets", "fonts", "NotoSansTC-Bold.ttf"))
			tryBoldPath(filepath.Join(uploadDir, "assets", "fonts", "NotoSansSC-Bold.ttf"))
		}
		pdf.AddUTF8FontFromBytes("Uni", "B", boldData)
		fontName, fontBold = "Uni", "Uni"
	} else {
		arialPaths := []string{
			filepath.Join("pdf-assets", "fonts", "Arial Unicode MS.ttf"),
			filepath.Join("pdf-assets", "fonts", "Arial.ttf"),
			filepath.Join(uploadDir, "assets", "fonts", "Arial Unicode MS.ttf"),
			filepath.Join(uploadDir, "assets", "fonts", "Arial.ttf"),
		}
		if basePath := strings.TrimSpace(h.cfg.PDFFontPath); basePath != "" && (strings.Contains(basePath, "Arial") || strings.Contains(basePath, "arial")) {
			arialPaths = append([]string{basePath}, arialPaths...)
		}
		if data, ok := tryFontPaths(arialPaths); ok {
			pdf.AddUTF8FontFromBytes("Arial", "", data)
			pdf.AddUTF8FontFromBytes("Arial", "B", data)
			fontName, fontBold = "Arial", "Arial"
		}
	}
	pageW := 210.0
	margin := 15.0
	pdf.SetMargins(margin, margin, margin)
	pdf.SetAutoPageBreak(true, 22)
	itemsPerPage := 10
	totalPages := (len(wo.Items) + itemsPerPage - 1) / itemsPerPage
	if totalPages == 0 {
		totalPages = 1
	}
	pdf.SetFooterFunc(func() {
		pdf.SetY(-15)
		pdf.SetFont(fontName, "", 8)
		pdf.SetTextColor(150, 150, 150)
		pdf.CellFormat(0, 5, "For questions concerning this document, please contact Chester Lin, +44 7516011596, chesterkklin@ducklincompany.co.uk", "", 1, "C", false, 0, "")
		pdf.CellFormat(0, 5, fmt.Sprintf("Page %d of %d", pdf.PageNo(), totalPages), "", 0, "C", false, 0, "")
	})

	poDate := wo.CreatedAt
	if wo.PODate != nil {
		poDate = *wo.PODate
	}
	dateStr := ordinalDay(poDate.Day()) + " " + poDate.Format("January 2006")
	client := &wo.WholesaleClient
	var deliveryLines []string
	if wo.WholesaleClientStore != nil {
		// Use selected shipping address
		store := wo.WholesaleClientStore
		if store.AddressLine1 != "" {
			deliveryLines = append(deliveryLines, store.AddressLine1)
		}
		if store.AddressLine2 != "" {
			deliveryLines = append(deliveryLines, store.AddressLine2)
		}
		if store.City != "" || store.Postcode != "" {
			deliveryLines = append(deliveryLines, strings.TrimSpace(store.City+" "+store.Postcode))
		}
	}
	if len(deliveryLines) == 0 {
		addr := client.Address
		if addr == "" {
			addr = "-"
		}
		deliveryLines = strings.Split(strings.ReplaceAll(addr, "\r\n", "\n"), "\n")
	}
	if len(deliveryLines) == 0 {
		deliveryLines = []string{"-"}
	}
	contentW := pageW - 2*margin

	// Load company settings for PDF header (configurable via management portal)
	company := models.CompanySettings{
		CompanyName:  "Ducklin Company Ltd",
		AddressLine1: "60 Ravensfield Gardens",
		AddressLine2: "Epsom",
		City:         "London",
		Postcode:     "KT19 0SR",
		Telephone:    "+44 7516 011596",
		Email:        "hello@ducklincompany.co.uk",
	}
	_ = h.db.First(&company, 1).Error // use defaults above if not found

	// Repeating page header: logo, ORDER CONFIRMATION bar, company, client/delivery, Account table
	pdf.SetHeaderFunc(func() {
		logoPath := strings.TrimSpace(h.cfg.PDFLogoPath)
		if logoPath == "" {
			logoPath = filepath.Join(uploadDir, "assets", "images", "pdf_logo.png")
		}
		if !filepath.IsAbs(logoPath) {
			if abs, err := filepath.Abs(logoPath); err == nil {
				logoPath = abs
			}
		}
		logoW, logoH := 50.0, 0.0
		if logoPath != "" {
			if _, err := os.Stat(logoPath); err == nil {
				if info := pdf.RegisterImage(logoPath, "PNG"); info != nil {
					wd, ht := info.Width(), info.Height()
					if wd > 0 && ht > 0 {
						logoH = logoW * (ht / wd)
						if logoH > 28 {
							logoH = 28
						}
						pdf.Image(logoPath, margin, 15, logoW, logoH, false, "PNG", 0, "")
					}
				}
			}
		}
		barW := 75.0
		barX := pageW - margin - barW
		barY := 15.0
		if isInvoice {
			pdf.SetFillColor(0, 128, 0)
		} else {
			pdf.SetFillColor(0, 0, 0)
		}
		pdf.Rect(barX, barY, barW, 9, "F")
		pdf.SetTextColor(255, 255, 255)
		pdf.SetFont(fontBold, "B", 12)
		pdf.SetXY(barX, barY+2)
		if isInvoice {
			pdf.CellFormat(barW, 6, "INVOICE", "", 1, "C", false, 0, "")
		} else {
			pdf.CellFormat(barW, 6, "ORDER CONFIRMATION", "", 1, "C", false, 0, "")
		}
		pdf.SetTextColor(0, 0, 0)
		keyW := 32.0
		poY := barY + 11 + 10
		pdf.SetXY(barX, poY)
		pdf.SetFont(fontBold, "B", 10)
		docRef := wo.PONumber + " / " + wo.RefNo
		if isInvoice {
			pdf.CellFormat(keyW, 5, "Invoice No:", "", 0, "L", false, 0, "")
		} else {
			pdf.CellFormat(keyW, 5, "PO/OC No:", "", 0, "L", false, 0, "")
		}
		pdf.SetFont(fontName, "", 10)
		pdf.CellFormat(barW-keyW, 5, docRef, "", 1, "L", false, 0, "")
		pdf.SetXY(barX, pdf.GetY()+5)
		pdf.SetFont(fontBold, "B", 10)
		pdf.CellFormat(keyW, 5, "Date:", "", 0, "L", false, 0, "")
		pdf.SetFont(fontName, "", 10)
		pdf.CellFormat(barW-keyW, 5, dateStr, "", 1, "L", false, 0, "")
		companyY := 15.0 + logoH + 6
		if logoH <= 0 {
			companyY = 15
		}
		pdf.SetXY(margin, companyY)
		pdf.SetFont(fontBold, "B", 11)
		if company.CompanyName != "" {
			pdf.CellFormat(0, 5, company.CompanyName, "", 1, "L", false, 0, "")
		}
		pdf.SetFont(fontName, "", 9)
		// 2 address lines + postal code
		if company.AddressLine1 != "" {
			pdf.CellFormat(0, 4, company.AddressLine1, "", 1, "L", false, 0, "")
		}
		if company.AddressLine2 != "" {
			pdf.CellFormat(0, 4, company.AddressLine2, "", 1, "L", false, 0, "")
		}
		if company.Postcode != "" {
			pdf.CellFormat(0, 4, company.Postcode, "", 1, "L", false, 0, "")
		}
		if company.Telephone != "" {
			pdf.CellFormat(0, 4, "Telephone: "+company.Telephone, "", 1, "L", false, 0, "")
		}
		if company.Email != "" {
			pdf.CellFormat(0, 4, "Email: "+company.Email, "", 1, "L", false, 0, "")
		}
		pdf.Ln(4)
		colW := contentW / 2
		labelW := 32.0
		valueW := colW - labelW
		rowH := 5.5
		boxY := pdf.GetY()
		// Left: company info. Right: store info (2 address lines only; client postcode not on the right)
		clientNameDisplay := client.Name
		if client.CompanyNumber != "" {
			clientNameDisplay = client.Name + " (" + client.CompanyNumber + ")"
		}
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Company Name:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, clientNameDisplay, "", 0, "L", false, 0, "")
		dLine1 := ""
		if len(deliveryLines) > 0 {
			dLine1 = deliveryLines[0]
		}
		if dLine1 == "" {
			dLine1 = client.AddressLine1
		}
		dLine2 := ""
		if len(deliveryLines) > 1 {
			dLine2 = deliveryLines[1]
		}
		if dLine2 == "" {
			dLine2 = client.AddressLine2
		}
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Delivery to:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, dLine1, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "VAT No:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, client.VATNumber, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, dLine2, "", 1, "L", false, 0, "")
		// Left address: Address: then address line 1, address line 2, postcode (3 lines)
		addrLine1 := ""
		if len(deliveryLines) > 0 {
			addrLine1 = deliveryLines[0]
		}
		if addrLine1 == "" {
			addrLine1 = client.AddressLine1
		}
		addrLine2 := ""
		if len(deliveryLines) > 1 {
			addrLine2 = deliveryLines[1]
		}
		if addrLine2 == "" {
			addrLine2 = client.AddressLine2
		}
		addrPostcode := ""
		if len(deliveryLines) > 2 {
			addrPostcode = strings.Join(deliveryLines[2:], " ")
		}
		if addrPostcode == "" {
			addrPostcode = client.Postcode
		}
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Address:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, addrLine1, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, "", "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, addrLine2, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, "", "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, addrPostcode, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, "", "", 1, "L", false, 0, "")
		contactName := client.ContactName
		contactEmail := client.Email
		contactPhone := client.Phone
		if wo.WholesaleClientStore != nil {
			if wo.WholesaleClientStore.ContactName != "" {
				contactName = wo.WholesaleClientStore.ContactName
			}
			if wo.WholesaleClientStore.Email != "" {
				contactEmail = wo.WholesaleClientStore.Email
			}
			if wo.WholesaleClientStore.Phone != "" {
				contactPhone = wo.WholesaleClientStore.Phone
			}
		}
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Contact Name:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactName, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Contact Name:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactName, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Email:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactEmail, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Email:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactEmail, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Telephone:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactPhone, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Telephone:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, client.Phone, "", 1, "L", false, 0, "")
		boxEndY := pdf.GetY()
		pdf.Rect(margin, boxY, contentW, boxEndY-boxY, "D")
		pdf.Line(margin+colW, boxY, margin+colW, boxEndY)
		pdf.Ln(4)
		sixth := contentW / 6
		wTerms := contentW - 3*sixth
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(sixth, 5, "Account Code", "1", 0, "L", false, 0, "")
		pdf.CellFormat(sixth, 5, "PO number", "1", 0, "L", false, 0, "")
		pdf.CellFormat(sixth, 5, "PO Date", "1", 0, "L", false, 0, "")
		pdf.CellFormat(wTerms, 5, "Terms", "1", 1, "L", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		termsForTable := wo.PaymentTerms
		if termsForTable == "" {
			termsForTable = client.Terms
		}
		if termsForTable == "" {
			termsForTable = "7 days on invoice."
		}
		pdf.CellFormat(sixth, 5, accountCodeOrName(client.AccountCode, client.Name, 15), "1", 0, "L", false, 0, "")
		pdf.CellFormat(sixth, 5, wo.PONumber, "1", 0, "L", false, 0, "")
		pdf.CellFormat(sixth, 5, dateStr, "1", 0, "L", false, 0, "")
		pdf.CellFormat(wTerms, 5, termsForTable, "1", 1, "L", false, 0, "")
		pdf.Ln(4)
	})

	pdf.AddPage()

	// ----- Order entries: 15 items per page, pad with "-"; multi-page with footer page number -----
	wDesc := contentW * 50 / 100
	wQty := contentW * 7 / 100
	wPrice := contentW * 8 / 100
	wNet := contentW * 8 / 100
	wVAT := contentW * 12 / 100
	wTotal := contentW - wDesc - wQty - wPrice - wNet - wVAT
	wVATRate := wVAT * 45 / 100
	wVATAmt := wVAT - wVATRate
	headerH := 6.0
	itemRowH := 5.0
	itemRowH2 := 3.5
	gapBetweenItems := 2.0
	emptyRowH := itemRowH + itemRowH2
	brdrL, brdrM, brdrR := "", "", ""

	var subtotal float64
	var totalQty float64
	itemIndex := 0
	drawTableHeader := func() {
		pdf.SetFont(fontBold, "B", 6)
		pdf.CellFormat(wDesc, headerH, "Item Description", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wQty, headerH, "Qty", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wPrice, headerH, "Price", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wNet, headerH, "Total Net", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wVAT, headerH, "VAT", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wTotal, headerH, "Total Amount", "1", 1, "R", false, 0, "")
		pdf.SetFont(fontName, "", 7)
	}

	for page := 0; page < totalPages; page++ {
		if page > 0 {
			pdf.AddPage()
		}
		tableStartY := pdf.GetY()
		drawTableHeader()

		itemsOnPage := itemsPerPage
		if itemIndex+itemsOnPage > len(wo.Items) {
			itemsOnPage = len(wo.Items) - itemIndex
		}
		// Full page: 15 items = 30 rows. Last page: itemsOnPage*2 + (15-itemsOnPage) rows (e.g. 1 item + 14 '-' = 2+14=16)
		rowsThisPage := itemsOnPage*2 + (itemsPerPage - itemsOnPage)
		linesUsed := 0

		for i := 0; i < itemsOnPage; i++ {
			it := wo.Items[itemIndex]
			itemIndex++
			line1 := it.Product.NameChinese
			if line1 == "" {
				line1 = it.Product.Name
			}
			if line1 == "" {
				line1 = fmt.Sprintf("Product #%d", it.ProductID)
			}
			line2 := it.Product.Name
			if line2 == line1 || line2 == "" {
				line2 = ""
			}
			vatRate := "0%"
			vatAmt := 0.0
			vatAmtStr := "£ " + fmt.Sprintf("%.2f", vatAmt)
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 9)
			}
			pdf.CellFormat(wDesc, itemRowH, line1, brdrL, 0, "L", false, 0, "")
			pdf.CellFormat(wQty, itemRowH, fmt.Sprintf("%.2f", it.Quantity), brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wPrice, itemRowH, fmt.Sprintf("£ %.2f", it.UnitPrice), brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wNet, itemRowH, fmt.Sprintf("£ %.2f", it.LineTotal), brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wVATRate, itemRowH, vatRate, brdrM, 0, "C", false, 0, "")
			pdf.CellFormat(wVATAmt, itemRowH, vatAmtStr, brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wTotal, itemRowH, fmt.Sprintf("£ %.2f", it.LineTotal), brdrR, 1, "R", false, 0, "")
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 7)
			}
			linesUsed++
			pdf.CellFormat(wDesc, itemRowH2, line2, brdrL, 0, "L", false, 0, "")
			pdf.CellFormat(wQty, itemRowH2, "", brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wPrice, itemRowH2, "", brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wNet, itemRowH2, "", brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wVATRate, itemRowH2, "", brdrM, 0, "L", false, 0, "")
			pdf.CellFormat(wVATAmt, itemRowH2, "", brdrM, 0, "R", false, 0, "")
			pdf.CellFormat(wTotal, itemRowH2, "", brdrR, 1, "R", false, 0, "")
			linesUsed++
			pdf.Ln(gapBetweenItems)
			subtotal += it.LineTotal
			totalQty += it.Quantity
		}

		for linesUsed < rowsThisPage {
			pdf.CellFormat(wDesc, emptyRowH, "-", brdrL, 0, "L", false, 0, "")
			pdf.CellFormat(wQty, emptyRowH, "-", brdrM, 0, "C", false, 0, "")
			pdf.CellFormat(wPrice, emptyRowH, "-", brdrM, 0, "C", false, 0, "")
			pdf.CellFormat(wNet, emptyRowH, "-", brdrM, 0, "C", false, 0, "")
			pdf.CellFormat(wVATRate, emptyRowH, "-", brdrM, 0, "C", false, 0, "")
			pdf.CellFormat(wVATAmt, emptyRowH, "-", brdrM, 0, "C", false, 0, "")
			pdf.CellFormat(wTotal, emptyRowH, "-", brdrR, 1, "C", false, 0, "")
			linesUsed++
		}

		tableEndY := pdf.GetY()
		x0 := margin
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wDesc
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wQty
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wPrice
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wNet
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wVATRate
		pdf.Line(x0, tableStartY+headerH, x0, tableEndY)
		x0 += wVATAmt
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wTotal
		pdf.Line(x0, tableStartY, x0, tableEndY)

		if page != totalPages-1 {
			pdf.Line(margin, tableEndY, margin+contentW, tableEndY)
			continue
		}
		// Last page only: totals, Total Qty row, order total, Internal Use
		break
	}

	if wo.Subtotal > 0 {
		subtotal = wo.Subtotal
	}
	totalNet := wo.TotalNet
	if totalNet == 0 {
		totalNet = subtotal - wo.DiscountAmount
	}
	vatTotal := wo.VATTotal
	// Amount due = Total Net + VAT; use derived value so table footer matches the Total Net column
	amountDue := totalNet + vatTotal
	orderShippingFee := wo.ShippingFee
	if orderShippingFee < 0 {
		orderShippingFee = 0
	}
	grandTotal := amountDue + orderShippingFee
	pdf.SetFont(fontName, "", 5)
	brdrLRB := "LRB"
	pdf.CellFormat(wDesc, itemRowH, "Total Qty of Items: ", brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wQty, itemRowH, fmt.Sprintf("%.2f", totalQty), brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wPrice, itemRowH, "", brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wNet, itemRowH, fmt.Sprintf("£ %.2f", totalNet), brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wVATRate, itemRowH, "", brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wVATAmt, itemRowH, fmt.Sprintf("£ %.2f", vatTotal), brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wTotal, itemRowH, fmt.Sprintf("£ %.2f", amountDue), brdrLRB, 1, "R", false, 0, "")

	// ----- Same row: Internal Use box (left, under product names) | Order total (right), stuck to product entry -----
	totLabelW := wVAT
	totValueW := wTotal
	totX := margin + wDesc + wQty + wPrice + wNet
	orderTotalH := 8.0
	reviewerName := ""
	if wo.Reviewer != nil {
		reviewerName = wo.Reviewer.FirstName + " " + wo.Reviewer.LastName
		if reviewerName == " " {
			reviewerName = wo.Reviewer.Username
		}
	}
	if reviewerName == "" {
		reviewerName = "-"
	}
	reviewDate := "-"
	if wo.ReviewedAt != nil {
		reviewDate = wo.ReviewedAt.Format("02/01/2006")
	}
	internalBoxW := 70.0
	internalColW := internalBoxW / 2
	internalBoxX := margin
	headerHInternal := 8.0
	rowHInternal := 6.0

	yBottomRow := pdf.GetY()

	// Left: Internal Use box for order confirmation; Bank + THANK YOU section for invoice (same position)
	if !isInvoice {
		pdf.SetXY(internalBoxX, yBottomRow+3)
		pdf.SetFillColor(0, 0, 0)
		pdf.SetTextColor(255, 255, 255)
		pdf.SetFont(fontBold, "B", 10)
		pdf.CellFormat(internalBoxW, headerHInternal, "For Ducklin Internal Use Only", "1", 1, "C", true, 0, "")
		pdf.SetFillColor(255, 255, 255)
		pdf.SetTextColor(0, 0, 0)
		pdf.SetX(internalBoxX)
		pdf.SetFont(fontBold, "B", 8)
		pdf.CellFormat(internalColW, rowHInternal, "Approved by", "1", 0, "C", false, 0, "")
		pdf.CellFormat(internalColW, rowHInternal, "Date", "1", 1, "C", false, 0, "")
		pdf.SetX(internalBoxX)
		pdf.SetFont(fontName, "", 8)
		pdf.CellFormat(internalColW, rowHInternal, reviewerName, "1", 0, "C", false, 0, "")
		pdf.CellFormat(internalColW, rowHInternal, reviewDate, "1", 1, "C", false, 0, "")
		pdf.SetTextColor(0, 0, 0)
	} else {
		// Invoice: payment info (free text up to 5 lines) or legacy bank fields + THANK YOU
		pdf.SetXY(internalBoxX, yBottomRow+3)
		pdf.SetTextColor(100, 100, 100)
		pdf.SetFont(fontName, "", 7)
		paymentInfo := strings.TrimSpace(company.PaymentInfo)
		if paymentInfo != "" {
			pdf.CellFormat(internalBoxW, 4, "Payment details:", "", 1, "L", false, 0, "")
			pdf.SetTextColor(0, 0, 0)
			pdf.SetFont(fontName, "", 8)
			lines := strings.Split(paymentInfo, "\n")
			for i := 0; i < 5 && i < len(lines); i++ {
				line := strings.TrimSpace(lines[i])
				if line != "" {
					pdf.CellFormat(internalBoxW, 4, line, "", 1, "L", false, 0, "")
				}
			}
		} else {
			bankName := company.BankAccountName
			if bankName == "" {
				bankName = "Heartwood Trading Ltd"
			}
			bankAcc := company.BankAccountNumber
			if bankAcc == "" {
				bankAcc = "25307108"
			}
			bankSort := company.BankSortCode
			if bankSort == "" {
				bankSort = "23-08-01"
			}
			bankAddr := company.BankAddress
			if bankAddr == "" {
				bankAddr = "56 Shoreditch High Street, London E1 6JJ"
			}
			bankIBAN := company.BankIBAN
			if bankIBAN == "" {
				bankIBAN = "GB90 TRWI 2308 0125 3071 08"
			}
			pdf.CellFormat(internalBoxW, 4, "Please make bank transfer payable to:", "", 1, "L", false, 0, "")
			pdf.SetTextColor(0, 0, 0)
			pdf.SetFont(fontName, "", 8)
			pdf.CellFormat(internalBoxW, 4, "Company Name: "+bankName, "", 1, "L", false, 0, "")
			pdf.CellFormat(internalBoxW, 4, "Account number: "+bankAcc, "", 1, "L", false, 0, "")
			pdf.CellFormat(internalBoxW, 4, "Sort Code: "+bankSort, "", 1, "L", false, 0, "")
			pdf.CellFormat(internalBoxW, 4, "Bank Address: "+bankAddr, "", 1, "L", false, 0, "")
			pdf.CellFormat(internalBoxW, 4, "IBAN: "+bankIBAN, "", 1, "L", false, 0, "")
		}
		pdf.SetTextColor(0, 0, 180)
		pdf.SetFont(fontBold, "B", 10)
		pdf.CellFormat(internalBoxW, 6, "THANK YOU", "", 1, "L", false, 0, "")
		pdf.SetTextColor(0, 0, 0)
	}

	// Right: Order total — Total Net, VAT Total, Shipping Fee, Amount Due
	pdf.SetFont(fontBold, "B", 8)
	pdf.SetXY(totX, yBottomRow)
	pdf.CellFormat(totLabelW, orderTotalH, "Total Net :", "1", 0, "R", false, 0, "")
	pdf.CellFormat(totValueW, orderTotalH, "£ "+fmt.Sprintf("%.2f", totalNet), "1", 1, "R", false, 0, "")
	pdf.SetXY(totX, yBottomRow+orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "VAT Total :", "1", 0, "R", false, 0, "")
	pdf.CellFormat(totValueW, orderTotalH, "£ "+fmt.Sprintf("%.2f", vatTotal), "1", 1, "R", false, 0, "")
	pdf.SetXY(totX, yBottomRow+2*orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "Shipping Fee :", "1", 0, "R", false, 0, "")
	pdf.CellFormat(totValueW, orderTotalH, "£ "+fmt.Sprintf("%.2f", orderShippingFee), "1", 1, "R", false, 0, "")
	pdf.SetXY(totX, yBottomRow+3*orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "Amount Due :", "1", 0, "R", false, 0, "")
	pdf.CellFormat(totValueW, orderTotalH, "£ "+fmt.Sprintf("%.2f", grandTotal), "1", 1, "R", false, 0, "")

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return "", fmt.Errorf("failed to render PDF: %w", err)
	}
	var filename string
	if isInvoice {
		filename = fmt.Sprintf("%s-invoice-%d.pdf", wo.OrderNumber, time.Now().UnixNano())
	} else {
		filename = fmt.Sprintf("%s-order-confirmation-%d.pdf", wo.OrderNumber, time.Now().UnixNano())
	}
	url, err := h.uploadWholesalePDF(filename, buf.Bytes())
	if err != nil {
		return "", err
	}
	return url, nil
}

// uploadWholesalePDF uploads PDF bytes to either cloud storage (if configured) or local filesystem.
func (h *WholesaleOrderHandler) uploadWholesalePDF(filename string, data []byte) (string, error) {
	if h.cfg.StorageProvider == "gcp" && h.cfg.GCPBucketName != "" {
		ctx := context.Background()
		client, err := storage.NewClient(ctx)
		if err != nil {
			return "", fmt.Errorf("failed to create GCP storage client: %w", err)
		}
		defer client.Close()

		bucket := client.Bucket(h.cfg.GCPBucketName)
		obj := bucket.Object("wholesale-docs/" + filename)
		writer := obj.NewWriter(ctx)
		writer.ContentType = "application/pdf"

		if _, err := writer.Write(data); err != nil {
			_ = writer.Close()
			return "", fmt.Errorf("failed to write PDF to GCP bucket: %w", err)
		}
		if err := writer.Close(); err != nil {
			return "", fmt.Errorf("failed to close GCP writer: %w", err)
		}

		if err := obj.ACL().Set(ctx, storage.AllUsers, storage.RoleReader); err != nil {
			fmt.Printf("Warning: failed to set public ACL for wholesale PDF %s: %v\n", filename, err)
		}

		url := fmt.Sprintf("https://storage.googleapis.com/%s/wholesale-docs/%s", h.cfg.GCPBucketName, filename)
		return url, nil
	}

	// Default: save locally under uploads/wholesale-docs
	uploadDir := h.cfg.UploadDir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	dir := filepath.Join(uploadDir, "wholesale-docs")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create wholesale-docs dir: %w", err)
	}
	filePath := filepath.Join(dir, filename)
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		return "", fmt.Errorf("failed to save wholesale PDF: %w", err)
	}

	baseURL := strings.TrimSuffix(h.cfg.BaseURL, "/")
	url := fmt.Sprintf("%s/uploads/wholesale-docs/%s", baseURL, filename)
	return url, nil
}

// ListShipments returns shipments. POS: pass store_id to get shipments for that store. Management: no filter or optional store_id.
func (h *WholesaleOrderHandler) ListShipments(c *gin.Context) {
	storeIDStr := c.Query("store_id")
	query := h.db.Model(&models.Shipment{})
	if storeIDStr != "" {
		storeID, err := strconv.ParseUint(storeIDStr, 10, 32)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid store_id"})
			return
		}
		query = query.Where("store_id = ?", uint(storeID))
	}
	var list []models.Shipment
	if err := query.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").
		Order("id DESC").Find(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, list)
}

// GetShipment returns one shipment by ID with order, store, and items (with product).
func (h *WholesaleOrderHandler) GetShipment(c *gin.Context) {
	var s models.Shipment
	if err := h.db.Preload("Store").
		Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.WholesaleClientStore").
		Preload("Items.WholesaleOrderItem.Product").
		First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	c.JSON(http.StatusOK, s)
}

// UpdateShipmentRequest allows updating courier and tracking number.
type UpdateShipmentRequest struct {
	Courier        *string `json:"courier"`
	TrackingNumber *string `json:"tracking_number"`
}

// UpdateShipment updates courier and/or tracking number (management/supervisor or POS for their store).
func (h *WholesaleOrderHandler) UpdateShipment(c *gin.Context) {
	var s models.Shipment
	if err := h.db.First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	var req UpdateShipmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	changes := map[string]interface{}{}
	if req.Courier != nil {
		changes["courier"] = map[string]interface{}{"old": s.Courier, "new": *req.Courier}
		s.Courier = *req.Courier
	}
	if req.TrackingNumber != nil {
		changes["tracking_number"] = map[string]interface{}{"old": s.TrackingNumber, "new": *req.TrackingNumber}
		s.TrackingNumber = *req.TrackingNumber
	}
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(changes) > 0 {
		h.audit(c, "wholesale_shipment_update", s.WholesaleOrderID, map[string]interface{}{
			"shipment_id": s.ID, "changes": changes,
		})
	}
	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// CompletePacking marks shipment as completed and generates the delivery note PDF.
func (h *WholesaleOrderHandler) CompletePacking(c *gin.Context) {
	var s models.Shipment
	if err := h.db.Preload("Store").
		Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.WholesaleClientStore").
		Preload("Items.WholesaleOrderItem").First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if s.Status == models.ShipmentStatusCompleted {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment already completed"})
		return
	}
	var body struct {
		CaseQty []struct {
			WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
			CaseQty              float64 `json:"case_qty"`
		} `json:"case_qty"`
	}
	_ = c.ShouldBindJSON(&body)
	// Apply case qty per item (from force-complete dialog)
	itemCaseQty := make(map[uint]float64)
	for _, e := range body.CaseQty {
		if e.CaseQty < 0 {
			e.CaseQty = 0
		}
		itemCaseQty[e.WholesaleOrderItemID] = e.CaseQty
	}
	for i := range s.Items {
		if cq, ok := itemCaseQty[s.Items[i].WholesaleOrderItemID]; ok {
			s.Items[i].CaseQty = cq
		}
		h.db.Model(&s.Items[i]).Update("case_qty", s.Items[i].CaseQty)
	}
	// Load products for items
	for i := range s.Items {
		h.db.Model(&s.Items[i].WholesaleOrderItem).Association("Product").Find(&s.Items[i].WholesaleOrderItem.Product)
	}
	url, err := h.generateDeliveryNotePDF(&s)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate delivery note: " + err.Error()})
		return
	}
	oldStatus := string(s.Status)
	s.DeliveryNotePDFURL = url
	s.Status = models.ShipmentStatusCompleted
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_shipment_complete_packing", s.WholesaleOrderID, map[string]interface{}{
		"shipment_id": s.ID, "old_status": oldStatus, "new_status": string(s.Status), "file_url": url,
	})
	// If all shipments for this order are completed, generate invoice PDF once.
	var shipments []models.Shipment
	if err := h.db.Where("wholesale_order_id = ?", s.WholesaleOrderID).Find(&shipments).Error; err == nil {
		allCompleted := len(shipments) > 0
		for _, sh := range shipments {
			if sh.Status != models.ShipmentStatusCompleted {
				allCompleted = false
				break
			}
		}
		if allCompleted {
			var existing models.WholesaleOrderDocument
			errDoc := h.db.Where("wholesale_order_id = ? AND type = ?", s.WholesaleOrderID, "invoice").First(&existing).Error
			if errors.Is(errDoc, gorm.ErrRecordNotFound) {
				var wo models.WholesaleOrder
				if err := h.db.Preload("Items.Product").
					Preload("WholesaleClient").
					Preload("Store").
					Preload("User").
					Preload("Reviewer").
					Preload("Documents").
					First(&wo, s.WholesaleOrderID).Error; err == nil {
					if invURL, err := h.generateInvoicePDF(&wo); err == nil && invURL != "" {
						doc := models.WholesaleOrderDocument{
							WholesaleOrderID: wo.ID,
							Type:             "invoice",
							FileURL:          invURL,
							CreatedAt:        time.Now(),
						}
						if err := h.db.Create(&doc).Error; err != nil {
							fmt.Printf("Failed to save wholesale invoice document for order %d: %v\n", wo.ID, err)
						} else {
							h.audit(c, "wholesale_order_generate_invoice", wo.ID, map[string]interface{}{
								"document_type": "invoice", "trigger": "all_shipments_completed", "file_url": invURL,
							})
						}
					} else if err != nil {
						fmt.Printf("Failed to generate wholesale invoice PDF for order %d: %v\n", wo.ID, err)
					}
				}
			}
		}
	}
	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// RegenerateDeliveryNote re-generates the delivery note PDF for a shipment and updates delivery_note_pdf_url.
func (h *WholesaleOrderHandler) RegenerateDeliveryNote(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var s models.Shipment
	if err := h.db.Preload("Store").
		Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.WholesaleClientStore").
		Preload("Items.WholesaleOrderItem").First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if len(s.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment has no items"})
		return
	}
	for i := range s.Items {
		h.db.Model(&s.Items[i].WholesaleOrderItem).Association("Product").Find(&s.Items[i].WholesaleOrderItem.Product)
	}
	url, err := h.generateDeliveryNotePDF(&s)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate delivery note: " + err.Error()})
		return
	}
	s.DeliveryNotePDFURL = url
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_shipment_regenerate_dn", s.WholesaleOrderID, map[string]interface{}{
		"shipment_id": s.ID, "document_type": "delivery_note", "file_url": url,
	})
	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// UpdateShipmentCaseQty updates case/box qty per item and regenerates the delivery note PDF for completed shipments.
func (h *WholesaleOrderHandler) UpdateShipmentCaseQty(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var s models.Shipment
	if err := h.db.Preload("Store").
		Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.WholesaleClientStore").
		Preload("Items.WholesaleOrderItem").First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if len(s.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment has no items"})
		return
	}
	var body struct {
		CaseQty []struct {
			WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
			CaseQty              float64 `json:"case_qty"`
		} `json:"case_qty"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}
	itemCaseQty := make(map[uint]float64)
	for _, e := range body.CaseQty {
		if e.CaseQty < 0 {
			e.CaseQty = 0
		}
		itemCaseQty[e.WholesaleOrderItemID] = e.CaseQty
	}
	for i := range s.Items {
		if cq, ok := itemCaseQty[s.Items[i].WholesaleOrderItemID]; ok {
			s.Items[i].CaseQty = cq
		}
		if err := h.db.Model(&s.Items[i]).Update("case_qty", s.Items[i].CaseQty).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	for i := range s.Items {
		h.db.Model(&s.Items[i].WholesaleOrderItem).Association("Product").Find(&s.Items[i].WholesaleOrderItem.Product)
	}
	if s.Status == models.ShipmentStatusCompleted {
		url, err := h.generateDeliveryNotePDF(&s)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to regenerate delivery note: " + err.Error()})
			return
		}
		s.DeliveryNotePDFURL = url
		if err := h.db.Save(&s).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		h.audit(c, "wholesale_shipment_update_case_qty", s.WholesaleOrderID, map[string]interface{}{
			"shipment_id": s.ID, "document_type": "delivery_note", "file_url": url,
		})
	}
	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// generateDeliveryNotePDF builds a delivery note PDF (same style as order confirmation): company header, client/delivery block,
// "Delivery Note" title, row with Account, PO number, Delivery Date, Delivery Channel, Received by; item table (Item Description, Item Qty, Case Qty).
func (h *WholesaleOrderHandler) generateDeliveryNotePDF(s *models.Shipment) (string, error) {
	if h.cfg == nil {
		return "", fmt.Errorf("missing config for PDF generation")
	}
	wo := &s.WholesaleOrder
	client := &wo.WholesaleClient

	// Determine shipment number (1-based position among all shipments for this order, ordered by ID)
	var allShipments []models.Shipment
	h.db.Where("wholesale_order_id = ?", wo.ID).Order("id ASC").Find(&allShipments)
	shipmentNum := 1
	for i, sh := range allShipments {
		if sh.ID == s.ID {
			shipmentNum = i + 1
			break
		}
	}

	if wo.RefNo == "" {
		wo.RefNo = fmt.Sprintf("%d", wo.ID)
	}

	// Order items come from shipment items (with product and case qty per item)

	pdf := gofpdf.New("P", "mm", "A4", "")
	// UTF-8 font: try Noto (CJK) first so Chinese displays locally, then Arial, else Helvetica.
	fontName, fontBold := "Helvetica", "Helvetica"
	uploadDir := strings.TrimSuffix(h.cfg.UploadDir, "/")
	if uploadDir == "" {
		uploadDir = "uploads"
	}
	tryFontPaths := func(paths []string) ([]byte, bool) {
		for _, p := range paths {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			if !filepath.IsAbs(p) {
				if abs, err := filepath.Abs(p); err == nil {
					p = abs
				}
			}
			data, err := os.ReadFile(p)
			if err == nil && len(data) > 0 {
				return data, true
			}
		}
		return nil, false
	}
	notoPaths := []string{}
	if basePath := strings.TrimSpace(h.cfg.PDFFontPath); basePath != "" && !strings.Contains(strings.ToLower(basePath), "arial") {
		notoPaths = append(notoPaths, basePath)
	}
	notoPaths = append(notoPaths,
		filepath.Join("pdf-assets", "fonts", "NotoSansTC-Regular.ttf"),
		filepath.Join("pdf-assets", "fonts", "NotoSansSC-Regular.ttf"),
		filepath.Join(uploadDir, "assets", "fonts", "NotoSansTC-Regular.ttf"),
		filepath.Join(uploadDir, "assets", "fonts", "NotoSansSC-Regular.ttf"),
	)
	if data, ok := tryFontPaths(notoPaths); ok {
		pdf.AddUTF8FontFromBytes("Uni", "", data)
		boldData := data
		for _, p := range notoPaths {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			if !filepath.IsAbs(p) {
				if abs, err := filepath.Abs(p); err == nil {
					p = abs
				}
			}
			dir, file := filepath.Dir(p), filepath.Base(p)
			boldFile := strings.Replace(file, "-Regular.", "-Bold.", 1)
			if boldFile == file {
				boldFile = strings.Replace(file, "Regular", "Bold", 1)
			}
			if boldFile != file {
				b, _ := os.ReadFile(filepath.Join(dir, boldFile))
				if len(b) > 0 {
					boldData = b
					break
				}
			}
		}
		pdf.AddUTF8FontFromBytes("Uni", "B", boldData)
		fontName, fontBold = "Uni", "Uni"
	} else {
		arialPaths := []string{
			filepath.Join("pdf-assets", "fonts", "Arial Unicode MS.ttf"),
			filepath.Join("pdf-assets", "fonts", "Arial.ttf"),
			filepath.Join(uploadDir, "assets", "fonts", "Arial Unicode MS.ttf"),
			filepath.Join(uploadDir, "assets", "fonts", "Arial.ttf"),
		}
		if basePath := strings.TrimSpace(h.cfg.PDFFontPath); basePath != "" && (strings.Contains(basePath, "Arial") || strings.Contains(basePath, "arial")) {
			arialPaths = append([]string{basePath}, arialPaths...)
		}
		if data, ok := tryFontPaths(arialPaths); ok {
			pdf.AddUTF8FontFromBytes("Arial", "", data)
			pdf.AddUTF8FontFromBytes("Arial", "B", data)
			fontName, fontBold = "Arial", "Arial"
		}
	}

	pageW := 210.0
	margin := 15.0
	pdf.SetMargins(margin, margin, margin)
	pdf.SetAutoPageBreak(true, 22)
	contentW := pageW - 2*margin

	company := models.CompanySettings{
		CompanyName: "Ducklin Company Ltd", AddressLine1: "60 Ravensfield Gardens", AddressLine2: "Epsom", City: "London", Postcode: "KT19 0SR",
		Telephone: "+44 7516 011596", Email: "hello@ducklincompany.co.uk",
	}
	_ = h.db.First(&company, 1).Error

	deliveryDate := time.Now()
	dateStr := ordinalDay(deliveryDate.Day()) + " " + deliveryDate.Format("January 2006")
	var dLine1, dLine2, addrPostcode string
	if wo.WholesaleClientStore != nil {
		store := wo.WholesaleClientStore
		dLine1 = store.AddressLine1
		dLine2 = store.AddressLine2
		if store.City != "" || store.Postcode != "" {
			addrPostcode = strings.TrimSpace(store.City + " " + store.Postcode)
		} else {
			addrPostcode = store.Postcode
		}
	}
	if dLine1 == "" {
		dLine1 = client.AddressLine1
	}
	if dLine1 == "" {
		dLine1 = "-"
	}
	if dLine2 == "" {
		dLine2 = client.AddressLine2
	}
	if addrPostcode == "" {
		addrPostcode = client.Postcode
	}

	pdf.SetHeaderFunc(func() {
		logoPath := strings.TrimSpace(h.cfg.PDFLogoPath)
		if logoPath == "" {
			logoPath = filepath.Join(uploadDir, "assets", "images", "pdf_logo.png")
		}
		if !filepath.IsAbs(logoPath) {
			if abs, err := filepath.Abs(logoPath); err == nil {
				logoPath = abs
			}
		}
		logoW, logoH := 50.0, 0.0
		if logoPath != "" {
			if _, err := os.Stat(logoPath); err == nil {
				if info := pdf.RegisterImage(logoPath, "PNG"); info != nil {
					wd, ht := info.Width(), info.Height()
					if wd > 0 && ht > 0 {
						logoH = logoW * (ht / wd)
						if logoH > 28 {
							logoH = 28
						}
						pdf.Image(logoPath, margin, 15, logoW, logoH, false, "PNG", 0, "")
					}
				}
			}
		}
		barW := 75.0
		barX := pageW - margin - barW
		barY := 15.0
		pdf.SetFillColor(0, 51, 102)
		pdf.Rect(barX, barY, barW, 9, "F")
		pdf.SetTextColor(255, 255, 255)
		pdf.SetFont(fontBold, "B", 12)
		pdf.SetXY(barX, barY+2)
		pdf.CellFormat(barW, 6, "Delivery Note", "", 1, "C", false, 0, "")
		pdf.SetTextColor(0, 0, 0)
		keyW := 32.0
		poY := barY + 11 + 10
		pdf.SetXY(barX, poY)
		pdf.SetFont(fontBold, "B", 10)
		dnRef := fmt.Sprintf("d%d - %s / %s", shipmentNum, wo.PONumber, wo.RefNo)
		pdf.CellFormat(keyW, 5, "DN No:", "", 0, "L", false, 0, "")
		pdf.SetFont(fontName, "", 10)
		pdf.CellFormat(barW-keyW, 5, dnRef, "", 1, "L", false, 0, "")
		pdf.SetXY(barX, pdf.GetY()+5)
		pdf.SetFont(fontBold, "B", 10)
		pdf.CellFormat(keyW, 5, "Date:", "", 0, "L", false, 0, "")
		pdf.SetFont(fontName, "", 10)
		pdf.CellFormat(barW-keyW, 5, dateStr, "", 1, "L", false, 0, "")
		companyY := 15.0 + logoH + 6
		if logoH <= 0 {
			companyY = 15
		}
		pdf.SetXY(margin, companyY)
		pdf.SetFont(fontBold, "B", 11)
		if company.CompanyName != "" {
			pdf.CellFormat(0, 5, company.CompanyName, "", 1, "L", false, 0, "")
		}
		pdf.SetFont(fontName, "", 9)
		if company.AddressLine1 != "" {
			pdf.CellFormat(0, 4, company.AddressLine1, "", 1, "L", false, 0, "")
		}
		if company.AddressLine2 != "" {
			pdf.CellFormat(0, 4, company.AddressLine2, "", 1, "L", false, 0, "")
		}
		if company.Postcode != "" {
			pdf.CellFormat(0, 4, company.Postcode, "", 1, "L", false, 0, "")
		}
		if company.Telephone != "" {
			pdf.CellFormat(0, 4, "Telephone: "+company.Telephone, "", 1, "L", false, 0, "")
		}
		if company.Email != "" {
			pdf.CellFormat(0, 4, "Email: "+company.Email, "", 1, "L", false, 0, "")
		}
		pdf.Ln(4)
		colW := contentW / 2
		labelW := 32.0
		valueW := colW - labelW
		rowH := 5.5
		boxY := pdf.GetY()
		clientNameDisplay := client.Name
		if client.CompanyNumber != "" {
			clientNameDisplay = client.Name + " (" + client.CompanyNumber + ")"
		}
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Company Name:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, clientNameDisplay, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Delivery to:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, dLine1, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "VAT No:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, client.VATNumber, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, dLine2, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Address:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, dLine1, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, "", "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, dLine2, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, addrPostcode, "", 1, "L", false, 0, "")
		contactName := client.ContactName
		contactEmail := client.Email
		contactPhone := client.Phone
		if wo.WholesaleClientStore != nil {
			if wo.WholesaleClientStore.ContactName != "" {
				contactName = wo.WholesaleClientStore.ContactName
			}
			if wo.WholesaleClientStore.Email != "" {
				contactEmail = wo.WholesaleClientStore.Email
			}
			if wo.WholesaleClientStore.Phone != "" {
				contactPhone = wo.WholesaleClientStore.Phone
			}
		}
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Contact Name:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactName, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Contact Name:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactName, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Email:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactEmail, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Email:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactEmail, "", 1, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Telephone:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, contactPhone, "", 0, "L", false, 0, "")
		pdf.SetFont(fontBold, "B", 9)
		pdf.CellFormat(labelW, rowH, "Telephone:", "", 0, "R", false, 0, "")
		pdf.SetFont(fontName, "", 9)
		pdf.CellFormat(valueW, rowH, client.Phone, "", 1, "L", false, 0, "")
		boxEndY := pdf.GetY()
		pdf.Rect(margin, boxY, contentW, boxEndY-boxY, "D")
		pdf.Line(margin+colW, boxY, margin+colW, boxEndY)
		pdf.Ln(4)
		// Second table: Account, PO number, Delivery Date, Delivery Channel, Received by / Delivery Reference (width ratio 2:2:2:3:3)
		w2 := contentW * 2 / 12
		w3 := contentW * 3 / 12

		pdf.SetFont(fontBold, "B", 7)
		pdf.CellFormat(w2, 5, "Account", "1", 0, "L", false, 0, "")
		pdf.CellFormat(w2, 5, "PO number", "1", 0, "L", false, 0, "")
		pdf.CellFormat(w2, 5, "Delivery Date", "1", 0, "L", false, 0, "")
		pdf.CellFormat(w3, 5, "Delivery Channel", "1", 0, "L", false, 0, "")
		pdf.CellFormat(w3, 5, "Received by / Delivery Reference", "1", 1, "L", false, 0, "")
		pdf.SetFont(fontName, "", 7)
		courier := s.Courier
		if courier == "" {
			courier = "-"
		}
		poNumberDisplay := wo.PONumber
		if ch := strings.TrimSpace(wo.OrderChannel); ch != "" && ch != "po" {
			switch strings.ToLower(ch) {
			case "whatsapp":
				poNumberDisplay = "Whatsapp"
			case "email":
				poNumberDisplay = "Email"
			default:
				if len(ch) >= 1 {
					poNumberDisplay = strings.ToUpper(ch[:1]) + strings.ToLower(ch[1:])
				} else {
					poNumberDisplay = ch
				}
			}
		} else if poNumberDisplay == "" {
			poNumberDisplay = "-"
		}
		pdf.CellFormat(w2, 5, accountCodeOrName(client.AccountCode, client.Name, 15), "1", 0, "L", false, 0, "")
		pdf.CellFormat(w2, 5, poNumberDisplay, "1", 0, "L", false, 0, "")
		pdf.CellFormat(w2, 5, dateStr, "1", 0, "L", false, 0, "")
		pdf.CellFormat(w3, 5, courier, "1", 0, "L", false, 0, "")
		pdf.CellFormat(w3, 5, s.TrackingNumber, "1", 1, "L", false, 0, "")
		pdf.Ln(4)
	})

	pdf.AddPage()
	// Item table full width: description (70%), item qty (15%), case qty (15%)
	wDesc := contentW * 70 / 100
	wItemQty := contentW * 15 / 100
	wCaseQty := contentW - wDesc - wItemQty
	headerH := 6.0
	itemRowH := 5.0
	itemRowH2 := 3.5
	gapBetweenItems := 2.0
	emptyRowH := itemRowH + itemRowH2
	itemsPerPage := 13
	totalPages := len(s.Items)/itemsPerPage + 1
	pdf.SetFooterFunc(func() {
		pdf.SetY(-15)
		pdf.SetFont(fontName, "", 8)
		pdf.SetTextColor(150, 150, 150)
		pdf.CellFormat(0, 5, "For questions concerning this document, please contact Chester Lin, +44 7516011596, chesterkklin@ducklincompany.co.uk", "", 1, "C", false, 0, "")
		pdf.CellFormat(0, 5, fmt.Sprintf("Page %d of %d", pdf.PageNo(), totalPages), "", 0, "C", false, 0, "")
	})

	var totalItemQty, totalCaseQty float64
	itemIndex := 0
	drawTableHeader := func() {
		pdf.SetFont(fontBold, "B", 8)
		pdf.CellFormat(wDesc, headerH, "Item Description", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wItemQty, headerH, "Item Qty", "1", 0, "C", false, 0, "")
		pdf.CellFormat(wCaseQty, headerH, "Case Qty", "1", 1, "C", false, 0, "")
		pdf.SetFont(fontName, "", 7)
	}

	for page := 0; page < totalPages; page++ {
		if page > 0 {
			pdf.AddPage()
		}
		tableStartY := pdf.GetY()
		drawTableHeader()
		rowsThisPage := itemsPerPage
		linesUsed := 0
		for i := 0; i < itemsPerPage && itemIndex < len(s.Items); i++ {
			si := s.Items[itemIndex]
			it := si.WholesaleOrderItem
			itemIndex++
			line1 := it.Product.NameChinese
			if line1 == "" {
				line1 = it.Product.Name
			}
			if line1 == "" {
				line1 = fmt.Sprintf("Product #%d", it.ProductID)
			}
			line2 := it.Product.Name
			if line2 == line1 || line2 == "" {
				line2 = ""
			}
			caseQty := si.CaseQty
			caseQtyStr := "-"
			if caseQty > 0 {
				caseQtyStr = fmt.Sprintf("%.2f", caseQty)
			}
			// No border between item entries (use "" so only table outline is drawn)
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 9)
			}
			pdf.CellFormat(wDesc, itemRowH, line1, "", 0, "L", false, 0, "")
			pdf.CellFormat(wItemQty, itemRowH, fmt.Sprintf("%.2f", it.Quantity), "", 0, "R", false, 0, "")
			pdf.CellFormat(wCaseQty, itemRowH, caseQtyStr, "", 1, "R", false, 0, "")
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 7)
			}
			linesUsed++
			totalItemQty += it.Quantity
			totalCaseQty += caseQty
			if line2 != "" {
				pdf.CellFormat(wDesc, itemRowH2, line2, "", 0, "L", false, 0, "")
				pdf.CellFormat(wItemQty, itemRowH2, "", "", 0, "R", false, 0, "")
				pdf.CellFormat(wCaseQty, itemRowH2, "", "", 1, "R", false, 0, "")
				// linesUsed++
			}
			pdf.Ln(gapBetweenItems)
		}
		for linesUsed < rowsThisPage {
			pdf.CellFormat(wDesc, emptyRowH, "-", "", 0, "L", false, 0, "")
			pdf.CellFormat(wItemQty, emptyRowH, "-", "", 0, "C", false, 0, "")
			pdf.CellFormat(wCaseQty, emptyRowH, "-", "", 1, "C", false, 0, "")
			pdf.Ln(gapBetweenItems)
			linesUsed++
		}
		tableEndY := pdf.GetY()
		x0 := margin
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wDesc
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wItemQty
		pdf.Line(x0, tableStartY, x0, tableEndY)
		x0 += wCaseQty
		pdf.Line(x0, tableStartY, x0, tableEndY)
		if page != totalPages-1 {
			pdf.Line(margin, tableEndY, margin+contentW, tableEndY)
			continue
		}
		break
	}

	pdf.SetFont(fontName, "", 9)
	pdf.CellFormat(wDesc, 6, "Total Qty of Items:", "LRB", 0, "R", false, 0, "")
	pdf.CellFormat(wItemQty, 6, fmt.Sprintf("%.0f", totalItemQty), "LRB", 0, "R", false, 0, "")
	totalCaseStr := "-"
	if totalCaseQty > 0 {
		totalCaseStr = fmt.Sprintf("%.0f", totalCaseQty)
	}
	pdf.CellFormat(wCaseQty, 6, totalCaseStr, "LRB", 1, "R", false, 0, "")

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return "", fmt.Errorf("failed to render PDF: %w", err)
	}
	filename := fmt.Sprintf("%s-delivery-note-%d-%d.pdf", wo.OrderNumber, s.ID, time.Now().UnixNano())
	url, err := h.uploadWholesalePDF(filename, buf.Bytes())
	if err != nil {
		return "", err
	}
	return url, nil
}

// AssignStoresRequest allows assigning each order line to a store (or nil for "no store").
type AssignStoresRequest struct {
	Assignments []struct {
		WholesaleOrderItemID uint  `json:"wholesale_order_item_id" binding:"required"`
		StoreID              *uint `json:"store_id"` // nil = no store assigned
	} `json:"assignments" binding:"required,min=1"`
}

func (h *WholesaleOrderHandler) AssignStores(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status != models.WholesaleOrderStatusApproved && wo.Status != models.WholesaleOrderStatusAssignShipment {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be approved or in assign_shipment to assign stores"})
		return
	}

	var req AssignStoresRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate stores exist
	for _, a := range req.Assignments {
		if a.StoreID != nil {
			var st models.Store
			if err := h.db.First(&st, *a.StoreID).Error; err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Store %d not found", *a.StoreID)})
				return
			}
		}
	}

	// Validate all items belong to this order
	var itemIDs []uint
	for _, a := range req.Assignments {
		itemIDs = append(itemIDs, a.WholesaleOrderItemID)
	}
	var count int64
	h.db.Model(&models.WholesaleOrderItem{}).Where("wholesale_order_id = ? AND id IN ?", wo.ID, itemIDs).Count(&count)
	if int(count) != len(itemIDs) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "All item IDs must belong to this order"})
		return
	}

	for _, a := range req.Assignments {
		if err := h.db.Model(&models.WholesaleOrderItem{}).Where("id = ?", a.WholesaleOrderItemID).Update("assigned_store_id", a.StoreID).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	// Build shipments: one per (order, store) that has assigned items; link items via ShipmentItem.
	type storeItems struct {
		storeID uint
		itemIDs []uint
	}
	byStore := make(map[uint][]uint)
	for _, a := range req.Assignments {
		if a.StoreID == nil {
			continue
		}
		byStore[*a.StoreID] = append(byStore[*a.StoreID], a.WholesaleOrderItemID)
	}
	// Remove existing shipment items for this order's shipments (re-assign replaces all).
	var existingShipments []models.Shipment
	if err := h.db.Where("wholesale_order_id = ?", wo.ID).Find(&existingShipments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	for _, s := range existingShipments {
		h.db.Where("shipment_id = ?", s.ID).Delete(&models.ShipmentItem{})
	}
	for storeID, itemIDs := range byStore {
		var ship models.Shipment
		err := h.db.Where("wholesale_order_id = ? AND store_id = ?", wo.ID, storeID).First(&ship).Error
		if err != nil {
			ship = models.Shipment{
				WholesaleOrderID: wo.ID,
				StoreID:          storeID,
				Status:           models.ShipmentStatusPacking,
			}
			if err := h.db.Create(&ship).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
		for _, itemID := range itemIDs {
			if err := h.db.Create(&models.ShipmentItem{ShipmentID: ship.ID, WholesaleOrderItemID: itemID}).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
	}
	// Delete shipments that no longer have any items (all unassigned from that store)
	for _, s := range existingShipments {
		var count int64
		h.db.Model(&models.ShipmentItem{}).Where("shipment_id = ?", s.ID).Count(&count)
		if count == 0 {
			h.db.Delete(&s)
		}
	}

	assignmentChanges := []map[string]interface{}{}
	for _, a := range req.Assignments {
		entry := map[string]interface{}{"item_id": a.WholesaleOrderItemID}
		if a.StoreID != nil {
			entry["store_id"] = *a.StoreID
		}
		assignmentChanges = append(assignmentChanges, entry)
	}
	h.audit(c, "wholesale_order_assign_stores", wo.ID, map[string]interface{}{
		"assignments": assignmentChanges,
	})

	var updated models.WholesaleOrder
	if err := h.db.Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items").
		First(&updated, wo.ID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

func (h *WholesaleOrderHandler) GetAuditLogs(c *gin.Context) {
	orderID := c.Param("id")
	var logs []models.AuditLog
	if err := h.db.Where("entity_type = ? AND entity_id = ?", "wholesale_order", orderID).
		Preload("User").Order("created_at DESC, id DESC").Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, logs)
}

// EmailDocument sends a document (OC, invoice, or DN) to the client's email and records an audit log.
func (h *WholesaleOrderHandler) EmailDocument(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.Preload("WholesaleClient").First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	var req struct {
		DocumentType string `json:"document_type" binding:"required"`
		Recipient    string `json:"recipient"`
		ShipmentID   *uint  `json:"shipment_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	recipient := req.Recipient
	if recipient == "" {
		recipient = wo.WholesaleClient.Email
	}
	if recipient == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No recipient email address"})
		return
	}

	actionMap := map[string]string{
		"order_confirmation": "wholesale_order_email_oc",
		"invoice":            "wholesale_order_email_invoice",
		"delivery_note":      "wholesale_order_email_dn",
	}
	action, ok := actionMap[req.DocumentType]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid document type"})
		return
	}

	changes := map[string]interface{}{
		"document_type": req.DocumentType,
		"recipient":     recipient,
	}
	if req.ShipmentID != nil {
		changes["shipment_id"] = *req.ShipmentID
	}

	// TODO: implement actual email sending here

	h.audit(c, action, wo.ID, changes)
	c.JSON(http.StatusOK, gin.H{"message": "Email recorded", "recipient": recipient})
}
