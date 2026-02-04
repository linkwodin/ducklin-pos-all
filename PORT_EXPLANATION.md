# Port Configuration for Cloud Run

## How Cloud Run Handles Ports

Cloud Run **automatically** handles port mapping:

1. **Internal Port (Container)**: Cloud Run sets `PORT=8080` environment variable
   - Your app must listen on whatever port is in the `PORT` environment variable
   - This is currently set to 8080 by Cloud Run (you cannot change this)

2. **External Port (Public URL)**: Cloud Run automatically maps to:
   - **Port 80** (HTTP)
   - **Port 443** (HTTPS)

## Your Current Setup

✅ **Your app is already configured correctly:**

```go
// backend/main.go
port := os.Getenv("PORT")  // Reads PORT from Cloud Run (8080)
if port == "" {
    port = "8868"  // Fallback for local development
}
router.Run(":" + port)  // Listens on the port Cloud Run provides
```

## Your Service URL

When you deploy to Cloud Run, your service will be accessible on:

- **HTTPS**: `https://pos-backend-xxxxx.run.app` (port 443)
- **HTTP**: `http://pos-backend-xxxxx.run.app` (port 80)

Both URLs automatically work - Cloud Run handles the port mapping!

## Why You Can't Use Port 80 Internally

- Cloud Run requires your container to listen on the `PORT` environment variable
- Cloud Run sets `PORT=8080` (or another port it chooses)
- You cannot override this - it's managed by Cloud Run
- The external port 80/443 is handled automatically by Cloud Run's load balancer

## Summary

✅ **Your current configuration is correct**
✅ **Your service is already accessible on port 80/443 externally**
✅ **No changes needed**

The issue you're experiencing is **not related to ports** - it's the database connection taking too long during startup. Focus on fixing the database connection, not the port configuration.

