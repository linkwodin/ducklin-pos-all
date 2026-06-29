package api

import (
	"net/http"
	"strings"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"
	"pos-system/backend/internal/utils"

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
	BankIBAN:                       "GB90 TRWI 2308 0125 3071 08",
	WholesaleOrderEmailDefaultCC:    "",
	ShipmentCouriers:                "In-house\nDPD\nRoyal Mail",
}

// SettingsHandler handles company/settings API.
type SettingsHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

// NewSettingsHandler creates a new SettingsHandler.
func NewSettingsHandler(db *gorm.DB, cfg *config.Config) *SettingsHandler {
	return &SettingsHandler{db: db, cfg: cfg}
}

func (h *SettingsHandler) loadOrCreateCompanySettings() (models.CompanySettings, error) {
	var s models.CompanySettings
	err := h.db.First(&s, companySettingsID).Error
	if err == nil {
		if saveErr := h.ensureInstallationID(&s); saveErr != nil {
			return s, saveErr
		}
		return s, nil
	}
	if err != gorm.ErrRecordNotFound {
		return s, err
	}
	s = defaultCompanySettings
	if createErr := h.db.Create(&s).Error; createErr != nil {
		return s, createErr
	}
	if saveErr := h.ensureInstallationID(&s); saveErr != nil {
		return s, saveErr
	}
	return s, nil
}

func (h *SettingsHandler) ensureInstallationID(s *models.CompanySettings) error {
	id, generated := utils.EnsureInstallationID(s.InstallationID, s.SystemFingerprint)
	if id == s.InstallationID && !generated {
		return nil
	}
	s.InstallationID = id
	return h.db.Model(s).Select("installation_id").Updates(map[string]interface{}{
		"installation_id": id,
	}).Error
}

// GetCompanySettings returns the company settings (singleton ID=1). Creates with defaults if not present.
func (h *SettingsHandler) GetCompanySettings(c *gin.Context) {
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
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
		PaymentTransferToInfo              *string `json:"payment_transfer_to_info"`
		WholesaleOrderEmailSubjectTemplate *string `json:"wholesale_order_email_subject_template"`
		WholesaleOrderEmailDefaultCC       *string `json:"wholesale_order_email_default_cc"`
		WholesaleOrderEmailDefaultBCC      *string `json:"wholesale_order_email_default_bcc"`
		ShipmentCouriers                   *string `json:"shipment_couriers"`
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
	if body.PaymentTransferToInfo != nil {
		lines := strings.Split(*body.PaymentTransferToInfo, "\n")
		if len(lines) > 5 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Payment transfer destinations must not exceed 5 lines"})
			return
		}
	}
	if body.ShipmentCouriers != nil {
		lines := strings.Split(*body.ShipmentCouriers, "\n")
		if len(lines) > 30 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Shipment couriers must not exceed 30 lines"})
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
	if body.PaymentTransferToInfo != nil {
		s.PaymentTransferToInfo = *body.PaymentTransferToInfo
	}
	if body.WholesaleOrderEmailSubjectTemplate != nil {
		s.WholesaleOrderEmailSubjectTemplate = *body.WholesaleOrderEmailSubjectTemplate
	}
	if body.WholesaleOrderEmailDefaultCC != nil {
		s.WholesaleOrderEmailDefaultCC = strings.TrimSpace(*body.WholesaleOrderEmailDefaultCC)
	}
	if body.WholesaleOrderEmailDefaultBCC != nil {
		s.WholesaleOrderEmailDefaultBCC = strings.TrimSpace(*body.WholesaleOrderEmailDefaultBCC)
	}
	if body.ShipmentCouriers != nil {
		s.ShipmentCouriers = *body.ShipmentCouriers
	}
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
}

func (h *SettingsHandler) companySettingsResponse(s models.CompanySettings) gin.H {
	s.LogoURL = normalizeLogoURL(s.LogoURL)
	pdfLogo := normalizeLogoURL(s.PdfLogoURL)
	webLogo := normalizeLogoURL(s.WebLogoURL)
	posLogo := normalizeLogoURL(s.PosLogoURL)
	return gin.H{
		"id":                                      s.ID,
		"company_name":                            s.CompanyName,
		"logo_url":                                s.LogoURL,
		"pdf_logo_url":                            pdfLogo,
		"web_logo_url":                            webLogo,
		"pos_logo_url":                            posLogo,
		"address_line1":                           s.AddressLine1,
		"address_line2":                           s.AddressLine2,
		"city":                                    s.City,
		"postcode":                                s.Postcode,
		"telephone":                               s.Telephone,
		"email":                                   s.Email,
		"bank_account_name":                       s.BankAccountName,
		"bank_account_number":                     s.BankAccountNumber,
		"bank_sort_code":                          s.BankSortCode,
		"bank_address":                            s.BankAddress,
		"bank_iban":                               s.BankIBAN,
		"payment_info":                            s.PaymentInfo,
		"payment_transfer_to_info":                s.PaymentTransferToInfo,
		"shipment_couriers":                       s.ShipmentCouriers,
		"wholesale_order_email_subject_template":  s.WholesaleOrderEmailSubjectTemplate,
		"wholesale_order_email_default_cc":        s.WholesaleOrderEmailDefaultCC,
		"wholesale_order_email_default_bcc":       s.WholesaleOrderEmailDefaultBCC,
		"wholesale_order_enabled":                 s.WholesaleOrderEnabled,
		"wholesale_serial_activated":              s.WholesaleSerialActivated,
		"pos_module_enabled":                      s.PosModuleEnabled,
		"pos_dlc_activated":                       s.PosDlcActivated,
		"updated_at":                              s.UpdatedAt,
	}
}
// UploadCompanyLogo accepts a multipart logo image and stores its URL on company settings (legacy; sets logo_url).
func (h *SettingsHandler) UploadCompanyLogo(c *gin.Context) {
	h.uploadCompanyLogoByType(c, LogoTypePDF, func(s *models.CompanySettings, url string) {
		s.LogoURL = url
		s.PdfLogoURL = url
	})
}

// UploadCompanyLogoByType uploads a logo for pdf, web, or pos.
func (h *SettingsHandler) UploadCompanyLogoByType(c *gin.Context) {
	logoType, ok := parseLogoType(c.Param("type"))
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid logo type; use pdf, web, or pos"})
		return
	}
	h.uploadCompanyLogoByType(c, logoType, func(s *models.CompanySettings, url string) {
		setLogoURLForType(s, logoType, url)
	})
}

func (h *SettingsHandler) uploadCompanyLogoByType(c *gin.Context, logoType string, apply func(*models.CompanySettings, string)) {
	file, err := c.FormFile("logo")
	if err != nil || file == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "logo file required"})
		return
	}
	productHandler := NewProductHandler(h.db, h.cfg)
	uploadedURL, uploadErr := productHandler.uploadBrandingLogoForType(file, logoType)
	if uploadErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
		return
	}
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	apply(&s, uploadedURL)
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
}

// UploadCompanyLogoAll uploads one image and updates pdf, web, and pos icons.
func (h *SettingsHandler) UploadCompanyLogoAll(c *gin.Context) {
	file, err := c.FormFile("logo")
	if err != nil || file == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "logo file required"})
		return
	}
	productHandler := NewProductHandler(h.db, h.cfg)
	urls, uploadErr := productHandler.uploadBrandingLogoForAllTypes(file)
	if uploadErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
		return
	}
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	s.LogoURL = urls.PdfURL
	s.PdfLogoURL = urls.PdfURL
	s.WebLogoURL = urls.WebURL
	s.PosLogoURL = urls.PosURL
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
}

type copyCompanyLogoBody struct {
	From string `json:"from"`
	To   string `json:"to"`
}

// CopyCompanyLogo copies and reprocesses one logo type to another.
func (h *SettingsHandler) CopyCompanyLogo(c *gin.Context) {
	var body copyCompanyLogoBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}
	from, okFrom := parseLogoType(body.From)
	to, okTo := parseLogoType(body.To)
	if !okFrom || !okTo {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid logo type; use pdf, web, or pos"})
		return
	}
	if from == to {
		c.JSON(http.StatusBadRequest, gin.H{"error": "from and to must differ"})
		return
	}
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	sourceURL := logoURLForType(s, from)
	if sourceURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source logo is empty"})
		return
	}
	productHandler := NewProductHandler(h.db, h.cfg)
	uploadedURL, copyErr := productHandler.copyBrandingLogoFromURL(sourceURL, to)
	if copyErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": copyErr.Error()})
		return
	}
	setLogoURLForType(&s, to, uploadedURL)
	if err := h.db.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.companySettingsResponse(s))
}

// GetPublicCompanyBranding returns company name and logos for unauthenticated clients (POS login screen).
func (h *SettingsHandler) GetPublicCompanyBranding(c *gin.Context) {
	s, err := h.loadOrCreateCompanySettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	webLogo := EffectiveWebLogoURL(s)
	posLogo := EffectivePosLogoURL(s)
	pdfLogo := EffectivePdfLogoURL(s)
	c.JSON(http.StatusOK, gin.H{
		"company_name": s.CompanyName,
		"logo_url":     webLogo,
		"web_logo_url": webLogo,
		"pos_logo_url": posLogo,
		"pdf_logo_url": pdfLogo,
	})
}
