# Firebase Hosting Setup Guide

## Prerequisites

1. **Install Firebase CLI:**
   ```bash
   npm install -g firebase-tools
   ```

2. **Login to Firebase:**
   ```bash
   firebase login
   ```

3. **Verify Firebase project:**
   - Make sure your GCP project `ducklin-uk-uat` is linked to Firebase
   - If not, enable Firebase in the GCP Console or create a Firebase project

## Initial Setup (One-time)

1. **Navigate to frontend directory:**
   ```bash
   cd management-frontend
   ```

2. **Initialize Firebase (if not already done):**
   ```bash
   firebase init hosting
   ```
   
   When prompted:
   - Select "Use an existing project"
   - Choose `ducklin-uk-uat`
   - Set public directory to: `dist`
   - Configure as single-page app: **Yes**
   - Set up automatic builds: **No** (we'll build manually)
   - Overwrite index.html: **No** (we have our own)

   Note: The `firebase.json` and `.firebaserc` files are already created, so you can skip this step if they exist.

## Deployment

### Option 1: Using the deployment script (Recommended)

```bash
# Deploy UAT version
./scripts/deploy-firebase.sh uat

# Deploy production version
./scripts/deploy-firebase.sh production
```

### Option 2: Manual deployment

```bash
cd management-frontend

# Build for UAT
npm run build:uat

# Deploy to Firebase
firebase deploy --only hosting
```

### Option 3: Using npm scripts

```bash
cd management-frontend

# Deploy UAT
npm run deploy:firebase:uat

# Deploy production
npm run deploy:firebase
```

## Environment Configuration

The build process uses environment files:
- **UAT**: Uses `env.uat` file (sets `VITE_API_URL` to UAT backend)
- **Production**: Uses default build (you may need to create `env.production`)

## Firebase Hosting Features

✅ **Automatic SPA routing** - All routes redirect to `index.html`  
✅ **CDN** - Fast global content delivery  
✅ **SSL certificates** - Automatic HTTPS  
✅ **Custom domains** - Easy to add your own domain  
✅ **Preview channels** - Test deployments before going live  

## Custom Domain Setup

1. **Add custom domain in Firebase Console:**
   - Go to Firebase Console → Hosting
   - Click "Add custom domain"
   - Follow the DNS configuration instructions

2. **Or use Firebase CLI:**
   ```bash
   firebase hosting:channel:deploy production --only hosting
   ```

## Preview Deployments

Create preview channels for testing:

```bash
firebase hosting:channel:deploy preview-channel-name
```

This creates a temporary URL for testing before deploying to production.

## Troubleshooting

### Build fails
- Check that all dependencies are installed: `npm install`
- Verify TypeScript compilation: `npm run build`

### Deployment fails
- Ensure you're logged in: `firebase login`
- Check project ID in `.firebaserc` matches your Firebase project
- Verify `firebase.json` configuration is correct

### Routes not working
- Ensure `firebase.json` has the rewrite rule: `"source": "**", "destination": "/index.html"`
- Check that `dist/index.html` exists after build

## Benefits over Cloud Storage

✅ Proper SPA routing support  
✅ Better caching and CDN  
✅ Automatic SSL certificates  
✅ Preview channels for testing  
✅ Better integration with Firebase services  
✅ Custom domain support  

