package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/storage"
	"github.com/gin-gonic/gin"
	"github.com/jung-kurt/gofpdf"
	"golang.org/x/net/context"
	"gorm.io/gorm"
	"pos-system/backend/internal/config"
	apimail "pos-system/backend/internal/mail"
	"pos-system/backend/internal/models"
)

type WholesaleOrderHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewWholesaleOrderHandler(db *gorm.DB, cfg *config.Config) *WholesaleOrderHandler {
	return &WholesaleOrderHandler{db: db, cfg: cfg}
}

// isOrderCompleted returns true when all shipments are done and payment is confirmed.
func isOrderCompleted(wo *models.WholesaleOrder) bool {
	if wo.PaymentConfirmedAt == nil {
		return false
	}
	if len(wo.Shipments) == 0 {
		return false
	}
	for _, s := range wo.Shipments {
		if s.Status != models.ShipmentStatusCompleted {
			return false
		}
	}
	return true
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

func wholesaleMgmtRolesOk(r string) bool {
	return r == "management" || r == "supervisor" || r == "admin" || r == "system_admin"
}

// requireManagementOrSupervisor aborts with 403 unless role is management, supervisor, admin, or system_admin.
func requireManagementOrSupervisor(c *gin.Context) bool {
	role, _ := c.Get("role")
	r, _ := role.(string)
	if !wholesaleMgmtRolesOk(r) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Admin or manager role required"})
		c.Abort()
		return false
	}
	return true
}

// requireManagementSupervisorOrAdmin allows the same wholesale management roles as requireManagementOrSupervisor.
func requireManagementSupervisorOrAdmin(c *gin.Context) bool {
	return requireManagementOrSupervisor(c)
}

func parseUnlockAfterCompletion(c *gin.Context) bool {
	return c.Query("unlock_after_completion") == "true" || c.PostForm("unlock_after_completion") == "true"
}

func (h *WholesaleOrderHandler) isWholesaleOrderFullyCompleted(orderID uint) (bool, error) {
	var wo models.WholesaleOrder
	if err := h.db.Select("payment_confirmed_at").First(&wo, orderID).Error; err != nil {
		return false, err
	}
	if wo.PaymentConfirmedAt == nil || wo.PaymentConfirmedAt.IsZero() {
		return false, nil
	}
	var shipments []models.Shipment
	if err := h.db.Where("wholesale_order_id = ?", orderID).Find(&shipments).Error; err != nil {
		return false, err
	}
	if len(shipments) == 0 {
		return false, nil
	}
	for _, s := range shipments {
		if s.Status != models.ShipmentStatusCompleted {
			return false, nil
		}
	}
	return true, nil
}

// rejectOrderUploadUnlessUnlocked blocks uploads/deletes on fully completed orders unless unlock_after_completion is set.
func (h *WholesaleOrderHandler) rejectOrderUploadUnlessUnlocked(c *gin.Context, orderID uint, unlockAfterCompletion bool) bool {
	completed, err := h.isWholesaleOrderFullyCompleted(orderID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return true
	}
	if !completed {
		return false
	}
	if unlockAfterCompletion {
		return false
	}
	c.JSON(http.StatusConflict, gin.H{
		"error": "Order is completed; unlock uploads to add or change attachments.",
		"code":  "order_upload_locked",
	})
	return true
}

// rejectIfOrderCompleted returns true and aborts with 403 if the order has payment_confirmed_at set.
func (h *WholesaleOrderHandler) rejectIfOrderCompleted(c *gin.Context, orderID uint) bool {
	var wo models.WholesaleOrder
	if err := h.db.Select("payment_confirmed_at").First(&wo, orderID).Error; err != nil {
		return false
	}
	if wo.PaymentConfirmedAt != nil && !wo.PaymentConfirmedAt.IsZero() {
		c.JSON(http.StatusForbidden, gin.H{"error": "Order is completed; updates and deletions are not allowed"})
		c.Abort()
		return true
	}
	return false
}

func abortIfWholesaleOrderDeleted(c *gin.Context, status string) bool {
	if status == models.WholesaleOrderStatusDeleted {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order has been deleted"})
		c.Abort()
		return true
	}
	return false
}

func (h *WholesaleOrderHandler) abortIfWholesaleOrderDeletedByID(c *gin.Context, orderID uint) bool {
	var wo models.WholesaleOrder
	if err := h.db.Select("status").First(&wo, orderID).Error; err != nil {
		return false
	}
	return abortIfWholesaleOrderDeleted(c, wo.Status)
}

// requirePosUserSupervisorOrManagement allows create for pos_user, supervisor, management, or admin.
func requirePosUserSupervisorOrManagement(c *gin.Context) bool {
	role, _ := c.Get("role")
	r, _ := role.(string)
	if r != "pos_user" && r != "supervisor" && r != "management" && r != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "POS user, supervisor, or admin role required"})
		c.Abort()
		return false
	}
	return true
}

type CreateWholesaleOrderRequest struct {
	WholesaleClientID      uint    `json:"wholesale_client_id" binding:"required"`
	WholesaleClientStoreID *uint   `json:"wholesale_client_store_id"` // shipping address
	StoreID                uint    `json:"store_id" binding:"required"`
	SectorID               *uint   `json:"sector_id"`
	PONumber               string  `json:"po_number"`
	OrderChannel           string  `json:"order_channel"` // "po" = client provided PO, "whatsapp" = we generate PO (delivery note shows "Whatsapp")
	PODate                 string  `json:"po_date"`
	OrderDate              string  `json:"order_date"`
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
			// Base price for wholesale order (PO-date "price"):
			// use the retail online store price for that season.
			unitPrice = cost.DirectRetailOnlineStorePriceGBP
			// If retail isn't set for that season, fallback later to current retail.
		}
		// If the PO-date retail price isn't set, fall back to current/latest retail.
		if unitPrice <= 0 {
			var currentCost models.ProductCost
			// "Current/latest price" should be the latest configured cost up to now.
			// Do not require effective_to > now, otherwise future/unset PO dates could yield 0.
			if err := h.db.Where("product_id = ? AND (effective_from IS NULL OR effective_from <= ?)",
				product.ID, now).
				Order("effective_from DESC").First(&currentCost).Error; err == nil {
				unitPrice = currentCost.DirectRetailOnlineStorePriceGBP
				if unitPrice <= 0 {
					// Last resort: if retail is still unset, use wholesale cost.
					unitPrice = currentCost.WholesaleCostGBP
				}
			} else {
				unitPrice = 0
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
		OrderDate:              parsePODate(req.OrderDate),
		PaymentTerms:           paymentTerms,
		ShippingFee:            shippingFee,
		Status:                 models.WholesaleOrderStatusPending,
		Subtotal:               subtotal,
		DiscountAmount:         discount,
		TotalNet:               totalNet,
		VATTotal:               vatTotal,
		AmountDue:              amountDue,
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

	// If no PO provided, always generate PO [003][dd][mm][yy] and store channel
	if wo.PONumber == "" {
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
	} else {
		// If client supplied a PO and channel indicates client PO (or blank), normalise to "po"
		if orderChannel == "po" || (orderChannel == "" && wo.PONumber != "") {
			wo.OrderChannel = "po"
			h.db.Model(&wo).Update("order_channel", "po")
		} else if orderChannel != "" {
			wo.OrderChannel = orderChannel
			h.db.Model(&wo).Update("order_channel", orderChannel)
		}
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

const poAttachmentDocType = "po_attachment"
const paymentProofDocType = "payment_proof"

// UploadPOAttachments accepts multipart form with files (key "po_attachments"). Saves each to wholesale-docs/po/ and creates a WholesaleOrderDocument with type po_attachment.
func (h *WholesaleOrderHandler) UploadPOAttachments(c *gin.Context) {
	if !requirePosUserSupervisorOrManagement(c) {
		return
	}
	orderID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order ID"})
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.First(&wo, orderID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	if h.rejectOrderUploadUnlessUnlocked(c, wo.ID, parseUnlockAfterCompletion(c)) {
		return
	}

	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Expected multipart form: " + err.Error()})
		return
	}
	files := form.File["po_attachments"]
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No files provided (use form key 'po_attachments')"})
		return
	}
	var existingCount int64
	h.db.Model(&models.WholesaleOrderDocument{}).Where("wholesale_order_id = ? AND type = ?", wo.ID, poAttachmentDocType).Count(&existingCount)

	allowedExt := map[string]bool{
		".pdf": true, ".png": true, ".jpg": true, ".jpeg": true, ".gif": true, ".webp": true,
	}
	var saved int
	for _, fh := range files {
		ext := strings.ToLower(filepath.Ext(fh.Filename))
		if ext == "" {
			ext = ".bin"
		}
		if !allowedExt[ext] {
			continue // skip disallowed
		}
		if existingCount >= 5 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 5 PO attachments allowed"})
			return
		}
		existingCount++
		url, err := h.savePOAttachment(uint(orderID), fh)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file " + fh.Filename + ": " + err.Error()})
			return
		}
		displayName := strings.TrimSpace(fh.Filename)
		if displayName == "" || displayName == "blob" || displayName == "file" ||
			strings.HasPrefix(displayName, "blob:") || len(displayName) < 2 {
			displayName = "PO attachment" + ext
		}
		doc := models.WholesaleOrderDocument{
			WholesaleOrderID: wo.ID,
			Type:             poAttachmentDocType,
			FileURL:          url,
			OriginalFilename: displayName,
			CreatedAt:        time.Now(),
		}
		if err := h.db.Create(&doc).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to record attachment"})
			return
		}
		saved++
	}
	c.JSON(http.StatusOK, gin.H{"saved": saved})
}

// savePOAttachment saves an uploaded file (PDF or image) to wholesale-docs/po/ and returns the public URL.
func (h *WholesaleOrderHandler) savePOAttachment(orderID uint, fh *multipart.FileHeader) (string, error) {
	f, err := fh.Open()
	if err != nil {
		return "", err
	}
	defer f.Close()
	data := make([]byte, fh.Size)
	if _, err := f.Read(data); err != nil {
		return "", err
	}
	ext := strings.ToLower(filepath.Ext(fh.Filename))
	if ext == "" {
		ext = ".bin"
	}
	safeName := fmt.Sprintf("%d_%d%s", orderID, time.Now().UnixNano(), ext)
	return h.uploadWholesaleFile("po/"+safeName, data)
}

// uploadWholesaleFile saves file bytes to wholesale-docs/ subpath (e.g. "po/123_xxx.pdf") and returns the public URL.
func wholesaleFileContentType(subpath string) string {
	switch strings.ToLower(filepath.Ext(subpath)) {
	case ".pdf":
		return "application/pdf"
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".heic":
		return "image/heic"
	case ".zip":
		return "application/zip"
	default:
		return "application/octet-stream"
	}
}

func readMultipartFileBytes(fh *multipart.FileHeader) ([]byte, error) {
	f, err := fh.Open()
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}

func (h *WholesaleOrderHandler) uploadWholesaleFile(subpath string, data []byte) (string, error) {
	if h.cfg.StorageProvider == "gcp" && h.cfg.GCPBucketName != "" {
		ctx := context.Background()
		client, err := storage.NewClient(ctx)
		if err != nil {
			return "", fmt.Errorf("gcp client: %w", err)
		}
		defer client.Close()
		objPath := "wholesale-docs/" + subpath
		bucket := client.Bucket(h.cfg.GCPBucketName)
		obj := bucket.Object(objPath)
		writer := obj.NewWriter(ctx)
		writer.ContentType = wholesaleFileContentType(subpath)
		if _, err := writer.Write(data); err != nil {
			_ = writer.Close()
			return "", err
		}
		if err := writer.Close(); err != nil {
			return "", err
		}
		if err := obj.ACL().Set(ctx, storage.AllUsers, storage.RoleReader); err != nil {
			// non-fatal
		}
		return fmt.Sprintf("https://storage.googleapis.com/%s/%s", h.cfg.GCPBucketName, objPath), nil
	}
	uploadDir := h.cfg.UploadDir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	dir := filepath.Join(uploadDir, "wholesale-docs", filepath.Dir(subpath))
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	filePath := filepath.Join(uploadDir, "wholesale-docs", subpath)
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		return "", err
	}
	baseURL := strings.TrimSuffix(h.cfg.BaseURL, "/")
	return fmt.Sprintf("%s/uploads/wholesale-docs/%s", baseURL, subpath), nil
}

// DeletePOAttachment deletes a document by ID if it belongs to the order and type is po_attachment.
func (h *WholesaleOrderHandler) DeletePOAttachment(c *gin.Context) {
	if !requirePosUserSupervisorOrManagement(c) {
		return
	}
	orderID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order ID"})
		return
	}
	docID, err := strconv.ParseUint(c.Param("docId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid document ID"})
		return
	}
	var doc models.WholesaleOrderDocument
	if err := h.db.First(&doc, docID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Document not found"})
		return
	}
	if doc.WholesaleOrderID != uint(orderID) || (doc.Type != poAttachmentDocType && doc.Type != paymentProofDocType) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Cannot delete this document"})
		return
	}
	if h.abortIfWholesaleOrderDeletedByID(c, uint(orderID)) {
		return
	}
	if h.rejectOrderUploadUnlessUnlocked(c, uint(orderID), parseUnlockAfterCompletion(c)) {
		return
	}
	if err := h.db.Delete(&doc).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// DownloadDocument streams a document file with Content-Disposition: attachment for download.
func (h *WholesaleOrderHandler) DownloadDocument(c *gin.Context) {
	if !requirePosUserSupervisorOrManagement(c) {
		return
	}
	orderID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order ID"})
		return
	}
	docID, err := strconv.ParseUint(c.Param("docId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid document ID"})
		return
	}
	var doc models.WholesaleOrderDocument
	if err := h.db.First(&doc, docID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Document not found"})
		return
	}
	if doc.WholesaleOrderID != uint(orderID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Cannot access this document"})
		return
	}
	// Any POS/supervisor/management user authenticated for wholesale routes may download documents
	// linked to the order (metadata is already exposed on order payloads; bulk ZIP needs OC/DN/invoice).
	filename := doc.OriginalFilename
	if filename == "" {
		if u, err := url.Parse(doc.FileURL); err == nil {
			filename = filepath.Base(u.Path)
		}
		if filename == "" {
			filename = "download"
		}
	}
	if doc.Type == "order_confirmation" || doc.Type == "invoice" || doc.Type == "delivery_note" {
		var wo models.WholesaleOrder
		if err := h.db.Select("id", "ref_no").First(&wo, orderID).Error; err == nil {
			refNo := strings.TrimSpace(wo.RefNo)
			if refNo == "" {
				refNo = fmt.Sprintf("D%d", wo.ID)
			}
			refNo = strings.ReplaceAll(refNo, "/", "_")
			refNo = strings.ReplaceAll(refNo, "\\", "_")
			refNo = strings.ReplaceAll(refNo, " ", "_")
			docType := doc.Type
			ext := strings.ToLower(filepath.Ext(filename))
			if ext == "" {
				ext = ".pdf"
			}
			timestamp := time.Now().Format("20060102-150405")
			filename = fmt.Sprintf("%s_%s_%d_%s%s", refNo, docType, doc.ID, timestamp, ext)
		}
	}

	var reader io.Reader
	if strings.Contains(doc.FileURL, "storage.googleapis.com") && h.cfg.GCPBucketName != "" {
		u, err := url.Parse(doc.FileURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid file URL"})
			return
		}
		path := strings.TrimPrefix(strings.TrimPrefix(u.Path, "/"), h.cfg.GCPBucketName+"/")
		if path == "" {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid GCS path"})
			return
		}
		ctx := context.Background()
		client, err := storage.NewClient(ctx)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to access storage"})
			return
		}
		defer client.Close()
		obj := client.Bucket(h.cfg.GCPBucketName).Object(path)
		r, err := obj.NewReader(ctx)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file"})
			return
		}
		defer r.Close()
		reader = r
	} else {
		u, err := url.Parse(doc.FileURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid file URL"})
			return
		}
		uploadDir := h.cfg.UploadDir
		if uploadDir == "" {
			uploadDir = "./uploads"
		}
		localPath := filepath.Join(uploadDir, strings.TrimPrefix(u.Path, "/uploads/"))
		f, err := os.Open(localPath)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "File not found"})
			return
		}
		defer f.Close()
		reader = f
	}

	preview := c.Query("preview") == "1"
	contentType := "application/octet-stream"
	if preview {
		ext := strings.ToLower(filepath.Ext(filename))
		switch ext {
		case ".jpg", ".jpeg":
			contentType = "image/jpeg"
		case ".png":
			contentType = "image/png"
		case ".gif":
			contentType = "image/gif"
		case ".webp":
			contentType = "image/webp"
		case ".pdf":
			contentType = "application/pdf"
		}
		c.Header("Content-Type", contentType)
		c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%q", filename))
	} else {
		c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
		c.Header("Content-Type", contentType)
	}
	io.Copy(c.Writer, reader)
}

// DownloadLegacyPaymentProof streams the order's payment_proof_url with Content-Disposition for backward compatibility.
func (h *WholesaleOrderHandler) DownloadLegacyPaymentProof(c *gin.Context) {
	if !requirePosUserSupervisorOrManagement(c) {
		return
	}
	orderID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order ID"})
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.First(&wo, orderID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}
	if wo.PaymentProofURL == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "No payment proof"})
		return
	}
	fileURL := wo.PaymentProofURL
	u, err := url.Parse(fileURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid file URL"})
		return
	}
	filename := filepath.Base(u.Path)
	if filename == "" {
		filename = "payment-proof"
	}

	var reader io.Reader
	if strings.Contains(fileURL, "storage.googleapis.com") && h.cfg.GCPBucketName != "" {
		path := strings.TrimPrefix(strings.TrimPrefix(u.Path, "/"), h.cfg.GCPBucketName+"/")
		if path == "" {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid GCS path"})
			return
		}
		ctx := context.Background()
		client, err := storage.NewClient(ctx)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to access storage"})
			return
		}
		defer client.Close()
		r, err := client.Bucket(h.cfg.GCPBucketName).Object(path).NewReader(ctx)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file"})
			return
		}
		defer r.Close()
		reader = r
	} else {
		uploadDir := h.cfg.UploadDir
		if uploadDir == "" {
			uploadDir = "./uploads"
		}
		localPath := filepath.Join(uploadDir, strings.TrimPrefix(u.Path, "/uploads/"))
		f, err := os.Open(localPath)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "File not found"})
			return
		}
		defer f.Close()
		reader = f
	}

	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
	c.Header("Content-Type", "application/octet-stream")
	io.Copy(c.Writer, reader)
}

// UploadPaymentProof accepts multipart form with files (key "payment_proofs"). Saves each as WholesaleOrderDocument type payment_proof. Confirms payment on first upload.
func (h *WholesaleOrderHandler) UploadPaymentProof(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	orderID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order ID"})
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.Preload("Shipments").First(&wo, orderID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	allCompleted := len(wo.Shipments) > 0
	for _, s := range wo.Shipments {
		if s.Status != models.ShipmentStatusCompleted {
			allCompleted = false
			break
		}
	}
	if !allCompleted {
		c.JSON(http.StatusBadRequest, gin.H{"error": "All shipments must be completed before confirming payment"})
		return
	}
	unlockAfterCompletion := parseUnlockAfterCompletion(c)
	if h.rejectOrderUploadUnlessUnlocked(c, wo.ID, unlockAfterCompletion) {
		return
	}
	if wo.PaymentConfirmedAt != nil && !unlockAfterCompletion {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Payment already confirmed; cannot upload more payment proof"})
		return
	}
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Expected multipart form"})
		return
	}
	files := form.File["payment_proofs"]
	if len(files) == 0 {
		files = form.File["payment_proof"] // backward compat: single file
	}
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No files provided (use form key 'payment_proofs')"})
		return
	}
	allowedExt := map[string]bool{
		".pdf": true, ".png": true, ".jpg": true, ".jpeg": true, ".gif": true, ".webp": true,
	}
	for _, fh := range files {
		ext := strings.ToLower(filepath.Ext(fh.Filename))
		if ext == "" {
			ext = ".bin"
		}
		if !allowedExt[ext] {
			continue
		}
		f, err := fh.Open()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to open file " + fh.Filename})
			return
		}
		data := make([]byte, fh.Size)
		if _, err := f.Read(data); err != nil {
			f.Close()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file " + fh.Filename})
			return
		}
		f.Close()
		if ext == "" {
			ext = ".pdf"
		}
		safeName := fmt.Sprintf("payment-proof-%d-%d%s", wo.ID, time.Now().UnixNano(), ext)
		url, err := h.uploadWholesaleFile("payment-proof/"+safeName, data)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file: " + err.Error()})
			return
		}
		displayName := strings.TrimSpace(fh.Filename)
		if displayName == "" || displayName == "blob" || displayName == "file" || strings.HasPrefix(displayName, "blob:") || len(displayName) < 2 {
			displayName = "Payment proof" + ext
		}
		doc := models.WholesaleOrderDocument{
			WholesaleOrderID: wo.ID,
			Type:             paymentProofDocType,
			FileURL:          url,
			OriginalFilename: displayName,
			CreatedAt:        time.Now(),
		}
		if err := h.db.Create(&doc).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to record payment proof"})
			return
		}
	}

	amountStr := ""
	if v := form.Value["amount"]; len(v) > 0 {
		amountStr = strings.TrimSpace(v[0])
	}
	transferDateStr := ""
	if v := form.Value["transfer_date"]; len(v) > 0 {
		transferDateStr = strings.TrimSpace(v[0])
	}
	transferredTo := ""
	if v := form.Value["transferred_to"]; len(v) > 0 {
		transferredTo = strings.TrimSpace(v[0])
	}

	changes := map[string]interface{}{
		"file_count": len(files),
	}
	if amountStr != "" {
		if amt, err := strconv.ParseFloat(amountStr, 64); err == nil {
			changes["amount"] = amt
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid amount"})
			return
		}
	}
	if transferDateStr != "" {
		// Validate format and keep original string for audit.
		if _, err := time.ParseInLocation("2006-01-02", transferDateStr, time.Local); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid transfer_date"})
			return
		}
		changes["transfer_date"] = transferDateStr
	}
	if transferredTo != "" {
		changes["transferred_to"] = transferredTo
	}

	h.audit(c, "wholesale_order_upload_payment_proof", wo.ID, changes)

	// If payment not yet confirmed, check whether total received from all payment-proof uploads >= order total.
	if wo.PaymentConfirmedAt == nil {
		var uploadLogs []models.AuditLog
		if err := h.db.Where("entity_type = ? AND entity_id = ? AND action = ?", "wholesale_order", wo.ID, "wholesale_order_upload_payment_proof").
			Find(&uploadLogs).Error; err == nil {
			var totalReceived float64
			for _, l := range uploadLogs {
				var changesMap map[string]interface{}
				if json.Unmarshal([]byte(l.Changes), &changesMap) == nil {
					if amt, ok := changesMap["amount"]; ok {
						switch v := amt.(type) {
						case float64:
							totalReceived += v
						case int:
							totalReceived += float64(v)
						case int64:
							totalReceived += float64(v)
						}
					}
				}
			}
			orderTotal := wo.TotalNet + wo.ShippingFee
			if totalReceived >= orderTotal-0.005 { // allow small rounding
				now := time.Now()
				wo.PaymentConfirmedAt = &now
				if err := h.db.Model(&wo).Update("payment_confirmed_at", wo.PaymentConfirmedAt).Error; err == nil {
					confirmChanges := map[string]interface{}{"auto_from_upload": true, "total_received": totalReceived}
					if amountStr != "" {
						if amt, err := strconv.ParseFloat(amountStr, 64); err == nil {
							confirmChanges["amount"] = amt
						}
					}
					if transferDateStr != "" {
						confirmChanges["transfer_date"] = transferDateStr
					}
					if transferredTo != "" {
						confirmChanges["transferred_to"] = transferredTo
					}
					h.audit(c, "wholesale_order_confirm_payment", wo.ID, confirmChanges)
				}
			}
		}
	}

	h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("Store").Preload("User").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Items.WholesaleOrderItem.Product").First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// ConfirmPayment confirms payment received (with or without proof).
func (h *WholesaleOrderHandler) ConfirmPayment(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var req struct {
		Amount        *float64 `json:"amount"`
		TransferDate  *string  `json:"transfer_date"`  // YYYY-MM-DD
		TransferredTo *string  `json:"transferred_to"` // account name/identifier
	}
	// Optional JSON body (frontend always sends, but keep it tolerant).
	if c.Request.ContentLength != 0 {
		// Ignore bind errors when body is empty/missing to keep backward compatibility.
		_ = c.ShouldBindJSON(&req)
	}
	orderID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order ID"})
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.Preload("Shipments").Preload("Documents").First(&wo, orderID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	allCompleted := len(wo.Shipments) > 0
	for _, s := range wo.Shipments {
		if s.Status != models.ShipmentStatusCompleted {
			allCompleted = false
			break
		}
	}
	if !allCompleted {
		c.JSON(http.StatusBadRequest, gin.H{"error": "All shipments must be completed before confirming payment"})
		return
	}
	if wo.PaymentConfirmedAt != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Payment already confirmed"})
		return
	}

	paymentTime := time.Now()
	if req.TransferDate != nil && strings.TrimSpace(*req.TransferDate) != "" {
		if parsed, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(*req.TransferDate), time.Local); err == nil {
			paymentTime = parsed
		}
	}
	wo.PaymentConfirmedAt = &paymentTime
	if err := h.db.Save(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	hasProof := wo.PaymentProofURL != ""
	if !hasProof && wo.Documents != nil {
		for _, d := range wo.Documents {
			if d.Type == paymentProofDocType {
				hasProof = true
				break
			}
		}
	}
	changes := map[string]interface{}{"with_proof": hasProof}
	if req.Amount != nil {
		changes["amount"] = *req.Amount
	}
	if req.TransferDate != nil {
		changes["transfer_date"] = *req.TransferDate
	}
	if req.TransferredTo != nil {
		changes["transferred_to"] = *req.TransferredTo
	}
	h.audit(c, "wholesale_order_confirm_payment", wo.ID, changes)
	h.db.Preload("Items.Product").Preload("WholesaleClient").Preload("Store").Preload("User").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Items.WholesaleOrderItem.Product").First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
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
	deliveryLocationFilter := strings.TrimSpace(c.Query("delivery_location"))
	poNumberFilter := c.Query("po_number")
	orderNumberFilter := c.Query("order_number")
	refNoFilter := c.Query("ref_no")
	orderDateFrom := c.Query("order_date_from")
	orderDateTo := c.Query("order_date_to")

	// POS user: approved+store_id = packing list; otherwise list orders created by this user (with filters).
	if r == "pos_user" {
		userIDInterface, _ := c.Get("user_id")
		userID := userIDInterface.(uint)

		if status == models.WholesaleOrderStatusApproved && storeID != "" {
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
			listQuery := h.db.Where("id IN ? AND status = ?", orderIDs, models.WholesaleOrderStatusApproved).
				Preload("WholesaleClient").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Sector").
				Preload("Items.Product").Preload("Items.AssignedStore").Preload("Documents").Preload("Shipments").Preload("Shipments.Items")
			if deliveryLocationFilter != "" {
				listQuery = listQuery.Where(
					"wholesale_client_store_id IN (SELECT id FROM wholesale_client_delivery_locations WHERE name LIKE ?)",
					"%"+deliveryLocationFilter+"%",
				)
			}
			var list []models.WholesaleOrder
			if err := listQuery.Order("created_at DESC").Limit(500).Find(&list).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			for i := range list {
				list[i].IsCompleted = isOrderCompleted(&list[i])
			}
			h.enrichWholesaleOrdersWorkflow(list)
			c.JSON(http.StatusOK, list)
			return
		}

		query := h.db.Model(&models.WholesaleOrder{}).Where("user_id = ?", userID).
			Preload("WholesaleClient").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Sector").
			Preload("Items.Product").Preload("Documents").Preload("Shipments").Preload("Shipments.Items")
		if status != "" {
			query = query.Where("status = ?", status)
		} else {
			query = query.Where("status != ? AND status != ?", models.WholesaleOrderStatusRejected, models.WholesaleOrderStatusDeleted)
		}
		if clientFilter != "" {
			query = query.Where("wholesale_client_id IN (SELECT id FROM wholesale_clients WHERE name LIKE ?)", "%"+clientFilter+"%")
		}
		if deliveryLocationFilter != "" {
			query = query.Where(
				"wholesale_client_store_id IN (SELECT id FROM wholesale_client_delivery_locations WHERE name LIKE ?)",
				"%"+deliveryLocationFilter+"%",
			)
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
		if orderDateFrom != "" {
			query = query.Where("COALESCE(order_date, created_at) >= ?", orderDateFrom)
		}
		if orderDateTo != "" {
			query = query.Where("COALESCE(order_date, created_at) <= ?", orderDateTo)
		}
		var list []models.WholesaleOrder
		if err := query.Order("created_at DESC").Limit(500).Find(&list).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		for i := range list {
			list[i].IsCompleted = isOrderCompleted(&list[i])
		}
		h.enrichWholesaleOrdersWorkflow(list)
		c.JSON(http.StatusOK, list)
		return
	}

	if !requireManagementSupervisorOrAdmin(c) {
		return
	}

	query := h.db.Model(&models.WholesaleOrder{}).
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Sector").
		Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("Documents").
		Preload("Shipments").
		Preload("Shipments.Items")
	if status != "" {
		query = query.Where("status = ?", status)
	} else {
		// Default list: hide rejected and soft-deleted; choose those explicitly via status filter
		query = query.Where("status != ? AND status != ?", models.WholesaleOrderStatusRejected, models.WholesaleOrderStatusDeleted)
	}
	if storeID != "" {
		query = query.Where("store_id = ?", storeID)
	}
	if clientFilter != "" {
		query = query.Where("wholesale_client_id IN (SELECT id FROM wholesale_clients WHERE name LIKE ?)", "%"+clientFilter+"%")
	}
	if deliveryLocationFilter != "" {
		query = query.Where(
			"wholesale_client_store_id IN (SELECT id FROM wholesale_client_delivery_locations WHERE name LIKE ?)",
			"%"+deliveryLocationFilter+"%",
		)
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
	if orderDateFrom != "" {
		query = query.Where("COALESCE(order_date, created_at) >= ?", orderDateFrom)
	}
	if orderDateTo != "" {
		query = query.Where("COALESCE(order_date, created_at) <= ?", orderDateTo)
	}

	sortBy := c.DefaultQuery("sort_by", "ref_no")
	sortDir := strings.ToUpper(c.DefaultQuery("sort_dir", "DESC"))
	if sortDir != "ASC" && sortDir != "DESC" {
		sortDir = "DESC"
	}
	switch sortBy {
	case "po_number":
		query = query.Order("po_number " + sortDir)
	case "total":
		query = query.Order("(COALESCE(total_net, 0) + COALESCE(shipping_fee, 0)) " + sortDir)
	case "order_date":
		// Fallback to created_at when order_date is NULL
		query = query.Order("COALESCE(order_date, created_at) " + sortDir)
	case "ref_no", "order_number":
		// OC number is stored in ref_no; keep order_number as alias for backwards compatibility
		query = query.Order("ref_no " + sortDir)
	default:
		query = query.Order("ref_no " + sortDir)
	}
	query = query.Limit(500)

	var list []models.WholesaleOrder
	if err := query.Find(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	for i := range list {
		list[i].IsCompleted = isOrderCompleted(&list[i])
	}
	h.enrichWholesaleOrdersWorkflow(list)
	c.Header("Cache-Control", "no-store, no-cache, must-revalidate")
	c.Header("Pragma", "no-cache")
	c.JSON(http.StatusOK, list)
}

func (h *WholesaleOrderHandler) Get(c *gin.Context) {
	role, _ := c.Get("role")
	// pos_user can only get their own; management/supervisor can get any
	var wo models.WholesaleOrder
	q := h.db.Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("WholesaleClient.Stores").
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
	h.enrichWholesaleOrdersWorkflow([]models.WholesaleOrder{wo})
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
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	if h.rejectIfOrderCompleted(c, wo.ID) {
		return
	}
	var req struct {
		PONumber                  *string  `json:"po_number"`
		OrderChannel              *string  `json:"order_channel"`
		RefNo                     *string  `json:"ref_no"`
		PODate                    *string  `json:"po_date"`
		OrderDate                 *string  `json:"order_date"`
		InvoiceDate               *string  `json:"invoice_date"` // YYYY-MM-DD; used on invoice PDF "Date:"
		ShippingFee               *float64 `json:"shipping_fee"`
		DiscountAmount            *float64 `json:"discount_amount"`                 // order-level discount in £
		WholesaleClientStore      *uint    `json:"wholesale_client_store_id"`       // shipping address
		ClearWholesaleClientStore *bool    `json:"clear_wholesale_client_store_id"` // when true, set to nil (use company address)
		Items                     []struct {
			ID                 uint     `json:"id"`
			UnitPrice          *float64 `json:"unit_price"`
			LineDiscountAmount *float64 `json:"line_discount_amount"` // per-line discount in £
		} `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	changes := map[string]interface{}{}
	poWasSetEmpty := false
	if req.PONumber != nil {
		newPo := strings.TrimSpace(*req.PONumber)
		changes["po_number"] = map[string]interface{}{"old": wo.PONumber, "new": newPo}
		wo.PONumber = newPo
		if newPo == "" {
			poWasSetEmpty = true
		}
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
	if req.ClearWholesaleClientStore != nil && *req.ClearWholesaleClientStore {
		changes["wholesale_client_store_id"] = map[string]interface{}{"old": wo.WholesaleClientStoreID, "new": nil}
		wo.WholesaleClientStoreID = nil
	} else if req.WholesaleClientStore != nil {
		changes["wholesale_client_store_id"] = map[string]interface{}{"old": wo.WholesaleClientStoreID, "new": *req.WholesaleClientStore}
		wo.WholesaleClientStoreID = req.WholesaleClientStore
	}
	if req.PODate != nil {
		oldDate := ""
		if wo.PODate != nil {
			oldDate = wo.PODate.Format("2006-01-02")
		}
		changes["po_date"] = map[string]interface{}{"old": oldDate, "new": *req.PODate}
		wo.PODate = parsePODate(*req.PODate)
	}
	if req.OrderDate != nil {
		oldDate := ""
		if wo.OrderDate != nil {
			oldDate = wo.OrderDate.Format("2006-01-02")
		}
		changes["order_date"] = map[string]interface{}{"old": oldDate, "new": *req.OrderDate}
		wo.OrderDate = parsePODate(*req.OrderDate)
	}
	if req.InvoiceDate != nil {
		oldDate := ""
		if wo.InvoiceDate != nil {
			oldDate = wo.InvoiceDate.Format("2006-01-02")
		}
		changes["invoice_date"] = map[string]interface{}{"old": oldDate, "new": *req.InvoiceDate}
		wo.InvoiceDate = parsePODate(*req.InvoiceDate)
	}
	if req.ShippingFee != nil {
		fee := *req.ShippingFee
		if fee < 0 {
			fee = 0
		}
		changes["shipping_fee"] = map[string]interface{}{"old": wo.ShippingFee, "new": fee}
		wo.ShippingFee = fee
	}
	if req.DiscountAmount != nil {
		disc := *req.DiscountAmount
		if disc < 0 {
			disc = 0
		}
		if disc > wo.Subtotal {
			disc = wo.Subtotal
		}
		changes["discount_amount"] = map[string]interface{}{"old": wo.DiscountAmount, "new": disc}
		wo.DiscountAmount = disc
		wo.TotalNet = wo.Subtotal - wo.DiscountAmount
		if wo.TotalNet < 0 {
			wo.TotalNet = 0
		}
		wo.AmountDue = wo.TotalNet + wo.VATTotal
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
			if it, ok := itemMap[ri.ID]; ok {
				change := map[string]interface{}{"item_id": ri.ID}
				updated := false
				if ri.UnitPrice != nil {
					oldPrice := it.UnitPrice
					it.UnitPrice = *ri.UnitPrice
					change["old_unit_price"] = oldPrice
					change["new_unit_price"] = *ri.UnitPrice
					updated = true
				}
				if ri.LineDiscountAmount != nil {
					oldDisc := it.LineDiscountAmount
					disc := *ri.LineDiscountAmount
					if disc < 0 {
						disc = 0
					}
					it.LineDiscountAmount = disc
					change["old_line_discount_amount"] = oldDisc
					change["new_line_discount_amount"] = disc
					updated = true
				}
				if updated {
					it.LineTotal = it.UnitPrice*it.Quantity - it.LineDiscountAmount
					if it.LineTotal < 0 {
						it.LineTotal = 0
					}
					h.db.Save(it)
					itemChanges = append(itemChanges, change)
				}
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
	// If shipping fee or discount was updated and all shipments are completed, re-generate invoice.
	regenerateInvoice := req.ShippingFee != nil || req.DiscountAmount != nil
	if regenerateInvoice {
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
				invoiceLocked, _ := h.isDocumentRegenLocked(wo.ID, "invoice", nil)
				if invoiceLocked {
					// Invoice was emailed; skip silent auto-regen on fee/discount update.
				} else {
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
							trigger := "shipping_fee_updated"
							if req.DiscountAmount != nil {
								trigger = "discount_updated"
							}
							h.audit(c, "wholesale_order_generate_invoice", wo.ID, map[string]interface{}{
								"document_type": "invoice", "trigger": trigger, "file_url": invURL,
							})
						}
					}
				}
				}
			}
		}
	}
	// If PO was explicitly cleared, regenerate a daily running PO number
	if poWasSetEmpty {
		loc := wo.CreatedAt.Location()
		startOfDay := time.Date(wo.CreatedAt.Year(), wo.CreatedAt.Month(), wo.CreatedAt.Day(), 0, 0, 0, 0, loc)
		endOfDay := startOfDay.Add(24 * time.Hour)
		var seq int64
		h.db.Model(&models.WholesaleOrder{}).
			Where("created_at >= ? AND created_at < ? AND id <= ?", startOfDay, endOfDay, wo.ID).
			Count(&seq)
		generatedPO := fmt.Sprintf("%03d%02d%02d%02d", seq, wo.CreatedAt.Day(), int(wo.CreatedAt.Month()), wo.CreatedAt.Year()%100)
		changes["generated_po_number"] = map[string]interface{}{"old": "", "new": generatedPO}
		wo.PONumber = generatedPO
		h.db.Model(&wo).Update("po_number", generatedPO)
	}
	if len(changes) > 0 {
		h.audit(c, "wholesale_order_update", wo.ID, changes)
	}
	h.db.Preload("Items.Product").Preload("WholesaleClient.Stores").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Sector").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// SetInvoiceSentAt records or clears the date the invoice was sent to the client (allowed even when payment is confirmed).
func (h *WholesaleOrderHandler) SetInvoiceSentAt(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	var invCount int64
	if err := h.db.Model(&models.WholesaleOrderDocument{}).
		Where("wholesale_order_id = ? AND type = ?", wo.ID, "invoice").
		Count(&invCount).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if invCount == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No invoice on this order; generate an invoice first"})
		return
	}
	var req struct {
		InvoiceSentAt *string `json:"invoice_sent_at"` // YYYY-MM-DD; empty string clears
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.InvoiceSentAt == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invoice_sent_at is required (use \"\" to clear)"})
		return
	}
	oldStr := ""
	if wo.InvoiceSentAt != nil {
		oldStr = wo.InvoiceSentAt.Format("2006-01-02")
	}
	newVal := strings.TrimSpace(*req.InvoiceSentAt)
	var newPtr *time.Time
	if newVal == "" {
		newPtr = nil
	} else {
		t, err := time.Parse("2006-01-02", newVal)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invoice_sent_at must be YYYY-MM-DD"})
			return
		}
		newPtr = &t
	}
	if err := h.db.Model(&wo).Update("invoice_sent_at", newPtr).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_invoice_sent", wo.ID, map[string]interface{}{
		"old": oldStr, "new": newVal,
	})
	h.db.Preload("Items.Product").Preload("WholesaleClient.Stores").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Sector").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
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
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
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
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
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
		Preload("WholesaleClientStore").
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
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
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
		Preload("Items.AssignedStore").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Sector").
		Preload("Reviewer").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// Resubmit changes a rejected order back to pending_approval so it can be endorsed again.
func (h *WholesaleOrderHandler) Resubmit(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status != models.WholesaleOrderStatusRejected {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only rejected orders can be resubmitted"})
		return
	}
	oldStatus := string(wo.Status)
	wo.Status = models.WholesaleOrderStatusPending
	wo.RejectionReason = ""
	wo.ReviewedAt = nil
	wo.ReviewedBy = nil
	if err := h.db.Save(&wo).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_order_resubmit", wo.ID, map[string]interface{}{
		"old_status": oldStatus, "new_status": string(wo.Status),
	})
	h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		First(&wo, wo.ID)
	c.JSON(http.StatusOK, wo)
}

// Archive soft-deletes an order by setting status to deleted. Completed orders cannot be deleted.
func (h *WholesaleOrderHandler) Archive(c *gin.Context) {
	if !requireManagementSupervisorOrAdmin(c) {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.Preload("Documents").Preload("Shipments").First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if wo.Status == models.WholesaleOrderStatusDeleted {
		c.JSON(http.StatusOK, wo)
		return
	}
	if isOrderCompleted(&wo) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Completed orders cannot be deleted"})
		return
	}

	oldStatus := wo.Status
	res := h.db.Model(&models.WholesaleOrder{}).Where("id = ?", wo.ID).Updates(map[string]interface{}{"status": models.WholesaleOrderStatusDeleted})
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete wholesale order"})
		return
	}
	wo.Status = models.WholesaleOrderStatusDeleted
	h.audit(c, "wholesale_order_delete", wo.ID, map[string]interface{}{
		"status": map[string]interface{}{"old": oldStatus, "new": models.WholesaleOrderStatusDeleted},
	})

	h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Sector").
		Preload("Reviewer").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
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
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	if wo.Status != models.WholesaleOrderStatusAssignShipment && wo.Status != models.WholesaleOrderStatusApproved {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be endorsed (assign_shipment or approved) to regenerate confirmation"})
		return
	}
	var regenBody struct {
		UnlockAfterEmail bool `json:"unlock_after_email"`
	}
	_ = c.ShouldBindJSON(&regenBody)
	if h.rejectDocumentRegenUnlessUnlocked(c, wo.ID, "order_confirmation", nil, regenBody.UnlockAfterEmail) {
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
	ocAudit := map[string]interface{}{
		"document_type": "order_confirmation", "file_url": url,
	}
	if regenBody.UnlockAfterEmail {
		ocAudit["unlock_after_email"] = true
	}
	h.audit(c, "wholesale_order_regenerate_oc", wo.ID, ocAudit)
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
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Reviewer").
		Preload("Documents").
		First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
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
	var invRegenBody struct {
		UnlockAfterEmail bool `json:"unlock_after_email"`
	}
	_ = c.ShouldBindJSON(&invRegenBody)
	if h.rejectDocumentRegenUnlessUnlocked(c, wo.ID, "invoice", nil, invRegenBody.UnlockAfterEmail) {
		return
	}
	// Keep hard order-level status aligned with "pending payment" after shipment completion.
	// Regenerating invoice should not leave/roll back UI to assign_shipment stage.
	if wo.PaymentConfirmedAt == nil && wo.Status != models.WholesaleOrderStatusApproved {
		oldStatus := wo.Status
		wo.Status = models.WholesaleOrderStatusApproved
		if err := h.db.Model(&wo).Update("status", wo.Status).Error; err == nil {
			h.audit(c, "wholesale_order_mark_pending_payment", wo.ID, map[string]interface{}{
				"old_status": oldStatus,
				"new_status": string(wo.Status),
				"trigger":    "regenerate_invoice",
			})
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
	invAudit := map[string]interface{}{
		"document_type": "invoice", "file_url": url,
	}
	if invRegenBody.UnlockAfterEmail {
		invAudit["unlock_after_email"] = true
	}
	h.audit(c, "wholesale_order_generate_invoice", wo.ID, invAudit)
	h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
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

func formatNumberWithCommas(v float64, decimals int) string {
	s := strconv.FormatFloat(v, 'f', decimals, 64)
	sign := ""
	if strings.HasPrefix(s, "-") {
		sign = "-"
		s = strings.TrimPrefix(s, "-")
	}
	parts := strings.SplitN(s, ".", 2)
	intPart := parts[0]
	if len(intPart) > 3 {
		var b strings.Builder
		pre := len(intPart) % 3
		if pre == 0 {
			pre = 3
		}
		b.WriteString(intPart[:pre])
		for i := pre; i < len(intPart); i += 3 {
			b.WriteString(",")
			b.WriteString(intPart[i : i+3])
		}
		intPart = b.String()
	}
	if len(parts) == 2 {
		return sign + intPart + "." + parts[1]
	}
	return sign + intPart
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
	if isInvoice {
		itemsPerPage = 9
	}

	// Render only real order items in the entry table.
	// Order-level discount is shown in the summary section.
	pdfItems := wo.Items

	totalPages := (len(pdfItems) + itemsPerPage - 1) / itemsPerPage
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
	poDateStr := ordinalDay(poDate.Day()) + " " + poDate.Format("Jan 2006")

	// "Date:" header:
	// - order_confirmation: prefer configured order_date, otherwise fall back to po_date.
	// - invoice: use wo.InvoiceDate (user-editable). If absent, use current date.
	//   Do NOT fall back to order/PO date for invoice.
	var dateStr string
	if isInvoice && wo.InvoiceDate != nil {
		dateStr = ordinalDay(wo.InvoiceDate.Day()) + " " + wo.InvoiceDate.Format("January 2006")
	}
	if dateStr == "" {
		if isInvoice {
			now := time.Now()
			dateStr = ordinalDay(now.Day()) + " " + now.Format("January 2006")
		} else {
			orderDate := wo.CreatedAt
			if wo.OrderDate != nil {
				orderDate = *wo.OrderDate
			} else if wo.PODate != nil {
				orderDate = *wo.PODate
			}
			dateStr = ordinalDay(orderDate.Day()) + " " + orderDate.Format("January 2006")
		}
	}
	if dateStr == "" {
		now := time.Now()
		dateStr = ordinalDay(now.Day()) + " " + now.Format("January 2006")
	}
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
		// Billing address block: always use client billing address (not delivery store address).
		addrLine1 := client.AddressLine1
		addrLine2 := client.AddressLine2
		addrPostcode := client.Postcode
		if addrLine1 == "" && addrLine2 == "" {
			addr := strings.TrimSpace(client.Address)
			if addr != "" {
				addrSplit := strings.Split(strings.ReplaceAll(addr, "\r\n", "\n"), "\n")
				if len(addrSplit) > 0 {
					addrLine1 = strings.TrimSpace(addrSplit[0])
				}
				if len(addrSplit) > 1 {
					addrLine2 = strings.TrimSpace(addrSplit[1])
				}
				if len(addrSplit) > 2 && addrPostcode == "" {
					addrPostcode = strings.TrimSpace(strings.Join(addrSplit[2:], " "))
				}
			}
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
		// For the PO number column in this table:
		// - if channel is 'po', show the actual client PO number
		// - otherwise show the channel label (e.g. WhatsApp, Email, or custom text).
		channel := strings.TrimSpace(wo.OrderChannel)
		poForTable := ""
		if channel != "" {
			if strings.EqualFold(channel, "po") {
				poForTable = wo.PONumber
			} else if strings.EqualFold(channel, "whatsapp") {
				poForTable = "WhatsApp"
			} else if strings.EqualFold(channel, "email") {
				poForTable = "Email"
			} else {
				// Fallback: use the raw channel text with first letter uppercased.
				lc := strings.ToLower(channel)
				poForTable = strings.ToUpper(lc[:1]) + lc[1:]
			}
		}
		pdf.CellFormat(sixth, 5, accountCodeOrName(client.AccountCode, client.Name, 15), "1", 0, "L", false, 0, "")
		pdf.CellFormat(sixth, 5, poForTable, "1", 0, "L", false, 0, "")
		pdf.CellFormat(sixth, 5, poDateStr, "1", 0, "L", false, 0, "")
		pdf.CellFormat(wTerms, 5, termsForTable, "1", 1, "L", false, 0, "")
		pdf.Ln(4)
	})

	pdf.AddPage()

	// ----- Order entries: itemsPerPage per page (OC=10, invoice=9), pad with "-"; multi-page with footer -----
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

	// Helper to render a GBP currency amount with the symbol at the left edge of the cell
	// and the numeric value right-aligned within the same cell width, without introducing
	// extra interior borders.
	drawGBP := func(width, height float64, border string, amount float64, ln int) {
		symW := 3.0
		if symW > width {
			symW = width / 4
		}
		// Derive borders for the symbol and numeric portions so that:
		// - the left edge of the full cell keeps its original left border
		// - the right edge keeps its original right border
		// - there is NO extra vertical line in the middle.
		symBorder := ""
		numBorder := ""
		switch border {
		case "":
			// no borders
		case "LRB":
			// verticals at left and right, plus bottom
			symBorder = "LB"
			numBorder = "RB"
		case "1":
			// full box: left/top/bottom on symbol, right/top/bottom on number
			symBorder = "LTB"
			numBorder = "RTB"
		default:
			// Fallback: keep caller's border on numeric part only.
			numBorder = border
		}

		// Currency symbol on the left.
		pdf.CellFormat(symW, height, "£", symBorder, 0, "L", false, 0, "")
		// Numeric part on the right.
		txt := formatNumberWithCommas(amount, 2)
		pdf.CellFormat(width-symW, height, txt, numBorder, ln, "R", false, 0, "")
	}

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
		if itemIndex+itemsOnPage > len(pdfItems) {
			itemsOnPage = len(pdfItems) - itemIndex
		}
		// Full page: itemsPerPage items (2 rows each). Last page: itemsOnPage*2 + (itemsPerPage-itemsOnPage) filler rows.
		rowsThisPage := itemsOnPage*2 + (itemsPerPage - itemsOnPage)
		linesUsed := 0

		for i := 0; i < itemsOnPage; i++ {
			it := pdfItems[itemIndex]
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
			// Use larger font only for the Chinese description.
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 9)
			}
			// Keep entry rows clean: show base unit price only.
			effectiveUnitPrice := it.UnitPrice

			pdf.CellFormat(wDesc, itemRowH, line1, brdrL, 0, "L", false, 0, "")
			// Numeric columns: use common item font size and currency layout helper.
			pdf.SetFont(fontName, "", 7)
			pdf.CellFormat(wQty, itemRowH, formatNumberWithCommas(it.Quantity, 2), brdrM, 0, "R", false, 0, "")
			drawGBP(wPrice, itemRowH, brdrM, effectiveUnitPrice, 0)
			drawGBP(wNet, itemRowH, brdrM, it.LineTotal, 0)
			pdf.CellFormat(wVATRate, itemRowH, vatRate, brdrM, 0, "C", false, 0, "")
			drawGBP(wVATAmt, itemRowH, brdrM, vatAmt, 0)
			drawGBP(wTotal, itemRowH, brdrR, it.LineTotal, 1)
			linesUsed++
			// Second line: English name (if any)
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
	discountAmount := wo.DiscountAmount
	if discountAmount < 0 {
		discountAmount = 0
	}
	totalNet := wo.TotalNet
	if totalNet <= 0 {
		totalNet = subtotal - discountAmount
	}
	if totalNet < 0 {
		totalNet = 0
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
	pdf.CellFormat(wQty, itemRowH, formatNumberWithCommas(totalQty, 2), brdrLRB, 0, "R", false, 0, "")
	pdf.CellFormat(wPrice, itemRowH, "", brdrLRB, 0, "R", false, 0, "")
	// This row should match the visible item table above, so use subtotal
	// (line totals after line-entry discounts, before order-level discount).
	drawGBP(wNet, itemRowH, brdrLRB, subtotal, 0)
	pdf.CellFormat(wVATRate, itemRowH, "", brdrLRB, 0, "R", false, 0, "")
	drawGBP(wVATAmt, itemRowH, brdrLRB, vatTotal, 0)
	drawGBP(wTotal, itemRowH, brdrLRB, subtotal+vatTotal, 1)

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

	// Right: Order total — Subtotal, Discount, Total Net, VAT Total, Shipping Fee, Amount Due
	pdf.SetFont(fontBold, "B", 8)
	pdf.SetXY(totX, yBottomRow)
	pdf.CellFormat(totLabelW, orderTotalH, "Subtotal :", "1", 0, "R", false, 0, "")
	drawGBP(totValueW, orderTotalH, "1", subtotal, 1)
	pdf.SetXY(totX, yBottomRow+orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "Discount :", "1", 0, "R", false, 0, "")
	drawGBP(totValueW, orderTotalH, "1", -discountAmount, 1)
	pdf.SetXY(totX, yBottomRow+2*orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "Total Net :", "1", 0, "R", false, 0, "")
	drawGBP(totValueW, orderTotalH, "1", totalNet, 1)
	pdf.SetXY(totX, yBottomRow+3*orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "VAT Total :", "1", 0, "R", false, 0, "")
	drawGBP(totValueW, orderTotalH, "1", vatTotal, 1)
	pdf.SetXY(totX, yBottomRow+4*orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "Shipping Fee :", "1", 0, "R", false, 0, "")
	drawGBP(totValueW, orderTotalH, "1", orderShippingFee, 1)
	pdf.SetXY(totX, yBottomRow+5*orderTotalH)
	pdf.CellFormat(totLabelW, orderTotalH, "Amount Due :", "1", 0, "R", false, 0, "")
	drawGBP(totValueW, orderTotalH, "1", grandTotal, 1)

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
	query := h.db.Model(&models.Shipment{}).
		Joins("INNER JOIN wholesale_orders wo ON wo.id = shipments.wholesale_order_id AND wo.status != ?", models.WholesaleOrderStatusDeleted)
	if storeIDStr != "" {
		storeID, err := strconv.ParseUint(storeIDStr, 10, 32)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid store_id"})
			return
		}
		query = query.Where("shipments.store_id = ?", uint(storeID))
	}
	statusStr := strings.TrimSpace(c.Query("status"))
	if statusStr != "" {
		if statusStr == "pending" {
			query = query.Where("shipments.status IN ?", []string{models.ShipmentStatusAssigned, models.ShipmentStatusPacking})
		} else {
			query = query.Where("shipments.status = ?", statusStr)
		}
	}
	includeOldCompleted := c.Query("include_old_completed") == "true" || statusStr == models.ShipmentStatusCompleted
	if !includeOldCompleted {
		cutoff := time.Now().AddDate(0, 0, -10)
		query = query.Where("shipments.status != ? OR shipments.updated_at >= ?", models.ShipmentStatusCompleted, cutoff)
	}
	var list []models.Shipment
	if err := query.Preload("Store").Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.Items.Product").Preload("Items.WholesaleOrderItem.Product").
		Order("COALESCE(wo.order_date, wo.created_at) DESC, shipments.id DESC").Find(&list).Error; err != nil {
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
		Preload("WholesaleOrder.Items.Product").
		Preload("Items.WholesaleOrderItem.Product").
		First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	c.JSON(http.StatusOK, s)
}

// UpdateShipmentRequest allows updating courier, tracking number and delivery date.
type UpdateShipmentRequest struct {
	Courier        *string `json:"courier"`
	TrackingNumber *string `json:"tracking_number"`
	DeliveryDate   *string `json:"delivery_date"` // optional YYYY-MM-DD; if empty string, clears the date
}

// UpdateShipment updates courier and/or tracking number (management/supervisor or POS for their store).
func (h *WholesaleOrderHandler) UpdateShipment(c *gin.Context) {
	var s models.Shipment
	if err := h.db.First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if h.abortIfWholesaleOrderDeletedByID(c, s.WholesaleOrderID) {
		return
	}
	if h.rejectIfOrderCompleted(c, s.WholesaleOrderID) {
		return
	}
	if strings.TrimSpace(s.SignedDeliveryNotePDFURL) != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot edit shipment after delivery proof is uploaded"})
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
	if req.DeliveryDate != nil {
		newDateStr := strings.TrimSpace(*req.DeliveryDate)
		if newDateStr == "" {
			changes["delivery_date"] = map[string]interface{}{"old": s.DeliveryDate, "new": nil}
			s.DeliveryDate = nil
		} else {
			t, err := time.Parse("2006-01-02", newDateStr)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid delivery_date, expected YYYY-MM-DD"})
				return
			}
			changes["delivery_date"] = map[string]interface{}{"old": s.DeliveryDate, "new": t}
			s.DeliveryDate = &t
		}
	}
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if strings.TrimSpace(s.TrackingNumber) != "" &&
		(s.Status == models.ShipmentStatusAssigned || s.Status == models.ShipmentStatusPacking || s.Status == models.ShipmentStatusPacked) {
		oldStatus := s.Status
		s.Status = models.ShipmentStatusShipped
		if err := h.db.Model(&s).Update("status", s.Status).Error; err == nil {
			changes["status"] = map[string]interface{}{"old": oldStatus, "new": s.Status}
		}
	}
	if len(changes) > 0 {
		h.audit(c, "wholesale_shipment_update", s.WholesaleOrderID, map[string]interface{}{
			"shipment_id": s.ID, "changes": changes,
		})
	}
	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// UpdateShipmentStatus moves a shipment on the management board (Jira-style column drag).
func (h *WholesaleOrderHandler) UpdateShipmentStatus(c *gin.Context) {
	var s models.Shipment
	if err := h.db.First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if h.abortIfWholesaleOrderDeletedByID(c, s.WholesaleOrderID) {
		return
	}
	if h.rejectIfOrderCompleted(c, s.WholesaleOrderID) {
		return
	}
	if strings.TrimSpace(s.SignedDeliveryNotePDFURL) != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot change status after delivery proof is uploaded"})
		return
	}
	var req struct {
		Status string `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	newStatus := strings.TrimSpace(req.Status)
	if newStatus == models.ShipmentStatusPacking {
		newStatus = models.ShipmentStatusAssigned
	}
	switch newStatus {
	case models.ShipmentStatusAssigned, models.ShipmentStatusPacked, models.ShipmentStatusShipped, models.ShipmentStatusCompleted:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shipment status"})
		return
	}
	oldStatus := s.Status
	if oldStatus == models.ShipmentStatusPacking && newStatus == models.ShipmentStatusAssigned {
		newStatus = models.ShipmentStatusAssigned
	}
	if oldStatus == newStatus || (oldStatus == models.ShipmentStatusPacking && newStatus == models.ShipmentStatusAssigned) {
		h.db.Preload("Store").Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.Items.Product").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
		c.JSON(http.StatusOK, s)
		return
	}
	if err := h.db.Model(&s).Update("status", newStatus).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	s.Status = newStatus
	h.audit(c, "wholesale_shipment_status", s.WholesaleOrderID, map[string]interface{}{
		"shipment_id": s.ID,
		"old_status":  oldStatus,
		"new_status":  newStatus,
	})
	if newStatus == models.ShipmentStatusCompleted {
		h.maybeGenerateInvoiceWhenAllShipmentsComplete(c, s.WholesaleOrderID)
	}
	if err := h.db.Preload("Store").Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.Items.Product").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, s)
}

// StartShipment saves actual boxes, courier, tracking, delivery date; generates delivery note.
// Status always becomes packed. Use courier pickup (or management status update) to mark shipped.
func (h *WholesaleOrderHandler) StartShipment(c *gin.Context) {
	var s models.Shipment
	if err := h.db.Preload("Store").
		Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.WholesaleClientStore").
		Preload("Items.WholesaleOrderItem").First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, s.WholesaleOrder.Status) {
		return
	}
	if models.ShipmentStatusIsCompleted(s.Status) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment already completed"})
		return
	}
	var body struct {
		CaseQty []struct {
			WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
			CaseQty              float64 `json:"case_qty"`
		} `json:"case_qty"`
		DeliveryDate   string `json:"delivery_date"`
		Courier        string `json:"courier"`
		TrackingNumber string `json:"tracking_number"`
	}
	_ = c.ShouldBindJSON(&body)

	if body.DeliveryDate != "" {
		if t, err := time.Parse("2006-01-02", body.DeliveryDate); err == nil {
			s.DeliveryDate = &t
		}
	}
	s.Courier = strings.TrimSpace(body.Courier)
	s.TrackingNumber = strings.TrimSpace(body.TrackingNumber)

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
	if err := h.db.Model(&s).Updates(map[string]interface{}{
		"courier": s.Courier, "tracking_number": s.TrackingNumber, "delivery_date": s.DeliveryDate,
	}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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

	s.Status = models.ShipmentStatusPacked
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	storeName := ""
	if s.Store.ID != 0 {
		storeName = s.Store.Name
	}
	h.audit(c, "wholesale_shipment_start", s.WholesaleOrderID, map[string]interface{}{
		"shipment_id": s.ID, "store_id": s.StoreID, "store_name": storeName,
		"has_tracking": strings.TrimSpace(s.TrackingNumber) != "", "file_url": url,
	})

	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// maybeGenerateInvoiceWhenAllShipmentsComplete generates invoice PDF if all shipments for the order are completed.
func (h *WholesaleOrderHandler) maybeGenerateInvoiceWhenAllShipmentsComplete(c *gin.Context, orderID uint) {
	var shipments []models.Shipment
	if err := h.db.Where("wholesale_order_id = ?", orderID).Find(&shipments).Error; err != nil || len(shipments) == 0 {
		return
	}
	for _, sh := range shipments {
		if sh.Status != models.ShipmentStatusCompleted {
			return
		}
	}

	// Guard against partial shipment setups:
	// only treat as "all shipments completed" when shipment items cover ALL order items.
	var totalOrderItems int64
	if err := h.db.Model(&models.WholesaleOrderItem{}).
		Where("wholesale_order_id = ?", orderID).
		Count(&totalOrderItems).Error; err != nil || totalOrderItems == 0 {
		return
	}
	var coveredItems int64
	if err := h.db.Model(&models.ShipmentItem{}).
		Joins("JOIN shipments ON shipments.id = shipment_items.shipment_id").
		Where("shipments.wholesale_order_id = ?", orderID).
		Distinct("shipment_items.wholesale_order_item_id").
		Count(&coveredItems).Error; err != nil {
		return
	}
	if coveredItems < totalOrderItems {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Reviewer").
		Preload("Documents").
		First(&wo, orderID).Error; err != nil {
		return
	}
	if wo.Status == models.WholesaleOrderStatusDeleted {
		return
	}

	// When all shipments are completed, move the order into "pending payment"
	// (order.status = approved, but payment_confirmed_at is still empty).
	// This makes the frontend depend on a hard order status rather than shipment-derived UI state.
	if wo.PaymentConfirmedAt == nil && wo.Status != models.WholesaleOrderStatusApproved {
		oldStatus := wo.Status
		wo.Status = models.WholesaleOrderStatusApproved
		if err := h.db.Save(&wo).Error; err == nil {
			h.audit(c, "wholesale_order_mark_pending_payment", wo.ID, map[string]interface{}{
				"old_status": oldStatus,
				"new_status": string(wo.Status),
			})
		}
	}

	var existing models.WholesaleOrderDocument
	if err := h.db.Where("wholesale_order_id = ? AND type = ?", orderID, "invoice").First(&existing).Error; err == nil {
		return // already has invoice
	}
	if invURL, err := h.generateInvoicePDF(&wo); err == nil && invURL != "" {
		doc := models.WholesaleOrderDocument{
			WholesaleOrderID: wo.ID,
			Type:             "invoice",
			FileURL:          invURL,
			CreatedAt:        time.Now(),
		}
		if err := h.db.Create(&doc).Error; err == nil {
			h.audit(c, "wholesale_order_generate_invoice", wo.ID, map[string]interface{}{
				"document_type": "invoice", "trigger": "all_shipments_completed", "file_url": invURL,
			})
		}
	}
}

// UploadSignedDeliveryNote accepts multipart form with file (key "signed_delivery_note"). Completes the shipment.
func (h *WholesaleOrderHandler) UploadSignedDeliveryNote(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var s models.Shipment
	if err := h.db.First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if h.abortIfWholesaleOrderDeletedByID(c, s.WholesaleOrderID) {
		return
	}
	if h.rejectOrderUploadUnlessUnlocked(c, s.WholesaleOrderID, parseUnlockAfterCompletion(c)) {
		return
	}
	if strings.TrimSpace(s.DeliveryNotePDFURL) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Generate a delivery note (Start shipment) before uploading a signed copy"})
		return
	}
	isReplace := strings.TrimSpace(s.SignedDeliveryNotePDFURL) != ""
	if isReplace {
		if !models.ShipmentStatusIsCompleted(s.Status) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Can only replace delivery proof on a completed shipment"})
			return
		}
	} else if !models.ShipmentStatusAllowsDeliveryProofUpload(s.Status) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment must be packed or shipped before uploading delivery proof"})
		return
	}
	fh, err := c.FormFile("signed_delivery_note")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file provided (use form key 'signed_delivery_note'): " + err.Error()})
		return
	}
	ext := strings.ToLower(filepath.Ext(fh.Filename))
	allowedExt := map[string]bool{
		".pdf": true, ".png": true, ".jpg": true, ".jpeg": true, ".gif": true, ".webp": true, ".heic": true,
	}
	if ext == "" || !allowedExt[ext] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File must be PDF or image (.pdf, .png, .jpg, .jpeg, .gif, .webp, .heic)"})
		return
	}
	data, err := readMultipartFileBytes(fh)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file: " + err.Error()})
		return
	}
	if len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Uploaded file is empty"})
		return
	}
	safeName := fmt.Sprintf("signed-dn-%d-%d%s", s.ID, time.Now().UnixNano(), ext)
	url, err := h.uploadWholesaleFile("signed-dn/"+safeName, data)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file: " + err.Error()})
		return
	}
	oldSignedURL := strings.TrimSpace(s.SignedDeliveryNotePDFURL)
	s.SignedDeliveryNotePDFURL = url
	if !isReplace {
		s.Status = models.ShipmentStatusCompleted
	}
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if isReplace {
		h.audit(c, "wholesale_shipment_replace_signed_dn", s.WholesaleOrderID, map[string]interface{}{
			"shipment_id": s.ID, "old_file_url": oldSignedURL, "file_url": url,
		})
	} else {
		h.audit(c, "wholesale_shipment_upload_signed_dn", s.WholesaleOrderID, map[string]interface{}{
			"shipment_id": s.ID, "file_url": url,
		})
		h.maybeGenerateInvoiceWhenAllShipmentsComplete(c, s.WholesaleOrderID)
	}
	h.db.Preload("Store").Preload("WholesaleOrder").Preload("Items.WholesaleOrderItem.Product").First(&s, s.ID)
	c.JSON(http.StatusOK, s)
}

// CompletePacking generates the delivery note PDF. POS packing sets status to packed;
// management force-complete sets status to completed.
func (h *WholesaleOrderHandler) CompletePacking(c *gin.Context) {
	var s models.Shipment
	if err := h.db.Preload("Store").
		Preload("WholesaleOrder").Preload("WholesaleOrder.WholesaleClient").Preload("WholesaleOrder.WholesaleClientStore").
		Preload("Items.WholesaleOrderItem").First(&s, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, s.WholesaleOrder.Status) {
		return
	}
	if models.ShipmentStatusIsCompleted(s.Status) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment already completed"})
		return
	}
	var body struct {
		CaseQty []struct {
			WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
			CaseQty              float64 `json:"case_qty"`
		} `json:"case_qty"`
		DeliveryDate  string `json:"delivery_date"` // optional YYYY-MM-DD; if set, used on delivery note PDF
		ForceComplete bool   `json:"force_complete"`
	}
	_ = c.ShouldBindJSON(&body)
	if !body.ForceComplete && !models.ShipmentStatusAllowsPacking(s.Status) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment is already packed"})
		return
	}
	// Optional delivery date (when completing shipment)
	if body.DeliveryDate != "" {
		if t, err := time.Parse("2006-01-02", body.DeliveryDate); err == nil {
			s.DeliveryDate = &t
		}
	}
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
	if body.ForceComplete {
		s.Status = models.ShipmentStatusCompleted
	} else {
		s.Status = models.ShipmentStatusPacked
	}
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.audit(c, "wholesale_shipment_complete_packing", s.WholesaleOrderID, map[string]interface{}{
		"shipment_id": s.ID, "old_status": oldStatus, "new_status": string(s.Status), "file_url": url, "force_complete": body.ForceComplete,
	})
	if body.ForceComplete {
		h.maybeGenerateInvoiceWhenAllShipmentsComplete(c, s.WholesaleOrderID)
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
	if abortIfWholesaleOrderDeleted(c, s.WholesaleOrder.Status) {
		return
	}
	if h.rejectIfOrderCompleted(c, s.WholesaleOrderID) {
		return
	}
	if strings.TrimSpace(s.SignedDeliveryNotePDFURL) != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot regenerate delivery note after delivery proof is uploaded"})
		return
	}
	var dnRegenBody struct {
		UnlockAfterEmail bool `json:"unlock_after_email"`
	}
	_ = c.ShouldBindJSON(&dnRegenBody)
	shipmentID := s.ID
	if h.rejectDocumentRegenUnlessUnlocked(c, s.WholesaleOrderID, "delivery_note", &shipmentID, dnRegenBody.UnlockAfterEmail) {
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
	dnAudit := map[string]interface{}{
		"shipment_id": s.ID, "document_type": "delivery_note", "file_url": url,
	}
	if dnRegenBody.UnlockAfterEmail {
		dnAudit["unlock_after_email"] = true
	}
	h.audit(c, "wholesale_shipment_regenerate_dn", s.WholesaleOrderID, dnAudit)
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
	if abortIfWholesaleOrderDeleted(c, s.WholesaleOrder.Status) {
		return
	}
	if h.rejectIfOrderCompleted(c, s.WholesaleOrderID) {
		return
	}
	if strings.TrimSpace(s.SignedDeliveryNotePDFURL) != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot edit shipment after delivery proof is uploaded"})
		return
	}
	var body struct {
		CaseQty []struct {
			WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
			CaseQty              float64 `json:"case_qty"`
		} `json:"case_qty"`
		DeliveryDate     string `json:"delivery_date"` // optional YYYY-MM-DD; if set, updates shipment delivery date
		UnlockAfterEmail bool   `json:"unlock_after_email"`
	}
	_ = c.ShouldBindJSON(&body)
	if body.DeliveryDate != "" {
		if t, err := time.Parse("2006-01-02", body.DeliveryDate); err == nil {
			s.DeliveryDate = &t
			h.db.Model(&s).Update("delivery_date", s.DeliveryDate)
		}
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
	if strings.TrimSpace(s.DeliveryNotePDFURL) != "" {
		shipmentID := s.ID
		if h.rejectDocumentRegenUnlessUnlocked(c, s.WholesaleOrderID, "delivery_note", &shipmentID, body.UnlockAfterEmail) {
			return
		}
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
		caseQtyAudit := map[string]interface{}{
			"shipment_id": s.ID, "document_type": "delivery_note", "file_url": url,
		}
		if body.UnlockAfterEmail {
			caseQtyAudit["unlock_after_email"] = true
		}
		h.audit(c, "wholesale_shipment_update_case_qty", s.WholesaleOrderID, caseQtyAudit)
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

	// Header date: use configured delivery_date when available; otherwise fallback to shipment creation date.
	headerDate := s.CreatedAt
	if s.DeliveryDate != nil {
		headerDate = *s.DeliveryDate
	}
	headerDateStr := ordinalDay(headerDate.Day()) + " " + headerDate.Format("January 2006")

	// Delivery date (may be different from header if delivery_date is not set)
	var deliveryDateStr string
	if s.DeliveryDate != nil {
		dd := *s.DeliveryDate
		deliveryDateStr = ordinalDay(dd.Day()) + " " + dd.Format("January 2006")
	}
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
		pdf.CellFormat(barW-keyW, 5, headerDateStr, "", 1, "L", false, 0, "")
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
		if deliveryDateStr == "" {
			deliveryDateStr = "-"
		}
		pdf.CellFormat(w2, 5, deliveryDateStr, "1", 0, "L", false, 0, "")
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
				caseQtyStr = formatNumberWithCommas(caseQty, 2)
			}
			lineQty := effectiveShipmentItemQty(&si, it.Quantity)
			// No border between item entries (use "" so only table outline is drawn)
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 9)
			}
			pdf.CellFormat(wDesc, itemRowH, line1, "", 0, "L", false, 0, "")
			pdf.CellFormat(wItemQty, itemRowH, formatNumberWithCommas(lineQty, 2), "", 0, "R", false, 0, "")
			pdf.CellFormat(wCaseQty, itemRowH, caseQtyStr, "", 1, "R", false, 0, "")
			if it.Product.NameChinese != "" {
				pdf.SetFont(fontName, "", 7)
			}
			linesUsed++
			totalItemQty += lineQty
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
	pdf.CellFormat(wItemQty, 6, formatNumberWithCommas(totalItemQty, 0), "LRB", 0, "R", false, 0, "")
	totalCaseStr := "-"
	if totalCaseQty > 0 {
		totalCaseStr = formatNumberWithCommas(totalCaseQty, 0)
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

func effectiveShipmentItemQty(si *models.ShipmentItem, orderQty float64) float64 {
	if si.Quantity > 0 {
		return si.Quantity
	}
	if orderQty > 0 {
		return orderQty
	}
	return 0
}

func (h *WholesaleOrderHandler) assignedQtyForOrderItem(itemID uint) (float64, error) {
	type row struct {
		Qty      float64
		OrderQty float64
	}
	var rows []row
	err := h.db.Table("shipment_items si").
		Select("si.quantity AS qty, woi.quantity AS order_qty").
		Joins("JOIN wholesale_order_items woi ON woi.id = si.wholesale_order_item_id").
		Joins("JOIN shipments s ON s.id = si.shipment_id").
		Where("si.wholesale_order_item_id = ?", itemID).
		Scan(&rows).Error
	if err != nil {
		return 0, err
	}
	var sum float64
	for _, r := range rows {
		if r.Qty > 0 {
			sum += r.Qty
		} else {
			sum += r.OrderQty
		}
	}
	return sum, nil
}

func (h *WholesaleOrderHandler) orderAllLinesFullyAssigned(orderID uint) (bool, error) {
	var items []models.WholesaleOrderItem
	if err := h.db.Where("wholesale_order_id = ?", orderID).Find(&items).Error; err != nil {
		return false, err
	}
	if len(items) == 0 {
		return false, nil
	}
	for _, item := range items {
		assigned, err := h.assignedQtyForOrderItem(item.ID)
		if err != nil {
			return false, err
		}
		if item.Quantity-assigned > 0.0001 {
			return false, nil
		}
	}
	return true, nil
}

func (h *WholesaleOrderHandler) promoteOrderToApprovedIfFullyAssigned(c *gin.Context, wo *models.WholesaleOrder) error {
	full, err := h.orderAllLinesFullyAssigned(wo.ID)
	if err != nil || !full {
		return err
	}
	if wo.Status != models.WholesaleOrderStatusAssignShipment {
		return nil
	}
	oldStatus := string(wo.Status)
	wo.Status = models.WholesaleOrderStatusApproved
	if err := h.db.Save(wo).Error; err != nil {
		return err
	}
	h.audit(c, "wholesale_order_complete_assignment", wo.ID, map[string]interface{}{
		"old_status": oldStatus, "new_status": string(wo.Status), "trigger": "auto_after_assign",
	})
	return nil
}

func (h *WholesaleOrderHandler) demoteOrderFromApprovedIfNotFullyAssigned(c *gin.Context, wo *models.WholesaleOrder) error {
	full, err := h.orderAllLinesFullyAssigned(wo.ID)
	if err != nil || full {
		return err
	}
	if wo.Status != models.WholesaleOrderStatusApproved {
		return nil
	}
	oldStatus := string(wo.Status)
	wo.Status = models.WholesaleOrderStatusAssignShipment
	if err := h.db.Save(wo).Error; err != nil {
		return err
	}
	h.audit(c, "wholesale_order_reopen_assignment", wo.ID, map[string]interface{}{
		"old_status": oldStatus, "new_status": string(wo.Status), "trigger": "unassign",
	})
	return nil
}

func (h *WholesaleOrderHandler) syncOrderItemAssignedStore(itemID uint) error {
	var item models.WholesaleOrderItem
	if err := h.db.First(&item, itemID).Error; err != nil {
		return err
	}
	assigned, err := h.assignedQtyForOrderItem(itemID)
	if err != nil {
		return err
	}
	if item.Quantity-assigned > 0.0001 {
		return h.db.Model(&item).Update("assigned_store_id", nil).Error
	}
	var storeIDs []uint
	if err := h.db.Model(&models.ShipmentItem{}).
		Joins("JOIN shipments ON shipments.id = shipment_items.shipment_id").
		Where("shipment_items.wholesale_order_item_id = ?", itemID).
		Distinct("shipments.store_id").
		Pluck("shipments.store_id", &storeIDs).Error; err != nil {
		return err
	}
	if len(storeIDs) == 1 {
		return h.db.Model(&item).Update("assigned_store_id", storeIDs[0]).Error
	}
	return h.db.Model(&item).Update("assigned_store_id", nil).Error
}

// AssignStoresRequest assigns a batch of order lines (optionally partial qty) to stores.
type AssignStoresRequest struct {
	Assignments []struct {
		WholesaleOrderItemID uint     `json:"wholesale_order_item_id" binding:"required"`
		StoreID              *uint    `json:"store_id"` // required for assign batch entries
		Quantity             *float64 `json:"quantity"` // optional; defaults to remaining pending qty
		CaseQty              *float64 `json:"case_qty"` // optional expected boxes for packing
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
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
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

	updated, err := h.applyAssignStoresBatch(c, &wo, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// AssignByDefaults assigns pending order lines to each product's wholesale_ship_from store.
func (h *WholesaleOrderHandler) AssignByDefaults(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.Preload("Items").First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	if wo.Status != models.WholesaleOrderStatusApproved && wo.Status != models.WholesaleOrderStatusAssignShipment {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be approved or in assign_shipment to assign stores"})
		return
	}

	req := AssignStoresRequest{}
	for _, item := range wo.Items {
		alreadyAssigned, err := h.assignedQtyForOrderItem(item.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		pending := item.Quantity - alreadyAssigned
		if pending <= 0.0001 {
			continue
		}
		var stock models.Stock
		if err := h.db.Where("product_id = ? AND wholesale_ship_from = ?", item.ProductID, true).First(&stock).Error; err != nil {
			continue
		}
		storeID := stock.StoreID
		qty := pending
		req.Assignments = append(req.Assignments, struct {
			WholesaleOrderItemID uint     `json:"wholesale_order_item_id" binding:"required"`
			StoreID              *uint    `json:"store_id"`
			Quantity             *float64 `json:"quantity"`
			CaseQty              *float64 `json:"case_qty"`
		}{
			WholesaleOrderItemID: item.ID,
			StoreID:              &storeID,
			Quantity:             &qty,
		})
	}
	if len(req.Assignments) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No pending lines with a default wholesale ship store configured"})
		return
	}

	updated, err := h.applyAssignStoresBatch(c, &wo, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

func (h *WholesaleOrderHandler) applyAssignStoresBatch(c *gin.Context, wo *models.WholesaleOrder, req AssignStoresRequest) (*models.WholesaleOrder, error) {
	for _, a := range req.Assignments {
		if a.StoreID != nil {
			var st models.Store
			if err := h.db.First(&st, *a.StoreID).Error; err != nil {
				return nil, fmt.Errorf("Store %d not found", *a.StoreID)
			}
		}
	}

	itemCaseQty := make(map[uint]float64)
	assignQty := make(map[uint]float64)
	for _, a := range req.Assignments {
		if a.CaseQty != nil {
			cq := *a.CaseQty
			if cq < 0 {
				cq = 0
			}
			itemCaseQty[a.WholesaleOrderItemID] = cq
		}
		if a.Quantity != nil {
			q := *a.Quantity
			if q < 0 {
				q = 0
			}
			assignQty[a.WholesaleOrderItemID] = q
		}
	}

	// Validate all items belong to this order
	var itemIDs []uint
	for _, a := range req.Assignments {
		if a.StoreID == nil {
			continue
		}
		itemIDs = append(itemIDs, a.WholesaleOrderItemID)
	}
	if len(itemIDs) == 0 {
		return nil, fmt.Errorf("No store assignments in request")
	}
	var count int64
	h.db.Model(&models.WholesaleOrderItem{}).Where("wholesale_order_id = ? AND id IN ?", wo.ID, itemIDs).Count(&count)
	if int(count) != len(itemIDs) {
		return nil, fmt.Errorf("All item IDs must belong to this order")
	}

	assignmentChanges := []map[string]interface{}{}
	touchedItemIDs := make(map[uint]struct{})

	for _, a := range req.Assignments {
		if a.StoreID == nil {
			continue
		}
		storeID := *a.StoreID

		var item models.WholesaleOrderItem
		if err := h.db.First(&item, a.WholesaleOrderItemID).Error; err != nil {
			return nil, fmt.Errorf("Order item %d not found", a.WholesaleOrderItemID)
		}
		if item.WholesaleOrderID != wo.ID {
			return nil, fmt.Errorf("All item IDs must belong to this order")
		}

		alreadyAssigned, err := h.assignedQtyForOrderItem(item.ID)
		if err != nil {
			return nil, err
		}
		pending := item.Quantity - alreadyAssigned
		if pending <= 0.0001 {
			return nil, fmt.Errorf("Item %d has no pending quantity to assign", item.ID)
		}

		qty := pending
		if q, ok := assignQty[item.ID]; ok {
			qty = q
		}
		if qty <= 0 {
			return nil, fmt.Errorf("Assign quantity must be greater than 0 for item %d", item.ID)
		}
		if qty > pending+0.0001 {
			return nil, fmt.Errorf("Assign quantity %.3f exceeds pending %.3f for item %d", qty, pending, item.ID)
		}

		var ship models.Shipment
		err = h.db.Where("wholesale_order_id = ? AND store_id = ?", wo.ID, storeID).First(&ship).Error
		if err != nil {
			ship = models.Shipment{
				WholesaleOrderID: wo.ID,
				StoreID:          storeID,
				Status:           models.ShipmentStatusAssigned,
			}
			if err := h.db.Create(&ship).Error; err != nil {
				return nil, err
			}
		} else if !models.ShipmentStatusAllowsPacking(ship.Status) {
			return nil, fmt.Errorf("Cannot assign to shipment %d in status %q", ship.ID, ship.Status)
		}

		var si models.ShipmentItem
		err = h.db.Where("shipment_id = ? AND wholesale_order_item_id = ?", ship.ID, item.ID).First(&si).Error
		if err != nil {
			si = models.ShipmentItem{
				ShipmentID:           ship.ID,
				WholesaleOrderItemID: item.ID,
				Quantity:             qty,
			}
			if cq, ok := itemCaseQty[item.ID]; ok {
				si.CaseQty = cq
			}
			if err := h.db.Create(&si).Error; err != nil {
				return nil, err
			}
		} else {
			cur := si.Quantity
			if cur <= 0 {
				si.Quantity = qty
			} else {
				si.Quantity = cur + qty
			}
			if cq, ok := itemCaseQty[item.ID]; ok {
				si.CaseQty = cq
			}
			if err := h.db.Save(&si).Error; err != nil {
				return nil, err
			}
		}

		touchedItemIDs[item.ID] = struct{}{}
		entry := map[string]interface{}{
			"item_id":  item.ID,
			"store_id": storeID,
			"quantity": qty,
		}
		if cq, ok := itemCaseQty[item.ID]; ok {
			entry["case_qty"] = cq
		}
		assignmentChanges = append(assignmentChanges, entry)
	}

	for itemID := range touchedItemIDs {
		if err := h.syncOrderItemAssignedStore(itemID); err != nil {
			return nil, err
		}
	}

	h.audit(c, "wholesale_order_assign_stores", wo.ID, map[string]interface{}{
		"assignments": assignmentChanges,
	})

	if err := h.promoteOrderToApprovedIfFullyAssigned(c, wo); err != nil {
		return nil, err
	}

	var updated models.WholesaleOrder
	if err := h.db.Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&updated, wo.ID).Error; err != nil {
		return nil, err
	}
	return &updated, nil
}

// UnassignStoresRequest removes assigned qty from store shipment lines (re-assign support).
type UnassignStoresRequest struct {
	Assignments []struct {
		WholesaleOrderItemID uint     `json:"wholesale_order_item_id" binding:"required"`
		StoreID              uint     `json:"store_id" binding:"required"`
		Quantity             *float64 `json:"quantity"` // optional; defaults to qty assigned on that store
	} `json:"assignments" binding:"required,min=1"`
}

func (h *WholesaleOrderHandler) UnassignStores(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	if wo.Status != models.WholesaleOrderStatusApproved && wo.Status != models.WholesaleOrderStatusAssignShipment {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order must be approved or in assign_shipment to unassign stores"})
		return
	}

	var req UnassignStoresRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updated, err := h.applyUnassignStoresBatch(c, &wo, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

func (h *WholesaleOrderHandler) applyUnassignStoresBatch(c *gin.Context, wo *models.WholesaleOrder, req UnassignStoresRequest) (*models.WholesaleOrder, error) {
	assignmentChanges := []map[string]interface{}{}
	touchedItemIDs := make(map[uint]struct{})

	for _, a := range req.Assignments {
		var item models.WholesaleOrderItem
		if err := h.db.First(&item, a.WholesaleOrderItemID).Error; err != nil {
			return nil, fmt.Errorf("Order item %d not found", a.WholesaleOrderItemID)
		}
		if item.WholesaleOrderID != wo.ID {
			return nil, fmt.Errorf("All item IDs must belong to this order")
		}

		var ship models.Shipment
		if err := h.db.Where("wholesale_order_id = ? AND store_id = ?", wo.ID, a.StoreID).First(&ship).Error; err != nil {
			return nil, fmt.Errorf("No shipment assigned to store %d for this order", a.StoreID)
		}
		if !models.ShipmentStatusAllowsPacking(ship.Status) {
			return nil, fmt.Errorf("Cannot unassign from shipment %d in status %q", ship.ID, ship.Status)
		}

		var si models.ShipmentItem
		if err := h.db.Where("shipment_id = ? AND wholesale_order_item_id = ?", ship.ID, item.ID).First(&si).Error; err != nil {
			return nil, fmt.Errorf("Item %d is not assigned to store %d", item.ID, a.StoreID)
		}

		cur := si.Quantity
		if cur <= 0 {
			cur = item.Quantity
		}
		qty := cur
		if a.Quantity != nil && *a.Quantity > 0 {
			qty = *a.Quantity
		}
		if qty <= 0 {
			return nil, fmt.Errorf("Unassign quantity must be greater than 0 for item %d", item.ID)
		}
		if qty > cur+0.0001 {
			return nil, fmt.Errorf("Unassign quantity %.3f exceeds assigned %.3f for item %d on store %d", qty, cur, item.ID, a.StoreID)
		}

		if qty >= cur-0.0001 {
			if err := h.db.Delete(&si).Error; err != nil {
				return nil, err
			}
		} else {
			si.Quantity = cur - qty
			if err := h.db.Save(&si).Error; err != nil {
				return nil, err
			}
		}

		var remaining int64
		if err := h.db.Model(&models.ShipmentItem{}).Where("shipment_id = ?", ship.ID).Count(&remaining).Error; err != nil {
			return nil, err
		}
		if remaining == 0 {
			if err := h.db.Delete(&ship).Error; err != nil {
				return nil, err
			}
		}

		touchedItemIDs[item.ID] = struct{}{}
		assignmentChanges = append(assignmentChanges, map[string]interface{}{
			"item_id":  item.ID,
			"store_id": a.StoreID,
			"quantity": qty,
		})
	}

	for itemID := range touchedItemIDs {
		if err := h.syncOrderItemAssignedStore(itemID); err != nil {
			return nil, err
		}
	}

	h.audit(c, "wholesale_order_unassign_stores", wo.ID, map[string]interface{}{
		"assignments": assignmentChanges,
	})

	if err := h.demoteOrderFromApprovedIfNotFullyAssigned(c, wo); err != nil {
		return nil, err
	}

	var updated models.WholesaleOrder
	if err := h.db.Preload("Items.Product").
		Preload("Items.AssignedStore").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&updated, wo.ID).Error; err != nil {
		return nil, err
	}
	return &updated, nil
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

func auditChangesStringSlice(changes map[string]interface{}, key string) []string {
	v, ok := changes[key]
	if !ok || v == nil {
		return nil
	}
	switch arr := v.(type) {
	case []interface{}:
		out := make([]string, 0, len(arr))
		for _, item := range arr {
			if s, ok := item.(string); ok && strings.TrimSpace(s) != "" {
				out = append(out, strings.TrimSpace(s))
			}
		}
		return out
	case []string:
		out := make([]string, 0, len(arr))
		for _, s := range arr {
			if strings.TrimSpace(s) != "" {
				out = append(out, strings.TrimSpace(s))
			}
		}
		return out
	default:
		return nil
	}
}

func auditChangesUintSlice(changes map[string]interface{}, key string) []uint {
	v, ok := changes[key]
	if !ok || v == nil {
		return nil
	}
	switch arr := v.(type) {
	case []interface{}:
		out := make([]uint, 0, len(arr))
		for _, item := range arr {
			switch n := item.(type) {
			case float64:
				if n > 0 {
					out = append(out, uint(n))
				}
			case json.Number:
				if i, err := n.Int64(); err == nil && i > 0 {
					out = append(out, uint(i))
				}
			}
		}
		return out
	default:
		return nil
	}
}

func bulkEmailAuditLocksDocType(changes map[string]interface{}, docType string, shipmentID *uint) bool {
	kinds := auditChangesStringSlice(changes, "attachment_kinds")
	if len(kinds) == 0 {
		return false
	}
	kindSet := make(map[string]struct{}, len(kinds))
	for _, k := range kinds {
		kindSet[k] = struct{}{}
	}
	switch docType {
	case "order_confirmation":
		_, ok := kindSet["order_confirmation"]
		return ok
	case "invoice":
		_, ok := kindSet["invoice"]
		return ok
	case "delivery_note":
		if _, ok := kindSet["delivery_note"]; !ok {
			return false
		}
		shipmentIDs := auditChangesUintSlice(changes, "shipment_ids")
		if len(shipmentIDs) == 0 || shipmentID == nil {
			return true
		}
		for _, sid := range shipmentIDs {
			if sid == *shipmentID {
				return true
			}
		}
		return false
	case "signed_delivery_note":
		if _, ok := kindSet["signed_delivery_note"]; !ok {
			return false
		}
		if sid, ok := auditChangesUint(changes, "signed_delivery_shipment_id"); ok && shipmentID != nil {
			return sid == *shipmentID
		}
		shipmentIDs := auditChangesUintSlice(changes, "shipment_ids")
		if len(shipmentIDs) == 0 || shipmentID == nil {
			return true
		}
		for _, sid := range shipmentIDs {
			if sid == *shipmentID {
				return true
			}
		}
		return false
	default:
		return false
	}
}

func auditLogLocksDocumentRegen(action string, changes map[string]interface{}, docType string, shipmentID *uint) bool {
	switch action {
	case "wholesale_order_email_oc":
		return docType == "order_confirmation"
	case "wholesale_order_email_invoice":
		return docType == "invoice"
	case "wholesale_order_email_dn":
		if docType != "delivery_note" {
			return false
		}
		sid, ok := auditChangesUint(changes, "shipment_id")
		if !ok {
			return true
		}
		if shipmentID == nil {
			return true
		}
		return sid == *shipmentID
	case "wholesale_order_email":
		return bulkEmailAuditLocksDocType(changes, docType, shipmentID)
	default:
		return false
	}
}

func (h *WholesaleOrderHandler) isDocumentRegenLocked(orderID uint, docType string, shipmentID *uint) (bool, error) {
	var logs []models.AuditLog
	if err := h.db.Where("entity_type = ? AND entity_id = ?", "wholesale_order", orderID).
		Where("action IN ?", []string{
			"wholesale_order_email",
			"wholesale_order_email_oc",
			"wholesale_order_email_invoice",
			"wholesale_order_email_dn",
		}).Find(&logs).Error; err != nil {
		return false, err
	}
	for _, log := range logs {
		var changes map[string]interface{}
		if err := json.Unmarshal([]byte(log.Changes), &changes); err != nil {
			continue
		}
		if auditLogLocksDocumentRegen(log.Action, changes, docType, shipmentID) {
			return true, nil
		}
	}
	return false, nil
}

func (h *WholesaleOrderHandler) rejectDocumentRegenUnlessUnlocked(c *gin.Context, orderID uint, docType string, shipmentID *uint, unlockAfterEmail bool) bool {
	locked, err := h.isDocumentRegenLocked(orderID, docType, shipmentID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return true
	}
	if locked && !unlockAfterEmail {
		c.JSON(http.StatusConflict, gin.H{
			"error":         "This document was emailed to the client. Confirm unlock to regenerate.",
			"code":          "document_regen_locked",
			"document_type": docType,
		})
		return true
	}
	return false
}

func auditChangesUint(changes map[string]interface{}, key string) (uint, bool) {
	v, ok := changes[key]
	if !ok || v == nil {
		return 0, false
	}
	switch n := v.(type) {
	case float64:
		if n < 0 {
			return 0, false
		}
		return uint(n), true
	case json.Number:
		i, err := n.Int64()
		if err != nil || i < 0 {
			return 0, false
		}
		return uint(i), true
	default:
		return 0, false
	}
}

func inferDocumentRestoreTarget(action string, changes map[string]interface{}) (docType string, shipmentID *uint, fileURL string, err error) {
	fileURL, _ = changes["file_url"].(string)
	fileURL = strings.TrimSpace(fileURL)
	if fileURL == "" {
		return "", nil, "", fmt.Errorf("audit log has no document to restore")
	}
	if dt, ok := changes["document_type"].(string); ok && strings.TrimSpace(dt) != "" {
		docType = strings.TrimSpace(dt)
	} else {
		switch action {
		case "wholesale_order_generate_oc", "wholesale_order_regenerate_oc":
			docType = "order_confirmation"
		case "wholesale_order_generate_invoice":
			docType = "invoice"
		case "wholesale_shipment_upload_signed_dn", "wholesale_shipment_replace_signed_dn":
			docType = "signed_delivery_note"
		case "wholesale_shipment_start", "wholesale_shipment_complete_packing",
			"wholesale_shipment_regenerate_dn", "wholesale_shipment_update_case_qty":
			docType = "delivery_note"
		default:
			return "", nil, "", fmt.Errorf("this audit entry does not support document restore")
		}
	}
	switch docType {
	case "order_confirmation", "invoice":
		return docType, nil, fileURL, nil
	case "delivery_note", "signed_delivery_note":
		sid, ok := auditChangesUint(changes, "shipment_id")
		if !ok {
			return "", nil, "", fmt.Errorf("shipment_id required to restore this document")
		}
		return docType, &sid, fileURL, nil
	default:
		return "", nil, "", fmt.Errorf("unsupported document type: %s", docType)
	}
}

// RestoreDocumentFromAudit sets the active document for an order/shipment to a file_url recorded in an audit log entry.
func (h *WholesaleOrderHandler) RestoreDocumentFromAudit(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	orderID64, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || orderID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order id"})
		return
	}
	auditLogID64, err := strconv.ParseUint(c.Param("auditLogId"), 10, 64)
	if err != nil || auditLogID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid audit log id"})
		return
	}
	orderID := uint(orderID64)
	auditLogID := uint(auditLogID64)

	var wo models.WholesaleOrder
	if err := h.db.Select("id", "status").First(&wo, orderID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}

	var log models.AuditLog
	if err := h.db.First(&log, auditLogID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Audit log not found"})
		return
	}
	if log.EntityType != "wholesale_order" || log.EntityID == nil || *log.EntityID != orderID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Audit log does not belong to this order"})
		return
	}

	var changes map[string]interface{}
	if err := json.Unmarshal([]byte(log.Changes), &changes); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid audit log changes"})
		return
	}
	docType, shipmentID, fileURL, err := inferDocumentRestoreTarget(log.Action, changes)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var restoreBody struct {
		UnlockAfterEmail bool `json:"unlock_after_email"`
	}
	_ = c.ShouldBindJSON(&restoreBody)
	if docType == "order_confirmation" || docType == "invoice" || docType == "delivery_note" || docType == "signed_delivery_note" {
		if h.rejectDocumentRegenUnlessUnlocked(c, orderID, docType, shipmentID, restoreBody.UnlockAfterEmail) {
			return
		}
	}

	var previousFileURL string
	switch docType {
	case "order_confirmation", "invoice":
		var existing models.WholesaleOrderDocument
		if err := h.db.Where("wholesale_order_id = ? AND type = ?", orderID, docType).First(&existing).Error; err == nil {
			previousFileURL = existing.FileURL
		}
		if previousFileURL == fileURL {
			c.JSON(http.StatusBadRequest, gin.H{"error": "This document version is already active"})
			return
		}
		h.db.Where("wholesale_order_id = ? AND type = ?", orderID, docType).Delete(&models.WholesaleOrderDocument{})
		doc := models.WholesaleOrderDocument{
			WholesaleOrderID: orderID,
			Type:             docType,
			FileURL:          fileURL,
			CreatedAt:        time.Now(),
		}
		if err := h.db.Create(&doc).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	case "delivery_note", "signed_delivery_note":
		var s models.Shipment
		if err := h.db.First(&s, *shipmentID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
			return
		}
		if s.WholesaleOrderID != orderID {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment does not belong to this order"})
			return
		}
		if docType == "delivery_note" {
			previousFileURL = s.DeliveryNotePDFURL
			if strings.TrimSpace(s.SignedDeliveryNotePDFURL) != "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot restore delivery note after delivery proof is uploaded"})
				return
			}
			if previousFileURL == fileURL {
				c.JSON(http.StatusBadRequest, gin.H{"error": "This document version is already active"})
				return
			}
			if err := h.db.Model(&s).Update("delivery_note_pdf_url", fileURL).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		} else {
			previousFileURL = s.SignedDeliveryNotePDFURL
			if previousFileURL == fileURL {
				c.JSON(http.StatusBadRequest, gin.H{"error": "This document version is already active"})
				return
			}
			if err := h.db.Model(&s).Update("signed_delivery_note_pdf_url", fileURL).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
	}

	auditPayload := map[string]interface{}{
		"restored_from_audit_log_id": auditLogID,
		"document_type":              docType,
		"file_url":                   fileURL,
		"previous_file_url":          previousFileURL,
	}
	if shipmentID != nil {
		auditPayload["shipment_id"] = *shipmentID
	}
	if restoreBody.UnlockAfterEmail {
		auditPayload["unlock_after_email"] = true
	}
	h.audit(c, "wholesale_order_restore_document", orderID, auditPayload)

	h.db.Preload("Items.Product").
		Preload("WholesaleClient").
		Preload("WholesaleClientStore").
		Preload("Store").
		Preload("User").
		Preload("Sector").
		Preload("Reviewer").
		Preload("Documents").
		Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&wo, orderID)
	c.JSON(http.StatusOK, wo)
}

func wholesaleOrderRefLabel(wo *models.WholesaleOrder) string {
	refNo := strings.TrimSpace(wo.RefNo)
	if refNo == "" {
		return fmt.Sprintf("D%d", wo.ID)
	}
	return refNo
}

func wholesaleOrderPONumberLabel(wo *models.WholesaleOrder) string {
	po := strings.TrimSpace(wo.PONumber)
	if po == "" {
		return wholesaleOrderRefLabel(wo)
	}
	return po
}

func wholesaleDeliveryNoteRefLabel(wo *models.WholesaleOrder, shipment *models.Shipment) string {
	if wo == nil || shipment == nil {
		return ""
	}
	if len(wo.Shipments) == 0 {
		return ""
	}
	sorted := append([]models.Shipment{}, wo.Shipments...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].ID < sorted[j].ID })
	shipmentNum := 0
	for i, s := range sorted {
		if s.ID == shipment.ID {
			shipmentNum = i + 1
			break
		}
	}
	if shipmentNum <= 0 {
		return ""
	}
	return fmt.Sprintf("d%d - %s / %s", shipmentNum, wholesaleOrderPONumberLabel(wo), wholesaleOrderRefLabel(wo))
}

const defaultWholesaleOrderEmailSubjectTemplate = "DUCKLIN COMPANY LTD Order Summary - {order ref} - {po number}"

const defaultWholesaleDeliveryProofEmailSubjectTemplate = "DUCKLIN COMPANY LTD Order Summary - {order ref} - {delivery number} - finished"

const defaultWholesaleOrderConfirmEmailSubjectTemplate = "DUCKLIN COMPANY LTD Order Confirmed - PO {po number} / {order ref}"

const defaultWholesaleShipmentsDeliveredEmailSubjectTemplate = "DUCKLIN COMPANY LTD Order Delivered - PO {po number} / {order ref}"

const defaultWholesaleInvoiceEmailSubjectTemplate = "DUCKLIN COMPANY LTD Order Invoice - PO {po number} / {order ref}"

func wholesaleOrderEmailStatusLabel(wo *models.WholesaleOrder) string {
	hasInvoice := false
	for _, d := range wo.Documents {
		if d.Type == "invoice" {
			hasInvoice = true
			break
		}
	}
	allShipmentsCompleted := len(wo.Shipments) > 0
	for _, s := range wo.Shipments {
		if s.Status != models.ShipmentStatusCompleted {
			allShipmentsCompleted = false
			break
		}
	}
	if hasInvoice && allShipmentsCompleted && wo.PaymentConfirmedAt != nil {
		return "Completed"
	}
	if wo.Status == models.WholesaleOrderStatusApproved && wo.PaymentConfirmedAt == nil {
		return "Awaiting payment"
	}
	switch wo.Status {
	case models.WholesaleOrderStatusPending:
		return "Pending approval"
	case models.WholesaleOrderStatusAssignShipment:
		return "Assign shipment"
	case models.WholesaleOrderStatusApproved:
		return "Approved"
	case models.WholesaleOrderStatusRejected:
		return "Rejected"
	case models.WholesaleOrderStatusDeleted:
		return "Deleted"
	default:
		return strings.ReplaceAll(wo.Status, "_", " ")
	}
}

func applyWholesaleOrderEmailSubjectTemplate(template string, wo *models.WholesaleOrder) string {
	tmpl := strings.TrimSpace(template)
	if tmpl == "" {
		tmpl = defaultWholesaleOrderEmailSubjectTemplate
	}
	ref := wholesaleOrderRefLabel(wo)
	orderNumber := strings.TrimSpace(wo.OrderNumber)
	if orderNumber == "" {
		orderNumber = ref
	}
	poNumber := wholesaleOrderPONumberLabel(wo)
	deliveryNumber := ""
	if len(wo.Shipments) > 0 {
		// Prefer shipments with a signed delivery note; otherwise fall back to latest shipment.
		var selected *models.Shipment
		for _, s := range wo.Shipments {
			if strings.TrimSpace(s.SignedDeliveryNotePDFURL) == "" {
				continue
			}
			sc := s
			if selected == nil || sc.ID > selected.ID {
				selected = &sc
			}
		}
		if selected == nil {
			for _, s := range wo.Shipments {
				sc := s
				if selected == nil || sc.ID > selected.ID {
					selected = &sc
				}
			}
		}
		if selected != nil {
			deliveryNumber = wholesaleDeliveryNoteRefLabel(wo, selected)
		}
	}
	return strings.NewReplacer(
		"{order ref}", ref,
		"{ref}", ref,
		"{po number}", poNumber,
		"{po_number}", poNumber,
		"{delivery number}", deliveryNumber,
		"{delivery_number}", deliveryNumber,
		"{status}", wholesaleOrderEmailStatusLabel(wo),
		"{order_number}", orderNumber,
		"{client_name}", strings.TrimSpace(wo.WholesaleClient.Name),
	).Replace(tmpl)
}

func wholesaleOrderEmailDefaultBody(wo *models.WholesaleOrder, attachmentPhrase string) string {
	if attachmentPhrase == "" {
		attachmentPhrase = "the attached documents"
	}
	clientName := strings.TrimSpace(wo.WholesaleClient.Name)
	if clientName == "" {
		clientName = "Customer"
	}
	ref := wholesaleOrderRefLabel(wo)
	orderNumber := strings.TrimSpace(wo.OrderNumber)
	if orderNumber == "" {
		orderNumber = ref
	}
	poNumber := strings.TrimSpace(wo.PONumber)
	if poNumber == "" {
		poNumber = "—"
	}
	total := wo.TotalNet + wo.ShippingFee
	return fmt.Sprintf(
		"Dear %s,\n\nPlease find %s for the following wholesale order:\n\nOrder ref: %s\nOrder number: %s\nStatus: %s\nPO number: %s\nTotal: £%.2f\n\nPlease let us know if you have any questions.\n\nThis message was sent from the POS management portal.\n",
		clientName,
		attachmentPhrase,
		ref,
		orderNumber,
		wholesaleOrderEmailStatusLabel(wo),
		poNumber,
		total,
	)
}

func wholesaleOrderEmailDefaultDeliveryCompleteBody(wo *models.WholesaleOrder, contactEmail string) string {
	if strings.TrimSpace(contactEmail) == "" {
		contactEmail = "hello@ducklincompany.co.uk"
	}
	clientName := strings.TrimSpace(wo.WholesaleClient.Name)
	if clientName == "" {
		clientName = "Customer"
	}
	ref := wholesaleOrderRefLabel(wo)
	orderNumber := strings.TrimSpace(wo.OrderNumber)
	if orderNumber == "" {
		orderNumber = ref
	}
	poNumber := strings.TrimSpace(wo.PONumber)
	if poNumber == "" {
		poNumber = "—"
	}
	amountDue := wo.TotalNet + wo.ShippingFee
	return fmt.Sprintf(
		"Dear %s,\n\nPlease find the attached documents for the following wholesale order:\n\nOrder ref: %s\nOrder number: %s\nPO number: %s\nAmount due: £%.2f\n\nPlease contact us by email %s if you have any queries regarding this order.\n\nPlease do not reply this email. This message was sent from the Ducklin POS management portal.\n",
		clientName,
		ref,
		orderNumber,
		poNumber,
		amountDue,
		strings.TrimSpace(contactEmail),
	)
}

func wholesaleOrderEmailDefaultOrderConfirmBody(wo *models.WholesaleOrder, contactEmail string) string {
	if strings.TrimSpace(contactEmail) == "" {
		contactEmail = "hello@ducklincompany.co.uk"
	}
	clientName := strings.TrimSpace(wo.WholesaleClient.Name)
	if clientName == "" {
		clientName = "Customer"
	}
	ref := wholesaleOrderRefLabel(wo)
	orderNumber := strings.TrimSpace(wo.OrderNumber)
	if orderNumber == "" {
		orderNumber = ref
	}
	poNumber := strings.TrimSpace(wo.PONumber)
	if poNumber == "" {
		poNumber = "—"
	}
	return fmt.Sprintf(
		"Dear %s,\n\nPlease find attached PO documents for the following wholesale order:\n\nOrder ref: %s\nOrder number: %s\nPO number: %s\n\nPlease confirm receipt at your earliest convenience.\n\nPlease contact us by email %s if you have any queries regarding this order.\n\nPlease do not reply this email. This message was sent from the Ducklin POS management portal.\n",
		clientName,
		ref,
		orderNumber,
		poNumber,
		strings.TrimSpace(contactEmail),
	)
}

func wholesaleOrderEmailDefaultInvoiceBody(wo *models.WholesaleOrder, contactEmail string) string {
	if strings.TrimSpace(contactEmail) == "" {
		contactEmail = "hello@ducklincompany.co.uk"
	}
	clientName := strings.TrimSpace(wo.WholesaleClient.Name)
	if clientName == "" {
		clientName = "Customer"
	}
	ref := wholesaleOrderRefLabel(wo)
	orderNumber := strings.TrimSpace(wo.OrderNumber)
	if orderNumber == "" {
		orderNumber = ref
	}
	poNumber := strings.TrimSpace(wo.PONumber)
	if poNumber == "" {
		poNumber = "—"
	}
	amountDue := wo.TotalNet + wo.ShippingFee
	return fmt.Sprintf(
		"Dear %s,\n\nPlease find attached invoice for the following wholesale order:\n\nOrder ref: %s\nOrder number: %s\nPO number: %s\nAmount due: £%.2f\n\nPlease contact us by email %s if you have any queries regarding this order.\n\nPlease do not reply this email. This message was sent from the Ducklin POS management portal.\n",
		clientName,
		ref,
		orderNumber,
		poNumber,
		amountDue,
		strings.TrimSpace(contactEmail),
	)
}

func isWholesaleShipmentsDeliveredEmail(attachments []string, signedDeliveryShipmentID *uint, emailType string) bool {
	if strings.TrimSpace(emailType) == "shipments_delivered" {
		return true
	}
	if signedDeliveryShipmentID != nil && *signedDeliveryShipmentID > 0 {
		return false
	}
	if len(attachments) == 0 {
		return false
	}
	for _, k := range attachments {
		if strings.TrimSpace(k) != "signed_delivery_note" {
			return false
		}
	}
	return true
}

func isWholesaleOrderConfirmEmail(attachments []string, emailType string) bool {
	if strings.TrimSpace(emailType) == "order_confirm" {
		return true
	}
	if len(attachments) == 0 {
		return false
	}
	for _, k := range attachments {
		k = strings.TrimSpace(k)
		if k != "po_attachment" && k != "order_confirmation" {
			return false
		}
	}
	return true
}

func isWholesaleInvoiceEmail(attachments []string, emailType string) bool {
	if strings.TrimSpace(emailType) == "invoice" {
		return true
	}
	if len(attachments) == 0 {
		return false
	}
	for _, k := range attachments {
		if strings.TrimSpace(k) != "invoice" {
			return false
		}
	}
	return true
}

func isWholesaleDeliveryCompleteEmail(attachments []string, signedDeliveryShipmentID *uint) bool {
	return isWholesaleShipmentsDeliveredEmail(attachments, signedDeliveryShipmentID, "")
}

func userDisplayName(u *models.User) string {
	if u == nil {
		return ""
	}
	name := strings.TrimSpace(strings.TrimSpace(u.FirstName) + " " + strings.TrimSpace(u.LastName))
	if name != "" {
		return name
	}
	return strings.TrimSpace(u.Username)
}

// EmailDocument sends a document (OC, invoice, or DN) with PDF attachment and records an audit log.
func (h *WholesaleOrderHandler) EmailDocument(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	if strings.TrimSpace(h.cfg.SMTPHost) == "" || strings.TrimSpace(h.cfg.SMTPUser) == "" || h.cfg.SMTPPassword == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Email is not configured (set SMTP_HOST, SMTP_USER, SMTP_PASSWORD)"})
		return
	}
	var wo models.WholesaleOrder
	if err := h.db.Preload("WholesaleClient").Preload("Documents").Preload("Shipments").First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	var req struct {
		DocumentType string   `json:"document_type" binding:"required"`
		Recipient    string   `json:"recipient"`
		To           []string `json:"to"`
		CC           string   `json:"cc"`
		Cc           []string `json:"cc_list"`
		BCC          string   `json:"bcc"`
		Bcc          []string `json:"bcc_list"`
		ShipmentID   *uint    `json:"shipment_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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

	toList := append([]string{}, req.To...)
	if r := strings.TrimSpace(req.Recipient); r != "" {
		toList = append(toList, parseEmailList(r)...)
	}
	if len(toList) == 0 {
		recipient := strings.TrimSpace(wo.WholesaleClient.Email)
		if recipient != "" {
			toList = append(toList, recipient)
		}
	}
	if len(toList) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No recipient email address"})
		return
	}

	ccList := append([]string{}, req.Cc...)
	if cc := strings.TrimSpace(req.CC); cc != "" {
		ccList = append(ccList, parseEmailList(cc)...)
	}
	if len(ccList) == 0 {
		userIDVal, _ := c.Get("user_id")
		if uid, ok := userIDVal.(uint); ok && uid > 0 {
			var u models.User
			if err := h.db.Select("email").First(&u, uid).Error; err == nil {
				if email := strings.TrimSpace(u.Email); email != "" {
					ccList = append(ccList, email)
				}
			}
		}
	}
	bccList := append([]string{}, req.Bcc...)
	if bcc := strings.TrimSpace(req.BCC); bcc != "" {
		bccList = append(bccList, parseEmailList(bcc)...)
	}

	var initiatorName string
	userIDVal, _ := c.Get("user_id")
	if uid, ok := userIDVal.(uint); ok && uid > 0 {
		var u models.User
		if err := h.db.Select("id", "username", "first_name", "last_name", "email").First(&u, uid).Error; err == nil {
			initiatorName = userDisplayName(&u)
		}
	}

	refLabel := wholesaleOrderRefLabel(&wo)
	var attachFilename string
	var pdfBytes []byte
	var docLabel string

	switch req.DocumentType {
	case "invoice":
		var doc models.WholesaleOrderDocument
		if err := h.db.Where("wholesale_order_id = ? AND type = ?", wo.ID, "invoice").First(&doc).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No invoice on this order; generate an invoice first"})
			return
		}
		data, err := h.readBytesFromFileURL(doc.FileURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read invoice PDF: " + err.Error()})
			return
		}
		pdfBytes = data
		docLabel = "Invoice"
		refSafe := strings.ReplaceAll(strings.ReplaceAll(refLabel, "/", "_"), "\\", "_")
		attachFilename = fmt.Sprintf("%s_invoice.pdf", refSafe)

	case "delivery_note":
		if req.ShipmentID == nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "shipment_id is required for delivery note"})
			return
		}
		var sh models.Shipment
		if err := h.db.Where("id = ? AND wholesale_order_id = ?", *req.ShipmentID, wo.ID).First(&sh).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
			return
		}
		if strings.TrimSpace(sh.DeliveryNotePDFURL) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No delivery note PDF for this shipment"})
			return
		}
		data, err := h.readBytesFromFileURL(sh.DeliveryNotePDFURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read delivery note PDF: " + err.Error()})
			return
		}
		pdfBytes = data
		docLabel = "Delivery note"
		refSafe := strings.ReplaceAll(strings.ReplaceAll(refLabel, "/", "_"), "\\", "_")
		attachFilename = fmt.Sprintf("%s_delivery_note_shipment_%d.pdf", refSafe, sh.ID)

	case "order_confirmation":
		var doc models.WholesaleOrderDocument
		if err := h.db.Where("wholesale_order_id = ? AND type = ?", wo.ID, "order_confirmation").First(&doc).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No order confirmation on this order"})
			return
		}
		data, err := h.readBytesFromFileURL(doc.FileURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read order confirmation PDF: " + err.Error()})
			return
		}
		pdfBytes = data
		docLabel = "Order confirmation"
		refSafe := strings.ReplaceAll(strings.ReplaceAll(refLabel, "/", "_"), "\\", "_")
		attachFilename = fmt.Sprintf("%s_order_confirmation.pdf", refSafe)
	}

	subject := fmt.Sprintf("%s — %s (%s)", docLabel, refLabel, wo.WholesaleClient.Name)
	body := wholesaleOrderEmailDefaultBody(&wo, fmt.Sprintf("the attached %s", strings.ToLower(docLabel)))
	from := h.cfg.EffectiveSMTPFrom()
	if err := apimail.SendWithAttachments(
		h.cfg.SMTPHost, h.cfg.SMTPPort, h.cfg.SMTPUser, h.cfg.SMTPPassword, from,
		toList, ccList, bccList, subject, body,
		[]apimail.Attachment{{Filename: attachFilename, ContentType: "application/pdf", Data: pdfBytes}},
	); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "Failed to send email: " + err.Error()})
		return
	}

	sentAt := time.Now().UTC()
	if req.DocumentType == "invoice" {
		today := time.Date(sentAt.Year(), sentAt.Month(), sentAt.Day(), 0, 0, 0, 0, time.UTC)
		_ = h.db.Model(&wo).Update("invoice_sent_at", &today).Error
	}

	changes := map[string]interface{}{
		"document_type": req.DocumentType,
		"recipient":     strings.Join(toList, ", "),
		"to":            toList,
		"sent_at":       sentAt.Format(time.RFC3339),
		"initiated_by":  initiatorName,
		"attachment":    attachFilename,
	}
	if len(ccList) > 0 {
		changes["cc"] = strings.Join(ccList, ", ")
		changes["cc_list"] = ccList
	}
	if len(bccList) > 0 {
		changes["bcc"] = strings.Join(bccList, ", ")
		changes["bcc_list"] = bccList
	}
	if req.ShipmentID != nil {
		changes["shipment_id"] = *req.ShipmentID
	}

	h.audit(c, action, wo.ID, changes)

	h.db.Preload("Items.Product").Preload("WholesaleClient.Stores").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Sector").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&wo, wo.ID)

	c.JSON(http.StatusOK, gin.H{
		"message":      "Email sent",
		"recipient":    strings.Join(toList, ", "),
		"to":           toList,
		"cc":           strings.Join(ccList, ", "),
		"cc_list":      ccList,
		"bcc":          strings.Join(bccList, ", "),
		"bcc_list":     bccList,
		"sent_at":      sentAt.Format(time.RFC3339),
		"initiated_by": initiatorName,
		"order":        wo,
	})
}

type WholesaleRevenueSummaryStat struct {
	TotalRevenue float64 `json:"total_revenue"`
}

type WholesaleProductSalesStat struct {
	ProductID          uint    `json:"product_id"`
	ProductName        string  `json:"product_name"`
	ProductNameChinese string  `json:"product_name_chinese"`
	Quantity           float64 `json:"quantity"`
	Revenue            float64 `json:"revenue"`
}

type WholesaleClientSalesStat struct {
	ClientID   uint    `json:"client_id"`
	ClientName string  `json:"client_name"`
	Revenue    float64 `json:"revenue"`
}

// parseWholesaleReportDateRange parses start_date/end_date from query params (yyyy-mm-dd).
// If not provided, it falls back to the last 30 days.
func parseWholesaleReportDateRange(c *gin.Context, defaultDays int) (startDate, endDate time.Time) {
	startStr := c.Query("start_date")
	endStr := c.Query("end_date")

	if startStr != "" && endStr != "" {
		s, err := time.Parse("2006-01-02", startStr)
		if err == nil {
			startDate = s
		} else {
			startDate = time.Now().AddDate(0, 0, -defaultDays)
		}

		e, err := time.Parse("2006-01-02", endStr)
		if err == nil {
			endDate = e
		} else {
			endDate = time.Now()
		}

		if endDate.Before(startDate) {
			startDate, endDate = endDate, startDate
		}
	} else {
		endDate = time.Now()
		startDate = endDate.AddDate(0, 0, -defaultDays)
	}

	return startDate, endDate
}

func parseCSVUint(s string) []uint {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]uint, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		v, err := strconv.ParseUint(p, 10, 64)
		if err != nil {
			continue
		}
		out = append(out, uint(v))
	}
	return out
}

// GetWholesaleRevenueSummaryStats returns a single-row revenue total for the given date range.
// "Revenue" is computed as SUM(total_net + shipping_fee) for paid (payment_confirmed_at is not null) orders.
func (h *WholesaleOrderHandler) GetWholesaleRevenueSummaryStats(c *gin.Context) {
	startDate, endDate := parseWholesaleReportDateRange(c, 30)
	storeIDs := parseCSVUint(c.Query("store_ids"))
	storeID := c.Query("store_id")

	// Use end-exclusive range for consistent behavior with other stats endpoints.
	endExclusive := endDate.AddDate(0, 0, 1)

	query := h.db.Table("wholesale_orders wo").
		Select("COALESCE(SUM(COALESCE(wo.total_net, 0) + COALESCE(wo.shipping_fee, 0)), 0) AS total_revenue").
		Where("wo.payment_confirmed_at IS NOT NULL").
		Where("wo.status != ? AND wo.status != ?", models.WholesaleOrderStatusRejected, models.WholesaleOrderStatusDeleted).
		Where("COALESCE(wo.order_date, wo.created_at) >= ? AND COALESCE(wo.order_date, wo.created_at) < ?", startDate, endExclusive)

	if len(storeIDs) > 0 {
		query = query.Where("wo.store_id IN ?", storeIDs)
	} else if storeID != "" {
		query = query.Where("wo.store_id = ?", storeID)
	}

	var stat WholesaleRevenueSummaryStat
	if err := query.Scan(&stat).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stat)
}

// GetWholesaleProductSalesStats aggregates quantities and line revenue per product for the given date range.
func (h *WholesaleOrderHandler) GetWholesaleProductSalesStats(c *gin.Context) {
	startDate, endDate := parseWholesaleReportDateRange(c, 30)
	storeIDs := parseCSVUint(c.Query("store_ids"))
	storeID := c.Query("store_id")
	endExclusive := endDate.AddDate(0, 0, 1)

	query := h.db.Table("wholesale_orders wo").
		Select(`
			woi.product_id AS product_id,
			p.name AS product_name,
			p.name_chinese AS product_name_chinese,
			SUM(woi.quantity) AS quantity,
			SUM(woi.line_total) AS revenue
		`).
		Joins("INNER JOIN wholesale_order_items woi ON wo.id = woi.wholesale_order_id").
		Joins("INNER JOIN products p ON p.id = woi.product_id").
		Where("wo.payment_confirmed_at IS NOT NULL").
		Where("wo.status != ? AND wo.status != ?", models.WholesaleOrderStatusRejected, models.WholesaleOrderStatusDeleted).
		Where("COALESCE(wo.order_date, wo.created_at) >= ? AND COALESCE(wo.order_date, wo.created_at) < ?", startDate, endExclusive).
		Group("woi.product_id, p.name, p.name_chinese").
		Order("revenue DESC")

	if len(storeIDs) > 0 {
		query = query.Where("wo.store_id IN ?", storeIDs)
	} else if storeID != "" {
		query = query.Where("wo.store_id = ?", storeID)
	}

	stats := make([]WholesaleProductSalesStat, 0)
	if err := query.Scan(&stats).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// GetWholesaleClientSalesStats aggregates revenue totals by wholesale client for the given date range.
func (h *WholesaleOrderHandler) GetWholesaleClientSalesStats(c *gin.Context) {
	startDate, endDate := parseWholesaleReportDateRange(c, 30)
	storeIDs := parseCSVUint(c.Query("store_ids"))
	storeID := c.Query("store_id")
	endExclusive := endDate.AddDate(0, 0, 1)

	query := h.db.Table("wholesale_orders wo").
		Select(`
			wo.wholesale_client_id AS client_id,
			wc.name AS client_name,
			SUM(COALESCE(wo.total_net, 0) + COALESCE(wo.shipping_fee, 0)) AS revenue
		`).
		Joins("INNER JOIN wholesale_clients wc ON wc.id = wo.wholesale_client_id").
		Where("wo.payment_confirmed_at IS NOT NULL").
		Where("wo.status != ? AND wo.status != ?", models.WholesaleOrderStatusRejected, models.WholesaleOrderStatusDeleted).
		Where("COALESCE(wo.order_date, wo.created_at) >= ? AND COALESCE(wo.order_date, wo.created_at) < ?", startDate, endExclusive).
		Group("wo.wholesale_client_id, wc.name").
		Order("revenue DESC")

	if len(storeIDs) > 0 {
		query = query.Where("wo.store_id IN ?", storeIDs)
	} else if storeID != "" {
		query = query.Where("wo.store_id = ?", storeID)
	}

	stats := make([]WholesaleClientSalesStat, 0)
	if err := query.Scan(&stats).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}
