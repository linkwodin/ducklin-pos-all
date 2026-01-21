package database

import (
	"fmt"
	"log"
	"strings"

	"pos-system/backend/internal/models"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Initialize creates a new database connection
func Initialize(databaseURL string) (*gorm.DB, error) {
	// Parse MySQL connection string
	// Format: mysql://user:password@host:port/database
	// For GCP/AWS, this will be provided as environment variable

	// Convert mysql:// URL format to DSN format
	// Supports both: mysql://user:password@host:port/database and direct DSN format
	dsn := databaseURL
	if strings.HasPrefix(databaseURL, "mysql://") {
		// Remove mysql:// prefix
		dsn = strings.TrimPrefix(databaseURL, "mysql://")

		// Parse and format properly
		// Format: user:password@host:port/database
		parts := strings.Split(dsn, "@")
		if len(parts) == 2 {
			userPass := parts[0]
			hostDB := parts[1]
			hostParts := strings.Split(hostDB, "/")
			if len(hostParts) == 2 {
				hostPort := hostParts[0]
				dbName := hostParts[1]

				// Add default port if not specified
				if !strings.Contains(hostPort, ":") {
					hostPort += ":3306"
				}

				// Build DSN: user:password@tcp(host:port)/database?charset=utf8mb4&parseTime=True&loc=Local
				dsn = userPass + "@tcp(" + hostPort + ")/" + dbName + "?charset=utf8mb4&parseTime=True&loc=Local"
			} else {
				return nil, fmt.Errorf("invalid database URL format: missing database name. Expected: mysql://user:password@host:port/database")
			}
		} else {
			return nil, fmt.Errorf("invalid database URL format: expected mysql://user:password@host:port/database")
		}
	} else if !strings.Contains(dsn, "@tcp(") {
		// If it's not a mysql:// URL and doesn't look like a DSN, it might be a simple format
		// Try to parse it as user:password@host:port/database (without mysql://)
		parts := strings.Split(dsn, "@")
		if len(parts) == 2 {
			userPass := parts[0]
			hostDB := parts[1]
			hostParts := strings.Split(hostDB, "/")
			if len(hostParts) == 2 {
				hostPort := hostParts[0]
				dbName := hostParts[1]
				if !strings.Contains(hostPort, ":") {
					hostPort += ":3306"
				}
				dsn = userPass + "@tcp(" + hostPort + ")/" + dbName + "?charset=utf8mb4&parseTime=True&loc=Local"
			}
		}
	}

	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Test connection
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get database instance: %w", err)
	}

	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Auto-migrate all models
	log.Println("Running database migrations...")
	err = db.AutoMigrate(
		// Base tables
		&models.User{},
		&models.Store{},
		&models.Sector{},
		&models.Product{},
		// Dependent tables
		&models.POSDevice{},
		&models.ProductCost{},
		&models.ProductSectorDiscount{},
		&models.Stock{},
		&models.RestockOrder{},
		&models.RestockOrderItem{},
		&models.Order{},
		&models.OrderItem{},
		&models.PriceHistory{},
		&models.CurrencyRate{},
		&models.AuditLog{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	log.Println("Database connection established and migrations completed successfully")
	return db, nil
}
