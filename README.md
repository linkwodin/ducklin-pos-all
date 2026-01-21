# POS System with Backend Management

A comprehensive Point of Sale system with backend management capabilities.

## Project Structure

```
pos-system/
├── backend/              # Go backend API
├── frontend/            # Flutter POS application
├── management-frontend/ # ReactJS admin web interface
├── database/            # Database schemas and migrations
└── docs/               # Documentation
```

## Features

### Backend Management System
- Product management (add/inactivate)
- Cost calculation (exchange rate, unit weight, buffers, freight, import duty, packaging)
- Sector management (configurable)
- Discount rates per product per sector
- Historical data tracking with price trend graphs
- PDF e-catalog generation (quarterly per sector)
- Stock management (multi-store, low stock alerts, re-stock tracking)
- User management (management team, POS users)
- POS device and store management

### POS System
- Cross-platform Flutter app (PC, Mac, iPad, Android)
- Offline SQLite storage with encryption
- Device code authentication
- User login with PIN or username/password
- Barcode scanning
- Product search/filter by category
- Products by quantity or weight
- Checkout with receipt (QR code)
- Stock management
- Multi-store inventory access

## Tech Stack

- **Backend**: Go (GCP/AWS Cloud Functions)
- **Frontend**: Flutter (POS), ReactJS (Admin Web)
- **Database**: MySQL (GCP/AWS), SQLite (POS offline)
- **Storage**: GCP/AWS (product images)

## Getting Started

See individual README files in each directory for setup instructions.

