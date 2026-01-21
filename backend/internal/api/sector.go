package api

import (
	"net/http"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type SectorHandler struct {
	db *gorm.DB
}

func NewSectorHandler(db *gorm.DB) *SectorHandler {
	return &SectorHandler{db: db}
}

type CreateSectorRequest struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
}

func (h *SectorHandler) ListSectors(c *gin.Context) {
	var sectors []models.Sector
	if err := h.db.Where("is_active = ?", true).Find(&sectors).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sectors)
}

func (h *SectorHandler) CreateSector(c *gin.Context) {
	var req CreateSectorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	sector := models.Sector{
		Name:        req.Name,
		Description: req.Description,
		IsActive:    true,
	}

	if err := h.db.Create(&sector).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, sector)
}

func (h *SectorHandler) UpdateSector(c *gin.Context) {
	var sector models.Sector
	if err := h.db.First(&sector, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Sector not found"})
		return
	}

	var req CreateSectorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	sector.Name = req.Name
	sector.Description = req.Description

	if err := h.db.Save(&sector).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sector)
}

func (h *SectorHandler) DeleteSector(c *gin.Context) {
	var sector models.Sector
	if err := h.db.First(&sector, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Sector not found"})
		return
	}

	// Soft delete
	sector.IsActive = false
	if err := h.db.Save(&sector).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Sector deactivated"})
}
