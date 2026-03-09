package api

import (
	"net/http"
	"strings"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func buildAddress(line1, line2, postcode string) string {
	var parts []string
	if line1 != "" {
		parts = append(parts, line1)
	}
	if line2 != "" {
		parts = append(parts, line2)
	}
	if postcode != "" {
		parts = append(parts, postcode)
	}
	return strings.Join(parts, "\n")
}

type WholesaleClientHandler struct {
	db *gorm.DB
}

func NewWholesaleClientHandler(db *gorm.DB) *WholesaleClientHandler {
	return &WholesaleClientHandler{db: db}
}

func (h *WholesaleClientHandler) List(c *gin.Context) {
	query := h.db.Model(&models.WholesaleClient{}).Preload("Sector").Preload("Stores")
	if c.Query("active_only") == "1" {
		query = query.Where("is_active = ?", true)
	}
	query = query.Order("name ASC")

	var list []models.WholesaleClient
	if err := query.Find(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, list)
}

func (h *WholesaleClientHandler) Get(c *gin.Context) {
	var client models.WholesaleClient
	if err := h.db.Preload("Sector").Preload("Stores").First(&client, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale client not found"})
		return
	}
	c.JSON(http.StatusOK, client)
}

type CreateWholesaleClientRequest struct {
	Name         string `json:"name" binding:"required"`
	ContactName  string `json:"contact_name"`
	Email        string `json:"email"`
	Phone        string `json:"phone"`
	Address      string `json:"address"`
	AddressLine1 string `json:"address_line1"`
	AddressLine2 string `json:"address_line2"`
	Postcode     string `json:"postcode"`
	VATNumber     string `json:"vat_number"`
	CompanyNumber string `json:"company_number"`
	Terms         string `json:"terms"`
	AccountCode   string `json:"account_code"`
	SectorID      *uint  `json:"sector_id"`
}

func (h *WholesaleClientHandler) Create(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var req CreateWholesaleClientRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	client := models.WholesaleClient{
		Name:         req.Name,
		ContactName:  req.ContactName,
		Email:        req.Email,
		Phone:        req.Phone,
		AddressLine1: req.AddressLine1,
		AddressLine2: req.AddressLine2,
		Postcode:     req.Postcode,
		VATNumber:     req.VATNumber,
		CompanyNumber: req.CompanyNumber,
		Terms:         req.Terms,
		AccountCode:   req.AccountCode,
		SectorID:     req.SectorID,
		IsActive:     true,
	}
	client.Address = buildAddress(client.AddressLine1, client.AddressLine2, client.Postcode)
	if req.Address != "" && client.Address == "" {
		client.Address = req.Address
	}
	if err := h.db.Create(&client).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.db.Preload("Sector").Preload("Stores").First(&client, client.ID)
	c.JSON(http.StatusCreated, client)
}

func (h *WholesaleClientHandler) Update(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var client models.WholesaleClient
	if err := h.db.First(&client, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale client not found"})
		return
	}
	var req CreateWholesaleClientRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	client.Name = req.Name
	client.ContactName = req.ContactName
	client.Email = req.Email
	client.Phone = req.Phone
	client.AddressLine1 = req.AddressLine1
	client.AddressLine2 = req.AddressLine2
	client.Postcode = req.Postcode
	client.VATNumber = req.VATNumber
	client.CompanyNumber = req.CompanyNumber
	client.Terms = req.Terms
	client.AccountCode = req.AccountCode
	client.SectorID = req.SectorID
	client.Address = buildAddress(client.AddressLine1, client.AddressLine2, client.Postcode)
	if req.Address != "" && client.Address == "" {
		client.Address = req.Address
	}
	if err := h.db.Save(&client).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.db.Preload("Sector").Preload("Stores").First(&client, client.ID)
	c.JSON(http.StatusOK, client)
}

func (h *WholesaleClientHandler) Delete(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var client models.WholesaleClient
	if err := h.db.First(&client, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale client not found"})
		return
	}
	client.IsActive = false
	if err := h.db.Save(&client).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, client)
}

// ── Client Stores (delivery locations) ──

type ClientStoreRequest struct {
	Name         string `json:"name" binding:"required"`
	AddressLine1 string `json:"address_line1"`
	AddressLine2 string `json:"address_line2"`
	City         string `json:"city"`
	Postcode     string `json:"postcode"`
	ContactName  string `json:"contact_name"`
	Email        string `json:"email"`
	Phone        string `json:"phone"`
}

func (h *WholesaleClientHandler) CreateStore(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var client models.WholesaleClient
	if err := h.db.First(&client, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale client not found"})
		return
	}
	var req ClientStoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	store := models.WholesaleClientStore{
		WholesaleClientID: client.ID,
		Name:              req.Name,
		AddressLine1:      req.AddressLine1,
		AddressLine2:      req.AddressLine2,
		City:              req.City,
		Postcode:          req.Postcode,
		ContactName:       req.ContactName,
		Email:             req.Email,
		Phone:             req.Phone,
		IsActive:          true,
	}
	if err := h.db.Create(&store).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, store)
}

func (h *WholesaleClientHandler) UpdateStore(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var store models.WholesaleClientStore
	if err := h.db.First(&store, c.Param("store_id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Store not found"})
		return
	}
	var req ClientStoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	store.Name = req.Name
	store.AddressLine1 = req.AddressLine1
	store.AddressLine2 = req.AddressLine2
	store.City = req.City
	store.Postcode = req.Postcode
	store.ContactName = req.ContactName
	store.Email = req.Email
	store.Phone = req.Phone
	if err := h.db.Save(&store).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, store)
}

func (h *WholesaleClientHandler) DeleteStore(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	var store models.WholesaleClientStore
	if err := h.db.First(&store, c.Param("store_id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Store not found"})
		return
	}
	store.IsActive = false
	if err := h.db.Save(&store).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, store)
}
