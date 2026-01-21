# POS System Setup Guide

## Prerequisites

### Backend
- Go 1.21 or higher
- MySQL 8.0 or higher
- Docker (optional, for containerized deployment)

### Frontend
- Flutter SDK 3.0 or higher
- Dart 3.0 or higher

## Backend Setup

1. **Navigate to backend directory:**
   ```bash
   cd backend
   ```

2. **Install dependencies:**
   ```bash
   go mod download
   ```

3. **Set up environment variables:**
   Create a `.env` file in the backend directory:
   ```env
   DATABASE_URL=mysql://username:password@localhost:3306/pos_system
   JWT_SECRET=your-secret-key-here
   ENVIRONMENT=development
   STORAGE_PROVIDER=local
   ```
   
   **Note**: For development, use `STORAGE_PROVIDER=local`. GCP/AWS buckets are not required.
   Product images are stored as URLs, so you can use any image URL.

4. **Create the database (if it doesn't exist):**
   ```bash
   mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS pos_system;"
   ```
   
   **Note**: Tables will be automatically created by GORM when you run the server.
   You can also manually run the schema if preferred: `mysql -u root -p pos_system < ../database/schema.sql`

5. **Run the server:**
   ```bash
   go run main.go
   ```

   The server will start on port 8080 by default.

## Frontend Setup

1. **Navigate to frontend directory:**
   ```bash
   cd frontend
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Update API URL:**
   Edit `lib/services/api_service.dart` and update the `_baseUrl`:
   ```dart
   _baseUrl = 'https://your-api-url.com/api/v1';
   ```

4. **Run the application:**
   ```bash
   flutter run
   ```

## Deployment

### Backend - Google Cloud Platform

1. **Set up Cloud Build:**
   ```bash
   gcloud builds submit --config cloudbuild.yaml
   ```

2. **Or deploy manually:**
   ```bash
   docker build -t gcr.io/PROJECT_ID/pos-backend .
   docker push gcr.io/PROJECT_ID/pos-backend
   gcloud run deploy pos-backend --image gcr.io/PROJECT_ID/pos-backend
   ```

### Backend - AWS

1. **Install Serverless Framework:**
   ```bash
   npm install -g serverless
   ```

2. **Deploy:**
   ```bash
   serverless deploy
   ```

### Frontend

1. **Build for production:**
   ```bash
   flutter build windows  # For Windows
   flutter build macos    # For macOS
   flutter build linux    # For Linux
   flutter build apk      # For Android
   flutter build ios      # For iOS
   ```

2. **Distribute the built application to POS devices**

## Initial Setup

1. **Create a management user:**
   Use the API or database directly to create the first management user.

2. **Register POS devices:**
   - Get device code from the POS app
   - Register device via API: `POST /api/v1/device/register`

3. **Set up stores:**
   - Create stores via API: `POST /api/v1/stores`

4. **Assign users to stores:**
   - Assign users via API or database

5. **Add products:**
   - Create products via API: `POST /api/v1/products`
   - Set product costs: `POST /api/v1/products/:id/cost`

6. **Sync POS devices:**
   - Users and products will be synced when POS app connects

## Features

### Backend Management
- Product management with cost calculation
- Sector-based pricing and discounts
- Stock management across multiple stores
- Re-stock order tracking
- Price history and trends
- PDF catalog generation
- User and device management

### POS System
- Offline-capable with encrypted SQLite
- PIN and username/password login
- Barcode scanning
- Product search and filtering
- Weight-based products
- Cart management
- Order processing with QR codes
- Receipt printing
- Stock synchronization

## API Documentation

See the API routes in `backend/internal/api/router.go` for available endpoints.

## Troubleshooting

### Database Connection Issues
- Verify MySQL is running
- Check DATABASE_URL format
- Ensure database exists and user has permissions

### POS Sync Issues
- Verify device is registered
- Check network connectivity
- Review API logs

### Build Issues
- Ensure all dependencies are installed
- Check Go/Flutter versions
- Review error messages for missing packages

