package api

import (
	"net/http"
	"strings"

	"pos-system/backend/internal/models"
	"pos-system/backend/internal/utils"
	"pos-system/backend/pkg/dlclicense"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// WholesaleOrderEnabledMiddleware blocks wholesale API when the module is disabled in company settings.
func WholesaleOrderEnabledMiddleware(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var s models.CompanySettings
		err := db.Select("wholesale_order_enabled").First(&s, companySettingsID).Error
		if err != nil || !s.WholesaleOrderEnabled {
			c.JSON(http.StatusForbidden, gin.H{"error": "Wholesale orders are disabled"})
			c.Abort()
			return
		}
		c.Next()
	}
}

type toggleWholesaleOrderBody struct {
	Enabled           bool   `json:"enabled"`
	Password          string `json:"password"`
	ProductSerialCode string `json:"product_serial_code"`
}

// ToggleWholesaleOrder enables or disables wholesale orders with password or product serial verification.
func (h *SettingsHandler) ToggleWholesaleOrder(c *gin.Context) {
	var body toggleWholesaleOrderBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	userIDVal, ok := c.Get("user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, ok := userIDVal.(uint)
	if !ok || userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if body.Enabled {
		if !s.WholesaleSerialActivated {
			if strings.TrimSpace(body.ProductSerialCode) == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Product serial code is required"})
				return
			}
			installationID, idErr := h.installationIDForDLC()
			if idErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": idErr.Error()})
				return
			}
			if !dlclicense.ValidateWholesaleCode(installationID, body.ProductSerialCode) {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid product serial code for this system"})
				return
			}
			s.WholesaleSerialActivated = true
		} else {
			if strings.TrimSpace(body.Password) == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Password is required"})
				return
			}
			if !utils.VerifyPassword(body.Password, user.PasswordHash) {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid password"})
				return
			}
		}
		s.WholesaleOrderEnabled = true
	} else {
		if strings.TrimSpace(body.Password) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Password is required"})
			return
		}
		if !utils.VerifyPassword(body.Password, user.PasswordHash) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid password"})
			return
		}
		s.WholesaleOrderEnabled = false
	}

	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
}
