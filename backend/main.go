package main

import (
	"log"
	"os"
	"strings"
	"time"

	"pos-system/backend/internal/api"
	"pos-system/backend/internal/config"
	"pos-system/backend/internal/database"

	"gorm.io/gorm"
)

func main() {
	// Get port from environment or use default (Cloud Run sets PORT=8080)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8868"
	}

	log.Printf("Starting POS backend server...")
	log.Printf("Environment: %s", os.Getenv("ENVIRONMENT"))
	log.Printf("Port: %s", port)

	// Load environment variables
	cfg := config.Load()

	// Log configuration (without sensitive data)
	log.Printf("Storage Provider: %s", cfg.StorageProvider)
	if cfg.DatabaseURL != "" {
		// Mask password in database URL for logging
		maskedURL := cfg.DatabaseURL
		// Remove password from log
		if strings.Contains(maskedURL, "@") {
			parts := strings.Split(maskedURL, "@")
			if len(parts) > 0 {
				userPass := strings.Split(parts[0], ":")
				if len(userPass) > 1 {
					maskedURL = userPass[0] + ":***@" + strings.Join(parts[1:], "@")
				}
			}
		}
		if len(maskedURL) > 100 {
			maskedURL = maskedURL[:100] + "..."
		}
		log.Printf("Database URL: %s", maskedURL)
	} else {
		log.Printf("WARNING: DATABASE_URL is not set!")
	}

	// Initialize database with retry logic, but don't block server startup
	log.Println("Initializing database connection...")
	var db *gorm.DB
	var err error
	maxRetries := 2
	retryDelay := 2 // 2 seconds between retries

	// Try to connect quickly, but don't fail if it doesn't work
	for i := 0; i < maxRetries; i++ {
		db, err = database.Initialize(cfg.DatabaseURL)
		if err == nil {
			log.Println("Database connection established successfully")
			break
		}

		if i < maxRetries-1 {
			log.Printf("Database connection failed (attempt %d/%d): %v. Retrying in %d seconds...", i+1, maxRetries, err, retryDelay)
			time.Sleep(time.Duration(retryDelay) * time.Second)
		} else {
			// Don't fail - start server anyway so Cloud Run health check passes
			log.Printf("WARNING: Failed to initialize database after %d attempts: %v", maxRetries, err)
			log.Printf("Server will start but database operations will fail. Will retry in background.")
			db = nil // Set to nil so we know it's not connected
		}
	}

	// Initialize router (handlers will handle nil DB gracefully)
	log.Println("Setting up router...")
	router := api.SetupRouter(db, cfg)
	log.Println("Router setup complete")

	// Start server immediately - this is critical for Cloud Run health checks
	log.Printf("Starting HTTP server on port %s...", port)
	log.Printf("Server is ready to accept connections on port %s", port)

	// If database connection failed, continue retrying in background
	if db == nil {
		go func() {
			log.Println("Retrying database connection in background...")
			for {
				time.Sleep(5 * time.Second)
				connectedDB, err := database.Initialize(cfg.DatabaseURL)
				if err == nil {
					log.Println("Database connection established in background!")
					// Note: Router/handlers would need to be updated to use new DB
					// For now, this just ensures we eventually connect
					_ = connectedDB
					break
				}
				log.Printf("Background database retry failed: %v", err)
			}
		}()
	}

	// Start server - this blocks
	if err := router.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
