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

	// Cloud Run can start multiple instances concurrently during deploy/traffic shifts.
	// Guard migrations with a DB advisory lock to avoid migration deadlocks across instances.
	var lockAcquired int
	if err := sqlDB.QueryRow("SELECT GET_LOCK('pos_system_migrate_lock', 30)").Scan(&lockAcquired); err != nil {
		return nil, fmt.Errorf("failed to acquire migration lock: %w", err)
	}
	if lockAcquired != 1 {
		return nil, fmt.Errorf("failed to acquire migration lock within timeout")
	}
	// Best-effort release even when later steps fail.
	defer func() {
		var released int
		if err := sqlDB.QueryRow("SELECT RELEASE_LOCK('pos_system_migrate_lock')").Scan(&released); err != nil {
			log.Printf("WARNING: failed to release migration lock: %v", err)
		}
	}()

	// Backfill empty ref_no before adding unique index (OC Number)
	_ = db.Exec("UPDATE wholesale_orders SET ref_no = CAST(id AS CHAR) WHERE ref_no = '' OR ref_no IS NULL").Error

	// Resolve duplicate ref_no so unique index can be applied (e.g. D123 → D123, D123.1, D123.2)
	var duplicates []struct {
		RefNo string
		Cnt   int64
	}
	db.Raw("SELECT ref_no, COUNT(*) as cnt FROM wholesale_orders GROUP BY ref_no HAVING cnt > 1").Scan(&duplicates)
	for _, d := range duplicates {
		var ids []uint
		db.Model(&models.WholesaleOrder{}).Where("ref_no = ?", d.RefNo).Order("id ASC").Pluck("id", &ids)
		for i, oid := range ids {
			newRef := d.RefNo
			if i > 0 {
				newRef = fmt.Sprintf("%s.%d", d.RefNo, i+1)
			}
			db.Exec("UPDATE wholesale_orders SET ref_no = ? WHERE id = ?", newRef, oid)
		}
	}

	// Auto-migrate all models
	log.Println("Running database migrations...")
	err = db.AutoMigrate(
		// Base tables
		&models.User{},
		&models.Store{},
		&models.Sector{},
		&models.ProductLine{},
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
		&models.StocktakeInventorySnapshot{},
		&models.StocktakeDayStartRecord{},
		&models.UserActivityEvent{},
		&models.WholesaleClient{},
		&models.WholesaleClientStore{},
		&models.WholesaleOrder{},
		&models.WholesaleOrderItem{},
		&models.WholesaleOrderDocument{},
		&models.CompanySettings{},
		&models.Shipment{},
		&models.ShipmentItem{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	// shipment_items: allow same order line on multiple store shipments (composite unique key).
	if err := db.Exec(
		"ALTER TABLE shipment_items ADD INDEX idx_shipment_items_wo_item (wholesale_order_item_id)",
	).Error; err != nil {
		log.Printf("shipment_items index migration (add wo_item index): %v", err)
	}
	if err := db.Exec("ALTER TABLE shipment_items DROP INDEX idx_shipment_wo_item").Error; err != nil {
		log.Printf("shipment_items index migration (drop old): %v", err)
	}
	if err := db.Exec(
		"ALTER TABLE shipment_items ADD UNIQUE INDEX idx_shipment_wo_item (shipment_id, wholesale_order_item_id)",
	).Error; err != nil {
		log.Printf("shipment_items index migration (add composite): %v", err)
	}

	// Align legacy archived rows with status-based soft delete (is_archived column may still exist in DB).
	_ = db.Exec(
		"UPDATE wholesale_orders SET status = ? WHERE COALESCE(is_archived, 0) = 1 AND status != ?",
		models.WholesaleOrderStatusDeleted,
		models.WholesaleOrderStatusDeleted,
	).Error

	// Convert effective_from/effective_to from datetime to date
	for _, stmt := range []string{
		"ALTER TABLE product_costs MODIFY effective_from DATE",
		"ALTER TABLE product_costs MODIFY effective_to DATE",
		"ALTER TABLE product_sector_discounts MODIFY effective_from DATE",
		"ALTER TABLE product_sector_discounts MODIFY effective_to DATE",
	} {
		if err := db.Exec(stmt).Error; err != nil {
			log.Printf("Column migration (may already be date): %v", err)
		}
	}

	log.Println("Database connection established and migrations completed successfully")

	_ = db.Exec(`
		UPDATE stores SET pos_receipt_settings_configured = 1
		WHERE pos_receipt_types IS NOT NULL
		  AND pos_receipt_types != ''
		  AND pos_receipt_types != '[]'
		  AND pos_auto_print_receipt_types IS NOT NULL
	`).Error

	_ = db.Exec(`
		UPDATE products SET sell_by_qty = 1
		WHERE (sell_by_qty = 0 OR sell_by_qty IS NULL)
		  AND (unit_type = 'quantity' OR can_sell_by_weight = 1)
	`).Error
	_ = db.Exec(`
		UPDATE products SET sell_by_weight = 1
		WHERE (sell_by_weight = 0 OR sell_by_weight IS NULL)
		  AND (can_sell_by_weight = 1 OR unit_type = 'weight')
	`).Error
	_ = db.Exec(`
		UPDATE products SET weight_barcode = barcode
		WHERE (weight_barcode IS NULL OR weight_barcode = '')
		  AND unit_type = 'weight'
		  AND barcode IS NOT NULL AND barcode != ''
	`).Error
	// Empty strings violate unique indexes; unused barcode columns must be NULL.
	_ = db.Exec(`UPDATE products SET weight_barcode = NULL WHERE weight_barcode = ''`).Error
	_ = db.Exec(`UPDATE products SET barcode = NULL WHERE barcode = ''`).Error
	_ = db.Exec(`
		UPDATE products SET sell_by_qty = 0
		WHERE unit_type = 'weight' AND can_sell_by_weight = 0 AND sell_by_weight = 1
	`).Error

	_ = db.Exec(`
		UPDATE products SET sell_by_qty = 0, sell_by_weight = 0, can_sell_by_weight = 0
		WHERE unit_type NOT IN ('quantity', 'weight') OR unit_type IS NULL OR unit_type = ''
	`).Error
	_ = db.Exec(`
		UPDATE products SET unit_type = 'quantity', sell_by_qty = 1, sell_by_weight = 0, can_sell_by_weight = 0
		WHERE unit_type = 'quantity' OR (unit_type IS NULL OR unit_type = '')
	`).Error
	_ = db.Exec(`
		UPDATE products SET unit_type = 'weight', sell_by_qty = 0, sell_by_weight = 1, can_sell_by_weight = 0
		WHERE unit_type = 'weight'
	`).Error
	_ = db.Exec(`
		UPDATE products SET sell_by_qty = 1, sell_by_weight = 0, can_sell_by_weight = 0
		WHERE unit_type = 'quantity' AND (sell_by_weight = 1 OR can_sell_by_weight = 1)
	`).Error
	_ = db.Exec(`
		UPDATE products SET sell_by_qty = 0, sell_by_weight = 1, can_sell_by_weight = 0
		WHERE unit_type = 'weight' AND sell_by_qty = 1
	`).Error

	if err := migrateProductLines(db); err != nil {
		log.Printf("WARNING: product line migration: %v", err)
	}
	clearAutoGeneratedVariantLabels(db)

	_ = db.Exec(
		"ALTER TABLE users MODIFY COLUMN role ENUM('management','pos_user','supervisor','hq_staff') NOT NULL",
	).Error

	backfillWholesalePaymentConfirmedAt(db)

	return db, nil
}
