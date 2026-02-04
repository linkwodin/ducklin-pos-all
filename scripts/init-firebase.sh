#!/bin/bash

# Script to initialize Firebase Hosting for the project

set -e

FRONTEND_DIR="management-frontend"
PROJECT_ID="${PROJECT_ID:-ducklin-uk-uat}"

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

print_info "Initializing Firebase Hosting for project: $PROJECT_ID"
print_info ""

# Check if Firebase project exists
print_info "Checking Firebase project..."
if ! firebase projects:list | grep -q "$PROJECT_ID"; then
    print_warn "Project '$PROJECT_ID' not found in Firebase"
    print_info "You may need to:"
    print_info "  1. Enable Firebase in GCP Console: https://console.cloud.google.com/firebase"
    print_info "  2. Or create a new Firebase project"
    print_info ""
    read -p "Do you want to create a new Firebase project? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        firebase projects:create "$PROJECT_ID" --display-name "POS System UAT"
    else
        exit 1
    fi
fi

# Use the project
print_info "Using Firebase project: $PROJECT_ID"
firebase use "$PROJECT_ID"

# Check if hosting is already initialized
if [ -f "firebase.json" ] && grep -q '"hosting"' firebase.json; then
    print_warn "firebase.json already exists with hosting configuration"
    print_info "Checking if hosting site exists..."
    
    # Try to list hosting sites
    if firebase hosting:sites:list &> /dev/null; then
        print_success "Hosting appears to be initialized"
        print_info "You can now deploy with: firebase deploy --only hosting"
        exit 0
    fi
fi

# Initialize hosting
print_info "Initializing Firebase Hosting..."
print_info ""
print_info "When prompted:"
print_info "  - Public directory: dist"
print_info "  - Configure as single-page app: Yes"
print_info "  - Set up automatic builds: No"
print_info "  - Overwrite index.html: No"
print_info ""

# Run firebase init hosting in non-interactive mode
# We'll use the existing firebase.json if it exists
if [ ! -f "firebase.json" ]; then
    print_info "Creating firebase.json..."
    cat > firebase.json << 'EOF'
{
  "hosting": {
    "public": "dist",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
EOF
fi

# Ensure .firebaserc exists
if [ ! -f ".firebaserc" ]; then
    print_info "Creating .firebaserc..."
    cat > .firebaserc << EOF
{
  "projects": {
    "default": "$PROJECT_ID"
  }
}
EOF
fi

# Try to create a hosting site if it doesn't exist
print_info "Checking for existing hosting site..."
SITES=$(firebase hosting:sites:list 2>/dev/null || echo "")

if [ -z "$SITES" ] || ! echo "$SITES" | grep -q "default"; then
    print_info "Creating default hosting site..."
    firebase hosting:sites:create default 2>/dev/null || print_warn "Site may already exist or creation failed"
fi

print_success "Firebase Hosting initialized!"
print_info ""
print_info "Next steps:"
print_info "  1. Build your frontend: npm run build:uat"
print_info "  2. Deploy: firebase deploy --only hosting"
print_info ""
print_info "Or use the deployment script:"
    print_info "  cd .. && ./scripts/deploy-firebase.sh uat"

cd ..

