package api

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	_ "image/gif" // Register GIF decoder
	"image/jpeg"
	_ "image/png" // Register PNG decoder
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"

	"cloud.google.com/go/storage"
	"github.com/disintegration/imaging"
	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
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
		// Use Find with Limit(1) instead of First to avoid "record not found" error logging
		// Find doesn't return an error when no records are found
		result := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", products[i].ID, time.Now()).
			Order("effective_from DESC").Limit(1).Find(&cost)
		if result.Error != nil {
			// Log actual errors
			fmt.Printf("Error loading cost for product %d: %v\n", products[i].ID, result.Error)
			products[i].CurrentCost = nil
		} else if result.RowsAffected == 0 {
			// No cost record exists, set to nil (will be handled by frontend)
			products[i].CurrentCost = nil
		} else {
			products[i].CurrentCost = &cost
		}
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

// ImportProductsFromExcel handles bulk product creation from an Excel file.
// Expected headers (first row):
// Chinese Name | English name | Unit | Barcode | Retail Price | Category (optional) | Sector - Loog Fung Retail (optional)
func (h *ProductHandler) ImportProductsFromExcel(c *gin.Context) {
	fileHeader, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file is required"})
		return
	}

	f, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to open uploaded file"})
		return
	}
	defer f.Close()

	xl, err := excelize.OpenReader(f)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid Excel file"})
		return
	}
	defer xl.Close()

	sheetName := xl.GetSheetName(0)
	if sheetName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Excel file has no sheets"})
		return
	}

	rows, err := xl.Rows(sheetName)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read Excel rows"})
		return
	}

	// Read header row
	if !rows.Next() {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Excel file is empty"})
		return
	}
	headerRow, err := rows.Columns()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read header row"})
		return
	}

	headerIndex := map[string]int{}
	for i, hcell := range headerRow {
		switch strings.TrimSpace(strings.ToLower(hcell)) {
		case strings.ToLower("Chinese Name"):
			headerIndex["chinese_name"] = i
		case strings.ToLower("English name"):
			headerIndex["english_name"] = i
		case strings.ToLower("Unit"):
			headerIndex["unit"] = i
		case strings.ToLower("Barcode"):
			headerIndex["barcode"] = i
		case strings.ToLower("Retail Price"):
			headerIndex["retail_price"] = i
		case strings.ToLower("Sector - Loog Fung Retail"):
			headerIndex["sector"] = i
		case strings.ToLower("Category"):
			headerIndex["category"] = i
		}
	}

	required := []string{"chinese_name", "english_name", "unit", "barcode", "retail_price"}
	for _, key := range required {
		if _, ok := headerIndex[key]; !ok {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("missing required header: %s", key)})
			return
		}
	}

	imported := 0
	updated := 0
	var rowErrors []string

	rowNum := 1 // header already read
	for rows.Next() {
		rowNum++
		cols, err := rows.Columns()
		if err != nil {
			rowErrors = append(rowErrors, fmt.Sprintf("row %d: failed to read row", rowNum))
			continue
		}

		get := func(key string) string {
			idx, ok := headerIndex[key]
			if !ok || idx >= len(cols) {
				return ""
			}
			return strings.TrimSpace(cols[idx])
		}

		nameZh := get("chinese_name")
		nameEn := get("english_name")
		unit := strings.ToLower(get("unit"))
		barcode := get("barcode")
		retailStr := get("retail_price")
		sectorName := get("sector")
		category := get("category")

		if nameEn == "" && nameZh == "" {
			rowErrors = append(rowErrors, fmt.Sprintf("row %d: missing product name", rowNum))
			continue
		}

		if unit == "" {
			unit = "quantity"
		}
		if unit != "quantity" && unit != "weight" {
			unit = "quantity"
		}

		// Parse Retail Price (Direct Retail Price)
		clean := strings.ReplaceAll(retailStr, ",", "")
		clean = strings.TrimPrefix(clean, "£")
		clean = strings.TrimSpace(clean)
		var retail float64
		if clean != "" {
			r, err := strconv.ParseFloat(clean, 64)
			if err != nil {
				rowErrors = append(rowErrors, fmt.Sprintf("row %d: invalid Retail Price", rowNum))
				continue
			}
			retail = r
		}

		// Find or create product (prefer barcode)
		var product models.Product
		var findErr error

		if barcode != "" {
			findErr = h.db.Where("barcode = ?", barcode).First(&product).Error
		} else if nameEn != "" {
			findErr = h.db.Where("name = ?", nameEn).First(&product).Error
		}

		if findErr != nil {
			if !errors.Is(findErr, gorm.ErrRecordNotFound) {
				rowErrors = append(rowErrors, fmt.Sprintf("row %d: %v", rowNum, findErr))
				continue
			}
			// New product
			// Use barcode as SKU if barcode is provided
			sku := ""
			if barcode != "" {
				sku = barcode
			}

			product = models.Product{
				Name:        nameEn,
				NameChinese: nameZh,
				Barcode:     barcode,
				SKU:         sku,
				Category:    category,
				UnitType:    unit,
				IsActive:    true,
			}
			if err := h.db.Create(&product).Error; err != nil {
				rowErrors = append(rowErrors, fmt.Sprintf("row %d: failed to create product: %v", rowNum, err))
				continue
			}
			imported++
		} else {
			// Update existing basic fields
			if nameEn != "" {
				product.Name = nameEn
			}
			if nameZh != "" {
				product.NameChinese = nameZh
			}
			product.UnitType = unit
			if barcode != "" {
				product.Barcode = barcode
				// Use barcode as SKU if SKU is empty
				if product.SKU == "" {
					product.SKU = barcode
				}
			}
			if category != "" {
				product.Category = category
			}
			if err := h.db.Save(&product).Error; err != nil {
				rowErrors = append(rowErrors, fmt.Sprintf("row %d: failed to update product: %v", rowNum, err))
				continue
			}
			updated++
		}

		// Update Direct Retail Online Store price
		if retail > 0 {
			var cost models.ProductCost
			err := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, time.Now()).
				Order("effective_from DESC").
				First(&cost).Error

			if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
				rowErrors = append(rowErrors, fmt.Sprintf("row %d: failed to load cost: %v", rowNum, err))
				continue
			}

			if errors.Is(err, gorm.ErrRecordNotFound) {
				// Create new cost record with all required fields
				now := time.Now()
				cost = models.ProductCost{
					ProductID:                       product.ID,
					ExchangeRate:                    1,
					UnitWeightG:                     1,
					WeightG:                         1,
					FreightRateHKDPerKG:             0,
					DirectRetailOnlineStorePriceGBP: retail,
					EffectiveFrom:                   &now, // Always set to current time
					EffectiveTo:                     nil,  // NULL means currently active
				}
				if err := h.db.Create(&cost).Error; err != nil {
					rowErrors = append(rowErrors, fmt.Sprintf("row %d: failed to create cost: %v", rowNum, err))
				}
			} else {
				// Update existing cost
				cost.ProductID = product.ID
				cost.DirectRetailOnlineStorePriceGBP = retail
				// Ensure EffectiveFrom is set if it's nil (shouldn't happen, but safety check)
				if cost.EffectiveFrom == nil {
					now := time.Now()
					cost.EffectiveFrom = &now
				}
				if err := h.db.Save(&cost).Error; err != nil {
					rowErrors = append(rowErrors, fmt.Sprintf("row %d: failed to update cost: %v", rowNum, err))
				}
			}
		}

		// Optionally link to sector (no hard failure if missing)
		if sectorName != "" {
			var sector models.Sector
			if err := h.db.Where("name = ?", sectorName).First(&sector).Error; err == nil {
				var psd models.ProductSectorDiscount
				if err := h.db.Where("product_id = ? AND sector_id = ?", product.ID, sector.ID).
					First(&psd).Error; errors.Is(err, gorm.ErrRecordNotFound) {
					psd = models.ProductSectorDiscount{
						ProductID:       product.ID,
						SectorID:        sector.ID,
						DiscountPercent: 0,
					}
					_ = h.db.Create(&psd).Error
				}
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"imported": imported,
		"updated":  updated,
		"errors":   rowErrors,
	})
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

// UpdateProductCostSimple allows updating just wholesale cost and retail price without full recalculation
func (h *ProductHandler) UpdateProductCostSimple(c *gin.Context) {
	var product models.Product
	if err := h.db.First(&product, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	var req struct {
		WholesaleCostGBP                *float64 `json:"wholesale_cost_gbp"`
		DirectRetailOnlineStorePriceGBP *float64 `json:"direct_retail_online_store_price_gbp"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get current cost or create new one
	var cost models.ProductCost
	err := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, time.Now()).
		Order("effective_from DESC").First(&cost).Error

	isNewRecord := false
	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Create new cost with minimal required fields
		now := time.Now()
		cost = models.ProductCost{
			ProductID:                       product.ID,
			ExchangeRate:                    1,
			UnitWeightG:                     1,
			WeightG:                         1,
			FreightRateHKDPerKG:             0,
			WholesaleCostGBP:                0,
			DirectRetailOnlineStorePriceGBP: 0,
			EffectiveFrom:                   &now,
		}
		isNewRecord = true
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Update fields if provided
	if req.WholesaleCostGBP != nil {
		if isNewRecord {
			// For new records, just set the value
			cost.WholesaleCostGBP = *req.WholesaleCostGBP
		} else if cost.WholesaleCostGBP != *req.WholesaleCostGBP {
			// Deactivate previous cost if wholesale cost changed
			now := time.Now()
			h.db.Model(&models.ProductCost{}).
				Where("product_id = ? AND effective_to IS NULL", product.ID).
				Update("effective_to", now)

			// Create new cost record with updated value
			cost.ID = 0 // Reset ID for new record
			cost.WholesaleCostGBP = *req.WholesaleCostGBP
			cost.EffectiveFrom = &now
			cost.EffectiveTo = nil
			isNewRecord = true
		} else {
			cost.WholesaleCostGBP = *req.WholesaleCostGBP
		}
	}

	if req.DirectRetailOnlineStorePriceGBP != nil {
		cost.DirectRetailOnlineStorePriceGBP = *req.DirectRetailOnlineStorePriceGBP
		// If only price changed (not wholesale cost), we still need to create a new record for history
		if !isNewRecord && req.WholesaleCostGBP == nil {
			// Price-only update: deactivate old record and create new one
			now := time.Now()
			h.db.Model(&models.ProductCost{}).
				Where("product_id = ? AND effective_to IS NULL", product.ID).
				Update("effective_to", now)

			cost.ID = 0 // Reset ID for new record
			cost.EffectiveFrom = &now
			cost.EffectiveTo = nil
			isNewRecord = true
		}
	}

	// Save cost (create or update)
	if isNewRecord || cost.ID == 0 {
		if err := h.db.Create(&cost).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else {
		if err := h.db.Save(&cost).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	// Record price history
	if req.WholesaleCostGBP != nil {
		h.recordPriceHistory(product.ID, nil, cost.WholesaleCostGBP, 0, cost.WholesaleCostGBP)
	}

	c.JSON(http.StatusOK, cost)
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

	now := time.Now()
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
		EffectiveFrom:                   &now,
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

	// Encode resized image to JPEG buffer
	var imgBuf bytes.Buffer
	err = jpeg.Encode(&imgBuf, resizedImg, &jpeg.Options{Quality: 85})
	if err != nil {
		return "", fmt.Errorf("failed to encode image: %w", err)
	}

	// Generate unique filename (always save as JPEG for consistency and smaller file size)
	originalExt := strings.ToLower(filepath.Ext(file.Filename))
	baseName := strings.TrimSuffix(filepath.Base(file.Filename), originalExt)
	filename := fmt.Sprintf("%d_%s.jpg", time.Now().UnixNano(), baseName)

	// Upload based on storage provider
	if h.cfg.StorageProvider == "gcp" && h.cfg.GCPBucketName != "" {
		// Upload to GCP Cloud Storage
		return h.uploadToGCP(filename, imgBuf.Bytes())
	}

	// Default: Save locally
	return h.saveLocally(filename, imgBuf.Bytes())
}

// uploadToGCP uploads image to GCP Cloud Storage bucket
func (h *ProductHandler) uploadToGCP(filename string, imageData []byte) (string, error) {
	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to create GCP storage client: %w", err)
	}
	defer client.Close()

	bucket := client.Bucket(h.cfg.GCPBucketName)
	obj := bucket.Object("user-icons/" + filename) // Store in user-icons/ subfolder

	writer := obj.NewWriter(ctx)
	writer.ContentType = "image/jpeg"
	writer.CacheControl = "public, max-age=31536000" // Cache for 1 year

	if _, err := writer.Write(imageData); err != nil {
		writer.Close()
		return "", fmt.Errorf("failed to write to GCP bucket: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("failed to close GCP bucket writer: %w", err)
	}

	// Make the object publicly readable
	if err := obj.ACL().Set(ctx, storage.AllUsers, storage.RoleReader); err != nil {
		// Log but don't fail - object might already be public
		fmt.Printf("Warning: Failed to set public ACL: %v\n", err)
	}

	// Return public URL
	imageURL := fmt.Sprintf("https://storage.googleapis.com/%s/user-icons/%s", h.cfg.GCPBucketName, filename)
	return imageURL, nil
}

// saveLocally saves image to local filesystem
func (h *ProductHandler) saveLocally(filename string, imageData []byte) (string, error) {
	// Create uploads directory if it doesn't exist
	uploadDir := h.cfg.UploadDir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create upload directory: %w", err)
	}

	filePath := filepath.Join(uploadDir, filename)

	// Save image data to file
	if err := os.WriteFile(filePath, imageData, 0644); err != nil {
		return "", fmt.Errorf("failed to save file: %w", err)
	}

	// Return URL
	baseURL := strings.TrimSuffix(h.cfg.BaseURL, "/")
	imageURL := fmt.Sprintf("%s/uploads/%s", baseURL, filename)
	return imageURL, nil
}
