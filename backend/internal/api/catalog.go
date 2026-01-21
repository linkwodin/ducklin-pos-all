package api

import (
	"fmt"
	"net/http"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/jung-kurt/gofpdf"
	"gorm.io/gorm"
)

type CatalogHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewCatalogHandler(db *gorm.DB, cfg *config.Config) *CatalogHandler {
	return &CatalogHandler{db: db, cfg: cfg}
}

func (h *CatalogHandler) GenerateCatalog(c *gin.Context) {
	sectorID, err := parseUint(c.Param("sector_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sector ID"})
		return
	}

	var sector models.Sector
	if err := h.db.First(&sector, sectorID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Sector not found"})
		return
	}

	// Get all active products with current costs and discounts
	var products []models.Product
	if err := h.db.Where("is_active = ?", true).Find(&products).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	var catalogItems []CatalogItem

	for _, product := range products {
		// Get current cost
		var cost models.ProductCost
		if err := h.db.Where("product_id = ? AND (effective_to IS NULL OR effective_to > ?)", product.ID, now).
			Order("effective_from DESC").First(&cost).Error; err != nil {
			continue // Skip products without cost
		}

		// Skip products without Direct Retail Online Store price
		if cost.DirectRetailOnlineStorePriceGBP <= 0 {
			continue
		}

		// Get product-specific discount for this sector
		var productDiscountPercent float64
		var discount models.ProductSectorDiscount
		if err := h.db.Where("product_id = ? AND sector_id = ? AND (effective_to IS NULL OR effective_to > ?)",
			product.ID, sectorID, now).Order("effective_from DESC").First(&discount).Error; err == nil {
			productDiscountPercent = discount.DiscountPercent
		}

		// Calculate final price: Direct Retail Price * (1 - sector discount rate / 100) * (1 - product discount / 100)
		// First apply sector discount rate, then product-specific discount
		priceAfterSectorDiscount := cost.DirectRetailOnlineStorePriceGBP * (1 - sector.DiscountRate/100.0)
		finalPrice := priceAfterSectorDiscount * (1 - productDiscountPercent/100.0)
		totalDiscountPercent := sector.DiscountRate + productDiscountPercent

		catalogItems = append(catalogItems, CatalogItem{
			Product:                      product,
			DirectRetailOnlineStorePrice: cost.DirectRetailOnlineStorePriceGBP,
			SectorDiscountRate:           sector.DiscountRate,
			ProductDiscountPercent:       productDiscountPercent,
			TotalDiscountPercent:         totalDiscountPercent,
			FinalPrice:                   finalPrice,
		})
	}

	// Generate PDF
	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.AddPage()
	pdf.SetFont("Arial", "B", 16)
	pdf.Cell(40, 10, fmt.Sprintf("Product Catalog - %s", sector.Name))
	pdf.Ln(10)

	// Get current quarter
	quarter := getCurrentQuarter()
	pdf.SetFont("Arial", "", 12)
	pdf.Cell(40, 10, fmt.Sprintf("Quarter: %s %d", quarter, time.Now().Year()))
	pdf.Ln(15)

	// Table header
	pdf.SetFont("Arial", "B", 10)
	pdf.Cell(40, 8, "Product")
	pdf.Cell(30, 8, "SKU")
	pdf.Cell(30, 8, "Barcode")
	pdf.Cell(30, 8, "Retail Price")
	pdf.Cell(25, 8, "Sector")
	pdf.Cell(25, 8, "Product")
	pdf.Cell(30, 8, "Final Price")
	pdf.Ln(8)

	// Table rows
	pdf.SetFont("Arial", "", 9)
	for _, item := range catalogItems {
		pdf.Cell(40, 6, truncateString(item.Product.Name, 30))
		pdf.Cell(30, 6, item.Product.SKU)
		pdf.Cell(30, 6, item.Product.Barcode)
		pdf.Cell(30, 6, fmt.Sprintf("£%.2f", item.DirectRetailOnlineStorePrice))
		if item.SectorDiscountRate > 0 {
			pdf.Cell(25, 6, fmt.Sprintf("%.1f%%", item.SectorDiscountRate))
		} else {
			pdf.Cell(25, 6, "-")
		}
		if item.ProductDiscountPercent > 0 {
			pdf.Cell(25, 6, fmt.Sprintf("%.1f%%", item.ProductDiscountPercent))
		} else {
			pdf.Cell(25, 6, "-")
		}
		pdf.Cell(30, 6, fmt.Sprintf("£%.2f", item.FinalPrice))
		pdf.Ln(6)
	}

	// Return PDF as base64 or save to storage
	// For now, return JSON with catalog data
	c.JSON(http.StatusOK, gin.H{
		"sector":       sector,
		"quarter":      fmt.Sprintf("%s %d", quarter, time.Now().Year()),
		"items":        catalogItems,
		"generated_at": time.Now(),
	})
}

func (h *CatalogHandler) DownloadCatalog(c *gin.Context) {
	// Similar to GenerateCatalog but returns PDF file
	// Implementation would generate PDF and return as file download
	c.JSON(http.StatusNotImplemented, gin.H{"error": "PDF download not yet implemented"})
}

type CatalogItem struct {
	Product                      models.Product `json:"product"`
	DirectRetailOnlineStorePrice float64        `json:"direct_retail_online_store_price"`
	SectorDiscountRate           float64        `json:"sector_discount_rate"`
	ProductDiscountPercent       float64        `json:"product_discount_percent"`
	TotalDiscountPercent         float64        `json:"total_discount_percent"`
	FinalPrice                   float64        `json:"final_price"`
}

func getCurrentQuarter() string {
	month := time.Now().Month()
	switch {
	case month >= 1 && month <= 3:
		return "Q1"
	case month >= 4 && month <= 6:
		return "Q2"
	case month >= 7 && month <= 9:
		return "Q3"
	default:
		return "Q4"
	}
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func parseUint(s string) (uint, error) {
	var result uint64
	_, err := fmt.Sscanf(s, "%d", &result)
	return uint(result), err
}
