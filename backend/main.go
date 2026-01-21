package main

import (
	"log"
	"os"

	"pos-system/backend/internal/api"
	"pos-system/backend/internal/config"
	"pos-system/backend/internal/database"
)

func main() {
	// Load environment variables
	cfg := config.Load()

	// Initialize database
	db, err := database.Initialize(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Initialize router
	router := api.SetupRouter(db, cfg)

	// Get port from environment or use default
	port := os.Getenv("PORT")
	if port == "" {
		port = "8868"
	}

	log.Printf("Server starting on port %s", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
