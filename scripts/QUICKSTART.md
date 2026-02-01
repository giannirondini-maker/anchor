# Quick Start: Building Anchor for Distribution

## TL;DR

```bash
# ⚠️ IMPORTANT: Use Node.js 20.20.0 via NVM
nvm use

# Build everything
./scripts/build-unified.sh

# Create DMG
./scripts/create-dmg.sh 1.0.0

# Done! Upload build/Anchor-1.0.0.dmg to GitHub releases
```

> **Note:** The bundled app uses Node.js 20.20.0. You must use the same version when building to avoid native module compatibility issues with `better-sqlite3`.

## What Was Implemented

✅ **BackendManager Service** ([BackendManager.swift](../Anchor/frontend/Sources/Services/BackendManager.swift))
  - Manages embedded Node.js backend lifecycle
  - Automatic health checks
  - Graceful startup/shutdown
  - Error handling and logging

✅ **App Lifecycle Integration** ([AnchorApp.swift](../Anchor/frontend/Sources/AnchorApp.swift))
  - Backend starts automatically on app launch
  - Backend stops when app quits
  - Exposed to all views via `@EnvironmentObject`

✅ **Unified Build Script** ([build-unified.sh](./build-unified.sh))
  - Downloads Node.js runtime for Apple Silicon
  - Builds frontend (Swift for arm64)
  - Builds backend (TypeScript → JavaScript)
  - Creates complete `.app` bundle
  - Generates Info.plist

✅ **DMG Creation Script** ([create-dmg.sh](./create-dmg.sh))
  - Professional DMG with drag-to-install UI
  - Release notes generation
  - SHA256 checksums
  - Upload instructions

## First Time Setup

```bash
# 1. Install NVM (if not already installed)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# 2. Install correct Node.js version
nvm install 20.20.0

# 3. Install Copilot CLI and authenticate
nvm use 20.20.0
npm install -g @github/copilot
copilot auth login

# 4. Install create-dmg for distribution
brew install create-dmg

# 5. Make scripts executable (already done)
chmod +x scripts/*.sh
```

## Build & Test Locally

```bash
# Ensure correct Node version
nvm use

# Build the app
./scripts/build-unified.sh

# Test it
open build/dist/Anchor.app

# If you see security warning:
xattr -cr build/dist/Anchor.app
open build/dist/Anchor.app
```

## Create Release

```bash
# Create DMG
./scripts/create-dmg.sh 1.0.0

# Test DMG
open build/Anchor-1.0.0.dmg

# Upload to GitHub (manual)
# - Go to https://github.com/yourusername/anchor/releases/new
# - Upload build/Anchor-1.0.0.dmg
# - Copy release notes from build/RELEASE_NOTES.md

# Or upload via GitHub CLI
gh release create v1.0.0 \
  build/Anchor-1.0.0.dmg \
  --title "Anchor v1.0.0" \
  --notes-file build/RELEASE_NOTES.md
```

## Key Features

### Single App Bundle
- ✅ No external dependencies
- ✅ Embedded Node.js runtime
- ✅ Self-contained backend
- ✅ Native macOS experience

### Apple Silicon Only
- ✅ Optimized for M1/M2/M3
- ✅ Smaller download size
- ✅ Better performance
- ❌ Intel Macs not supported (by design)

### GitHub Copilot Integration
- ✅ Uses GitHub Copilot SDK
- ✅ No API keys needed
- ✅ Automatic authentication via GitHub CLI
- ⚠️ Users need GitHub Copilot CLI installed

## Sharing with Colleagues

1. **Build and create DMG** (as shown above)
2. **Share the DMG file** (via Google Drive, Dropbox, etc.)
3. **Tell them to:**
   - Install GitHub CLI: `brew install gh`
   - Install Copilot: `gh extension install github/gh-copilot`
   - Authenticate: `gh auth login`
   - Open the DMG and drag Anchor to Applications
   - If security warning: `xattr -cr /Applications/Anchor.app`

## File Locations

| File | Purpose |
|------|---------|
| [BackendManager.swift](../Anchor/frontend/Sources/Services/BackendManager.swift) | Backend process management |
| [AnchorApp.swift](../Anchor/frontend/Sources/AnchorApp.swift) | App lifecycle with backend integration |
| [build-unified.sh](./build-unified.sh) | Main build script |
| [create-dmg.sh](./create-dmg.sh) | DMG creation script |
| [README.md](./README.md) | Detailed documentation |

## Troubleshooting

**Build fails?**
```bash
# Clean everything and rebuild
rm -rf build tools/node-runtime
./scripts/build-unified.sh
```

**App won't open?**
```bash
xattr -cr /Applications/Anchor.app
```

**Backend not starting?**
```bash
# Check GitHub CLI is installed
gh --version
gh extension list  # Should show github/gh-copilot
```

**Custom port needed?**
```bash
# Set custom port via environment variable
export ANCHOR_PORT=4000
open /Applications/Anchor.app
```

## Next Steps

- [ ] Test the build process locally
- [ ] Create your first DMG
- [ ] Test on a clean Mac
- [ ] Share with colleagues
- [ ] (Optional) Add custom app icon to `Anchor/assets/AppIcon.icns`
- [ ] (Optional) Add DMG background to `Anchor/assets/dmg-background.png`
- [ ] (Optional) Set up GitHub Actions for automated builds

## Questions?

See [README.md](./README.md) for detailed documentation.

---

**Ready to build?** Just run: `./scripts/build-unified.sh`
