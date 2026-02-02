#!/bin/bash

###############################################################################
# Anchor - Unified App Bundle Build Script for Apple Silicon
#
# This script creates a complete macOS app bundle with:
# - SwiftUI frontend
# - Embedded Node.js backend
# - Node.js runtime for Apple Silicon (arm64)
#
# Prerequisites:
# - Xcode Command Line Tools
# - Node.js 20+ (for building)
# - Swift toolchain
#
# Usage: ./scripts/build-unified.sh
###############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="Anchor"
APP_VERSION="1.0.1"
APP_IDENTIFIER="com.gianni.rondini.anchor"
BUNDLE_DISPLAY_NAME="Anchor"
MIN_MACOS_VERSION="14.0"
NODE_VERSION="20.20.0"

# Paths
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$BUILD_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
BACKEND_DIR="$PROJECT_ROOT/backend"
TOOLS_DIR="$PROJECT_ROOT/tools"

# Node.js download URL for Apple Silicon
NODE_DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-arm64.tar.gz"
NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-arm64.tar.gz"

###############################################################################
# Helper Functions
###############################################################################

print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Required command '$1' not found. Please install it first."
        exit 1
    fi
}

###############################################################################
# Validation
###############################################################################

print_step "Validating build environment..."

# Check required commands
check_command "node"
check_command "npm"
check_command "swift"
check_command "curl"

# Verify we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script must be run on macOS"
    exit 1
fi

# Check Node.js version (must be v20.x to match embedded runtime)
CURRENT_NODE_VERSION=$(node --version)
NODE_MAJOR_VERSION=$(echo "$CURRENT_NODE_VERSION" | cut -d'.' -f1 | sed 's/v//')

print_info "Detected Node.js: $CURRENT_NODE_VERSION"
print_info "Node.js location: $(which node)"
print_info "npm location: $(which npm)"

# Check for .nvmrc and suggest using it
if [[ -f "$PROJECT_ROOT/.nvmrc" ]]; then
    NVMRC_VERSION=$(cat "$PROJECT_ROOT/.nvmrc")
    if [[ "$CURRENT_NODE_VERSION" != "v$NVMRC_VERSION" && "$CURRENT_NODE_VERSION" != "$NVMRC_VERSION" ]]; then
        print_warning "Project .nvmrc specifies Node.js v$NVMRC_VERSION"
        print_info "Run 'nvm use' in the project directory to switch versions"
    fi
fi

if [[ "$NODE_MAJOR_VERSION" != "20" ]]; then
    print_warning "Node.js v20.x required for building (current: $CURRENT_NODE_VERSION)"
    print_info "The bundled app uses Node.js v${NODE_VERSION}"
    print_info "Native modules (better-sqlite3) must be compiled with matching Node.js version"
    echo ""
    print_info "To fix, run:"
    echo "  nvm install 20.20.0 && nvm use 20.20.0"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_info "Using Node.js $(node --version) ✓"

# Verify directories exist
if [[ ! -d "$FRONTEND_DIR" ]]; then
    print_error "Frontend directory not found: $FRONTEND_DIR"
    exit 1
fi

if [[ ! -d "$BACKEND_DIR" ]]; then
    print_error "Backend directory not found: $BACKEND_DIR"
    exit 1
fi

print_success "Environment validation passed"

###############################################################################
# Clean Build Directory
###############################################################################

print_step "Cleaning previous build..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$TOOLS_DIR"

print_success "Build directory cleaned"

###############################################################################
# Download and Prepare Node.js Runtime (if needed)
###############################################################################

print_step "Preparing Node.js runtime for Apple Silicon..."

NODE_RUNTIME_DIR="$TOOLS_DIR/node-runtime"

if [[ ! -d "$NODE_RUNTIME_DIR" ]]; then
    print_info "Downloading Node.js v${NODE_VERSION} for Apple Silicon..."
    
    cd "$TOOLS_DIR"
    
    # Download Node.js
    if [[ ! -f "$NODE_ARCHIVE" ]]; then
        curl -# -L -O "$NODE_DOWNLOAD_URL"
    fi
    
    # Extract the archive
    print_info "Extracting Node.js runtime..."
    tar -xzf "$NODE_ARCHIVE"
    
    # Create runtime directory with just what we need
    mkdir -p "$NODE_RUNTIME_DIR/bin"
    cp "node-v${NODE_VERSION}-darwin-arm64/bin/node" "$NODE_RUNTIME_DIR/bin/"
    
    # Clean up
    rm -rf "node-v${NODE_VERSION}-darwin-arm64"
    
    print_success "Node.js runtime prepared"
else
    print_info "Using cached Node.js runtime"
fi

###############################################################################
# Build Backend
###############################################################################

print_step "Building backend..."

cd "$BACKEND_DIR"

# Install production dependencies
print_info "Installing backend dependencies..."
npm ci --production=false

# Build TypeScript
print_info "Compiling TypeScript..."
npm run build

# Verify build output
if [[ ! -f "$BACKEND_DIR/dist/index.js" ]]; then
    print_error "Backend build failed: dist/index.js not found"
    exit 1
fi

# Install production dependencies only (remove dev dependencies)
print_info "Optimizing dependencies for production..."
rm -rf node_modules
npm ci --production --silent

print_success "Backend built successfully"

###############################################################################
# Build Frontend
###############################################################################

print_step "Building frontend for Apple Silicon..."

cd "$FRONTEND_DIR"

# Build for Apple Silicon only (arm64)
print_info "Compiling Swift code for arm64..."
swift build -c release --arch arm64

# Verify build output
if [[ ! -f "$FRONTEND_DIR/.build/arm64-apple-macosx/release/$APP_NAME" ]]; then
    print_error "Frontend build failed: executable not found"
    exit 1
fi

print_success "Frontend built successfully"

###############################################################################
# Create App Bundle Structure
###############################################################################

print_step "Creating app bundle structure..."

# Create bundle directories
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

print_success "App bundle structure created"

###############################################################################
# Copy Frontend Executable
###############################################################################

print_step "Copying frontend executable..."

cp "$FRONTEND_DIR/.build/arm64-apple-macosx/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

print_success "Frontend executable copied"

###############################################################################
# Copy App Icon
###############################################################################

print_step "Copying app icon..."

APP_ICON="$PROJECT_ROOT/assets/AppIcon.icns"
if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_BUNDLE/Contents/Resources/"
    print_success "App icon copied"
else
    print_warning "App icon not found at: $APP_ICON"
    print_info "App will use default icon"
fi

###############################################################################
# Copy Backend
###############################################################################

print_step "Copying backend..."

# Create backend directory in Resources
mkdir -p "$APP_BUNDLE/Contents/Resources/backend"

# Copy backend files
cp -r "$BACKEND_DIR/dist" "$APP_BUNDLE/Contents/Resources/backend/"
cp -r "$BACKEND_DIR/node_modules" "$APP_BUNDLE/Contents/Resources/backend/"
cp "$BACKEND_DIR/package.json" "$APP_BUNDLE/Contents/Resources/backend/"

# Create data directory for SQLite database
mkdir -p "$APP_BUNDLE/Contents/Resources/backend/data"

print_success "Backend copied"

###############################################################################
# Copy Node.js Runtime
###############################################################################

print_step "Copying Node.js runtime..."

cp -r "$NODE_RUNTIME_DIR" "$APP_BUNDLE/Contents/Resources/node"
chmod +x "$APP_BUNDLE/Contents/Resources/node/bin/node"

print_success "Node.js runtime copied"

###############################################################################
# Create Info.plist
###############################################################################

print_step "Creating Info.plist..."

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$BUNDLE_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_IDENTIFIER</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
EOF

print_success "Info.plist created"

###############################################################################
# Set Permissions
###############################################################################

print_step "Setting permissions..."

# Make everything in the bundle readable
chmod -R u+rw "$APP_BUNDLE"

# Make executables executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/Resources/node/bin/node"

print_success "Permissions set"

###############################################################################
# Create Build Info
###############################################################################

print_step "Creating build info..."

BUILD_INFO="$DIST_DIR/BUILD_INFO.txt"

cat > "$BUILD_INFO" << EOF
Anchor - Build Information
==========================

Build Date: $(date)
App Version: $APP_VERSION
Node.js Version: $NODE_VERSION
Architecture: Apple Silicon (arm64)
macOS Minimum: $MIN_MACOS_VERSION

Bundle Location: $APP_BUNDLE

Installation:
1. Copy $APP_NAME.app to /Applications
2. For first launch, you may need to run:
   xattr -cr /Applications/$APP_NAME.app
3. Launch $APP_NAME from Applications

Prerequisites:
- GitHub Copilot CLI must be installed and authenticated
- GitHub Copilot Pro/Business license required

Setup GitHub Copilot CLI:
  brew install gh
  gh extension install github/gh-copilot
  gh auth login

Note: This build is for Apple Silicon Macs only.
EOF

print_success "Build info created"

###############################################################################
# Summary
###############################################################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "Build completed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "App bundle: $APP_BUNDLE"
print_info "Build info: $BUILD_INFO"
echo ""
print_info "Bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
print_warning "Next steps:"
echo "  1. Test the app: open \"$APP_BUNDLE\""
echo "  2. Create DMG: ./scripts/create-dmg.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
