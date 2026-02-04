package api

import (
	"errors"
	"net/http"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"
	"pos-system/backend/internal/utils"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"gorm.io/gorm"
)

type AuthHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewAuthHandler(db *gorm.DB, cfg *config.Config) *AuthHandler {
	return &AuthHandler{db: db, cfg: cfg}
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type PINLoginRequest struct {
	Username   string `json:"username" binding:"required"`
	PIN        string `json:"pin" binding:"required"`
	DeviceCode string `json:"device_code"`
}

type LoginResponse struct {
	Token string      `json:"token"`
	User  models.User `json:"user"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if database is available
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Database connection not available. Please try again later."})
		return
	}

	var user models.User
	if err := h.db.Where("username = ? AND is_active = ?", req.Username, true).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		} else {
			// Log the actual error for debugging
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error: " + err.Error()})
		}
		return
	}

	// Verify password (supports both Argon2 hash and plain text for easy setup)
	if !utils.VerifyPassword(req.Password, user.PasswordHash) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// If password was plain text, hash it with Argon2 and update the database
	if utils.IsPlainText(user.PasswordHash) {
		hashedPassword, err := utils.HashPassword(req.Password)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
			return
		}
		user.PasswordHash = hashedPassword
		if err := h.db.Model(&user).Update("password_hash", hashedPassword).Error; err != nil {
			// Log error but don't fail login
			// Password will be hashed on next login
		}
	}

	token, err := h.generateJWT(user.ID, user.Username, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	// Clear sensitive data
	user.PasswordHash = ""
	user.PINHash = ""

	c.JSON(http.StatusOK, LoginResponse{
		Token: token,
		User:  user,
	})
}

func (h *AuthHandler) PINLogin(c *gin.Context) {
	var req PINLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if database is available
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Database connection not available. Please try again later."})
		return
	}

	// Verify device code if provided
	if req.DeviceCode != "" {
		// Normalize device code for lookup (wrap with braces for database)
		normalizedDeviceCode := normalizeDeviceCodeForStorage(normalizeDeviceCodeForLookup(req.DeviceCode))
		var device models.POSDevice
		if err := h.db.Where("device_code = ? AND is_active = ?", normalizedDeviceCode, true).First(&device).Error; err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid device code"})
			return
		}
	}

	var user models.User
	if err := h.db.Where("username = ? AND is_active = ?", req.Username, true).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error: " + err.Error()})
		}
		return
	}

	if user.PINHash == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "PIN not set for user"})
		return
	}

	// Verify PIN (supports both Argon2 hash and plain text for easy setup)
	if !utils.VerifyPassword(req.PIN, user.PINHash) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid PIN"})
		return
	}

	// If PIN was plain text, hash it with Argon2 and update the database
	if utils.IsPlainText(user.PINHash) {
		hashedPIN, err := utils.HashPIN(req.PIN)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash PIN"})
			return
		}
		user.PINHash = hashedPIN
		if err := h.db.Model(&user).Update("pin_hash", hashedPIN).Error; err != nil {
			// Log error but don't fail login
			// PIN will be hashed on next login
		}
	}

	token, err := h.generateJWT(user.ID, user.Username, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	// Clear sensitive data
	user.PasswordHash = ""
	user.PINHash = ""

	c.JSON(http.StatusOK, LoginResponse{
		Token: token,
		User:  user,
	})
}

func (h *AuthHandler) generateJWT(userID uint, username, role string) (string, error) {
	claims := jwt.MapClaims{
		"user_id":  userID,
		"username": username,
		"role":     role,
		"exp":      time.Now().Add(time.Duration(h.cfg.JWTExpiration) * time.Hour).Unix(),
		"iat":      time.Now().Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.cfg.JWTSecret))
}

func authMiddleware(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := c.GetHeader("Authorization")
		if tokenString == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
			c.Abort()
			return
		}

		// Remove "Bearer " prefix if present
		if len(tokenString) > 7 && tokenString[:7] == "Bearer " {
			tokenString = tokenString[7:]
		}

		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			return []byte(jwtSecret), nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
			c.Abort()
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token claims"})
			c.Abort()
			return
		}

		// Set user info in context
		c.Set("user_id", uint(claims["user_id"].(float64)))
		c.Set("username", claims["username"].(string))
		c.Set("role", claims["role"].(string))

		c.Next()
	}
}
