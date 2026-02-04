package api

import (
	"pos-system/backend/internal/config"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// BuildDate is set at compile time using -ldflags
// Example: go build -ldflags "-X 'pos-system/backend/internal/api.BuildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
var BuildDate string

// SetupRouter configures and returns the Gin router
func SetupRouter(db *gorm.DB, cfg *config.Config) *gin.Engine {
	router := gin.Default()

	// CORS middleware
	router.Use(corsMiddleware())

	// Serve uploaded files statically
	if cfg.UploadDir != "" {
		router.Static("/uploads", cfg.UploadDir)
	} else {
		router.Static("/uploads", "./uploads")
	}

	// Health check
	router.GET("/health", healthCheck)

	// Initialize handlers
	authHandler := NewAuthHandler(db, cfg)
	productHandler := NewProductHandler(db, cfg)
	sectorHandler := NewSectorHandler(db)
	categoryHandler := NewCategoryHandler(db)
	stockHandler := NewStockHandler(db)
	orderHandler := NewOrderHandler(db, cfg)
	userHandler := NewUserHandler(db, cfg)
	deviceHandler := NewDeviceHandler(db)
	catalogHandler := NewCatalogHandler(db, cfg)
	currencyHandler := NewCurrencyHandler(db)
	auditHandler := NewAuditHandler(db)

	// Public routes
	public := router.Group("/api/v1")
	{
		public.POST("/auth/login", authHandler.Login)
		public.POST("/auth/pin-login", authHandler.PINLogin)
		public.POST("/device/register", deviceHandler.RegisterDevice)
		public.GET("/device/:device_code/users", deviceHandler.GetUsersForDevice)
		public.GET("/device/:device_code/products", deviceHandler.GetProductsForDevice)
	}

	// Protected routes
	protected := router.Group("/api/v1")
	protected.Use(authMiddleware(cfg.JWTSecret))
	{
		// Products
		protected.GET("/products", productHandler.ListProducts)
		protected.GET("/products/:id", productHandler.GetProduct)
		protected.POST("/products", productHandler.CreateProduct)
		protected.PUT("/products/:id", productHandler.UpdateProduct)
		protected.DELETE("/products/:id", productHandler.DeleteProduct)
		protected.POST("/products/:id/cost", productHandler.SetProductCost)
		protected.PUT("/products/:id/cost", productHandler.UpdateProductCostSimple)
		protected.GET("/products/:id/price-history", productHandler.GetPriceHistory)
		protected.POST("/products/import-excel", productHandler.ImportProductsFromExcel)

		// Sectors
		protected.GET("/sectors", sectorHandler.ListSectors)
		protected.POST("/sectors", sectorHandler.CreateSector)
		protected.PUT("/sectors/:id", sectorHandler.UpdateSector)
		protected.DELETE("/sectors/:id", sectorHandler.DeleteSector)

		// Categories
		protected.GET("/categories", categoryHandler.ListCategories)
		protected.POST("/categories", categoryHandler.CreateCategory)
		protected.DELETE("/categories/:name", categoryHandler.DeleteCategory)
		protected.PUT("/categories/:name/rename", categoryHandler.RenameCategory)

		// Product-Sector Discounts
		protected.POST("/products/:id/discounts/:sector_id", productHandler.SetDiscount)
		protected.GET("/products/:id/discounts", productHandler.GetDiscounts)

		// Stock
		protected.GET("/stock", stockHandler.ListStock)
		protected.GET("/stock/:store_id", stockHandler.GetStoreStock)
		protected.GET("/stock/low-stock", stockHandler.GetLowStock)
		protected.GET("/stock/incoming", stockHandler.GetIncomingStock) // Get on-the-way stock
		protected.PUT("/stock/:product_id/:store_id", stockHandler.UpdateStock)

		// Audit Logs
		protected.GET("/audit/stock", auditHandler.GetStockAuditLogs)
		protected.GET("/audit/order", auditHandler.GetOrderAuditLogs)

		// Re-stock Orders
		protected.GET("/restock-orders", stockHandler.ListRestockOrders)
		protected.POST("/restock-orders", stockHandler.CreateRestockOrder)
		protected.PUT("/restock-orders/:id/tracking", stockHandler.UpdateTrackingNumber)
		protected.PUT("/restock-orders/:id/receive", stockHandler.ReceiveRestockOrder)

		// Orders
		protected.GET("/orders", orderHandler.ListOrders)
		protected.GET("/orders/stats/revenue", orderHandler.GetDailyRevenueStats)
		protected.GET("/orders/stats/product-sales", orderHandler.GetDailyProductSalesStats)
		protected.POST("/orders", orderHandler.CreateOrder)
		protected.GET("/orders/:id", orderHandler.GetOrder)
		protected.PUT("/orders/:id/pay", orderHandler.MarkPaid)
		protected.PUT("/orders/:id/complete", orderHandler.MarkComplete)
		protected.PUT("/orders/:id/cancel", orderHandler.MarkCancelled)
		protected.PUT("/orders/pickup/:order_number", orderHandler.MarkPickedUp)

		// Users
		protected.GET("/users", userHandler.ListUsers)
		protected.GET("/users/:id", userHandler.GetUser)
		protected.POST("/users", userHandler.CreateUser)
		protected.PUT("/users/:id", userHandler.UpdateUser)
		protected.PUT("/users/:id/pin", userHandler.UpdatePIN)
		protected.PUT("/users/:id/icon", userHandler.UpdateIcon)
		protected.PUT("/users/:id/stores", userHandler.UpdateUserStores)

		// Devices (protected endpoints for management)
		protected.GET("/devices", deviceHandler.ListDevices)
		protected.GET("/devices/:id", deviceHandler.GetDevice)
		protected.GET("/stores/:store_id/devices", deviceHandler.ListDevicesByStore)

		// Stores
		protected.GET("/stores", stockHandler.ListStores)
		protected.POST("/stores", stockHandler.CreateStore)

		// Catalogs
		protected.GET("/catalogs/:sector_id", catalogHandler.GenerateCatalog)
		protected.GET("/catalogs/:sector_id/download", catalogHandler.DownloadCatalog)

		// Currency Rates
		protected.GET("/currency-rates", currencyHandler.ListCurrencyRates)
		protected.GET("/currency-rates/:code", currencyHandler.GetCurrencyRate)
		protected.POST("/currency-rates", currencyHandler.CreateCurrencyRate)
		protected.PUT("/currency-rates/:code", currencyHandler.UpdateCurrencyRate)
		protected.PUT("/currency-rates/:code/pin", currencyHandler.TogglePinCurrencyRate)
		protected.DELETE("/currency-rates/:code", currencyHandler.DeleteCurrencyRate)
		protected.POST("/currency-rates/sync", currencyHandler.SyncCurrencyRates)
	}

	return router
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

func healthCheck(c *gin.Context) {
	// Health check doesn't require database - just verify server is running
	response := gin.H{
		"status":  "ok",
		"service": "pos-backend",
	}

	// Add build date if available
	if BuildDate != "" {
		response["build_date"] = BuildDate
	}

	c.JSON(200, response)
}
