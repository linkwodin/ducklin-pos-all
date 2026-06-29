package api

import (
	"net/http"

	"pos-system/backend/internal/utils"

	"github.com/gin-gonic/gin"
)

// BackendVersion is the API release label (build date is set separately via ldflags).
const BackendVersion = "1.0.0"

// GetSystemInfo returns installation identity and build versions for DLC activation.
func (h *SettingsHandler) GetSystemInfo(c *gin.Context) {
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"backend_version":    BackendVersion,
		"backend_build_date": BuildDate,
		"installation_id":    utils.FormatInstallationID(s.InstallationID),
	})
}

func (h *SettingsHandler) installationIDForDLC() (string, error) {
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		return "", err
	}
	return s.InstallationID, nil
}
