package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type CurrencyHandler struct {
	db *gorm.DB
}

func NewCurrencyHandler(db *gorm.DB) *CurrencyHandler {
	return &CurrencyHandler{db: db}
}

type CreateCurrencyRateRequest struct {
	CurrencyCode string  `json:"currency_code" binding:"required"`
	RateToGBP    float64 `json:"rate_to_gbp" binding:"required"`
	IsPinned     bool    `json:"is_pinned"`
}

type UpdateCurrencyRateRequest struct {
	RateToGBP float64 `json:"rate_to_gbp" binding:"required"`
	IsPinned  bool    `json:"is_pinned"`
}

type TogglePinRequest struct {
	IsPinned bool `json:"is_pinned"`
}

// ListCurrencyRates returns all currency rates, sorted with pinned ones first
func (h *CurrencyHandler) ListCurrencyRates(c *gin.Context) {
	var rates []models.CurrencyRate
	if err := h.db.Order("is_pinned DESC, currency_code").Find(&rates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, rates)
}

// GetCurrencyRate returns a specific currency rate
func (h *CurrencyHandler) GetCurrencyRate(c *gin.Context) {
	code := c.Param("code")
	var rate models.CurrencyRate
	if err := h.db.Where("currency_code = ?", code).First(&rate).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Currency rate not found"})
		return
	}

	c.JSON(http.StatusOK, rate)
}

// CreateCurrencyRate creates a new currency rate
func (h *CurrencyHandler) CreateCurrencyRate(c *gin.Context) {
	var req CreateCurrencyRateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if currency already exists
	var existing models.CurrencyRate
	if err := h.db.Where("currency_code = ?", req.CurrencyCode).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Currency rate already exists"})
		return
	}

	rate := models.CurrencyRate{
		CurrencyCode: req.CurrencyCode,
		RateToGBP:    req.RateToGBP,
		IsPinned:     req.IsPinned,
		LastUpdated:  time.Now(),
		UpdatedBy:    "manual",
	}

	if err := h.db.Create(&rate).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, rate)
}

// UpdateCurrencyRate updates an existing currency rate
func (h *CurrencyHandler) UpdateCurrencyRate(c *gin.Context) {
	code := c.Param("code")
	var rate models.CurrencyRate
	if err := h.db.Where("currency_code = ?", code).First(&rate).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Currency rate not found"})
		return
	}

	var req UpdateCurrencyRateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	rate.RateToGBP = req.RateToGBP
	rate.IsPinned = req.IsPinned
	rate.LastUpdated = time.Now()
	rate.UpdatedBy = "manual"

	if err := h.db.Save(&rate).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, rate)
}

// TogglePinCurrencyRate toggles the pin status of a currency
func (h *CurrencyHandler) TogglePinCurrencyRate(c *gin.Context) {
	code := c.Param("code")
	var rate models.CurrencyRate
	if err := h.db.Where("currency_code = ?", code).First(&rate).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Currency rate not found"})
		return
	}

	var req TogglePinRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	rate.IsPinned = req.IsPinned
	if err := h.db.Save(&rate).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, rate)
}

// DeleteCurrencyRate deletes a currency rate
func (h *CurrencyHandler) DeleteCurrencyRate(c *gin.Context) {
	code := c.Param("code")
	if err := h.db.Where("currency_code = ?", code).Delete(&models.CurrencyRate{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Currency rate deleted"})
}

// SyncCurrencyRates fetches latest rates from a free API and updates the database
// Main purchasing currencies: CNY, USD, HKD, JPY (can be pinned after sync)
func (h *CurrencyHandler) SyncCurrencyRates(c *gin.Context) {
	// Using exchangerate-api.com free tier (no API key needed for basic usage)
	// Base currency: GBP
	url := "https://api.exchangerate-api.com/v4/latest/GBP"

	resp, err := http.Get(url)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to fetch rates: %v", err)})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("API returned status %d: %s", resp.StatusCode, string(body))})
		return
	}

	var apiResponse struct {
		Base  string             `json:"base"`
		Date  string             `json:"date"`
		Rates map[string]float64 `json:"rates"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&apiResponse); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to parse API response: %v", err)})
		return
	}

	// Update or create currency rates
	updatedCount := 0
	now := time.Now()

	// Add GBP itself (1:1) - always pinned
	gbpRate := models.CurrencyRate{
		CurrencyCode: "GBP",
		RateToGBP:    1.0,
		IsPinned:     true, // GBP is always pinned as base currency
		LastUpdated:  now,
		UpdatedBy:    "api_sync",
	}
	var existingGBP models.CurrencyRate
	if err := h.db.Where("currency_code = ?", "GBP").First(&existingGBP).Error; err == nil {
		// Preserve existing pin status if manually set, otherwise set to true
		if existingGBP.UpdatedBy == "manual" {
			gbpRate.IsPinned = existingGBP.IsPinned
		}
		gbpRate.RateToGBP = 1.0 // Always 1.0 for GBP
		gbpRate.LastUpdated = now
		gbpRate.UpdatedBy = "api_sync"
		h.db.Model(&existingGBP).Updates(gbpRate)
	} else {
		h.db.Create(&gbpRate)
	}
	updatedCount++

	// Update other currencies (preserve pin status if manually set)
	for currencyCode, rate := range apiResponse.Rates {
		// Skip if rate is invalid
		if rate <= 0 {
			continue
		}

		var existing models.CurrencyRate
		result := h.db.Where("currency_code = ?", currencyCode).First(&existing)

		if result.Error == nil {
			// Update existing - preserve pin status if manually set
			preservePin := existing.UpdatedBy == "manual" && existing.IsPinned
			existing.RateToGBP = rate
			existing.LastUpdated = now
			existing.UpdatedBy = "api_sync"
			if !preservePin {
				existing.IsPinned = false // Reset pin on sync unless manually pinned
			}
			h.db.Save(&existing)
		} else {
			// Create new - default to unpinned
			currencyRate := models.CurrencyRate{
				CurrencyCode: currencyCode,
				RateToGBP:    rate,
				IsPinned:     false,
				LastUpdated:  now,
				UpdatedBy:    "api_sync",
			}
			h.db.Create(&currencyRate)
		}
		updatedCount++
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "Currency rates synced successfully",
		"updated_count": updatedCount,
		"sync_date":     now,
	})
}
