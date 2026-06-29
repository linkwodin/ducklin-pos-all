package api

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ProductLineHandler struct {
	db             *gorm.DB
	productHandler *ProductHandler
}

func NewProductLineHandler(db *gorm.DB, productHandler *ProductHandler) *ProductLineHandler {
	return &ProductLineHandler{db: db, productHandler: productHandler}
}

type CreateProductLineRequest struct {
	Name        string `json:"name" binding:"required"`
	NameChinese string `json:"name_chinese"`
	Category    string `json:"category"`
	ImageURL    string `json:"image_url"`
}

type UpdateProductLineRequest struct {
	Name        string `json:"name"`
	NameChinese string `json:"name_chinese"`
	Category    string `json:"category"`
	ImageURL    string `json:"image_url"`
	IsActive    *bool  `json:"is_active"`
}

func (h *ProductLineHandler) List(c *gin.Context) {
	var lines []models.ProductLine
	query := h.db.Where("is_active = ?", true)
	if category := strings.TrimSpace(c.Query("category")); category != "" {
		query = query.Where("TRIM(category) = ?", category)
	}
	if err := query.Preload("Variants", "is_active = ?", true).Order("name ASC").Find(&lines).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	for i := range lines {
		attachCurrentCostsToVariants(h.db, &lines[i])
	}
	c.JSON(http.StatusOK, lines)
}

func (h *ProductLineHandler) Get(c *gin.Context) {
	var line models.ProductLine
	if err := h.db.Preload("Variants", "is_active = ?", true).First(&line, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product line not found"})
		return
	}
	attachCurrentCostsToVariants(h.db, &line)
	attachStockTotalsToVariants(h.db, &line)
	c.JSON(http.StatusOK, line)
}

func (h *ProductLineHandler) Create(c *gin.Context) {
	if rejectIfPosUserWrite(c) {
		return
	}
	var req CreateProductLineRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	line := models.ProductLine{
		Name:        strings.TrimSpace(req.Name),
		NameChinese: strings.TrimSpace(req.NameChinese),
		Category:    normalizeCategory(req.Category),
		ImageURL:    strings.TrimSpace(req.ImageURL),
		IsActive:    true,
	}
	if line.Name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
		return
	}
	if err := h.db.Create(&line).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, line)
}

func (h *ProductLineHandler) Update(c *gin.Context) {
	if rejectIfPosUserWrite(c) {
		return
	}
	var line models.ProductLine
	if err := h.db.First(&line, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product line not found"})
		return
	}
	var req UpdateProductLineRequest
	contentType := c.GetHeader("Content-Type")
	if strings.HasPrefix(contentType, "multipart/form-data") {
		req.Name = c.PostForm("name")
		req.NameChinese = c.PostForm("name_chinese")
		req.Category = c.PostForm("category")
	} else if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var imageURL string
	file, err := c.FormFile("image")
	if err == nil && file != nil && h.productHandler != nil {
		uploadedURL, uploadErr := h.productHandler.uploadImage(file, c)
		if uploadErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
			return
		}
		imageURL = uploadedURL
	} else if req.ImageURL != "" {
		imageURL = strings.TrimSpace(req.ImageURL)
	}

	nameChanged := false
	if req.Name != "" {
		trimmed := strings.TrimSpace(req.Name)
		if trimmed != line.Name {
			nameChanged = true
		}
		line.Name = trimmed
	}
	if strings.HasPrefix(contentType, "multipart/form-data") {
		line.NameChinese = strings.TrimSpace(req.NameChinese)
		line.Category = normalizeCategory(req.Category)
	} else {
		if req.NameChinese != "" || c.Request.ContentLength > 0 {
			line.NameChinese = strings.TrimSpace(req.NameChinese)
		}
		if req.Category != "" || c.GetHeader("Content-Type") == "application/json" {
			line.Category = normalizeCategory(req.Category)
		}
	}
	if imageURL != "" {
		line.ImageURL = imageURL
	} else if req.ImageURL != "" {
		line.ImageURL = strings.TrimSpace(req.ImageURL)
	}
	if req.IsActive != nil {
		line.IsActive = *req.IsActive
	}
	if err := h.db.Save(&line).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if nameChanged {
		var variants []models.Product
		h.db.Where("product_line_id = ? AND is_active = ?", line.ID, true).Find(&variants)
		for _, v := range variants {
			newName := variantDisplayName(line.Name, v.VariantLabel, v.UnitType)
			if v.Name != newName {
				_ = h.db.Model(&v).Update("name", newName).Error
			}
		}
	}
	if err := h.db.Preload("Variants", "is_active = ?", true).First(&line, line.ID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	attachCurrentCostsToVariants(h.db, &line)
	attachStockTotalsToVariants(h.db, &line)
	c.JSON(http.StatusOK, line)
}

func (h *ProductLineHandler) Delete(c *gin.Context) {
	if rejectIfPosUserWrite(c) {
		return
	}
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var activeVariants int64
	h.db.Model(&models.Product{}).Where("product_line_id = ? AND is_active = ?", id, true).Count(&activeVariants)
	if activeVariants > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "deactivate all variants before deactivating the product line"})
		return
	}
	if err := h.db.Model(&models.ProductLine{}).Where("id = ?", id).Update("is_active", false).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Product line deactivated"})
}

// resolveProductLine returns an existing line or creates one from product metadata.
func resolveProductLine(db *gorm.DB, req CreateProductRequest, imageURL string) (*models.ProductLine, error) {
	if req.ProductLineID > 0 {
		var line models.ProductLine
		if err := db.First(&line, req.ProductLineID).Error; err != nil {
			return nil, err
		}
		return &line, nil
	}
	line := models.ProductLine{
		Name:        strings.TrimSpace(req.Name),
		NameChinese: strings.TrimSpace(req.NameChinese),
		Category:    normalizeCategory(req.Category),
		ImageURL:    imageURL,
		IsActive:    true,
	}
	if err := db.Create(&line).Error; err != nil {
		return nil, err
	}
	return &line, nil
}

func productLineHasActiveWeightVariant(db *gorm.DB, productLineID uint, excludeProductID uint) (bool, error) {
	if productLineID == 0 {
		return false, nil
	}
	var count int64
	q := db.Model(&models.Product{}).
		Where("product_line_id = ? AND is_active = ? AND unit_type = ?", productLineID, true, "weight")
	if excludeProductID > 0 {
		q = q.Where("id != ?", excludeProductID)
	}
	if err := q.Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

func coalesceString(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return strings.TrimSpace(a)
	}
	return strings.TrimSpace(b)
}

func coalesceCategory(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return normalizeCategory(a)
	}
	return normalizeCategory(b)
}

func variantDisplayName(lineName, variantLabel, unitType string) string {
	lineName = strings.TrimSpace(lineName)
	variantLabel = strings.TrimSpace(variantLabel)
	if isWeightUnitType(unitType) {
		if per := formatPerWeightVariantLabel(variantLabel); per != "" {
			return lineName + " – " + per
		}
		return lineName
	}
	switch strings.ToLower(variantLabel) {
	case "", "standard", "unit", "weight":
		return lineName
	default:
		return lineName + " – " + variantLabel
	}
}

func normalizeWeightVariantGramsLabel(s string) string {
	return strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		if r == '.' {
			return r
		}
		return -1
	}, strings.TrimSpace(s))
}

func weightGramsFromVariantLabel(s string) (float64, bool) {
	s = normalizeWeightVariantGramsLabel(s)
	if s == "" || s == "." {
		return 0, false
	}
	g, err := strconv.ParseFloat(s, 64)
	if err != nil || g <= 0 {
		return 0, false
	}
	return g, true
}

func formatPerWeightVariantLabel(variantLabel string) string {
	g, ok := weightGramsFromVariantLabel(variantLabel)
	if !ok {
		return ""
	}
	if g == float64(int64(g)) {
		return fmt.Sprintf("per %dg", int64(g))
	}
	return fmt.Sprintf("per %sg", strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.3f", g), "0"), "."))
}

func attachCurrentCostsToVariants(db *gorm.DB, line *models.ProductLine) {
	if len(line.Variants) == 0 {
		return
	}
	productIDs := make([]uint, len(line.Variants))
	for i, v := range line.Variants {
		productIDs[i] = v.ID
	}
	now := time.Now()
	var costs []models.ProductCost
	_ = db.Where(
		"product_id IN ? AND (effective_from IS NULL OR effective_from <= ?)",
		productIDs, now,
	).Order("effective_from DESC").Find(&costs).Error
	costByProduct := map[uint]*models.ProductCost{}
	for i := range costs {
		pid := costs[i].ProductID
		if _, exists := costByProduct[pid]; !exists {
			c := costs[i]
			costByProduct[pid] = &c
		}
	}
	for i := range line.Variants {
		line.Variants[i].CurrentCost = costByProduct[line.Variants[i].ID]
	}
}

// attachStockTotalsToVariants sums on-hand stock for each variant across every store location.
func attachStockTotalsToVariants(db *gorm.DB, line *models.ProductLine) {
	if len(line.Variants) == 0 {
		return
	}
	byID := make(map[uint]*models.Product, len(line.Variants))
	ids := make([]uint, len(line.Variants))
	for i := range line.Variants {
		ids[i] = line.Variants[i].ID
		byID[line.Variants[i].ID] = &line.Variants[i]
	}
	var stockRows []models.Stock
	if err := db.Where("product_id IN ?", ids).Find(&stockRows).Error; err != nil {
		return
	}
	hasRows := map[uint]bool{}
	qtyTotals := map[uint]float64{}
	weightTotals := map[uint]float64{}
	for i := range stockRows {
		s := &stockRows[i]
		p := byID[s.ProductID]
		if p == nil {
			continue
		}
		hasRows[s.ProductID] = true
		if productSellByWeight(p) {
			weightTotals[s.ProductID] += effectiveWeightQuantityG(s, p)
		} else {
			qtyTotals[s.ProductID] += effectivePrepackedQuantity(s, p)
		}
	}
	for i := range line.Variants {
		pid := line.Variants[i].ID
		if !hasRows[pid] {
			continue
		}
		if productSellByWeight(&line.Variants[i]) {
			total := weightTotals[pid]
			line.Variants[i].TotalStockWeightG = &total
		} else {
			total := qtyTotals[pid]
			line.Variants[i].TotalStockQuantity = &total
		}
	}
}
