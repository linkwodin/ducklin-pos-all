# Firebase Hosting Setup Fix

## Issue
Firebase Hosting site needs to be created through the Firebase Console first.

## Solution

### Option 1: Create Site via Firebase Console (Recommended)

1. **Go to Firebase Console:**
   - Visit: https://console.firebase.google.com/project/ducklin-uk-uat/hosting
   - Or: https://console.firebase.google.com/

2. **Enable Firebase Hosting:**
   - Click "Get Started" on Hosting
   - This will automatically create the default site

3. **Then deploy:**
   ```bash
   cd management-frontend
   npm run build:uat
   firebase deploy --only hosting
   ```

### Option 2: Use Firebase CLI to Initialize

Run the initialization script:
```bash
chmod +x init-firebase.sh
./scripts/init-firebase.sh
```

This will guide you through the setup.

### Option 3: Manual CLI Setup

```bash
cd management-frontend

# Make sure you're using the right project
firebase use ducklin-uk-uat

# Initialize hosting (interactive)
firebase init hosting

# When prompted:
# - Use existing project: Yes, select ducklin-uk-uat
# - Public directory: dist
# - Single-page app: Yes
# - Automatic builds: No
# - Overwrite index.html: No

# Then deploy
npm run build:uat
firebase deploy --only hosting
```

## After Site is Created

Once the site exists, you can deploy with:
```bash
./scripts/deploy-firebase.sh uat
```

Or manually:
```bash
cd management-frontend
npm run build:uat
firebase deploy --only hosting
```

## Troubleshooting

If you still get "no Hosting site" error:
1. Check Firebase Console to ensure Hosting is enabled
2. Verify project ID in `.firebaserc` matches your Firebase project
3. Try: `firebase projects:list` to see available projects
4. Try: `firebase use --add` to add the project if needed

