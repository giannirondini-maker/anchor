#!/bin/bash

###############################################################################
# Anchor - DMG Creation Script
#
# Creates a professional DMG installer for Anchor using create-dmg
#
# Prerequisites:
# - create-dmg (install with: brew install create-dmg)
# - Built app bundle (run ./scripts/build-unified.sh first)
#
# Usage: ./scripts/create-dmg.sh [version]
#
# Example: ./scripts/create-dmg.sh 1.0.0
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
DEFAULT_VERSION="1.0.0"
VERSION="${1:-$DEFAULT_VERSION}"

# Paths
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$BUILD_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ASSETS_DIR="$PROJECT_ROOT/assets"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

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
        print_error "Required command '$1' not found."
        if [[ "$1" == "create-dmg" ]]; then
            echo ""
            print_info "Install with: brew install create-dmg"
        fi
        exit 1
    fi
}

###############################################################################
# Validation
###############################################################################

print_step "Validating environment..."

# Check for create-dmg
check_command "create-dmg"

# Verify we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script must be run on macOS"
    exit 1
fi

# Verify app bundle exists
if [[ ! -d "$APP_BUNDLE" ]]; then
    print_error "App bundle not found: $APP_BUNDLE"
    print_info "Run ./scripts/build-unified.sh first"
    exit 1
fi

print_success "Environment validation passed"

###############################################################################
# Create Assets (if needed)
###############################################################################

print_step "Preparing DMG assets..."

# Create assets directory if it doesn't exist
mkdir -p "$ASSETS_DIR"

# Check if we need to create a simple background
DMG_BACKGROUND="$ASSETS_DIR/dmg-background.png"
if [[ ! -f "$DMG_BACKGROUND" ]]; then
    print_info "No custom background found, DMG will use default appearance"
    DMG_BACKGROUND=""
fi

# Check for app icon
APP_ICON="$ASSETS_DIR/AppIcon.icns"
if [[ ! -f "$APP_ICON" ]]; then
    print_info "No custom app icon found"
    APP_ICON=""
fi

print_success "Assets prepared"

###############################################################################
# Clean Previous DMG
###############################################################################

print_step "Cleaning previous DMG..."

if [[ -f "$DMG_PATH" ]]; then
    rm -f "$DMG_PATH"
    print_info "Removed existing DMG"
fi

print_success "Cleanup complete"

###############################################################################
# Create DMG
###############################################################################

print_step "Creating DMG installer..."

# Build create-dmg command
DMG_ARGS=(
    --volname "$APP_NAME"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 100
    --icon "$APP_NAME.app" 150 190
    --hide-extension "$APP_NAME.app"
    --app-drop-link 450 185
)

# Add background if available
if [[ -n "$DMG_BACKGROUND" ]]; then
    DMG_ARGS+=(--background "$DMG_BACKGROUND")
fi

# Add volume icon if available
if [[ -n "$APP_ICON" ]]; then
    DMG_ARGS+=(--volicon "$APP_ICON")
fi

# Add output path and source
DMG_ARGS+=("$DMG_PATH")
DMG_ARGS+=("$APP_BUNDLE")

# Create the DMG
print_info "Running create-dmg..."
create-dmg "${DMG_ARGS[@]}" || true

# Note: create-dmg returns non-zero exit code even on success sometimes
# Verify DMG was created
if [[ ! -f "$DMG_PATH" ]]; then
    print_error "DMG creation failed"
    exit 1
fi

print_success "DMG created successfully"

###############################################################################
# Create Release Notes
###############################################################################

print_step "Creating release notes..."

RELEASE_NOTES="$BUILD_DIR/RELEASE_NOTES.md"

cat > "$RELEASE_NOTES" << EOF
# Anchor v${VERSION}

## Installation

1. **Download** \`$DMG_NAME\`
2. **Open** the DMG file
3. **Drag** Anchor.app to the Applications folder
4. **Launch** Anchor from Applications

## First Launch

If you see a security warning:

### Method 1: Right-click
- Right-click on Anchor in Applications
- Select "Open"
- Click "Open" in the dialog

### Method 2: Terminal
\`\`\`bash
xattr -cr /Applications/Anchor.app
\`\`\`

## Prerequisites

Anchor requires **GitHub Copilot CLI** to be installed and authenticated:

\`\`\`bash
# Install GitHub CLI
brew install gh

# Install Copilot extension
gh extension install github/gh-copilot

# Authenticate
gh auth login
\`\`\`

You also need an active **GitHub Copilot Pro** or **GitHub Copilot Business** license.

## System Requirements

- **macOS**: 14.0 (Sonoma) or later
- **Architecture**: Apple Silicon (M1/M2/M3)
- **GitHub Copilot**: Active Pro or Business license
- **GitHub CLI**: Latest version with Copilot extension

## What's New in v${VERSION}

- Initial release
- Native macOS interface with SwiftUI
- Embedded Node.js backend (no separate installation needed)
- Real-time streaming responses
- Conversation history with tags
- Multi-model support (GPT-4, Claude, etc.)
- Dark mode support

## Features

✨ **Native macOS App**: Built with SwiftUI for optimal performance
🚀 **Self-contained**: No external dependencies to install
💬 **Real-time Chat**: Streaming responses from GitHub Copilot
📝 **Conversation Management**: Save and organize your chats
🏷️ **Tags**: Organize conversations with custom tags
🎨 **Beautiful UI**: Native macOS design with dark mode
🔒 **Secure**: Uses your GitHub authentication
📎 **Attachments**: Support for PDF, text, and image files
⌨️ **Keyboard Shortcuts**: Navigate and control the app efficiently

## Support

- **Documentation**: See README.md in repository

## License

MIT License - See LICENSE file for details

---

**Built**: $(date)
**Architecture**: Apple Silicon (arm64)
**Bundle Size**: $(du -sh "$APP_BUNDLE" | cut -f1)
**DMG Size**: $(du -sh "$DMG_PATH" | cut -f1)
EOF

print_success "Release notes created"

###############################################################################
# Generate Checksums
###############################################################################

print_step "Generating checksums..."

CHECKSUMS_FILE="$BUILD_DIR/checksums.txt"

cat > "$CHECKSUMS_FILE" << EOF
SHA256 Checksums for Anchor v${VERSION}
========================================

DMG File:
---------
EOF

# Generate SHA256 checksum
if command -v shasum &> /dev/null; then
    cd "$BUILD_DIR"
    shasum -a 256 "$DMG_NAME" >> "$CHECKSUMS_FILE"
    print_success "Checksums generated"

    # Create a combined release notes file that includes checksums so it can be
    # passed directly to the GitHub CLI using --notes-file
    COMBINED_RELEASE_NOTES="$BUILD_DIR/RELEASE_NOTES_WITH_CHECKSUMS.md"
    {
        cat "$RELEASE_NOTES"
        echo ""
        echo "----"
        echo ""
        cat "$CHECKSUMS_FILE"
    } > "$COMBINED_RELEASE_NOTES"
    print_info "Combined release notes (with checksums): $COMBINED_RELEASE_NOTES"
else
    print_warning "shasum not found, skipping checksum generation"
fi

###############################################################################
# Create Upload Instructions
###############################################################################

print_step "Creating upload instructions..."

UPLOAD_INSTRUCTIONS="$BUILD_DIR/UPLOAD_INSTRUCTIONS.md"

cat > "$UPLOAD_INSTRUCTIONS" << EOF
GitHub Release Upload Instructions
===================================

1. Go to: https://github.com/yourusername/anchor/releases/new

2. Create a new tag: v${VERSION}

3. Release title: Anchor v${VERSION}

4. Upload these files:
   - $DMG_NAME (the DMG installer)
   - $(basename "$CHECKSUMS_FILE") (SHA256 checksums)
   
5. Copy release notes from: RELEASE_NOTES.md

6. Check "Create a discussion for this release" (optional)

7. Click "Publish release"

Alternative: Using GitHub CLI
------------------------------

\`\`\`bash
# Create a release with combined notes (includes checksums) and upload assets
gh release create v${VERSION} \\
  "$DMG_PATH" \\
  "$CHECKSUMS_FILE" \\
  --title "Anchor v${VERSION}" \\
  --notes-file "$COMBINED_RELEASE_NOTES"
\`\`\`

Verification
------------

After uploading, verify:
- DMG downloads correctly
- DMG opens without errors
- App launches successfully
- Release notes are formatted correctly (checksums appended)

Announcement
------------

Consider announcing the release:
- Update repository README.md
- Post on social media
- Notify team/users
EOF

print_success "Upload instructions created"

###############################################################################
# Summary
###############################################################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "DMG creation completed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "DMG file: $DMG_PATH"
print_info "DMG size: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
print_info "Release notes: $RELEASE_NOTES"
print_info "Checksums: $CHECKSUMS_FILE"
print_info "Upload instructions: $UPLOAD_INSTRUCTIONS"
echo ""
print_warning "Next steps:"
echo "  1. Test the DMG: open \"$DMG_PATH\""
echo "  2. Verify installation on a clean Mac"
echo "  3. Upload to GitHub releases (see UPLOAD_INSTRUCTIONS.txt)"
echo ""
print_info "Quick test command:"
echo "  open \"$DMG_PATH\""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
