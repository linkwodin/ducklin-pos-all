package api

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"strconv"
	"strings"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"
	"pos-system/backend/internal/utils"

	"io/ioutil"
	"sync"

	"github.com/disintegration/imaging"
	"github.com/gin-gonic/gin"
	"golang.org/x/image/draw"
	"golang.org/x/image/font"
	"golang.org/x/image/font/basicfont"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
	"gorm.io/gorm"
)

type UserHandler struct {
	db  *gorm.DB
	cfg *config.Config
}

func NewUserHandler(db *gorm.DB, cfg *config.Config) *UserHandler {
	return &UserHandler{db: db, cfg: cfg}
}

var iconFont font.Face
var iconFontOnce sync.Once

// loadIconFont loads a monospace font for icon generation
// First tries to load a custom font from fonts/icon.ttf, then system fonts, falls back to basicfont
func loadIconFont() font.Face {
	iconFontOnce.Do(func() {
		// Priority 1: Try custom font file in fonts/icon.ttf (relative to backend directory)
		fontPaths := []string{
			"fonts/icon.ttf",                                                  // Custom font (highest priority)
			"backend/fonts/icon.ttf",                                          // Alternative path
			"/System/Library/Fonts/Monaco.ttf",                                // macOS system font
			"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",             // Linux
			"/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", // Linux
			"C:/Windows/Fonts/consola.ttf",                                    // Windows
			"C:/Windows/Fonts/cour.ttf",                                       // Windows (Courier New)
		}

		for _, fontPath := range fontPaths {
			if fontData, err := ioutil.ReadFile(fontPath); err == nil {
				if tt, err := opentype.Parse(fontData); err == nil {
					// Create a face with large size for high-resolution rendering
					// Size 280 for 1600x1600 canvas (70% of previous 400, text will be ~17.5% of canvas height)
					face, err := opentype.NewFace(tt, &opentype.FaceOptions{
						Size:    200,
						DPI:     288,
						Hinting: font.HintingFull,
					})
					if err == nil {
						iconFont = face
						return
					}
				}
			}
		}

		// Fallback to basicfont if no font found
		iconFont = basicfont.Face7x13
	})

	return iconFont
}

type CreateUserRequest struct {
	Username  string `json:"username" binding:"required"`
	Password  string `json:"password" binding:"required"`
	PIN       string `json:"pin"`
	FirstName string `json:"first_name" binding:"required"`
	LastName  string `json:"last_name" binding:"required"`
	Email     string `json:"email"`
	Role      string `json:"role" binding:"required,oneof=management pos_user supervisor"`
	StoreIDs  []uint `json:"store_ids"`
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
		CurrentPIN string `json:"current_pin"`
		PIN        string `json:"pin" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// If updating own PIN, verify current PIN first (unless user is management updating another user)
	if uint(userID) == currentUserID && req.CurrentPIN != "" {
		var user models.User
		if err := h.db.First(&user, userID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}

		// Verify current PIN
		if !utils.VerifyPassword(req.CurrentPIN, user.PINHash) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Current PIN is incorrect"})
			return
		}
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
	currentUserIDInterface, _ := c.Get("user_id")
	currentUserID := currentUserIDInterface.(uint)

	// Users can only update their own icon, or management can update any
	if uint(userID) != currentUserID {
		role, _ := c.Get("role")
		if role != "management" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
			return
		}
	}

	// Check if it's multipart form data (file upload) or JSON (icon URL or color generation)
	contentType := c.GetHeader("Content-Type")
	var iconURL string
	var bgColor, textColor string

	if strings.HasPrefix(contentType, "multipart/form-data") {
		// Handle file upload
		file, err := c.FormFile("icon")
		if err == nil && file != nil {
			// Upload image using product handler's upload method (reuse logic)
			productHandler := NewProductHandler(h.db, h.cfg)
			uploadedURL, uploadErr := productHandler.uploadImage(file, c)
			if uploadErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
				return
			}
			iconURL = uploadedURL
		} else {
			// Check for color-based icon generation
			bgColor = c.PostForm("bg_color")
			textColor = c.PostForm("text_color")
			if bgColor != "" && textColor != "" {
				// Generate icon URL from colors
				var user models.User
				if err := h.db.First(&user, userID).Error; err != nil {
					c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
					return
				}
				// Generate icon using colors
				iconURL = h.generateIconFromColors(user.FirstName, user.LastName, bgColor, textColor, c)
			}
		}
	} else {
		// Handle JSON request
		var req struct {
			IconURL   string `json:"icon_url"`
			BgColor   string `json:"bg_color"`
			TextColor string `json:"text_color"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		bgColor = req.BgColor
		textColor = req.TextColor

		if req.IconURL != "" {
			iconURL = req.IconURL
		} else if req.BgColor != "" && req.TextColor != "" {
			// Generate icon from colors
			var user models.User
			if err := h.db.First(&user, userID).Error; err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
				return
			}
			iconURL = h.generateIconFromColors(user.FirstName, user.LastName, req.BgColor, req.TextColor, c)
		}
	}

	if iconURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "icon_url, icon file, or bg_color/text_color is required"})
		return
	}

	// Prepare update data
	updateData := map[string]interface{}{
		"icon_url": iconURL,
	}

	// Save bg_color and text_color if provided (for remembering last selection)
	if bgColor != "" {
		updateData["icon_bg_color"] = bgColor
	}
	if textColor != "" {
		updateData["icon_text_color"] = textColor
	}

	if err := h.db.Model(&models.User{}).Where("id = ?", userID).Updates(updateData).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Icon updated successfully", "icon_url": iconURL})
}

// generateIconFromColors generates a PNG icon image from background and text colors
func (h *UserHandler) generateIconFromColors(firstName, lastName, bgColor, textColor string, c *gin.Context) string {
	// Get initials
	initials := ""
	if firstName != "" && lastName != "" {
		initials = string(firstName[0]) + string(lastName[0])
	} else if firstName != "" {
		initials = string(firstName[0])
	} else {
		initials = "?"
	}
	initials = strings.ToUpper(initials)

	// Parse colors
	bgCol, err := parseColor(bgColor)
	if err != nil {
		bgCol = color.RGBA{R: 0x21, G: 0x96, B: 0xF3, A: 0xFF} // Default blue
	}
	textCol, err := parseColor(textColor)
	if err != nil {
		textCol = color.RGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF} // Default white
	}

	// Render text directly on a high-resolution canvas for crisp, anti-aliased output
	face := loadIconFont()

	// Create a high-resolution canvas (1600x1600) for sharp rendering
	canvasSize := 1600
	canvas := image.NewRGBA(image.Rect(0, 0, canvasSize, canvasSize))

	// Fill background
	draw.Draw(canvas, canvas.Bounds(), &image.Uniform{bgCol}, image.Point{}, draw.Src)

	// Measure text
	textWidth := font.MeasureString(face, initials).Ceil()
	textHeight := face.Metrics().Height.Ceil()

	// Center text on canvas
	x := (canvasSize - textWidth) / 2
	y := (canvasSize-textHeight)/2 + face.Metrics().Ascent.Ceil()

	point := fixed.Point26_6{
		X: fixed.Int26_6(x * 64),
		Y: fixed.Int26_6(y * 64),
	}

	// Draw text directly on high-resolution canvas (anti-aliased)
	d := &font.Drawer{
		Dst:  canvas,
		Src:  &image.Uniform{textCol},
		Face: face,
		Dot:  point,
	}
	d.DrawString(initials)

	// Scale down to 100x100 for final image (high quality Lanczos resampling from high-res source)
	img := imaging.Resize(canvas, 100, 100, imaging.Lanczos)

	// Encode as PNG
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		// Fallback to a simple colored square if encoding fails
		return fmt.Sprintf("data:image/png;base64,%s", base64.StdEncoding.EncodeToString([]byte("")))
	}

	// Convert to base64 data URL
	dataURL := "data:image/png;base64," + base64.StdEncoding.EncodeToString(buf.Bytes())
	return dataURL
}

// parseColor parses a color string (hex, rgb, or named color)
func parseColor(colorStr string) (color.Color, error) {
	// Remove # if present
	colorStr = strings.TrimPrefix(colorStr, "#")

	// Try to parse as hex
	if len(colorStr) == 6 {
		var r, g, b uint8
		if _, err := fmt.Sscanf(colorStr, "%02x%02x%02x", &r, &g, &b); err == nil {
			return color.RGBA{R: r, G: g, B: b, A: 0xFF}, nil
		}
	}

	// Try to parse as rgb(r, g, b)
	if strings.HasPrefix(colorStr, "rgb") {
		var r, g, b uint8
		if _, err := fmt.Sscanf(colorStr, "rgb(%d,%d,%d)", &r, &g, &b); err == nil {
			return color.RGBA{R: r, G: g, B: b, A: 0xFF}, nil
		}
	}

	// Named colors (basic set)
	namedColors := map[string]color.RGBA{
		"red":     {R: 0xFF, G: 0x00, B: 0x00, A: 0xFF},
		"green":   {R: 0x00, G: 0xFF, B: 0x00, A: 0xFF},
		"blue":    {R: 0x00, G: 0x00, B: 0xFF, A: 0xFF},
		"white":   {R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF},
		"black":   {R: 0x00, G: 0x00, B: 0x00, A: 0xFF},
		"yellow":  {R: 0xFF, G: 0xFF, B: 0x00, A: 0xFF},
		"cyan":    {R: 0x00, G: 0xFF, B: 0xFF, A: 0xFF},
		"magenta": {R: 0xFF, G: 0x00, B: 0xFF, A: 0xFF},
	}

	if col, ok := namedColors[strings.ToLower(colorStr)]; ok {
		return col, nil
	}

	return nil, fmt.Errorf("invalid color: %s", colorStr)
}
