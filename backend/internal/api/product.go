package api

import (
	"fmt"
	"image"
	_ "image/gif" // Register GIF decoder
	"image/jpeg"
	_ "image/png" // Register PNG decoder
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"

	"github.com/disintegration/imaging"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ProductHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewProductHandler(db *gorm.DB, cfg *config.Config) *ProductHandler {
	return &ProductHandler{db: db, cfg: cfg}
}

type CreateProductRequest struct {
	Name        string `json:"name" binding:"required"`
	NameChinese string `json:"name_chinese"`
	Barcode     string `json:"barcode"`
	SKU         string `json:"sku"`
	Category    string `json:"category"`
	ImageURL    string `json:"image_url"`
	UnitType    string `json:"unit_type" binding:"required,oneof=quantity weight"`
}

type SetCostRequest struct {
	ExchangeRate                    float64 `json:"exchange_rate" binding:"required"`
	PurchasingCostHKD               float64 `json:"purchasing_cost_hkd"`
	UnitWeightG                     int     `json:"unit_weight_g" binding:"required"`
	PurchasingCostBufferPercent     float64 `json:"purchasing_cost_buffer_percent"`
	WeightG                         int     `json:"weight_g" binding:"required"`
	WeightBufferPercent             float64 `json:"weight_buffer_percent"`
	FreightRateHKDPerKG             float64 `json:"freight_rate_hkd_per_kg" binding:"required"`
	FreightBufferHKD                float64 `json:"freight_buffer_hkd"`
	ImportDutyPercent               float64 `json:"import_duty_percent"`
	PackagingGBP                    float64 `json:"packaging_gbp"`
	DirectRetailOnlineStorePriceGBP float64 `json:"direct_retail_online_store_price_gbp"` // Direct Retail Online Store price
}

func (h *ProductHandler) ListProducts(c *gin.Context) {
	var products []models.Product
	query := h.db.Where("is_active = ?", true)

	// Filter by category if provided
	if category := c.Query("category"); category != "" {
		query = query.Where("category = ?", category)
	}

	if err := query.Find(&products).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Load current costs
	for i := range products {
		var cost models.ProductCost
		h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", products[i].ID, time.Now()).
			Order("effective_from DESC").First(&cost)
		products[i].CurrentCost = &cost
	}

	c.JSON(http.StatusOK, products)
}

func (h *ProductHandler) GetProduct(c *gin.Context) {
	var product models.Product
	if err := h.db.First(&product, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	// Load current cost
	var cost models.ProductCost
	h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, time.Now()).
		Order("effective_from DESC").First(&cost)
	product.CurrentCost = &cost

	c.JSON(http.StatusOK, product)
}

func (h *ProductHandler) CreateProduct(c *gin.Context) {
	var req CreateProductRequest

	// Check if it's multipart form data (file upload)
	contentType := c.GetHeader("Content-Type")
	if strings.HasPrefix(contentType, "multipart/form-data") {
		// Handle form data with file upload
		req.Name = c.PostForm("name")
		req.NameChinese = c.PostForm("name_chinese")
		req.Barcode = c.PostForm("barcode")
		req.SKU = c.PostForm("sku")
		req.Category = c.PostForm("category")
		req.UnitType = c.PostForm("unit_type")

		if req.Name == "" || req.UnitType == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name and unit_type are required"})
			return
		}
	} else {
		// Handle JSON (backward compatibility)
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	// Handle image upload (file upload only, no URL)
	var imageURL string
	file, err := c.FormFile("image")
	if err == nil && file != nil {
		// File was uploaded
		uploadedURL, uploadErr := h.uploadImage(file, c)
		if uploadErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
			return
		}
		imageURL = uploadedURL
	} else if req.ImageURL != "" {
		// Allow image URL only for JSON backward compatibility
		imageURL = req.ImageURL
	}

	product := models.Product{
		Name:        req.Name,
		NameChinese: req.NameChinese,
		Barcode:     req.Barcode,
		SKU:         req.SKU,
		Category:    req.Category,
		ImageURL:    imageURL,
		UnitType:    req.UnitType,
		IsActive:    true,
	}

	if err := h.db.Create(&product).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, product)
}

func (h *ProductHandler) UpdateProduct(c *gin.Context) {
	var product models.Product
	if err := h.db.First(&product, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	var req CreateProductRequest

	// Check if it's multipart form data (file upload)
	contentType := c.GetHeader("Content-Type")
	if strings.HasPrefix(contentType, "multipart/form-data") {
		// Handle form data with file upload
		req.Name = c.PostForm("name")
		req.NameChinese = c.PostForm("name_chinese")
		req.Barcode = c.PostForm("barcode")
		req.SKU = c.PostForm("sku")
		req.Category = c.PostForm("category")
		req.UnitType = c.PostForm("unit_type")

		if req.Name == "" || req.UnitType == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name and unit_type are required"})
			return
		}
	} else {
		// Handle JSON (backward compatibility)
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	// Handle image upload (file upload only, no URL)
	var imageURL string
	file, err := c.FormFile("image")
	if err == nil && file != nil {
		// File was uploaded
		uploadedURL, uploadErr := h.uploadImage(file, c)
		if uploadErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
			return
		}
		imageURL = uploadedURL
	} else if req.ImageURL != "" {
		// Allow image URL only for JSON backward compatibility
		imageURL = req.ImageURL
	} else {
		// Keep existing image if no new one provided
		imageURL = product.ImageURL
	}

	product.Name = req.Name
	product.NameChinese = req.NameChinese
	product.Barcode = req.Barcode
	product.SKU = req.SKU
	product.Category = req.Category
	product.ImageURL = imageURL
	product.UnitType = req.UnitType

	if err := h.db.Save(&product).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, product)
}

func (h *ProductHandler) DeleteProduct(c *gin.Context) {
	var product models.Product
	if err := h.db.First(&product, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	// Soft delete
	product.IsActive = false
	if err := h.db.Save(&product).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Product deactivated"})
}

func (h *ProductHandler) SetProductCost(c *gin.Context) {
	var product models.Product
	if err := h.db.First(&product, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	var req SetCostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Calculate costs based on Excel formula
	cost := h.calculateProductCost(product.ID, req)

	// Deactivate previous cost
	now := time.Now()
	h.db.Model(&models.ProductCost{}).
		Where("product_id = ? AND effective_to IS NULL", product.ID).
		Update("effective_to", now)

	// Create new cost
	if err := h.db.Create(&cost).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Record price history
	h.recordPriceHistory(product.ID, nil, cost.WholesaleCostGBP, 0, cost.WholesaleCostGBP)

	c.JSON(http.StatusCreated, cost)
}

func (h *ProductHandler) calculateProductCost(productID uint, req SetCostRequest) models.ProductCost {
	// Calculate purchasing cost in GBP
	purchasingCostGBP := req.PurchasingCostHKD / req.ExchangeRate

	// Calculate cost buffer
	costBufferGBP := purchasingCostGBP * (req.PurchasingCostBufferPercent / 100.0)

	// Adjusted purchasing cost
	adjustedPurchasingCostGBP := purchasingCostGBP + costBufferGBP

	// Calculate freight
	weightKG := float64(req.WeightG) / 1000.0
	weightWithBuffer := weightKG * (1 + req.WeightBufferPercent/100.0)
	freightHKD := (req.FreightRateHKDPerKG * weightWithBuffer) + req.FreightBufferHKD
	freightGBP := freightHKD / req.ExchangeRate

	// Calculate import duty
	importDutyGBP := adjustedPurchasingCostGBP * (req.ImportDutyPercent / 100.0)

	// Calculate wholesale cost
	wholesaleCostGBP := adjustedPurchasingCostGBP + freightGBP + importDutyGBP + req.PackagingGBP

	return models.ProductCost{
		ProductID:                       productID,
		ExchangeRate:                    req.ExchangeRate,
		PurchasingCostHKD:               req.PurchasingCostHKD,
		PurchasingCostGBP:               purchasingCostGBP,
		UnitWeightG:                     req.UnitWeightG,
		PurchasingCostBufferPercent:     req.PurchasingCostBufferPercent,
		CostBufferGBP:                   costBufferGBP,
		AdjustedPurchasingCostGBP:       adjustedPurchasingCostGBP,
		WeightG:                         req.WeightG,
		WeightBufferPercent:             req.WeightBufferPercent,
		FreightRateHKDPerKG:             req.FreightRateHKDPerKG,
		FreightBufferHKD:                req.FreightBufferHKD,
		FreightHKD:                      freightHKD,
		FreightGBP:                      freightGBP,
		ImportDutyPercent:               req.ImportDutyPercent,
		ImportDutyGBP:                   importDutyGBP,
		PackagingGBP:                    req.PackagingGBP,
		WholesaleCostGBP:                wholesaleCostGBP,
		DirectRetailOnlineStorePriceGBP: req.DirectRetailOnlineStorePriceGBP,
		EffectiveFrom:                   time.Now(),
	}
}

func (h *ProductHandler) SetDiscount(c *gin.Context) {
	var product models.Product
	if err := h.db.First(&product, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	var sector models.Sector
	if err := h.db.First(&sector, c.Param("sector_id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Sector not found"})
		return
	}

	var req struct {
		DiscountPercent float64 `json:"discount_percent" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Deactivate previous discount
	now := time.Now()
	h.db.Model(&models.ProductSectorDiscount{}).
		Where("product_id = ? AND sector_id = ? AND effective_to IS NULL", product.ID, sector.ID).
		Update("effective_to", now)

	// Create new discount
	discount := models.ProductSectorDiscount{
		ProductID:       product.ID,
		SectorID:        sector.ID,
		DiscountPercent: req.DiscountPercent,
		EffectiveFrom:   now,
	}

	if err := h.db.Create(&discount).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Record price history using Direct Retail Online Store Price
	var cost models.ProductCost
	h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, time.Now()).
		Order("effective_from DESC").First(&cost)

	// Use Direct Retail Online Store Price as base, fallback to WholesaleCostGBP if not set
	basePrice := cost.DirectRetailOnlineStorePriceGBP
	if basePrice <= 0 {
		basePrice = cost.WholesaleCostGBP
	}

	// Apply sector discount rate first, then product discount
	var sectorDiscountRate float64
	if sector.DiscountRate > 0 {
		sectorDiscountRate = sector.DiscountRate
	}
	priceAfterSectorDiscount := basePrice * (1 - sectorDiscountRate/100.0)
	finalPrice := priceAfterSectorDiscount * (1 - req.DiscountPercent/100.0)
	totalDiscountPercent := sectorDiscountRate + req.DiscountPercent

	h.recordPriceHistory(product.ID, &sector.ID, basePrice, totalDiscountPercent, finalPrice)

	c.JSON(http.StatusCreated, discount)
}

func (h *ProductHandler) GetDiscounts(c *gin.Context) {
	var discounts []models.ProductSectorDiscount
	if err := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)",
		c.Param("id"), time.Now()).Find(&discounts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, discounts)
}

func (h *ProductHandler) GetPriceHistory(c *gin.Context) {
	var history []models.PriceHistory
	query := h.db.Where("product_id = ?", c.Param("id"))

	if sectorID := c.Query("sector_id"); sectorID != "" {
		query = query.Where("sector_id = ?", sectorID)
	}

	if err := query.Order("recorded_at DESC").Limit(100).Find(&history).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, history)
}

func (h *ProductHandler) recordPriceHistory(productID uint, sectorID *uint, wholesaleCost, discountPercent, finalPrice float64) {
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

// uploadImage handles image file uploads
func (h *ProductHandler) uploadImage(file *multipart.FileHeader, c *gin.Context) (string, error) {
	// Validate file type
	ext := strings.ToLower(filepath.Ext(file.Filename))
	allowedExts := []string{".jpg", ".jpeg", ".png", ".gif"}
	// Note: WebP support can be added by importing golang.org/x/image/webp
	allowed := false
	for _, allowedExt := range allowedExts {
		if ext == allowedExt {
			allowed = true
			break
		}
	}
	if !allowed {
		return "", fmt.Errorf("invalid file type. Allowed: %v", allowedExts)
	}

	// No file size limit - we'll resize large images

	// Create uploads directory if it doesn't exist
	uploadDir := h.cfg.UploadDir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create upload directory: %w", err)
	}

	// Generate unique filename (always save as JPEG for consistency and smaller file size)
	// Extract original extension for reference, but save as .jpg
	originalExt := strings.ToLower(filepath.Ext(file.Filename))
	baseName := strings.TrimSuffix(filepath.Base(file.Filename), originalExt)
	filename := fmt.Sprintf("%d_%s.jpg", time.Now().UnixNano(), baseName)
	filePath := filepath.Join(uploadDir, filename)

	// Open and decode image
	src, err := file.Open()
	if err != nil {
		return "", fmt.Errorf("failed to open uploaded file: %w", err)
	}
	defer src.Close()

	// Decode image (supports JPEG, PNG, GIF)
	// Note: WebP support requires golang.org/x/image/webp package
	img, _, err := image.Decode(src)
	if err != nil {
		return "", fmt.Errorf("failed to decode image (supported: JPEG, PNG, GIF): %w", err)
	}

	// Resize image if it's too large (max 1920x1920, maintain aspect ratio)
	maxWidth := 1920
	maxHeight := 1920
	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	var resizedImg image.Image = img
	if width > maxWidth || height > maxHeight {
		// Calculate new dimensions maintaining aspect ratio
		ratio := float64(width) / float64(height)
		var newWidth, newHeight int
		if width > height {
			newWidth = maxWidth
			newHeight = int(float64(maxWidth) / ratio)
		} else {
			newHeight = maxHeight
			newWidth = int(float64(maxHeight) * ratio)
		}
		resizedImg = imaging.Resize(img, newWidth, newHeight, imaging.Lanczos)
	}

	// Save resized image
	dst, err := os.Create(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to create file: %w", err)
	}
	defer dst.Close()

	// Always save as JPEG for consistency and smaller file size
	// Convert all formats (PNG, GIF, WebP) to JPEG
	err = jpeg.Encode(dst, resizedImg, &jpeg.Options{Quality: 85})
	if err != nil {
		return "", fmt.Errorf("failed to encode image: %w", err)
	}

	// Return URL
	baseURL := strings.TrimSuffix(h.cfg.BaseURL, "/")
	imageURL := fmt.Sprintf("%s/uploads/%s", baseURL, filename)
	return imageURL, nil
}
