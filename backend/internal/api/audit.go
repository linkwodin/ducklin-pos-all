package api

import (
	"net/http"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AuditHandler struct {
	db *gorm.DB
}

func NewAuditHandler(db *gorm.DB) *AuditHandler {
	return &AuditHandler{db: db}
}

// GetStockAuditLogs returns audit logs for a specific stock item
func (h *AuditHandler) GetStockAuditLogs(c *gin.Context) {
	productID := c.Query("product_id")
	storeID := c.Query("store_id")
	entityID := c.Query("entity_id")

	if productID == "" && storeID == "" && entityID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "product_id, store_id, or entity_id is required"})
		return
	}

	var logs []models.AuditLog
	query := h.db.Where("action = ? AND entity_type = ?", "stock_update", "stock").
		Preload("User").
		Order("created_at DESC")

	if entityID != "" {
		query = query.Where("entity_id = ?", entityID)
	} else if productID != "" && storeID != "" {
		// Find stock ID first
		var stock models.Stock
		if err := h.db.Where("product_id = ? AND store_id = ?", productID, storeID).
			First(&stock).Error; err == nil {
			query = query.Where("entity_id = ?", stock.ID)
		} else {
			// No stock found, return empty
			c.JSON(http.StatusOK, []models.AuditLog{})
			return
		}
	}

	if err := query.Limit(100).Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, logs)
}

// GetOrderAuditLogs returns audit logs for a specific order
func (h *AuditHandler) GetOrderAuditLogs(c *gin.Context) {
	orderID := c.Query("order_id")
	entityID := c.Query("entity_id")

	if orderID == "" && entityID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "order_id or entity_id is required"})
		return
	}

	var logs []models.AuditLog
	query := h.db.Where("entity_type = ?", "order").
		Preload("User").
		Order("created_at DESC")

	if entityID != "" {
		query = query.Where("entity_id = ?", entityID)
	} else if orderID != "" {
		query = query.Where("entity_id = ?", orderID)
	}

	if err := query.Limit(100).Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, logs)
}
