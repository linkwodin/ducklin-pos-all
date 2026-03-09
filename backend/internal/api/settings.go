package api

import (
	"net/http"
	"strings"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const companySettingsID = 1

var defaultCompanySettings = models.CompanySettings{
	ID:                companySettingsID,
	CompanyName:       "Ducklin Company Ltd",
	AddressLine1:      "60 Ravensfield Gardens",
	AddressLine2:      "Epsom",
	City:              "London",
	Postcode:          "KT19 0SR",
	Telephone:         "+44 7516 011596",
	Email:             "hello@ducklincompany.co.uk",
	BankAccountName:   "Heartwood Trading Ltd",
	BankAccountNumber: "25307108",
	BankSortCode:      "23-08-01",
	BankAddress:       "56 Shoreditch High Street, London E1 6JJ",
	BankIBAN:          "GB90 TRWI 2308 0125 3071 08",
}

// SettingsHandler handles company/settings API.
type SettingsHandler struct {
	db *gorm.DB
}

// NewSettingsHandler creates a new SettingsHandler.
func NewSettingsHandler(db *gorm.DB) *SettingsHandler {
	return &SettingsHandler{db: db}
}

// GetCompanySettings returns the company settings (singleton ID=1). Creates with defaults if not present.
func (h *SettingsHandler) GetCompanySettings(c *gin.Context) {
	var s models.CompanySettings
	err := h.db.First(&s, companySettingsID).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			// Create default row
			s = defaultCompanySettings
			if createErr := h.db.Create(&s).Error; createErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create default company settings"})
				return
			}
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusOK, s)
}

// UpdateCompanySettings updates the company settings (singleton ID=1).
func (h *SettingsHandler) UpdateCompanySettings(c *gin.Context) {
	var body struct {
		CompanyName       *string `json:"company_name"`
		AddressLine1      *string `json:"address_line1"`
		AddressLine2      *string `json:"address_line2"`
		City              *string `json:"city"`
		Postcode          *string `json:"postcode"`
		Telephone         *string `json:"telephone"`
		Email             *string `json:"email"`
		BankAccountName   *string `json:"bank_account_name"`
		BankAccountNumber *string `json:"bank_account_number"`
		BankSortCode      *string `json:"bank_sort_code"`
		BankAddress       *string `json:"bank_address"`
		BankIBAN          *string `json:"bank_iban"`
		PaymentInfo       *string `json:"payment_info"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if body.PaymentInfo != nil {
		lines := strings.Split(*body.PaymentInfo, "\n")
		if len(lines) > 5 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Payment details must not exceed 5 lines (invoice layout)"})
			return
		}
	}
	var s models.CompanySettings
	err := h.db.First(&s, companySettingsID).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			s = defaultCompanySettings
			if err := h.db.Create(&s).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create company settings"})
				return
			}
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	// Apply partial update
	if body.CompanyName != nil {
		s.CompanyName = *body.CompanyName
	}
	if body.AddressLine1 != nil {
		s.AddressLine1 = *body.AddressLine1
	}
	if body.AddressLine2 != nil {
		s.AddressLine2 = *body.AddressLine2
	}
	if body.City != nil {
		s.City = *body.City
	}
	if body.Postcode != nil {
		s.Postcode = *body.Postcode
	}
	if body.Telephone != nil {
		s.Telephone = *body.Telephone
	}
	if body.Email != nil {
		s.Email = *body.Email
	}
	if body.BankAccountName != nil {
		s.BankAccountName = *body.BankAccountName
	}
	if body.BankAccountNumber != nil {
		s.BankAccountNumber = *body.BankAccountNumber
	}
	if body.BankSortCode != nil {
		s.BankSortCode = *body.BankSortCode
	}
	if body.BankAddress != nil {
		s.BankAddress = *body.BankAddress
	}
	if body.BankIBAN != nil {
		s.BankIBAN = *body.BankIBAN
	}
	if body.PaymentInfo != nil {
		s.PaymentInfo = *body.PaymentInfo
	}
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, s)
}
