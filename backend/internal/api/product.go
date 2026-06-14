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

func fillProductRequestWeightFields(c *gin.Context, req *CreateProductRequest) {
	fillProductRequestSaleFields(c, req)
}

type ProductHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewProductHandler(db *gorm.DB, cfg *config.Config) *ProductHandler {
	return &ProductHandler{db: db, cfg: cfg}
}

// truncateToDate strips the time portion, keeping only the date at midnight UTC.
func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func today() time.Time {
	return truncateToDate(time.Now())
}

type CreateProductRequest struct {
	ProductLineID uint   `json:"product_line_id"`
	VariantLabel  string `json:"variant_label"`
	UnitsPerPack  float64 `json:"units_per_pack"`
	Name        string `json:"name"`
	NameChinese string `json:"name_chinese"`
	Barcode     string `json:"barcode"`
	SKU         string `json:"sku"`
	Category    string `json:"category"`
	ImageURL    string `json:"image_url"`
	UnitType    string `json:"unit_type"`
	SellByQty   bool   `json:"sell_by_qty"`
	SellByWeight bool  `json:"sell_by_weight"`
	WeightBarcode string `json:"weight_barcode"`
	// Optional: 1-8 digit prefix for weight-product receipt barcodes (weight unit only).
	WeightBarcodePrefix string `json:"weight_barcode_prefix"`
	// Optional: grams the retail price applies to (weight products only; 0 = 1 kg default).
	PriceWeightG float64 `json:"price_weight_g"`
	// CanSellByWeight enables weight sales and dual inventory (prepacked + loose weight).
	CanSellByWeight bool `json:"can_sell_by_weight"`
	// PrepackWeightG: grams per prepacked unit for pack/unpack (required when CanSellByWeight).
	PrepackWeightG float64 `json:"prepack_weight_g"`
	// Optional: units per box for wholesale orders (0 or missing = unknown)
	WholesaleUnitsPerBox float64 `json:"wholesale_units_per_box"`
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
	DirectRetailOnlineStorePriceGBP float64 `json:"direct_retail_online_store_price_gbp"`
	EffectiveFrom                   string  `json:"effective_from"`
	EffectiveTo                     string  `json:"effective_to"`
}

func (h *ProductHandler) ListProducts(c *gin.Context) {
	var products []models.Product
	query := h.db.Where("is_active = ?", true).Preload("ProductLine")

	// Filter by category if provided (match trimmed so normalized names work)
	if category := strings.TrimSpace(c.Query("category")); category != "" {
		query = query.Where("TRIM(category) = ?", category)
	}

	if err := query.Find(&products).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Determine which cost record to load per product.
	// If effective_from & effective_to are provided, first try exact range match,
	// then fall back to cost effective on effective_from date, then current.
	// This endpoint is frequently used by the wholesale order creation UI, so avoid
	// N+1 queries by batching cost/discount lookups across all products.
	var qEfFrom, qEfTo *time.Time
	if ef := c.Query("effective_from"); ef != "" {
		if t, err := time.Parse("2006-01-02", ef); err == nil {
			qEfFrom = &t
		}
	}
	if et := c.Query("effective_to"); et != "" {
		if t, err := time.Parse("2006-01-02", et); err == nil {
			qEfTo = &t
		}
	}

	now := time.Now()
	productIDs := make([]uint, 0, len(products))
	for _, p := range products {
		productIDs = append(productIDs, p.ID)
	}
	if len(productIDs) == 0 {
		c.JSON(http.StatusOK, products)
		return
	}

	// ---- Costs (batched) ----
	// Rule in date-range mode (PO date):
	// - pick candidate cost for the PO-date (exact effective range first, then effective-on-date)
	// - if candidate.WholesaleCostGBP <= 0 (unset), use the "current" latest cost up to now
	// - if candidate is missing, use the "current" latest cost up to now
	//
	// Keep it batched: query candidate costs in bulk, query current costs in bulk, then decide per product in memory.
	costByProduct := map[uint]*models.ProductCost{}
	if qEfFrom != nil && qEfTo != nil {
		// Candidate 1: exact effective range.
		var exactCosts []models.ProductCost
		_ = h.db.Where(
			"product_id IN ? AND effective_from = ? AND effective_to = ?",
			productIDs, *qEfFrom, *qEfTo,
		).Find(&exactCosts).Error
		for i := range exactCosts {
			pid := exactCosts[i].ProductID
			if _, exists := costByProduct[pid]; !exists {
				c := exactCosts[i]
				costByProduct[pid] = &c
			}
		}

		// Candidate 2: effective-on-date for products where exact was missing.
		missingExactIDs := make([]uint, 0, len(productIDs))
		for _, pid := range productIDs {
			if costByProduct[pid] == nil {
				missingExactIDs = append(missingExactIDs, pid)
			}
		}
		if len(missingExactIDs) > 0 {
			var fallbackCosts []models.ProductCost
			_ = h.db.Where(
				"product_id IN ? AND (effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
				missingExactIDs, *qEfFrom, *qEfFrom,
			).Order("effective_from DESC").Find(&fallbackCosts).Error
			for i := range fallbackCosts {
				pid := fallbackCosts[i].ProductID
				if costByProduct[pid] != nil {
					continue
				}
				c := fallbackCosts[i]
				costByProduct[pid] = &c
			}
		}

		// Current: latest configured cost up to now (regardless of effective_to).
		currentByProduct := map[uint]models.ProductCost{}
		var currentCosts []models.ProductCost
		_ = h.db.Where(
			"product_id IN ? AND (effective_from IS NULL OR effective_from <= ?)",
			productIDs, now,
		).Order("effective_from DESC").Find(&currentCosts).Error
		for i := range currentCosts {
			pid := currentCosts[i].ProductID
			if _, exists := currentByProduct[pid]; !exists {
				currentByProduct[pid] = currentCosts[i]
			}
		}

		// Final decision per product.
		finalByProduct := map[uint]*models.ProductCost{}
		for _, pid := range productIDs {
			cand := costByProduct[pid]
			curr, ok := currentByProduct[pid]
			// Previous-season "price" should be the retail price field.
			// If it's unset (stored as 0), we fall back to current retail.
			if cand != nil && cand.DirectRetailOnlineStorePriceGBP > 0 {
				finalByProduct[pid] = cand
				continue
			}
			if ok {
				c := curr
				finalByProduct[pid] = &c
				continue
			}
			// If neither candidate nor current exists, keep whatever we have.
			finalByProduct[pid] = cand
		}

		for i := range products {
			products[i].CurrentCost = finalByProduct[products[i].ID]
		}
	} else {
		// Current mode: just return latest configured cost up to now.
		currentCosts := []models.ProductCost{}
		_ = h.db.Where(
			"product_id IN ? AND (effective_from IS NULL OR effective_from <= ?)",
			productIDs, now,
		).Order("effective_from DESC").Find(&currentCosts).Error
		seen := map[uint]bool{}
		for i := range currentCosts {
			pid := currentCosts[i].ProductID
			if seen[pid] {
				continue
			}
			seen[pid] = true
			c := currentCosts[i]
			costByProduct[pid] = &c
		}
		for i := range products {
			products[i].CurrentCost = costByProduct[products[i].ID]
		}
	}

	// ---- Discounts (batched) ----
	discountsByProduct := map[uint][]models.ProductSectorDiscount{}
	if qEfFrom != nil && qEfTo != nil {
		// Exact range
		var exactDiscounts []models.ProductSectorDiscount
		_ = h.db.Where("product_id IN ? AND effective_from = ? AND effective_to = ?",
			productIDs, *qEfFrom, *qEfTo).Order("id DESC").Find(&exactDiscounts).Error
		hasExact := map[uint]bool{}
		for i := range exactDiscounts {
			pid := exactDiscounts[i].ProductID
			hasExact[pid] = true
			discountsByProduct[pid] = append(discountsByProduct[pid], exactDiscounts[i])
		}

		// Fallback products that have no exact discounts.
		var missingIDs []uint
		for _, id := range productIDs {
			if !hasExact[id] {
				missingIDs = append(missingIDs, id)
			}
		}
		if len(missingIDs) > 0 {
			var fallbackDiscounts []models.ProductSectorDiscount
			_ = h.db.Where("product_id IN ? AND (effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
				missingIDs, *qEfFrom, *qEfFrom).Order("effective_from DESC").Find(&fallbackDiscounts).Error
			for i := range fallbackDiscounts {
				pid := fallbackDiscounts[i].ProductID
				discountsByProduct[pid] = append(discountsByProduct[pid], fallbackDiscounts[i])
			}
		}
	} else {
		// Current mode
		var currentDiscounts []models.ProductSectorDiscount
		_ = h.db.Where("product_id IN ? AND (effective_to IS NULL OR effective_to > ?)",
			productIDs, now).Order("effective_from DESC").Find(&currentDiscounts).Error
		for i := range currentDiscounts {
			pid := currentDiscounts[i].ProductID
			discountsByProduct[pid] = append(discountsByProduct[pid], currentDiscounts[i])
		}
	}

	for i := range products {
		// When multiple records exist per sector, keep the first one (deterministic due to ORDER BY above).
		seen := map[uint]bool{}
		filtered := make([]models.ProductSectorDiscount, 0, len(discountsByProduct[products[i].ID]))
		for _, d := range discountsByProduct[products[i].ID] {
			if !seen[d.SectorID] {
				seen[d.SectorID] = true
				filtered = append(filtered, d)
			}
		}
		products[i].Discounts = filtered
	}

	c.JSON(http.StatusOK, products)
}

func (h *ProductHandler) GetProduct(c *gin.Context) {
	var product models.Product
	if err := h.db.Preload("ProductLine").First(&product, c.Param("id")).Error; err != nil {
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

func fillProductLineRequestFields(c *gin.Context, req *CreateProductRequest) {
	if pl := strings.TrimSpace(c.PostForm("product_line_id")); pl != "" {
		if v, err := strconv.ParseUint(pl, 10, 64); err == nil {
			req.ProductLineID = uint(v)
		}
	}
	req.VariantLabel = strings.TrimSpace(c.PostForm("variant_label"))
	if up := strings.TrimSpace(c.PostForm("units_per_pack")); up != "" {
		if v, err := strconv.ParseFloat(up, 64); err == nil {
			req.UnitsPerPack = v
		}
	}
	if wub := strings.TrimSpace(c.PostForm("wholesale_units_per_box")); wub != "" {
		if v, err := strconv.ParseFloat(wub, 64); err == nil {
			req.WholesaleUnitsPerBox = v
		}
	}
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
		if pw := strings.TrimSpace(c.PostForm("price_weight_g")); pw != "" {
			v, err := strconv.ParseFloat(pw, 64)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "price_weight_g must be a number"})
				return
			}
			req.PriceWeightG = v
		}

		if (req.Name == "" && req.ProductLineID == 0) || req.UnitType == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name (or product_line_id) and unit_type are required"})
			return
		}
		fillProductRequestWeightFields(c, &req)
		fillProductLineRequestFields(c, &req)
	} else {
		// Handle JSON (backward compatibility)
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	if req.ProductLineID == 0 && strings.TrimSpace(req.Name) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required when creating a new product line"})
		return
	}
	if strings.TrimSpace(req.UnitType) == "" {
		req.UnitType = "quantity"
	}
	if err := validateProductSaleModes(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	prefix, prefixErr := deriveWeightBarcodePrefix(req, req.UnitType)
	if prefixErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": prefixErr.Error()})
		return
	}
	priceWeightG, pwErr := normalizePriceWeightG(isWeightUnitType(req.UnitType), req.PriceWeightG)
	if pwErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": pwErr.Error()})
		return
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

	line, lineErr := resolveProductLine(h.db, req, imageURL)
	if lineErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid product_line_id"})
		return
	}
	if imageURL != "" && line.ImageURL == "" {
		line.ImageURL = imageURL
		_ = h.db.Model(line).Update("image_url", imageURL).Error
	}

	if isWeightUnitType(req.UnitType) {
		hasWeight, err := productLineHasActiveWeightVariant(h.db, line.ID, 0)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if hasWeight {
			c.JSON(http.StatusBadRequest, gin.H{"error": "this product line already has a weight variant"})
			return
		}
	}

	variantLabel := strings.TrimSpace(req.VariantLabel)
	unitsPerPack := req.UnitsPerPack
	wholesaleUnitsPerBox := req.WholesaleUnitsPerBox
	if isWeightUnitType(req.UnitType) {
		variantLabel = normalizeWeightVariantGramsLabel(variantLabel)
		unitsPerPack = 0
		if g, ok := weightGramsFromVariantLabel(variantLabel); ok {
			priceWeightG = g
		}
	}

	displayName := variantDisplayName(line.Name, variantLabel, req.UnitType)
	if strings.TrimSpace(req.Name) != "" && req.ProductLineID == 0 {
		displayName = strings.TrimSpace(req.Name)
		line.Name = displayName
		_ = h.db.Model(line).Update("name", displayName).Error
	}

	product := models.Product{
		ProductLineID:        line.ID,
		Name:                 displayName,
		NameChinese:          coalesceString(req.NameChinese, line.NameChinese),
		SKU:                  req.SKU,
		Category:             coalesceCategory(req.Category, line.Category),
		ImageURL:             coalesceString(imageURL, line.ImageURL),
		VariantLabel:         variantLabel,
		UnitsPerPack:         unitsPerPack,
		UnitType:             req.UnitType,
		WeightBarcodePrefix:  prefix,
		PriceWeightG:         priceWeightG,
		WholesaleUnitsPerBox: wholesaleUnitsPerBox,
		IsActive:             true,
	}
	applyProductSaleFields(&product, req)

	if err := saveProduct(h.db, &product); err != nil {
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
		if pw := strings.TrimSpace(c.PostForm("price_weight_g")); pw != "" {
			v, err := strconv.ParseFloat(pw, 64)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "price_weight_g must be a number"})
				return
			}
			req.PriceWeightG = v
		}

		if (req.Name == "" && req.ProductLineID == 0) || req.UnitType == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name (or product_line_id) and unit_type are required"})
			return
		}
		fillProductRequestWeightFields(c, &req)
		fillProductLineRequestFields(c, &req)
	} else {
		// Handle JSON (backward compatibility)
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	if strings.TrimSpace(req.UnitType) == "" {
		req.UnitType = "quantity"
	}
	if err := validateProductSaleModes(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	prefix, prefixErr := deriveWeightBarcodePrefix(req, req.UnitType)
	if prefixErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": prefixErr.Error()})
		return
	}
	priceWeightG, pwErr := normalizePriceWeightG(isWeightUnitType(req.UnitType), req.PriceWeightG)
	if pwErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": pwErr.Error()})
		return
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

	if req.ProductLineID > 0 {
		product.ProductLineID = req.ProductLineID
	}
	lineID := product.ProductLineID
	if isWeightUnitType(req.UnitType) {
		hasWeight, err := productLineHasActiveWeightVariant(h.db, lineID, product.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if hasWeight {
			c.JSON(http.StatusBadRequest, gin.H{"error": "this product line already has a weight variant"})
			return
		}
	}
	if isWeightUnitType(req.UnitType) {
		product.VariantLabel = normalizeWeightVariantGramsLabel(req.VariantLabel)
		product.UnitsPerPack = 0
		if g, ok := weightGramsFromVariantLabel(product.VariantLabel); ok {
			priceWeightG = g
		}
	} else {
		product.VariantLabel = strings.TrimSpace(req.VariantLabel)
		product.UnitsPerPack = req.UnitsPerPack
	}
	if product.ProductLineID > 0 {
		var line models.ProductLine
		if err := h.db.First(&line, product.ProductLineID).Error; err == nil {
			product.Name = variantDisplayName(line.Name, product.VariantLabel, req.UnitType)
		}
	} else if strings.TrimSpace(req.Name) != "" {
		product.Name = strings.TrimSpace(req.Name)
	}
	product.NameChinese = req.NameChinese
	product.SKU = req.SKU
	product.Category = normalizeCategory(req.Category)
	product.ImageURL = imageURL
	product.UnitType = req.UnitType
	product.WeightBarcodePrefix = prefix
	product.PriceWeightG = priceWeightG
	product.WholesaleUnitsPerBox = req.WholesaleUnitsPerBox
	applyProductSaleFields(&product, req)

	if err := saveProduct(h.db, &product); err != nil {
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
				Category:    normalizeCategory(category),
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
				product.Category = normalizeCategory(category)
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

	// Parse optional date range
	var efFrom, efTo *time.Time
	if req.EffectiveFrom != "" {
		t, err := time.Parse("2006-01-02", req.EffectiveFrom)
		if err == nil {
			efFrom = &t
		}
	}
	if req.EffectiveTo != "" {
		t, err := time.Parse("2006-01-02", req.EffectiveTo)
		if err == nil {
			efTo = &t
		}
	}

	if efFrom != nil && efTo != nil {
		// Date-range mode: upsert by matching product + date range
		var existing models.ProductCost
		err := h.db.Where("product_id = ? AND effective_from = ? AND effective_to = ?",
			product.ID, *efFrom, *efTo).First(&existing).Error
		if err == nil {
			// Override existing record
			cost.ID = existing.ID
			cost.CreatedAt = existing.CreatedAt
		}
		cost.EffectiveFrom = efFrom
		cost.EffectiveTo = efTo
		if cost.ID != 0 {
			if err := h.db.Save(&cost).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		} else {
			if err := h.db.Create(&cost).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
	} else {
		// Original behaviour: deactivate previous, create new
		tod := today()
		h.db.Model(&models.ProductCost{}).
			Where("product_id = ? AND effective_to IS NULL", product.ID).
			Update("effective_to", tod)
		cost.EffectiveFrom = &tod
		if err := h.db.Create(&cost).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

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
		EffectiveFrom                   *string  `json:"effective_from"`
		EffectiveTo                     *string  `json:"effective_to"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse optional date range
	var efFrom, efTo *time.Time
	if req.EffectiveFrom != nil && *req.EffectiveFrom != "" {
		t, err := time.Parse("2006-01-02", *req.EffectiveFrom)
		if err == nil {
			efFrom = &t
		}
	}
	if req.EffectiveTo != nil && *req.EffectiveTo != "" {
		t, err := time.Parse("2006-01-02", *req.EffectiveTo)
		if err == nil {
			efTo = &t
		}
	}

	hasDateRange := efFrom != nil && efTo != nil

	var cost models.ProductCost
	isNewRecord := false

	if hasDateRange {
		// Look for existing cost with matching date range to override
		err := h.db.Where("product_id = ? AND effective_from = ? AND effective_to = ?",
			product.ID, *efFrom, *efTo).First(&cost).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// Also check for open-ended record starting at the same date
			err2 := h.db.Where("product_id = ? AND effective_from = ? AND effective_to IS NULL",
				product.ID, *efFrom).First(&cost).Error
			if errors.Is(err2, gorm.ErrRecordNotFound) {
				cost = models.ProductCost{
					ProductID:       product.ID,
					ExchangeRate:    1,
					UnitWeightG:     1,
					WeightG:         1,
					EffectiveFrom:   efFrom,
					EffectiveTo:     efTo,
				}
				isNewRecord = true
			}
		} else if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		// Update the date range on existing record
		cost.EffectiveFrom = efFrom
		cost.EffectiveTo = efTo
	} else {
		// Original behaviour: get current active cost
		err := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, today()).
			Order("effective_from DESC").First(&cost).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			tod := today()
			cost = models.ProductCost{
				ProductID:       product.ID,
				ExchangeRate:    1,
				UnitWeightG:     1,
				WeightG:         1,
				EffectiveFrom:   &tod,
			}
			isNewRecord = true
		} else if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	if req.WholesaleCostGBP != nil {
		if isNewRecord {
			cost.WholesaleCostGBP = *req.WholesaleCostGBP
		} else if hasDateRange {
			cost.WholesaleCostGBP = *req.WholesaleCostGBP
		} else if cost.WholesaleCostGBP != *req.WholesaleCostGBP {
			tod := today()
			h.db.Model(&models.ProductCost{}).
				Where("product_id = ? AND effective_to IS NULL", product.ID).
				Update("effective_to", tod)
			cost.ID = 0
			cost.WholesaleCostGBP = *req.WholesaleCostGBP
			cost.EffectiveFrom = &tod
			cost.EffectiveTo = nil
			isNewRecord = true
		}
	}

	if req.DirectRetailOnlineStorePriceGBP != nil {
		cost.DirectRetailOnlineStorePriceGBP = *req.DirectRetailOnlineStorePriceGBP
		if !isNewRecord && !hasDateRange && req.WholesaleCostGBP == nil {
			tod := today()
			h.db.Model(&models.ProductCost{}).
				Where("product_id = ? AND effective_to IS NULL", product.ID).
				Update("effective_to", tod)
			cost.ID = 0
			cost.EffectiveFrom = &tod
			cost.EffectiveTo = nil
			isNewRecord = true
		}
	}

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
		DiscountPercent float64 `json:"discount_percent"`
		SectorPriceGBP float64 `json:"sector_price_gbp"`
		EffectiveFrom   string  `json:"effective_from"`
		EffectiveTo     string  `json:"effective_to"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var efFrom, efTo *time.Time
	if req.EffectiveFrom != "" {
		t, err := time.Parse("2006-01-02", req.EffectiveFrom)
		if err == nil {
			efFrom = &t
		}
	}
	if req.EffectiveTo != "" {
		t, err := time.Parse("2006-01-02", req.EffectiveTo)
		if err == nil {
			efTo = &t
		}
	}

	var discount models.ProductSectorDiscount

	if efFrom != nil && efTo != nil {
		// Date-range mode: upsert by matching product + sector + date range
		err := h.db.Where("product_id = ? AND sector_id = ? AND effective_from = ? AND effective_to = ?",
			product.ID, sector.ID, *efFrom, *efTo).First(&discount).Error
		if err == nil {
			discount.DiscountPercent = req.DiscountPercent
			discount.SectorPriceGBP = req.SectorPriceGBP
			if err := h.db.Save(&discount).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		} else {
			discount = models.ProductSectorDiscount{
				ProductID:       product.ID,
				SectorID:        sector.ID,
				DiscountPercent: req.DiscountPercent,
				SectorPriceGBP:  req.SectorPriceGBP,
				EffectiveFrom:   *efFrom,
				EffectiveTo:     efTo,
			}
			if err := h.db.Create(&discount).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
	} else {
		// Current mode: deactivate old, create new
		tod := today()
		h.db.Model(&models.ProductSectorDiscount{}).
			Where("product_id = ? AND sector_id = ? AND effective_to IS NULL", product.ID, sector.ID).
			Update("effective_to", tod)

		discount = models.ProductSectorDiscount{
			ProductID:       product.ID,
			SectorID:        sector.ID,
			DiscountPercent: req.DiscountPercent,
			SectorPriceGBP:  req.SectorPriceGBP,
			EffectiveFrom:   tod,
		}
		if err := h.db.Create(&discount).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	var cost models.ProductCost
	h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, time.Now()).
		Order("effective_from DESC").First(&cost)

	basePrice := cost.DirectRetailOnlineStorePriceGBP
	if basePrice <= 0 {
		basePrice = cost.WholesaleCostGBP
	}

	var finalPrice float64
	if req.SectorPriceGBP > 0 {
		finalPrice = req.SectorPriceGBP
	} else {
		var sectorDiscountRate float64
		if sector.DiscountRate > 0 {
			sectorDiscountRate = sector.DiscountRate
		}
		priceAfterSectorDiscount := basePrice * (1 - sectorDiscountRate/100.0)
		finalPrice = priceAfterSectorDiscount * (1 - req.DiscountPercent/100.0)
	}
	totalDiscountPercent := req.DiscountPercent
	if sector.DiscountRate > 0 {
		totalDiscountPercent += sector.DiscountRate
	}

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
