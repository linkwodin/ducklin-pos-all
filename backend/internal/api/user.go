package api

import (
	"net/http"
	"strconv"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"
	"pos-system/backend/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type UserHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewUserHandler(db *gorm.DB, cfg *config.Config) *UserHandler {
	return &UserHandler{db: db, cfg: cfg}
}

type CreateUserRequest struct {
	Username  string   `json:"username" binding:"required"`
	Password  string   `json:"password" binding:"required"`
	PIN       string   `json:"pin"`
	FirstName string   `json:"first_name" binding:"required"`
	LastName  string   `json:"last_name" binding:"required"`
	Email     string   `json:"email"`
	Role      string   `json:"role" binding:"required,oneof=management pos_user supervisor"`
	StoreIDs  []uint   `json:"store_ids"`
}

func (h *UserHandler) ListUsers(c *gin.Context) {
	var users []models.User
	if err := h.db.Preload("Stores").Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Clear sensitive data
	for i := range users {
		users[i].PasswordHash = ""
		users[i].PINHash = ""
	}

	c.JSON(http.StatusOK, users)
}

func (h *UserHandler) GetUser(c *gin.Context) {
	var user models.User
	if err := h.db.Preload("Stores").First(&user, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Clear sensitive data
	user.PasswordHash = ""
	user.PINHash = ""

	c.JSON(http.StatusOK, user)
}

func (h *UserHandler) CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Hash password
	passwordHash, err := utils.HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	// Hash PIN if provided
	var pinHash string
	if req.PIN != "" {
		pinHash, err = utils.HashPIN(req.PIN)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash PIN"})
			return
		}
	}

	// Generate icon color
	iconColor := utils.GenerateIconColor(req.FirstName, req.LastName)

	user := models.User{
		Username:     req.Username,
		PasswordHash: passwordHash,
		PINHash:      pinHash,
		FirstName:    req.FirstName,
		LastName:     req.LastName,
		Email:        req.Email,
		Role:         req.Role,
		IconColor:    iconColor,
		IsActive:     true,
	}

	if err := h.db.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Assign stores
	if len(req.StoreIDs) > 0 {
		for _, storeID := range req.StoreIDs {
			h.db.Exec("INSERT INTO user_stores (user_id, store_id) VALUES (?, ?)", user.ID, storeID)
		}
	}

	h.db.Preload("Stores").First(&user, user.ID)

	// Clear sensitive data
	user.PasswordHash = ""
	user.PINHash = ""

	c.JSON(http.StatusCreated, user)
}

func (h *UserHandler) UpdateUser(c *gin.Context) {
	var user models.User
	if err := h.db.First(&user, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	var req struct {
		FirstName string `json:"first_name"`
		LastName  string `json:"last_name"`
		Email     string `json:"email"`
		Role      string `json:"role"`
		IsActive  *bool  `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.FirstName != "" {
		user.FirstName = req.FirstName
	}
	if req.LastName != "" {
		user.LastName = req.LastName
	}
	if req.Email != "" {
		user.Email = req.Email
	}
	if req.Role != "" {
		user.Role = req.Role
	}
	if req.IsActive != nil {
		user.IsActive = *req.IsActive
	}

	if err := h.db.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Clear sensitive data
	user.PasswordHash = ""
	user.PINHash = ""

	c.JSON(http.StatusOK, user)
}

func (h *UserHandler) UpdatePIN(c *gin.Context) {
	userID, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	currentUserIDInterface, _ := c.Get("user_id")
	currentUserID := currentUserIDInterface.(uint)

	// Users can only update their own PIN, or management can update any
	if uint(userID) != currentUserID {
		role, _ := c.Get("role")
		if role != "management" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
			return
		}
	}

	var req struct {
		PIN string `json:"pin" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	pinHash, err := utils.HashPIN(req.PIN)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash PIN"})
		return
	}

	if err := h.db.Model(&models.User{}).Where("id = ?", userID).Update("pin_hash", pinHash).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "PIN updated successfully"})
}

func (h *UserHandler) UpdateIcon(c *gin.Context) {
	userID, _ := strconv.ParseUint(c.Param("id"), 10, 32)

	var req struct {
		IconURL string `json:"icon_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.db.Model(&models.User{}).Where("id = ?", userID).Update("icon_url", req.IconURL).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Icon updated successfully"})
}

