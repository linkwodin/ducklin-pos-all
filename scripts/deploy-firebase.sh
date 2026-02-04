#!/bin/bash

# Script to deploy frontend to Firebase Hosting

set -e

FRONTEND_DIR="management-frontend"
ENV="${1:-uat}"

print_info() {
    echo "ℹ️  $1"
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1"
}

print_warn() {
    echo "⚠️  $1"
}

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    print_error "Firebase CLI is not installed"
    print_info "Install it with: npm install -g firebase-tools"
    exit 1
fi

# Check if user is logged in
if ! firebase projects:list &> /dev/null; then
    print_warn "Not logged in to Firebase"
    print_info "Logging in..."
    firebase login
fi

# Navigate to frontend directory
if [ ! -d "$FRONTEND_DIR" ]; then
    print_error "Frontend directory '$FRONTEND_DIR' not found"
    exit 1
fi

cd "$FRONTEND_DIR"

# Check if firebase.json exists
if [ ! -f "firebase.json" ]; then
    print_error "firebase.json not found"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    print_info "Installing dependencies..."
    npm install
fi

# Clean previous builds
print_info "Cleaning previous builds..."
rm -rf dist
rm -rf node_modules/.vite

# Build based on environment
# Set DEPLOY_TARGET to firebase so vite.config.ts uses absolute paths
export DEPLOY_TARGET=firebase

if [ "$ENV" == "uat" ]; then
    print_info "Building for UAT environment..."
    npm run build:uat
elif [ "$ENV" == "production" ] || [ "$ENV" == "prod" ]; then
    print_info "Building for production environment..."
    npm run build:prod
else
    print_info "Building for default environment..."
    npm run build
fi

# Check if build was successful
if [ ! -d "dist" ] || [ ! -f "dist/index.html" ]; then
    print_error "Build failed - 'dist/index.html' not found"
    exit 1
fi

print_success "Build completed successfully"

# Get Firebase project ID from .firebaserc (we're already in management-frontend directory)
FIREBASE_PROJECT="ducklin-uk-uat"  # Default project
if [ -f ".firebaserc" ]; then
    # Extract project ID from .firebaserc JSON (looks for "default": "project-id")
    EXTRACTED=$(grep '"default"' .firebaserc | sed -E 's/.*"default"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' 2>/dev/null || echo "")
    if [ -n "$EXTRACTED" ]; then
        FIREBASE_PROJECT="$EXTRACTED"
    fi
fi

# Deploy to Firebase
print_info "Deploying to Firebase Hosting..."
# Use default hosting (the uat target in .firebaserc maps to "default" site)
firebase deploy --only hosting

print_success "Deployment completed!"

# Display Firebase URL
FIREBASE_URL="https://${FIREBASE_PROJECT}.web.app"
print_success "Frontend deployed successfully!"
print_info "Frontend URL: $FIREBASE_URL"

cd ..

