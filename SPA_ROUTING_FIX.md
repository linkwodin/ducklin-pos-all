# SPA Routing Fix for Cloud Storage

## Problem
Cloud Storage's `notFoundPage` setting doesn't work with direct `storage.googleapis.com` URLs. When accessing a non-existent path like `/login`, it returns an XML error instead of serving `index.html`.

## Solutions

### Option 1: Use Firebase Hosting (Recommended)
Firebase Hosting automatically handles SPA routing:

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize Firebase in your frontend directory
cd management-frontend
firebase init hosting

# Deploy
firebase deploy --only hosting
```

### Option 2: Use Direct index.html URLs
For development/testing, always access:
```
https://storage.googleapis.com/ducklin-uk-uat-pos-frontend-uat/index.html
```

React Router will handle client-side routing from there.

### Option 3: Cloud Load Balancer (Production)
Run the setup script:
```bash
chmod +x setup-load-balancer.sh
./setup-load-balancer.sh
```

This creates a Load Balancer that properly handles SPA routing.

### Option 4: Cloud Run Proxy (Simple Alternative)
Create a simple Cloud Run service that serves the SPA and handles routing.

## Current Status
- ✅ Bucket is configured with `notFoundPage: index.html`
- ✅ Bucket is publicly readable
- ⚠️  Direct `storage.googleapis.com` URLs don't support SPA routing
- ✅ React Router works when accessing `index.html` directly

## Recommendation
For UAT, use **Option 2** (direct `index.html` access). For production, use **Option 1** (Firebase Hosting) or **Option 3** (Load Balancer).

