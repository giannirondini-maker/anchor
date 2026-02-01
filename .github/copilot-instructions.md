# Copilot Instructions for Anchor

This document provides comprehensive guidance for AI-assisted development on the Anchor project.

## Project Overview

**Anchor** is a native macOS chat client for GitHub Copilot, providing a ChatGPT-like experience. It consists of:

- **Frontend**: Native SwiftUI macOS application
- **Backend**: Node.js/TypeScript server using the GitHub Copilot SDK
- **Build System**: Shell scripts for creating distributable `.app` bundles and DMG installers

### Key Technologies

| Component | Technology | Version Requirements |
|-----------|------------|---------------------|
| Frontend | SwiftUI | macOS 14.0+, Swift 5.9+ |
| Backend | Node.js/TypeScript | Node.js 20.x LTS |
| Database | SQLite (better-sqlite3) | Embedded |
| Build | Swift Package Manager, npm | Xcode 15+ |
| Distribution | DMG Installer | Apple Silicon (arm64) |

---

## Project Structure

```
Anchor/
├── .nvmrc                    # Node version specification (20.20.0)
├── README.md                 # Project documentation
├── assets/                   # App icons and images
│
├── backend/                  # Node.js/TypeScript backend
│   ├── package.json
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   ├── src/
│   │   ├── index.ts          # Entry point
│   │   ├── server.ts         # HTTP/WebSocket server
│   │   ├── config.ts         # Configuration management
│   │   ├── middleware/       # Express middleware
│   │   ├── routes/           # API route handlers
│   │   ├── services/         # Business logic
│   │   │   ├── copilot.service.ts    # Copilot SDK wrapper
│   │   │   └── database.service.ts   # SQLite operations
│   │   ├── types/            # TypeScript type definitions
│   │   └── websocket/        # WebSocket handlers
│   └── tests/                # Vitest test files
│
├── frontend/                 # SwiftUI macOS app
│   ├── Package.swift         # Swift Package Manager manifest
│   ├── Package.resolved      # Dependency lock file
│   ├── Sources/              # Swift source files
│   │   ├── AnchorApp.swift   # App entry point
│   │   ├── AppState.swift    # Global state management
│   │   ├── Configuration.swift
│   │   ├── Models.swift      # Data models
│   │   ├── Services/         # Network, WebSocket services
│   │   └── Views/            # SwiftUI views
│   └── Tests/                # XCTest files
│
├── scripts/                  # Build and packaging scripts
│   ├── build-unified.sh      # Creates .app bundle
│   ├── create-dmg.sh         # Creates DMG installer
│   ├── QUICKSTART.md
│   └── README.md
│
├── build/                    # Build output directory
│   ├── dist/Anchor.app       # Built application
│   ├── Anchor-*.dmg          # DMG installer
│   └── checksums.txt
│
└── tools/
    └── node-runtime/         # Embedded Node.js for distribution
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         macOS Application                           │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    SwiftUI Frontend                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │  ChatView   │  │ SidebarView │  │  SettingsView       │    │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘    │  │
│  │         │                │                     │              │  │
│  │  ┌──────▼────────────────▼─────────────────────▼──────────┐   │  │
│  │  │                    AppState                            │   │  │
│  │  │  (ObservableObject - Global State Management)          │   │  │
│  │  └──────────────────────┬─────────────────────────────────┘   │  │
│  │                         │                                     │  │
│  │  ┌──────────────────────▼─────────────────────────────────┐   │  │
│  │  │              NetworkService / WebSocketService         │   │  │
│  │  └──────────────────────┬─────────────────────────────────┘   │  │
│  └─────────────────────────┼─────────────────────────────────────┘  │
│                            │ HTTP/WebSocket                         │
│  ┌─────────────────────────▼─────────────────────────────────────┐  │
│  │                  Embedded Node.js Backend                     │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │                   Express Server                        │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐   │  │  │
│  │  │  │  Routes  │  │Middleware│  │  WebSocket Server    │   │  │  │
│  │  │  └────┬─────┘  └──────────┘  └──────────┬───────────┘   │  │  │
│  │  └───────┼────────────────────────────────┼────────────────┘  │  │
│  │          │                                │                   │  │
│  │  ┌───────▼────────────────────────────────▼────────────────┐  │  │
│  │  │                    Services Layer                       │  │  │
│  │  │  ┌─────────────────────┐  ┌─────────────────────────┐   │  │  │
│  │  │  │  CopilotService     │  │  DatabaseService        │   │  │  │
│  │  │  │  (SDK Wrapper)      │  │  (SQLite)               │   │  │  │
│  │  │  └─────────┬───────────┘  └─────────────────────────┘   │  │  │
│  │  └────────────┼────────────────────────────────────────────┘  │  │
│  └───────────────┼───────────────────────────────────────────────┘  │
└──────────────────┼──────────────────────────────────────────────────┘
                   │ JSON-RPC
┌──────────────────▼───────────────────────────────────────────────────┐
│                     GitHub Copilot CLI                               │
│                   (@github/copilot v0.0.400+)                        │
└──────────────────────────────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     GitHub Copilot API                               │
│              (GPT-4, Claude, and other models)                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Development Guidelines

### Environment Setup

```bash
# 1. Clone and enter directory
git clone <repo-url> && cd Anchor

# 2. Use correct Node.js version (CRITICAL)
nvm use  # Uses .nvmrc (20.20.0)

# 3. Install and authenticate Copilot CLI
npm install -g @github/copilot
copilot auth login
copilot --version  # Must be 0.0.400+

# 4. Backend setup (development mode)
cd backend
npm install
npm run dev  # Starts on port 3848 with dev database

# 5. Frontend setup (separate terminal)
cd frontend
swift build && .build/arm64-apple-macosx/debug/Anchor
# Or: open Package.swift  # Opens in Xcode
```

### Development vs Production Environments

The app supports separate development and production environments:

| Aspect | Development | Production |
|--------|-------------|------------|
| **Port** | 3848 | 3847 |
| **Database** | `~/Library/Application Support/Anchor-Dev/data.sqlite` | `~/Library/Application Support/Anchor/data.sqlite` |
| **Backend** | Started manually (`npm run dev`) | Embedded in app bundle |
| **Detection** | Bundle path contains `DerivedData`, `.build`, or `Build/Products` | Bundled `.app` |

**Environment Variables** (optional overrides):
- `ANCHOR_ENV`: Set to `development` or `production` to override auto-detection
- `ANCHOR_PORT`: Override the port (frontend)
- `PORT`: Override the port (backend)
- `DATABASE_PATH`: Override the database path (backend)

### Critical Requirements

1. **Node.js Version**: Always use Node.js 20.x. Native modules (`better-sqlite3`) must match the bundled runtime version.

2. **Copilot CLI Version**: Must be v0.0.400+ for SDK protocol version 2 compatibility.

3. **macOS Version**: Minimum macOS 14.0 (Sonoma) for SwiftUI features.

---

## Backend Architecture

### Entry Points

- **`src/index.ts`**: Application bootstrap, initializes services
- **`src/server.ts`**: Express server factory with HTTP and WebSocket setup

### Key Services

#### CopilotService (`src/services/copilot.service.ts`)

Wraps the GitHub Copilot SDK for LLM interactions:

```typescript
// Key methods
class CopilotService {
  async initialize(): Promise<void>           // Connect to Copilot CLI
  async getAuthStatus(): Promise<AuthStatus>  // Check authentication
  async listModels(): Promise<ModelInfo[]>    // Available LLM models
  async createSession(model: string): Promise<string>  // Start chat session
  async sendMessage(sessionId: string, content: string): AsyncGenerator<string>
}
```

**Session Management**:
- Sessions are cached with metadata (model, timestamps, message count)
- Idle timeout: 30 minutes
- Max history messages for context: 50

#### DatabaseService (`src/services/database.service.ts`)

SQLite-based persistence for conversations and tags:
- Uses `better-sqlite3` for synchronous operations
- In-memory database supported for testing (`:memory:`)

### API Routes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/api/status` | Copilot connection status |
| GET | `/api/models` | List available models |
| POST | `/api/sessions` | Create chat session |
| DELETE | `/api/sessions/:id` | End session |
| GET | `/api/conversations` | List conversations |
| POST | `/api/conversations` | Create conversation |
| PUT | `/api/conversations/:id` | Update conversation |
| DELETE | `/api/conversations/:id` | Delete conversation |
| GET | `/api/tags` | List tags |
| POST | `/api/tags` | Create tag |

### WebSocket Protocol

Connection: `ws://localhost:3001/ws`

**Client → Server Messages**:
```typescript
{ type: "chat", sessionId: string, content: string }
{ type: "ping" }
```

**Server → Client Messages**:
```typescript
{ type: "chunk", content: string }      // Streaming response
{ type: "done", fullContent: string }   // Stream complete
{ type: "error", error: string, code?: string }
{ type: "pong" }
```

---

## Frontend Architecture

### State Management

**AppState** (`Sources/AppState.swift`): Central `ObservableObject` managing:
- Current conversation and messages
- WebSocket connection state
- Backend status
- User preferences

### Key Views

| View | Purpose |
|------|---------|
| `MainWindowView` | Root container with sidebar and content |
| `ChatView` | Message display and input |
| `SidebarView` | Conversation list and navigation |
| `SettingsView` | User preferences |
| `TagEditorView` | Tag management |

### Services

- **NetworkService**: HTTP API client for REST endpoints
- **WebSocketService**: Real-time chat communication
- **BackendManager**: Manages embedded backend lifecycle (in bundled app)

### Configuration

```swift
struct Configuration {
    static let backendHost = "localhost"
    static let backendPort = 3001
    static let wsEndpoint = "ws://localhost:3001/ws"
}
```

---

## Build System

### Development Build

```bash
# Backend (with hot reload)
cd backend && npm run dev

# Frontend
cd frontend && swift build
# Or open Package.swift in Xcode
```

### Production Build

```bash
# Ensure Node 20
nvm use

# Build unified app bundle
./scripts/build-unified.sh

# Create DMG installer
./scripts/create-dmg.sh
```

**Build Output**:
```
build/
├── dist/
│   └── Anchor.app/
│       ├── Contents/
│       │   ├── MacOS/Anchor          # Swift executable
│       │   ├── Resources/
│       │   │   ├── backend/          # Compiled TypeScript
│       │   │   └── node/             # Embedded Node.js runtime
│       │   └── Info.plist
├── Anchor-1.0.0.dmg
├── checksums.txt
└── RELEASE_NOTES.md
```

### What build-unified.sh Does

1. Validates environment (Node version, Xcode tools)
2. Downloads Node.js v22.21.1 for Apple Silicon
3. Builds backend (`tsc`) and installs production dependencies
4. Builds frontend (`swift build -c release`)
5. Creates `.app` bundle structure
6. Embeds backend and Node.js runtime
7. Generates `Info.plist`
8. Sets executable permissions

---

## Testing

### Backend Tests

```bash
cd backend
npm test              # Run all tests
npm run test:watch    # Watch mode
npm run test:coverage # Coverage report
```

Test files: `backend/tests/*.test.ts`

Key test file: `api.integration.test.ts` - Tests HTTP routes with in-memory database.

### Frontend Tests

```bash
cd frontend
swift test
# Or run in Xcode: ⌘U
```

Test files: `frontend/Tests/`
- `AppStateTests.swift`
- `ConfigurationTests.swift`
- `ModelsTests.swift`
- `TagEditorTests.swift`

---

## Common Development Tasks

### Adding a New API Endpoint

1. Define types in `backend/src/types/index.ts`
2. Add route handler in `backend/src/routes/`
3. Register route in `backend/src/server.ts`
4. Add corresponding method in `frontend/Sources/Services/NetworkService.swift`
5. Write tests in `backend/tests/`

### Adding a New SwiftUI View

1. Create view file in `frontend/Sources/Views/`
2. Add navigation in `MainWindowView` or parent view
3. Update `AppState` if new state is needed
4. Write tests in `frontend/Tests/`

### Modifying Database Schema

1. Update schema in `backend/src/services/database.service.ts`
2. Add migration logic if needed (for existing users)
3. Update TypeScript types in `backend/src/types/`
4. Update Swift models in `frontend/Sources/Models.swift`

### Adding a New Copilot Feature

1. Check SDK capabilities in `@github/copilot-sdk`
2. Extend `CopilotService` in `backend/src/services/copilot.service.ts`
3. Add API route if HTTP access needed
4. Add WebSocket message type if real-time needed
5. Update frontend services and views

---

## Error Handling

### Backend Error Codes

Defined in `backend/src/types/index.ts`:

```typescript
enum ErrorCodes {
  SESSION_NOT_FOUND = "SESSION_NOT_FOUND",
  MODEL_NOT_AVAILABLE = "MODEL_NOT_AVAILABLE",
  AUTHENTICATION_REQUIRED = "AUTHENTICATION_REQUIRED",
  RATE_LIMITED = "RATE_LIMITED",
  SDK_ERROR = "SDK_ERROR",
  DATABASE_ERROR = "DATABASE_ERROR"
}
```

### Frontend Error Handling

- Network errors: Displayed via `AppState.errorMessage`
- WebSocket disconnects: Auto-reconnect with exponential backoff
- Backend unavailable: Show connection status indicator

---

## Configuration Reference

### Backend (`backend/src/config.ts`)

| Variable | Default (Dev) | Default (Prod) | Description |
|----------|---------------|----------------|-------------|
| `ANCHOR_ENV` | `development` | `production` | Environment mode |
| `PORT` | 3848 | 3847 | HTTP server port |
| `DATABASE_PATH` | `~/Library/Application Support/Anchor-Dev/data.sqlite` | `~/Library/Application Support/Anchor/data.sqlite` | SQLite file path |
| `DISABLE_RATE_LIMIT` | false | false | Disable rate limiting |
| `sdk.logLevel` | "info" | "info" | Copilot SDK log level |

### Environment Variables

```bash
# Backend - Development
ANCHOR_ENV=development  # Uses port 3848 and Anchor-Dev database
PORT=3848               # Override port
DATABASE_PATH=./data/dev.db  # Override database path

# Backend - Production (bundled app)
# These are set automatically, but can be overridden:
PORT=3847
DATABASE_PATH=~/Library/Application\ Support/Anchor/data.sqlite

# Frontend
ANCHOR_ENV=development  # Force development mode
ANCHOR_PORT=3848        # Override backend port
ANCHOR_API_URL=http://localhost:3848/api  # Override API URL
ANCHOR_WS_URL=ws://localhost:3848/ws      # Override WebSocket URL

# Testing
DATABASE_PATH=:memory:   # In-memory database
```

---

## Troubleshooting Guide

### "SDK protocol version mismatch"
```bash
nvm use 20.20.0
npm update -g @github/copilot
copilot --version  # Verify 0.0.400+
```

### "Copilot CLI not found"
```bash
npm install -g @github/copilot
copilot auth login
```

### App won't open (security warning)
```bash
xattr -cr /Applications/Anchor.app
```

### Backend fails to start
```bash
# Check Node version
node --version  # Should be 20.x

# Check Copilot auth
copilot auth status
```

### Frontend build fails
```bash
# Clean build artifacts
cd frontend
rm -rf .build
swift build
```

### Database issues
```bash
# Reset database
rm backend/data/anchor.db
# Restart backend - will recreate schema
```

---

## Code Style Guidelines

### TypeScript (Backend)

- Use `async/await` over raw promises
- Export singleton services (e.g., `export const copilotService = new CopilotService()`)
- Use strict TypeScript (`strict: true` in tsconfig)
- Document public methods with JSDoc

### Swift (Frontend)

- Use SwiftUI's `@Observable` macro for state (macOS 14+)
- Prefer `async/await` over completion handlers
- Use `@MainActor` for UI-bound code
- Follow Apple's Swift API Design Guidelines

### General

- Keep functions focused (single responsibility)
- Write descriptive commit messages
- Add tests for new features
- Update documentation for API changes

---

## Dependencies

### Backend (npm)

| Package | Purpose |
|---------|---------|
| `@github/copilot-sdk` | Official Copilot SDK |
| `express` | HTTP server |
| `ws` | WebSocket server |
| `better-sqlite3` | SQLite database |
| `uuid` | ID generation |
| `vitest` | Testing framework |

### Frontend (Swift Package Manager)

| Package | Purpose |
|---------|---------|
| `swift-markdown-ui` | Markdown rendering |

---

## Release Process

1. Update version in:
   - `backend/package.json`
   - `scripts/build-unified.sh` (VERSION variable)
   - `scripts/create-dmg.sh` (VERSION variable)

2. Build and test:
   ```bash
   nvm use
   ./scripts/build-unified.sh
   ./scripts/create-dmg.sh
   ```

3. Test the DMG installation on a clean system

4. Create GitHub release with:
   - DMG file
   - Checksums
   - Release notes

---

## Security Considerations

- GitHub authentication handled by Copilot CLI (not stored in app)
- Local SQLite database (user data stays on device)
- No telemetry or external analytics
- WebSocket communication is local-only (localhost)

---

## Future Development Areas

- [ ] Possibility to provide attachments in the conversation
- [ ] CI/CD for Auto-release mechanism
