# POS Management System - React Frontend

This is the ReactJS web application for the management team to manage the POS system.

## Features

- **Product Management**: Add, edit, and manage products with cost configuration
- **Sector Management**: Configure customer sectors (wholesaler, restaurant, etc.)
- **Discount Management**: Set discount rates for products by sector
- **Stock Management**: View stock levels, low stock alerts, and manage re-stock orders
- **User Management**: Manage users (management, POS users, supervisors)
- **Store & Device Management**: Manage stores and POS devices
- **Catalog Generation**: Generate PDF e-catalogs for each sector (quarterly)
- **Price History**: View price trends with interactive charts

## Tech Stack

- React 18 with TypeScript
- Vite for build tooling
- Material-UI (MUI) for UI components
- React Router for navigation
- Recharts for data visualization
- Axios for API calls
- Notistack for notifications

## Setup

1. Install dependencies:
```bash
cd management-frontend
npm install
```

2. Configure API URL (optional):
Create a `.env` file:
```
VITE_API_URL=http://localhost:8080/api/v1
```

3. Start development server:
```bash
npm run dev
```

The app will be available at `http://localhost:3000`

## Build for Production

```bash
npm run build
```

The built files will be in the `dist` directory.

## Project Structure

```
management-frontend/
├── src/
│   ├── components/      # Reusable components
│   ├── context/         # React context (Auth)
│   ├── pages/          # Page components
│   ├── services/       # API service layer
│   ├── types/          # TypeScript type definitions
│   ├── App.tsx         # Main app component
│   └── main.tsx        # Entry point
├── package.json
├── tsconfig.json
└── vite.config.ts
```

## API Integration

The frontend communicates with the Go backend API. Make sure the backend is running on `http://localhost:8080` (or configure the URL in `.env`).

All API calls are handled through the `src/services/api.ts` file, which uses Axios with JWT token authentication.

## Authentication

Users log in with username and password. The JWT token is stored in localStorage and automatically included in API requests.

## Environment Variables

- `VITE_API_URL`: Backend API base URL (default: `/api/v1`)

