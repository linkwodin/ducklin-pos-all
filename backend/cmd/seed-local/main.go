// seed-local creates the database schema (via GORM migrations) and a default admin user
// for local development. Safe to re-run — skips seeding when a management user already exists.
//
// Usage (from backend/): go run ./cmd/seed-local
package main

import (
	"fmt"
	"log"
	"os"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/database"
	"pos-system/backend/internal/models"
	"pos-system/backend/internal/utils"

	"gorm.io/gorm"
)

func main() {
	cfg := config.Load()
	if cfg.DatabaseURL == "" {
		log.Fatal("DATABASE_URL is not set — run INSTALL-LOCAL first or create backend/.env")
	}

	db, err := database.Initialize(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Database setup failed: %v", err)
	}

	username := envOr("SEED_ADMIN_USERNAME", "admin")
	password := envOr("SEED_ADMIN_PASSWORD", "admin123")
	pin := envOr("SEED_ADMIN_PIN", "1234")

	var count int64
	if err := db.Model(&models.User{}).Where("role = ?", "management").Count(&count).Error; err != nil {
		log.Fatalf("Failed to check users: %v", err)
	}
	if count > 0 {
		fmt.Println("Management user already exists — skipping seed.")
		return
	}

	passwordHash, err := utils.HashPassword(password)
	if err != nil {
		log.Fatalf("Failed to hash password: %v", err)
	}
	pinHash, err := utils.HashPIN(pin)
	if err != nil {
		log.Fatalf("Failed to hash PIN: %v", err)
	}

	store := models.Store{Name: "Main Store", Address: "Local development", IsActive: true}
	if err := db.FirstOrCreate(&store, models.Store{Name: "Main Store"}).Error; err != nil {
		log.Fatalf("Failed to create store: %v", err)
	}

	user := models.User{
		Username:     username,
		PasswordHash: passwordHash,
		PINHash:      pinHash,
		FirstName:    "Admin",
		LastName:     "User",
		Email:        "admin@localhost",
		Role:         "management",
		IconColor:    utils.GenerateIconColor("Admin", "User"),
		IsActive:     true,
	}
	if err := db.Create(&user).Error; err != nil {
		log.Fatalf("Failed to create admin user: %v", err)
	}
	if err := db.Model(&user).Association("Stores").Append(&store); err != nil {
		log.Fatalf("Failed to assign store: %v", err)
	}

	seedSectors(db)

	fmt.Println("")
	fmt.Println("Local seed complete.")
	fmt.Printf("  Management login: %s / %s\n", username, password)
	fmt.Printf("  Default store:    %s (id=%d)\n", store.Name, store.ID)
	fmt.Println("  Management UI:    http://localhost:3000")
	fmt.Println("  API:              http://localhost:8868/api/v1")
	fmt.Println("")
}

func seedSectors(db *gorm.DB) {
	defaults := []models.Sector{
		{Name: "Wholesale", Description: "Wholesale customers", IsActive: true},
		{Name: "Restaurant", Description: "Restaurant trade", IsActive: true},
		{Name: "Retail", Description: "Retail customers", IsActive: true},
	}
	for _, s := range defaults {
		_ = db.FirstOrCreate(&s, models.Sector{Name: s.Name}).Error
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
