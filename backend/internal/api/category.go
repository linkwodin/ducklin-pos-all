package api

import (
	"net/http"
	"strings"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"golang.org/x/text/unicode/norm"
	"gorm.io/gorm"
)

type CategoryHandler struct {
	db *gorm.DB
}

func NewCategoryHandler(db *gorm.DB) *CategoryHandler {
	return &CategoryHandler{db: db}
}

// normalizeCategory trims and applies Unicode NFC so duplicate-looking names merge.
func normalizeCategory(s string) string {
	return norm.NFC.String(strings.TrimSpace(s))
}

// ListCategories returns distinct category names from products, normalized (trim + NFC)
// so that "罐頭鮑魚" and " 罐頭鮑魚 " or different Unicode forms appear as one.
func (h *CategoryHandler) ListCategories(c *gin.Context) {
	var raw []string
	if err := h.db.Model(&models.Product{}).
		Where("category IS NOT NULL AND category != '' AND is_active = ?", true).
		Distinct("category").
		Pluck("category", &raw).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	seen := make(map[string]bool)
	var categories []string
	for _, s := range raw {
		n := normalizeCategory(s)
		if n == "" || seen[n] {
			continue
		}
		seen[n] = true
		categories = append(categories, n)
	}

	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

// CreateCategory creates a category by ensuring at least one product has this category
// In practice, categories are created when products are created/updated
func (h *CategoryHandler) CreateCategory(c *gin.Context) {
	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if category already exists
	var count int64
	h.db.Model(&models.Product{}).
		Where("category = ?", req.Name).
		Count(&count)

	if count > 0 {
		c.JSON(http.StatusOK, gin.H{"message": "Category already exists", "category": req.Name})
		return
	}

	// Category will be created when a product uses it
	// For now, just return success
	c.JSON(http.StatusOK, gin.H{"message": "Category will be created when used in a product", "category": req.Name})
}

// DeleteCategory removes a category by updating all products with this category
func (h *CategoryHandler) DeleteCategory(c *gin.Context) {
	categoryName := c.Param("name")
	if categoryName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Category name is required"})
		return
	}

	// Update all products with this category to have empty category
	result := h.db.Model(&models.Product{}).
		Where("category = ?", categoryName).
		Update("category", "")

	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": result.Error.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":          "Category deleted successfully",
		"products_updated": result.RowsAffected,
	})
}

// NormalizeCategories normalizes all product categories (trim + Unicode NFC) so
// duplicate-looking names (e.g. "罐頭鮑魚" vs " 罐頭鮑魚 " or different Unicode) become one.
func (h *CategoryHandler) NormalizeCategories(c *gin.Context) {
	var products []models.Product
	if err := h.db.Where("category IS NOT NULL AND category != ''").Find(&products).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	updated := 0
	for _, p := range products {
		normalized := normalizeCategory(p.Category)
		if normalized != p.Category {
			if err := h.db.Model(&p).Update("category", normalized).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			updated++
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"message":          "Categories normalized",
		"products_updated": updated,
	})
}

// RenameCategory renames a category across all products
func (h *CategoryHandler) RenameCategory(c *gin.Context) {
	oldName := c.Param("name")
	if oldName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Category name is required"})
		return
	}

	var req struct {
		NewName string `json:"new_name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Update all products with old category name to new category name
	result := h.db.Model(&models.Product{}).
		Where("category = ?", oldName).
		Update("category", req.NewName)

	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": result.Error.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":          "Category renamed successfully",
		"old_name":         oldName,
		"new_name":         req.NewName,
		"products_updated": result.RowsAffected,
	})
}
