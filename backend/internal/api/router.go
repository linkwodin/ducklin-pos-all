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
	productLineHandler := NewProductLineHandler(db, productHandler)
	sectorHandler := NewSectorHandler(db)
	categoryHandler := NewCategoryHandler(db)
	stockHandler := NewStockHandler(db)
	orderHandler := NewOrderHandler(db, cfg)
	userHandler := NewUserHandler(db, cfg)
	deviceHandler := NewDeviceHandler(db)
	catalogHandler := NewCatalogHandler(db, cfg)
	currencyHandler := NewCurrencyHandler(db)
	auditHandler := NewAuditHandler(db)
	stocktakeHandler := NewStocktakeHandler(db)
	wholesaleOrderHandler := NewWholesaleOrderHandler(db, cfg)
	wholesaleClientHandler := NewWholesaleClientHandler(db)
	settingsHandler := NewSettingsHandler(db, cfg)

	// Public routes
	public := router.Group("/api/v1")
	{
		public.POST("/auth/login", authHandler.Login)
		public.POST("/auth/pin-login", PosModuleEnabledMiddleware(db), authHandler.PINLogin)
		public.POST("/auth/refresh", authHandler.Refresh)
		public.POST("/device/register", PosModuleEnabledMiddleware(db), deviceHandler.RegisterDevice)
		public.GET("/device/:device_code/users", deviceHandler.GetUsersForDevice)
		public.GET("/device/:device_code/products", deviceHandler.GetProductsForDevice)
		public.GET("/device/:device_code/info", deviceHandler.GetDeviceInfo)
		public.GET("/public/company-branding", settingsHandler.GetPublicCompanyBranding)
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

		// Product lines (catalog grouping; variants are products)
		protected.GET("/product-lines", productLineHandler.List)
		protected.GET("/product-lines/:id", productLineHandler.Get)
		protected.POST("/product-lines", productLineHandler.Create)
		protected.PUT("/product-lines/:id", productLineHandler.Update)
		protected.DELETE("/product-lines/:id", productLineHandler.Delete)

		// Sectors
		protected.GET("/sectors", sectorHandler.ListSectors)
		protected.POST("/sectors", sectorHandler.CreateSector)
		protected.PUT("/sectors/:id", sectorHandler.UpdateSector)
		protected.DELETE("/sectors/:id", sectorHandler.DeleteSector)

		// Categories
		protected.GET("/categories", categoryHandler.ListCategories)
		protected.POST("/categories", categoryHandler.CreateCategory)
		protected.POST("/categories/normalize", categoryHandler.NormalizeCategories)
		protected.DELETE("/categories/:name", categoryHandler.DeleteCategory)
		protected.PUT("/categories/:name/rename", categoryHandler.RenameCategory)

		// Product-Sector Discounts
		protected.POST("/products/:id/discounts/:sector_id", productHandler.SetDiscount)
		protected.GET("/products/:id/discounts", productHandler.GetDiscounts)

		// Stock
		protected.GET("/stock", stockHandler.ListStock)
		protected.GET("/stock/report", stockHandler.GetStockReport)
		protected.GET("/stock/by-product/:product_id", stockHandler.GetProductStockAssignments)
		protected.POST("/stock/assign", stockHandler.AssignProductsToStore)
		protected.POST("/stock/set-assignments", stockHandler.SetStockAssignments)
		protected.POST("/stock/unassign", stockHandler.UnassignProductsFromStore)
		protected.GET("/stock/:store_id", stockHandler.GetStoreStock)
		protected.GET("/stock/low-stock", stockHandler.GetLowStock)
		protected.GET("/stock/incoming", stockHandler.GetIncomingStock) // Get on-the-way stock
		protected.PUT("/stock/:product_id/:store_id", stockHandler.UpdateStock)
		protected.POST("/stock/:product_id/:store_id/convert", stockHandler.ConvertStockInventory)

		// Audit Logs
		protected.GET("/audit/stock", auditHandler.GetStockAuditLogs)
		protected.GET("/audit/order", auditHandler.GetOrderAuditLogs)

		// Stocktake day-start (record first login / done / skipped; list for management)
		protected.POST("/stocktake-day-start", stocktakeHandler.RecordFirstLoginOrResult)
		protected.GET("/stocktake-day-start", stocktakeHandler.ListDayStartRecords)
		// User activity events (for timetable: login, logout, stocktake)
		protected.GET("/user-activity-events", stocktakeHandler.ListUserActivityEvents)

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
		protected.PUT("/users/:id/work-settings", userHandler.UpdateUserWorkSettings)

		// Devices (protected endpoints for management)
		protected.GET("/devices", deviceHandler.ListDevices)
		protected.GET("/devices/:id", deviceHandler.GetDevice)
		protected.PUT("/device/configure", deviceHandler.ConfigureDevice) // add or update device store (management only)
		protected.GET("/stores/:store_id/devices", deviceHandler.ListDevicesByStore)

		// Stores
		protected.GET("/stores", stockHandler.ListStores)
		protected.GET("/stores/:store_id", stockHandler.GetStore)
		protected.POST("/stores", stockHandler.CreateStore)
		protected.PUT("/stores/:store_id", stockHandler.UpdateStore)

		// Catalogs
		protected.GET("/catalogs/:sector_id", catalogHandler.GenerateCatalog)
		protected.GET("/catalogs/:sector_id/download", catalogHandler.DownloadCatalog)

		// Company settings (for PDF/document company address and contact)
		protected.GET("/settings/company", settingsHandler.GetCompanySettings)
		protected.PUT("/settings/company", settingsHandler.UpdateCompanySettings)
		protected.POST("/settings/company/logo", settingsHandler.UploadCompanyLogo)
		protected.POST("/settings/company/logo/copy", settingsHandler.CopyCompanyLogo)
		protected.POST("/settings/company/logo/all", settingsHandler.UploadCompanyLogoAll)
		protected.POST("/settings/company/logo/:type", settingsHandler.UploadCompanyLogoByType)
		protected.GET("/settings/system-info", settingsHandler.GetSystemInfo)
		protected.POST("/settings/company/wholesale/toggle", settingsHandler.ToggleWholesaleOrder)
		protected.POST("/settings/company/pos/toggle", settingsHandler.TogglePosModule)

		wholesale := protected.Group("", WholesaleOrderEnabledMiddleware(db))
		{
			wholesale.GET("/stock/wholesale-ship-from", stockHandler.GetWholesaleShipFromMap)
			wholesale.GET("/wholesale-clients", wholesaleClientHandler.List)
			wholesale.GET("/wholesale-clients/:id", wholesaleClientHandler.Get)
			wholesale.POST("/wholesale-clients", wholesaleClientHandler.Create)
			wholesale.PUT("/wholesale-clients/:id", wholesaleClientHandler.Update)
			wholesale.DELETE("/wholesale-clients/:id", wholesaleClientHandler.Delete)
			wholesale.POST("/wholesale-clients/:id/stores", wholesaleClientHandler.CreateStore)
			wholesale.PUT("/wholesale-clients/:id/stores/:store_id", wholesaleClientHandler.UpdateStore)
			wholesale.DELETE("/wholesale-clients/:id/stores/:store_id", wholesaleClientHandler.DeleteStore)
			wholesale.POST("/wholesale-orders", wholesaleOrderHandler.Create)
			wholesale.GET("/wholesale-orders", wholesaleOrderHandler.List)
			wholesale.GET("/wholesale-orders/recent-order-channels", wholesaleOrderHandler.RecentOrderChannels)
			wholesale.GET("/wholesale-orders/stats/revenue-summary", wholesaleOrderHandler.GetWholesaleRevenueSummaryStats)
			wholesale.GET("/wholesale-orders/stats/product-sales", wholesaleOrderHandler.GetWholesaleProductSalesStats)
			wholesale.GET("/wholesale-orders/stats/client-sales", wholesaleOrderHandler.GetWholesaleClientSalesStats)
			wholesale.POST("/wholesale-orders/test-email", wholesaleOrderHandler.SendTestEmail)
			wholesale.POST("/wholesale-orders/bulk-attachments-zip-email", wholesaleOrderHandler.BulkAttachmentsZipEmail)
			wholesale.GET("/wholesale-orders/:id", wholesaleOrderHandler.Get)
			wholesale.PUT("/wholesale-orders/:id", wholesaleOrderHandler.Update)
			wholesale.PUT("/wholesale-orders/:id/approve", wholesaleOrderHandler.Approve)
			wholesale.GET("/wholesale-orders/:id/endorse-allocation-preview", wholesaleOrderHandler.EndorseAllocationPreview)
			wholesale.PUT("/wholesale-orders/:id/reject", wholesaleOrderHandler.Reject)
			wholesale.PUT("/wholesale-orders/:id/archive", wholesaleOrderHandler.Archive)
			wholesale.PUT("/wholesale-orders/:id/resubmit", wholesaleOrderHandler.Resubmit)
			wholesale.PUT("/wholesale-orders/:id/assign", wholesaleOrderHandler.AssignStores)
			wholesale.PUT("/wholesale-orders/:id/unassign", wholesaleOrderHandler.UnassignStores)
			wholesale.PUT("/wholesale-orders/:id/assign-by-defaults", wholesaleOrderHandler.AssignByDefaults)
			wholesale.PUT("/wholesale-orders/:id/complete-assignment", wholesaleOrderHandler.CompleteAssignment)
			wholesale.POST("/wholesale-orders/:id/regenerate-order-confirmation", wholesaleOrderHandler.RegenerateOrderConfirmation)
			wholesale.POST("/wholesale-orders/:id/generate-invoice", wholesaleOrderHandler.GenerateInvoice)
			wholesale.PATCH("/wholesale-orders/:id/invoice-sent", wholesaleOrderHandler.SetInvoiceSentAt)
			wholesale.GET("/wholesale-orders/:id/audit-logs", wholesaleOrderHandler.GetAuditLogs)
			wholesale.POST("/wholesale-orders/:id/audit-logs/:auditLogId/restore-document", wholesaleOrderHandler.RestoreDocumentFromAudit)
			wholesale.POST("/wholesale-orders/:id/email", wholesaleOrderHandler.EmailOrder)
			wholesale.POST("/wholesale-orders/:id/skip-email", wholesaleOrderHandler.SkipWholesaleOrderEmail)
			wholesale.POST("/wholesale-orders/:id/email-document", wholesaleOrderHandler.EmailDocument)
			wholesale.POST("/wholesale-orders/:id/po-attachments", wholesaleOrderHandler.UploadPOAttachments)
			wholesale.DELETE("/wholesale-orders/:id/documents/:docId", wholesaleOrderHandler.DeletePOAttachment)
			wholesale.GET("/wholesale-orders/:id/documents/:docId/download", wholesaleOrderHandler.DownloadDocument)
			wholesale.GET("/wholesale-orders/:id/legacy-payment-proof/download", wholesaleOrderHandler.DownloadLegacyPaymentProof)
			wholesale.POST("/wholesale-orders/:id/upload-payment-proof", wholesaleOrderHandler.UploadPaymentProof)
			wholesale.POST("/wholesale-orders/:id/confirm-payment", wholesaleOrderHandler.ConfirmPayment)
			wholesale.GET("/shipments", wholesaleOrderHandler.ListShipments)
			wholesale.GET("/shipments/:id", wholesaleOrderHandler.GetShipment)
			wholesale.PUT("/shipments/:id", wholesaleOrderHandler.UpdateShipment)
			wholesale.PATCH("/shipments/:id/status", wholesaleOrderHandler.UpdateShipmentStatus)
			wholesale.POST("/shipments/:id/start-shipment", wholesaleOrderHandler.StartShipment)
			wholesale.POST("/shipments/:id/upload-signed-delivery-note", wholesaleOrderHandler.UploadSignedDeliveryNote)
			wholesale.POST("/shipments/:id/complete-packing", wholesaleOrderHandler.CompletePacking)
			wholesale.POST("/shipments/:id/regenerate-delivery-note", wholesaleOrderHandler.RegenerateDeliveryNote)
			wholesale.PUT("/shipments/:id/case-qty", wholesaleOrderHandler.UpdateShipmentCaseQty)
		}

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
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, Pragma, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")

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
