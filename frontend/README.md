# POS System - Flutter Frontend

Cross-platform Flutter application for Point of Sale operations.

## Prerequisites

- Flutter SDK 3.0 or higher
- Dart 3.0 or higher
- Android Studio / Xcode (for mobile development)
- VS Code or Android Studio (recommended IDE)

## Setup

1. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

2. **Update API URL:**
   Edit `lib/services/api_service.dart` and update the `_baseUrl`:
   ```dart
   _baseUrl = 'http://your-api-url.com/api/v1';
   ```

3. **Configure device code:**
   The app will generate a device code automatically. This code needs to be registered with the backend via the management system.

## Running the Application

### Development

```bash
flutter run
```

### Platform-Specific

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux

# Android
flutter run -d android

# iOS (macOS only)
flutter run -d ios
```

## Building for Production

### Windows
```bash
flutter build windows
```

### macOS
```bash
flutter build macos
```

### Linux
```bash
flutter build linux
```

### Android
```bash
flutter build apk        # APK file
flutter build appbundle  # App Bundle for Play Store
```

### iOS
```bash
flutter build ios
```

## Features

### Authentication
- **Device Code Login**: The app generates a device code that must be registered with the backend
- **PIN Login**: Quick login with user PIN (for POS users)
- **Username/Password Login**: Full authentication for management accounts

### Product Management
- **Barcode Scanning**: Scan product barcodes to add to cart
- **Product Search**: Search and filter products by category
- **Weight-based Products**: Manual weight input for weight-based products
- **Quantity-based Products**: Standard quantity selection

### Order Processing
- **Cart Management**: Add, remove, and modify items in cart
- **Checkout**: Process orders with QR code generation
- **Receipt Printing**: Print receipts with order details
- **Payment Integration**: Mark orders as paid and completed

### Stock Management
- **Local Inventory**: View stock from local SQLite database
- **Multi-store Access**: View inventory from other stores (for supervisors)
- **Re-stock Tracking**: View incoming re-stock orders with tracking numbers
- **Low Stock Alerts**: Notifications for low stock items

### Offline Support
- **SQLite Database**: Encrypted local database for offline operation
- **Data Sync**: Automatic sync when network is available
- **Offline Orders**: Create orders offline, sync when connected

## Project Structure

```
frontend/
├── lib/
│   ├── main.dart                    # Application entry point
│   ├── providers/                   # State management
│   │   ├── auth_provider.dart
│   │   ├── order_provider.dart
│   │   ├── product_provider.dart
│   │   └── stock_provider.dart
│   ├── screens/                     # UI screens
│   │   ├── login_screen.dart
│   │   ├── pin_login_screen.dart
│   │   ├── username_login_screen.dart
│   │   ├── pos_screen.dart
│   │   ├── product_selection_screen.dart
│   │   ├── cart_screen.dart
│   │   ├── checkout_screen.dart
│   │   ├── barcode_scanner_screen.dart
│   │   └── weight_input_dialog.dart
│   └── services/                    # API and database services
│       ├── api_service.dart
│       └── database_service.dart
└── pubspec.yaml                     # Flutter dependencies
```

## Configuration

### API Configuration

Update `lib/services/api_service.dart`:
```dart
static const String _baseUrl = 'http://your-backend-url.com/api/v1';
```

### Database Configuration

The SQLite database is automatically created and encrypted. Database settings can be modified in `lib/services/database_service.dart`.

## Device Registration

1. **Get Device Code**: The app displays a device code on first launch
2. **Register Device**: Use the management web interface to register the device
3. **Assign to Store**: Link the device to a specific store
4. **Sync Data**: The app will automatically sync users and products

## Troubleshooting

### Build Issues

- Run `flutter clean` and `flutter pub get`
- Ensure Flutter SDK is up to date: `flutter upgrade`
- Check for platform-specific requirements

### API Connection Issues

- Verify backend is running and accessible
- Check API URL in `api_service.dart`
- Review network permissions (for mobile)

### Database Issues

- Clear app data and reinstall
- Check database encryption key
- Verify SQLite plugin is properly installed

### Barcode Scanner Issues

- Ensure camera permissions are granted
- Check barcode scanner plugin installation
- Verify device camera is working

## Dependencies

Key packages used:
- `sqflite` - SQLite database
- `flutter_barcode_scanner` - Barcode scanning
- `qr_flutter` - QR code generation
- `http` - API communication
- `provider` - State management
- `shared_preferences` - Local storage

See `pubspec.yaml` for complete dependency list.

