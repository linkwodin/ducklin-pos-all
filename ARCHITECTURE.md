# POS System Architecture

## Overview

This is a comprehensive Point of Sale system with backend management capabilities, designed for multi-store operations with offline support.

## System Components

### 1. Backend Management System (Go)

**Location:** `backend/`

**Technology Stack:**
- Go 1.21+
- Gin Web Framework
- GORM (ORM)
- MySQL Database
- JWT Authentication
- PDF Generation (gofpdf)

**Key Features:**
- RESTful API
- Product management with cost calculation (based on Excel structure)
- Sector-based pricing and discounts
- Multi-store stock management
- Re-stock order tracking
- Price history tracking
- PDF catalog generation
- User and device management

**API Structure:**
- `/api/v1/auth/*` - Authentication endpoints
- `/api/v1/products/*` - Product management
- `/api/v1/sectors/*` - Sector management
- `/api/v1/stock/*` - Stock management
- `/api/v1/orders/*` - Order processing
- `/api/v1/users/*` - User management
- `/api/v1/device/*` - Device registration and data sync
- `/api/v1/catalogs/*` - PDF catalog generation

### 2. POS Application (Flutter)

**Location:** `frontend/`

**Technology Stack:**
- Flutter 3.0+
- Provider (State Management)
- SQLite with Encryption (Offline Storage)
- Dio (HTTP Client)
- Mobile Scanner (Barcode Scanning)
- QR Flutter (QR Code Generation)
- Printing (Receipt Printing)

**Key Features:**
- Cross-platform (Windows, macOS, Linux, iOS, Android)
- Offline-first architecture
- Encrypted local database
- Device code authentication
- PIN and username/password login
- Barcode scanning
- Product search and filtering
- Weight-based products
- Cart management
- Order processing with QR codes
- Receipt printing
- Stock synchronization

**Screen Structure:**
- `LoginScreen` - Initial login/device registration
- `UserSelectionScreen` - User icon selection
- `PINLoginScreen` - PIN entry
- `UsernameLoginScreen` - Username/password login
- `POSScreen` - Main POS interface
- `ProductSelectionScreen` - Product browsing and selection
- `CartScreen` - Shopping cart
- `CheckoutScreen` - Order processing and receipt
- `BarcodeScannerScreen` - Barcode scanning
- `WeightInputDialog` - Weight input for weight-based products

### 3. Database Schema

**Location:** `database/schema.sql`

**Tables:**
- `users` - System users (management, POS users, supervisors)
- `stores` - Physical store locations
- `pos_devices` - Registered POS devices
- `sectors` - Customer sectors (wholesaler, restaurant, etc.)
- `products` - Product catalog
- `product_costs` - Product cost configurations (with history)
- `product_sector_discounts` - Sector-specific discounts
- `stock` - Inventory per store
- `restock_orders` - Re-stock order tracking
- `restock_order_items` - Re-stock order line items
- `orders` - POS orders
- `order_items` - Order line items
- `price_history` - Price trend data
- `audit_logs` - System audit trail

## Data Flow

### Product Cost Calculation

Based on the Excel structure provided:

1. **Purchasing Cost Calculation:**
   - Purchasing Cost (GBP) = Purchasing Cost (HKD) / Exchange Rate
   - Cost Buffer = Purchasing Cost × Buffer %
   - Adjusted Purchasing Cost = Purchasing Cost + Cost Buffer

2. **Freight Calculation:**
   - Weight (kg) = (Weight (g) × (1 + Weight Buffer %)) / 1000
   - Freight (HKD) = (Freight Rate × Weight) + Freight Buffer
   - Freight (GBP) = Freight (HKD) / Exchange Rate

3. **Final Cost:**
   - Wholesale Cost = Adjusted Purchasing Cost + Freight + Import Duty + Packaging

4. **Sector Pricing:**
   - Final Price = Wholesale Cost × (1 - Discount %)

### Order Processing Flow

1. **Product Selection:**
   - User scans barcode or selects product
   - For weight-based products, user enters weight
   - Product added to cart with calculated price

2. **Checkout:**
   - Order created with items
   - QR code generated with order details
   - Order saved locally (offline support)

3. **Payment:**
   - Payment processed externally
   - Order marked as paid

4. **Completion:**
   - Order marked as complete
   - Stock reduced automatically

### Sync Flow

1. **Device Registration:**
   - POS device generates/retrieves device code
   - Device registered with store assignment

2. **Data Sync:**
   - POS requests users and products for device
   - Data downloaded and stored locally (encrypted)
   - Periodic sync for updates

3. **Order Sync:**
   - Orders created offline are queued
   - When online, orders synced to server
   - Stock updates propagated

## Security

### Authentication
- JWT tokens for API authentication
- PIN hashing with bcrypt
- Password hashing with bcrypt
- Device code validation

### Data Protection
- Encrypted SQLite database (SQLCipher)
- HTTPS for API communication
- Secure token storage

## Deployment

### Backend Options

1. **Google Cloud Platform:**
   - Cloud Run (serverless containers)
   - Cloud SQL (MySQL)
   - Cloud Storage (product images)

2. **AWS:**
   - Lambda (serverless functions)
   - RDS (MySQL)
   - S3 (product images)

3. **Traditional:**
   - Docker containers
   - Self-hosted MySQL
   - Local file storage or cloud storage

### Frontend Distribution

- **Windows:** Executable installer
- **macOS:** DMG or App Store
- **Linux:** AppImage or DEB/RPM packages
- **iOS:** App Store
- **Android:** APK or Play Store

## Future Enhancements

1. **Image Storage Integration:**
   - GCP Cloud Storage upload/download
   - AWS S3 upload/download
   - Image optimization and CDN

2. **Advanced Reporting:**
   - Sales analytics
   - Inventory reports
   - Price trend visualization

3. **Multi-language Support:**
   - i18n implementation
   - Language selection

4. **Advanced Features:**
   - Customer management
   - Loyalty programs
   - Promotions and coupons
   - Advanced inventory management

## Notes

- The cost calculation follows the Excel structure provided
- Offline support ensures POS can operate without internet
- Device code can be generated from device identifiers or manually assigned
- Image storage integration structure is in place but needs implementation based on chosen provider
- PDF catalog generation is basic and can be enhanced with more formatting

