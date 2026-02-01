# Anchor Build Scripts

This directory contains scripts for building and packaging the Anchor macOS application as a unified app bundle.

## Overview

Anchor uses a **Unified App Bundle** approach, which embeds both the SwiftUI frontend and Node.js backend into a single `.app` file. This provides a seamless, native macOS experience with no external dependencies.

## Prerequisites

### Required Tools

1. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```

2. **Node.js 20.x LTS** (via NVM - **required**)
   
   > ⚠️ **CRITICAL**: You must use Node.js v20.x for building. The bundled app embeds Node.js v20.20.0, and native modules must be compiled with a matching major version.

   ```bash
   # Install NVM if needed
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
   
   # Install Node.js 20
   nvm install 20.20.0
   
   # Use it (do this every time before building!)
   nvm use 20.20.0
   # Or simply:
   nvm use  # Uses version from .nvmrc
   ```

3. **Swift Toolchain** (included with Xcode)

4. **create-dmg** (for DMG creation)
   ```bash
   brew install create-dmg
   ```

### GitHub Copilot CLI Setup

The Copilot CLI must be installed in your Node.js 20 environment:

```bash
# Make sure you're using Node 20
nvm use 20.20.0

# Install Copilot CLI globally
npm install -g @github/copilot

# Authenticate
copilot auth login

# Verify version (must be 0.0.400 or later)
copilot --version
```

> **Note**: The Copilot CLI version must be **0.0.400+** to support SDK protocol version 2.

### GitHub Copilot Subscription

Users of the app will need:
- GitHub Copilot Pro or Business license
- Authenticated Copilot CLI (see above)

## Build Process

### Step 1: Build the Unified App Bundle

> ⚠️ **Before building**: Always ensure you're using Node.js 20:
> ```bash
> nvm use  # Or: nvm use 20.20.0
> ```

This script builds both frontend and backend, downloads the Node.js runtime for Apple Silicon, and creates the complete `.app` bundle:

```bash
./scripts/build-unified.sh
```

**What it does:**
- ✅ Validates build environment
- ✅ Downloads Node.js v22.21.1 for Apple Silicon (arm64)
- ✅ Builds backend (TypeScript → JavaScript)
- ✅ Installs production dependencies
- ✅ Builds frontend (Swift → native executable)
- ✅ Creates `Anchor.app` bundle structure
- ✅ Embeds backend and Node.js runtime
- ✅ Generates `Info.plist`
- ✅ Sets proper permissions

**Output:**
```
build/
  dist/
    Anchor.app/          ← The complete application
  BUILD_INFO.txt         ← Build metadata
```

### Step 2: Create DMG Installer

Once the app bundle is built, create a professional DMG installer:

```bash
./scripts/create-dmg.sh [version]
```

**Example:**
```bash
./scripts/create-dmg.sh 1.0.0
```

**What it does:**
- ✅ Creates a professional DMG with drag-to-install UI
- ✅ Generates release notes
- ✅ Creates SHA256 checksums
- ✅ Provides upload instructions for GitHub releases

**Output:**
```
build/
  Anchor-1.0.0.dmg           ← Distributable installer
  RELEASE_NOTES.md           ← GitHub release notes
  checksums.txt              ← SHA256 verification
  UPLOAD_INSTRUCTIONS.txt    ← How to publish
```

## Complete Build Workflow

```bash
# 0. IMPORTANT: Ensure correct Node.js version
nvm use  # Uses .nvmrc (v20.20.0)

# 1. Build the app bundle
./scripts/build-unified.sh

# 2. Test the app locally
open build/dist/Anchor.app

# 3. Create DMG for distribution
./scripts/create-dmg.sh 1.0.0

# 4. Test the DMG
open build/Anchor-1.0.0.dmg

# 5. Upload to GitHub releases (manual or via gh CLI)
gh release create v1.0.0 \
  build/Anchor-1.0.0.dmg \
  --title "Anchor v1.0.0" \
  --notes-file build/RELEASE_NOTES.md
```

## Architecture Details

### App Bundle Structure

```
Anchor.app/
├── Contents/
│   ├── Info.plist                    # App metadata
│   ├── MacOS/
│   │   └── Anchor                    # SwiftUI executable
│   ├── Resources/
│   │   ├── backend/                  # Embedded Node.js backend
│   │   │   ├── dist/                 # Compiled TypeScript
│   │   │   ├── node_modules/         # Production dependencies
│   │   │   ├── package.json
│   │   │   └── data/                 # SQLite database location
│   │   └── node/                     # Embedded Node.js runtime
│   │       └── bin/
│   │           └── node              # Node.js v22.21.1 (arm64)
│   └── Frameworks/                   # (reserved for future use)
```

### Backend Lifecycle

The SwiftUI app manages the backend process via `BackendManager`:

1. **App Launch**: Frontend starts backend process automatically
2. **Health Checks**: Periodic health checks ensure backend is responsive
3. **App Termination**: Backend is gracefully stopped when app quits

### Architecture Target

- **Platform**: macOS 14.0+ (Sonoma and later)
- **Architecture**: Apple Silicon (arm64) only
- **Node.js**: v20.20.0 embedded
- **Swift**: Latest stable toolchain

## Troubleshooting

### Build Issues

**Problem**: `Node.js version mismatch warning`
```bash
# The build script detected you're not using Node.js 20
# Solution: Switch to Node.js 20 via NVM
nvm use 20.20.0
# Or simply:
nvm use  # Uses version from .nvmrc

# Then rebuild
./scripts/build-unified.sh
```

**Problem**: `Node.js runtime not found`
```bash
# Solution: Delete cached runtime and rebuild
rm -rf tools/node-runtime
./scripts/build-unified.sh
```

**Problem**: `Frontend build failed`
```bash
# Solution: Clean Swift build
cd frontend
swift package clean
cd ..
./scripts/build-unified.sh
```

**Problem**: `Backend build failed`
```bash
# Solution: Clean and rebuild backend
cd backend
rm -rf dist node_modules
nvm use  # Ensure correct Node version!
npm install
npm run build
cd ..
./scripts/build-unified.sh
```

**Problem**: `better-sqlite3` compilation errors or crashes
```bash
# This usually means Node.js version mismatch
# The bundled app uses Node 20.20.0, so you must build with Node 20
nvm use 20.20.0
cd backend
rm -rf node_modules
npm install
cd ..
./scripts/build-unified.sh
```

### Runtime Issues

**Problem**: App won't open (security warning)
```bash
# Solution: Remove quarantine attribute
xattr -cr /Applications/Anchor.app
```

**Problem**: `SDK protocol version mismatch` error
```bash
# The Copilot CLI is outdated - must be v0.0.400+
# Solution: Update Copilot CLI in your Node 20 environment
nvm use 20.20.0
npm update -g @github/copilot
copilot --version  # Verify it shows 0.0.400 or later
```

**Problem**: Backend fails to start / Copilot not found
```bash
# Ensure Copilot CLI is installed in your Node 20 environment
nvm use 20.20.0
npm install -g @github/copilot
copilot auth login
```

**Problem**: Permission denied errors
```bash
# Solution: Fix permissions
chmod +x /Applications/Anchor.app/Contents/MacOS/Anchor
chmod +x /Applications/Anchor.app/Contents/Resources/node/bin/node
```

## Development vs Production

### Development Mode

During development, run frontend and backend separately:

```bash
# Terminal 1: Backend
cd Anchor/backend
npm run dev

# Terminal 2: Frontend
cd Anchor/frontend
swift run
```

### Production Mode

For distribution, use the unified bundle:

```bash
./scripts/build-unified.sh
./scripts/create-dmg.sh 1.0.0
```

## Customization

### Change App Version

Edit in `build-unified.sh`:
```bash
APP_VERSION="1.0.0"  # Change this
```

### Change Default Port

The app uses port **3847** by default. To customize:

**Option 1: Set environment variable before running**
```bash
export ANCHOR_PORT=4000
open /Applications/Anchor.app
```

**Option 2: Modify default in code**
- Backend: Edit `Anchor/backend/src/config.ts` → `SERVER_PORT`
- Frontend: Edit `Anchor/frontend/Sources/Configuration.swift` → `backendPort` default

**Option 3: Use custom URLs**
```bash
export ANCHOR_API_URL=http://localhost:4000/api
export ANCHOR_WS_URL=ws://localhost:4000/ws
open /Applications/Anchor.app
```

### Change Node.js Version

Edit in `build-unified.sh`:
```bash
NODE_VERSION="22.21.1"  # Change this
```

### Add App Icon

1. Create `Anchor/assets/AppIcon.icns`
2. The build script will automatically include it

### Add DMG Background

1. Create a 600x400 PNG: `Anchor/assets/dmg-background.png`
2. The DMG script will automatically use it

## Code Signing (Future)

For wider distribution, you'll need to code sign:

```bash
# Sign the app (requires Apple Developer ID)
codesign --deep --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime \
  build/dist/Anchor.app

# Notarize (requires Apple Developer account)
xcrun notarytool submit build/Anchor-1.0.0.dmg \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait
```

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '20'
      
      - name: Install create-dmg
        run: brew install create-dmg
      
      - name: Build App Bundle
        run: ./scripts/build-unified.sh
      
      - name: Create DMG
        run: ./scripts/create-dmg.sh ${GITHUB_REF#refs/tags/v}
      
      - name: Upload Release
        uses: softprops/action-gh-release@v1
        with:
          files: build/*.dmg
```

## License

MIT License - See LICENSE file for details.

---

**Last Updated**: February 1, 2026  
**For**: Anchor v1.0.0  
**Platform**: macOS (Apple Silicon)
