package database

import (
	"fmt"
	"log"
	"net/url"
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
	// For Cloud SQL: mysql://user:password@/database?unix_socket=/cloudsql/CONNECTION_NAME
	// For GCP/AWS, this will be provided as environment variable

	// Log the received database URL (masked for security)
	maskedURL := databaseURL
	if strings.Contains(maskedURL, "@") {
		parts := strings.Split(maskedURL, "@")
		if len(parts) > 0 {
			userPass := strings.Split(parts[0], ":")
			if len(userPass) > 1 {
				maskedURL = userPass[0] + ":***@" + strings.Join(parts[1:], "@")
			}
		}
	}
	log.Printf("Parsing database URL: %s", maskedURL)

	// Convert mysql:// URL format to DSN format
	// Supports both: mysql://user:password@host:port/database and direct DSN format
	// Also supports Cloud SQL Unix socket: mysql://user:password@/database?unix_socket=/cloudsql/CONNECTION_NAME
	dsn := databaseURL
	if strings.HasPrefix(databaseURL, "mysql://") {
		// Remove mysql:// prefix
		dsn = strings.TrimPrefix(databaseURL, "mysql://")

		// Check if it's a Cloud SQL Unix socket connection
		if strings.Contains(dsn, "unix_socket=/cloudsql/") {
			// Format: user:password@/database?unix_socket=/cloudsql/CONNECTION_NAME
			// Parse it directly - GORM MySQL driver supports Unix socket in DSN
			// Convert to: user:password@unix(/cloudsql/CONNECTION_NAME)/database?charset=utf8mb4&parseTime=True&loc=Local
			parts := strings.Split(dsn, "@")
			if len(parts) == 2 {
				userPass := parts[0]
				// URL decode the password if it contains encoded characters
				userPassParts := strings.SplitN(userPass, ":", 2)
				if len(userPassParts) == 2 {
					decodedPassword, err := url.QueryUnescape(userPassParts[1])
					if err == nil {
						userPass = userPassParts[0] + ":" + decodedPassword
					}
				}
				rest := parts[1]

				// Extract database name and unix_socket
				dbAndSocket := strings.Split(rest, "?")
				if len(dbAndSocket) == 2 {
					dbName := strings.TrimPrefix(dbAndSocket[0], "/")
					queryParams := dbAndSocket[1]

					// Extract unix_socket value
					socketPath := ""
					for _, param := range strings.Split(queryParams, "&") {
						if strings.HasPrefix(param, "unix_socket=") {
							encodedPath := strings.TrimPrefix(param, "unix_socket=")
							// URL decode the socket path if needed
							decodedPath, err := url.QueryUnescape(encodedPath)
							if err == nil {
								socketPath = decodedPath
							} else {
								socketPath = encodedPath
							}
							break
						}
					}

					if socketPath != "" {
						// Build DSN for Unix socket: user:password@unix(/cloudsql/CONNECTION_NAME)/database?charset=utf8mb4&parseTime=True&loc=Local
						dsn = userPass + "@unix(" + socketPath + ")/" + dbName + "?charset=utf8mb4&parseTime=True&loc=Local"
						log.Printf("Using Cloud SQL Unix socket connection: %s", socketPath)
					} else {
						return nil, fmt.Errorf("invalid Cloud SQL connection: unix_socket parameter not found")
					}
				} else {
					return nil, fmt.Errorf("invalid Cloud SQL connection format: expected mysql://user:password@/database?unix_socket=/cloudsql/CONNECTION_NAME")
				}
			} else {
				return nil, fmt.Errorf("invalid Cloud SQL connection format: expected mysql://user:password@/database?unix_socket=/cloudsql/CONNECTION_NAME")
			}
		} else {
			// Regular TCP connection
			// Parse and format properly
			// Format: user:password@host:port/database
			parts := strings.Split(dsn, "@")
			if len(parts) == 2 {
				userPass := parts[0]
				// URL decode the password if it contains encoded characters
				userPassParts := strings.SplitN(userPass, ":", 2)
				if len(userPassParts) == 2 {
					decodedPassword, err := url.QueryUnescape(userPassParts[1])
					if err == nil {
						userPass = userPassParts[0] + ":" + decodedPassword
					}
				}
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

	// Add connection timeout parameters to DSN if not already present
	if !strings.Contains(dsn, "timeout") {
		if strings.Contains(dsn, "?") {
			dsn += "&timeout=10s&readTimeout=10s&writeTimeout=10s"
		} else {
			dsn += "?timeout=10s&readTimeout=10s&writeTimeout=10s"
		}
	}

	// Log the final DSN (masked)
	finalMaskedDSN := dsn
	if strings.Contains(finalMaskedDSN, "@") {
		parts := strings.Split(finalMaskedDSN, "@")
		if len(parts) > 0 {
			userPass := strings.Split(parts[0], ":")
			if len(userPass) > 1 {
				finalMaskedDSN = userPass[0] + ":***@" + strings.Join(parts[1:], "@")
			}
		}
	}
	log.Printf("Connecting with DSN: %s", finalMaskedDSN)

	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Test connection with timeout
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get database instance: %w", err)
	}

	// Set connection pool settings
	sqlDB.SetMaxIdleConns(5)
	sqlDB.SetMaxOpenConns(10)
	sqlDB.SetConnMaxLifetime(5 * 60 * 1000000000) // 5 minutes in nanoseconds

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
		&models.StocktakeDayStartRecord{},
		&models.UserActivityEvent{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	log.Println("Database connection established and migrations completed successfully")
	return db, nil
}
