# POS System Backend

Go backend API for the POS management system.

## Prerequisites

- Go 1.21 or higher
- MySQL 8.0 or higher
- Docker (optional, for containerized deployment)

## Setup

1. **Install dependencies:**
   ```bash
   go mod download
   ```

2. **Set up environment variables:**
   Create a `.env` file in the backend directory:
   ```env
   DATABASE_URL=mysql://username:password@localhost:3306/pos_system
   JWT_SECRET=your-secret-key-here
   JWT_EXPIRATION=24
   PORT=8080
   ENVIRONMENT=development
   STORAGE_PROVIDER=local
   UPLOAD_DIR=./uploads
   BASE_URL=http://localhost:8868
   ```
   
   **Note**: For development, you can use `STORAGE_PROVIDER=local` (or leave it unset). 
   Product images can be uploaded directly (stored in `UPLOAD_DIR`). 
   Images are automatically resized to a maximum of 1920x1920 pixels (maintaining aspect ratio) 
   and converted to JPEG format for optimal storage. There is no file size limit - large images 
   will be automatically resized. Supported formats: JPEG, PNG, GIF.
   GCP/AWS buckets are only needed for production deployments.

3. **Create the database (if it doesn't exist):**
   ```bash
   mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS pos_system;"
   ```
   
   **Note**: Tables will be automatically created by GORM on first run. 
   You can also manually run the schema if preferred: `mysql -u root -p pos_system < ../database/schema.sql`

4. **Run the server:**
   ```bash
   go run main.go
   ```

   The server will start on port 8080 by default.

## Configuration

The application uses environment variables for configuration. See `internal/config/config.go` for all available options.

### Required Environment Variables

- `DATABASE_URL`: MySQL connection string
- `JWT_SECRET`: Secret key for JWT token signing

### Optional Environment Variables

- `JWT_EXPIRATION`: JWT token expiration in hours (default: 24)
- `PORT`: Server port (default: 8080)
- `ENVIRONMENT`: Environment mode - "development" or "production" (default: "development")
- `STORAGE_PROVIDER`: Storage provider - "local", "gcp", or "aws" (default: "local")
  - **Development**: Use "local" - no cloud storage needed, just provide image URLs
  - **Production**: Use "gcp" or "aws" for cloud storage
- `GCP_BUCKET_NAME`: GCP bucket name (only needed if STORAGE_PROVIDER=gcp)
- `AWS_S3_BUCKET`: AWS S3 bucket name (only needed if STORAGE_PROVIDER=aws)
- `AWS_ACCESS_KEY`: AWS access key (only needed if STORAGE_PROVIDER=aws)
- `AWS_SECRET_KEY`: AWS secret key (only needed if STORAGE_PROVIDER=aws)
- `AWS_REGION`: AWS region (default: "us-east-1")
- `UPLOAD_DIR`: Directory for local file uploads (default: "./uploads")
- `BASE_URL`: Base URL for serving uploaded files (default: "http://localhost:8868")

## API Endpoints

### Public Endpoints

- `POST /api/v1/auth/login` - Username/password login
- `POST /api/v1/auth/pin-login` - PIN-based login
- `POST /api/v1/device/register` - Register POS device
- `GET /api/v1/device/:device_code/users` - Get users for device
- `GET /api/v1/device/:device_code/products` - Get products for device

### Protected Endpoints (Require JWT Token)

#### Products
- `GET /api/v1/products` - List products
- `GET /api/v1/products/:id` - Get product details
- `POST /api/v1/products` - Create product
- `PUT /api/v1/products/:id` - Update product
- `DELETE /api/v1/products/:id` - Deactivate product
- `POST /api/v1/products/:id/cost` - Set product cost
- `GET /api/v1/products/:id/price-history` - Get price history
- `POST /api/v1/products/:product_id/discounts/:sector_id` - Set discount
- `GET /api/v1/products/:product_id/discounts` - Get discounts

#### Sectors
- `GET /api/v1/sectors` - List sectors
- `POST /api/v1/sectors` - Create sector
- `PUT /api/v1/sectors/:id` - Update sector
- `DELETE /api/v1/sectors/:id` - Deactivate sector

#### Stock
- `GET /api/v1/stock` - List stock
- `GET /api/v1/stock/:store_id` - Get store stock
- `GET /api/v1/stock/low-stock` - Get low stock items
- `PUT /api/v1/stock/:product_id/:store_id` - Update stock

#### Re-stock Orders
- `GET /api/v1/restock-orders` - List re-stock orders
- `POST /api/v1/restock-orders` - Create re-stock order
- `PUT /api/v1/restock-orders/:id/tracking` - Update tracking number
- `PUT /api/v1/restock-orders/:id/receive` - Mark order as received

#### Users
- `GET /api/v1/users` - List users
- `GET /api/v1/users/:id` - Get user
- `POST /api/v1/users` - Create user
- `PUT /api/v1/users/:id` - Update user
- `PUT /api/v1/users/:id/pin` - Update PIN
- `PUT /api/v1/users/:id/icon` - Update icon

#### Stores
- `GET /api/v1/stores` - List stores
- `POST /api/v1/stores` - Create store

#### Catalogs
- `GET /api/v1/catalogs/:sector_id` - Generate catalog
- `GET /api/v1/catalogs/:sector_id/download` - Download PDF catalog

## Development

### Running Tests

```bash
go test ./...
```

### Building

```bash
go build -o pos-backend main.go
```

## Deployment

### Docker

1. **Build the image:**
   ```bash
   docker build -t pos-backend .
   ```

2. **Run the container:**
   ```bash
   docker run -p 8080:8080 --env-file .env pos-backend
   ```

### Google Cloud Platform

1. **Build and push:**
   ```bash
   gcloud builds submit --config cloudbuild.yaml
   ```

2. **Or deploy manually:**
   ```bash
   docker build -t gcr.io/PROJECT_ID/pos-backend .
   docker push gcr.io/PROJECT_ID/pos-backend
   gcloud run deploy pos-backend --image gcr.io/PROJECT_ID/pos-backend
   ```

### AWS Lambda (Serverless)

1. **Install Serverless Framework:**
   ```bash
   npm install -g serverless
   ```

2. **Deploy:**
   ```bash
   serverless deploy
   ```

## Project Structure

```
backend/
├── internal/
│   ├── api/          # HTTP handlers
│   ├── config/       # Configuration
│   ├── database/     # Database connection
│   ├── models/       # Data models
│   └── utils/        # Utility functions
├── main.go           # Application entry point
├── go.mod            # Go dependencies
└── Dockerfile        # Docker configuration
```

## Database Auto-Migration

GORM automatically creates and migrates database tables on startup. You only need to:

1. Create the database: `CREATE DATABASE pos_system;`
2. Set the `DATABASE_URL` in your `.env` file
3. Run the server - tables will be created automatically

The schema will be kept in sync with your models. If you prefer to use the SQL schema file instead, you can still run `mysql -u root -p pos_system < ../database/schema.sql` manually.

## Development Mode

For local development, you **do not need** GCP or AWS buckets:

1. Set `STORAGE_PROVIDER=local` (or leave it unset - defaults to "local")
2. Product images can be:
   - **Uploaded directly** via the web interface (stored in `UPLOAD_DIR`, served at `/uploads/`)
   - URLs to external images (e.g., `https://example.com/image.jpg`)
   - Any publicly accessible image URL

The backend supports both file uploads (stored locally) and image URLs. Uploaded images are automatically served via the `/uploads/` endpoint. Cloud storage (GCP/AWS) is only needed for production deployments with distributed systems.

## Troubleshooting

### Database Connection Issues

- Verify MySQL is running
- Check DATABASE_URL format: `mysql://user:password@host:port/database`
- Ensure database exists and user has permissions

### JWT Token Issues

- Verify JWT_SECRET is set
- Check token expiration time
- Ensure Authorization header format: `Bearer <token>`

### Storage Issues

- **Development**: No storage setup needed - just use `STORAGE_PROVIDER=local`
- **Production**: Ensure GCP/AWS credentials are properly configured if using cloud storage

### Build Issues

- Ensure Go 1.21+ is installed
- Run `go mod download` to fetch dependencies
- Check for missing environment variables
- Note: The `cloud.google.com/go/storage` dependency in go.mod is optional and only needed if you implement GCP storage uploads

