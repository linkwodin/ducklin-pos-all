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

// PosModuleEnabledMiddleware blocks POS device login when the module is disabled.
func PosModuleEnabledMiddleware(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var s models.CompanySettings
		err := db.Select("pos_module_enabled").First(&s, companySettingsID).Error
		if err != nil || !s.PosModuleEnabled {
			c.JSON(http.StatusForbidden, gin.H{"error": "POS module is disabled"})
			c.Abort()
			return
		}
		c.Next()
	}
}

type togglePosModuleBody struct {
	Enabled           bool   `json:"enabled"`
	Password          string `json:"password"`
	ProductSerialCode string `json:"product_serial_code"`
}

// TogglePosModule enables or disables the POS module with password or product serial verification.
func (h *SettingsHandler) TogglePosModule(c *gin.Context) {
	var body togglePosModuleBody
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
		if !s.PosDlcActivated {
			if strings.TrimSpace(body.ProductSerialCode) == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Product serial code is required"})
				return
			}
			installationID, idErr := h.installationIDForDLC()
			if idErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": idErr.Error()})
				return
			}
			if !dlclicense.ValidatePOSCode(installationID, body.ProductSerialCode) {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid product serial code for this system"})
				return
			}
			s.PosDlcActivated = true
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
		s.PosModuleEnabled = true
	} else {
		if strings.TrimSpace(body.Password) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Password is required"})
			return
		}
		if !utils.VerifyPassword(body.Password, user.PasswordHash) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid password"})
			return
		}
		s.PosModuleEnabled = false
	}

	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
}
