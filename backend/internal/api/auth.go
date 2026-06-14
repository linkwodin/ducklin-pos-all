package api

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
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
	Username   string `json:"username" binding:"required"`
	Password   string `json:"password" binding:"required"`
	DeviceCode string `json:"device_code"`
}

type PINLoginRequest struct {
	Username   string `json:"username" binding:"required"`
	PIN        string `json:"pin" binding:"required"`
	DeviceCode string `json:"device_code"`
}

type LoginResponse struct {
	Token            string      `json:"token"`
	User             models.User `json:"user"`
	LastStocktakeAt  *string     `json:"last_stocktake_at,omitempty"`
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

	resp := LoginResponse{Token: token, User: user}
	if req.DeviceCode != "" {
		if lastAt := h.lastStocktakeAtForDevice(req.DeviceCode); lastAt != nil {
			resp.LastStocktakeAt = lastAt
		}
	}
	c.JSON(http.StatusOK, resp)
}

// Refresh issues a new JWT when the caller presents a current or recently-expired token
// (same calendar day grace). Keeps management sessions alive during long work days.
func (h *AuthHandler) Refresh(c *gin.Context) {
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Database connection not available. Please try again later."})
		return
	}

	tokenString := bearerTokenFromHeader(c.GetHeader("Authorization"))
	if tokenString == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
		return
	}

	claims, err := parseJWTClaimsWithGrace(tokenString, h.cfg.JWTSecret, refreshGracePeriod(h.cfg.JWTExpiration))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
		return
	}

	uid, ok := jwtClaimUint(claims, "user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token: missing or invalid user_id"})
		return
	}

	var user models.User
	if err := h.db.Where("id = ? AND is_active = ?", uid, true).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error: " + err.Error()})
		}
		return
	}

	token, err := h.generateJWT(user.ID, user.Username, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	user.PasswordHash = ""
	user.PINHash = ""
	c.JSON(http.StatusOK, LoginResponse{Token: token, User: user})
}

func bearerTokenFromHeader(header string) string {
	header = strings.TrimSpace(header)
	if len(header) > 7 && strings.EqualFold(header[:7], "Bearer ") {
		return strings.TrimSpace(header[7:])
	}
	return header
}

func parseJWTClaimsWithGrace(tokenString, secret string, grace time.Duration) (jwt.MapClaims, error) {
	parser := jwt.NewParser(jwt.WithLeeway(grace))
	token, err := parser.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || token == nil || !token.Valid {
		return nil, err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, errors.New("invalid token claims")
	}
	return claims, nil
}

func refreshGracePeriod(jwtExpirationHours int) time.Duration {
	grace := time.Duration(jwtExpirationHours) * time.Hour
	if grace < 72*time.Hour {
		return 72 * time.Hour
	}
	return grace
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

	// Verify device code if provided and get store for last_stocktake_at
	var deviceStoreID *uint
	if req.DeviceCode != "" {
		normalizedDeviceCode := normalizeDeviceCodeForStorage(normalizeDeviceCodeForLookup(req.DeviceCode))
		var device models.POSDevice
		if err := h.db.Where("device_code = ? AND is_active = ?", normalizedDeviceCode, true).First(&device).Error; err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid device code"})
			return
		}
		deviceStoreID = &device.StoreID
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

	resp := LoginResponse{Token: token, User: user}
	if deviceStoreID != nil {
		if lastAt := h.lastStocktakeAtForStore(*deviceStoreID); lastAt != nil {
			resp.LastStocktakeAt = lastAt
		}
	}
	c.JSON(http.StatusOK, resp)
}

// lastStocktakeAtForDevice returns last_stocktake_at (RFC3339) for the device's store, or nil.
func (h *AuthHandler) lastStocktakeAtForDevice(deviceCode string) *string {
	normalizedDeviceCode := normalizeDeviceCodeForStorage(normalizeDeviceCodeForLookup(deviceCode))
	var device models.POSDevice
	if err := h.db.Where("device_code = ? AND is_active = ?", normalizedDeviceCode, true).First(&device).Error; err != nil {
		return nil
	}
	return h.lastStocktakeAtForStore(device.StoreID)
}

// lastStocktakeAtForStore returns last_stocktake_at (RFC3339) for the store — only from completed (done) events.
// Skip and first_login do not clear the reminder; only stocktake_day_start_done does.
func (h *AuthHandler) lastStocktakeAtForStore(storeID uint) *string {
	var out struct {
		MaxAt *time.Time `gorm:"column:max_at"`
	}
	err := h.db.Model(&models.UserActivityEvent{}).
		Select("MAX(occurred_at) AS max_at").
		Where("store_id = ? AND event_type = ?", storeID, models.EventStocktakeDayStartDone).
		Scan(&out).Error
	if err != nil || out.MaxAt == nil {
		return nil
	}
	s := out.MaxAt.Format(time.RFC3339)
	return &s
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

// jwtClaimUint reads user_id-style numeric claims without panicking (jwt.JSON can decode numbers as float64).
func jwtClaimUint(claims jwt.MapClaims, key string) (uint, bool) {
	raw, ok := claims[key]
	if !ok || raw == nil {
		return 0, false
	}
	switch v := raw.(type) {
	case float64:
		if v < 0 || v > 1<<31 {
			return 0, false
		}
		return uint(v), true
	case string:
		n, err := strconv.ParseUint(strings.TrimSpace(v), 10, 32)
		if err != nil {
			return 0, false
		}
		return uint(n), true
	default:
		return 0, false
	}
}

func jwtClaimString(claims jwt.MapClaims, key string) (string, bool) {
	raw, ok := claims[key]
	if !ok || raw == nil {
		return "", false
	}
	s, ok := raw.(string)
	if !ok {
		return "", false
	}
	s = strings.TrimSpace(s)
	return s, s != ""
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

		uid, ok := jwtClaimUint(claims, "user_id")
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token: missing or invalid user_id"})
			c.Abort()
			return
		}
		role, ok := jwtClaimString(claims, "role")
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token: missing or invalid role"})
			c.Abort()
			return
		}
		username, _ := jwtClaimString(claims, "username")

		c.Set("user_id", uid)
		c.Set("username", username)
		c.Set("role", role)

		c.Next()
	}
}
