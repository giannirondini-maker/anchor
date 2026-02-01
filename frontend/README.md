# Anchor Frontend

Native macOS SwiftUI application for Anchor - a chat client for GitHub Copilot.

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.9+

## Backend Dependency

The frontend requires the backend server to be running. For development:

```bash
# In a separate terminal
cd backend
nvm use        # Important: Use Node 20.20.0
npm install
npm run dev
```

See [backend/README.md](../backend/README.md) for full setup instructions, including Copilot CLI installation.

## Setup

### Option 1: Using Xcode (Recommended)

1. Open the package directly in Xcode:
   ```bash
   cd frontend
   open Package.swift
   ```

2. Wait for Xcode to resolve dependencies

3. Select the "Anchor" scheme and click Run (⌘R)

### Option 2: Command Line Build & Run

1. Build the project:
   ```bash
   cd frontend
   swift build
   ```

2. Run the built application (path varies by architecture):
   ```bash
   # On Apple Silicon (M1/M2/M3):
   .build/arm64-apple-macosx/debug/Anchor
   
   # On Intel Macs:
   .build/x86_64-apple-macosx/debug/Anchor
   ```

### Option 3: Create Release Build

1. Build for release:
   ```bash
   swift build -c release
   ```

2. The executable will be at:
   ```bash
   # Apple Silicon:
   .build/arm64-apple-macosx/release/Anchor
   
   # Intel:
   .build/x86_64-apple-macosx/release/Anchor
   ```

## Configuration

### Model selection behavior when creating conversations

- When creating a conversation without specifying a model the frontend will:
  1. Use the requested `model` if provided when calling the API.
  2. Prefer `Configuration.defaultModel` **if it appears in the backend/SDK-provided `availableModels` list**.
  3. If the configured default is missing, pick the **first model with `multiplier == 0`** from `availableModels` (free/no-cost model) when available.
  4. Otherwise use the first model in `availableModels` and fallback to `Configuration.defaultModel` if no models are available.

- Note: multipliers are reported by the backend/SDK (billing info) and are not altered by the frontend.

## Configuration

The frontend can be configured via environment variables. These allow you to connect to different backend servers or change default settings.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ANCHOR_API_URL` | `http://localhost:3848/api` | Backend API base URL (HTTP/REST endpoints - dev mode) |
| `ANCHOR_WS_URL` | `ws://localhost:3848/ws` | WebSocket URL for real-time streaming (dev mode) |
| `ANCHOR_DEFAULT_MODEL` | `gpt-5-mini` | Default model to use when creating conversations |

### How to Set Environment Variables

#### Via Command Line (swift run)

```bash
# Set a single variable
ANCHOR_API_URL="http://api.example.com" swift run

# Set multiple variables
ANCHOR_API_URL="http://localhost:3848/api" \
ANCHOR_WS_URL="ws://localhost:3848/ws" \
ANCHOR_DEFAULT_MODEL="claude-sonnet-4-20250514" \
swift run
```

#### Via Command Line (direct executable)

```bash
# Build first
swift build

# Then run with environment variables
ANCHOR_API_URL="http://localhost:3848/api" \
ANCHOR_WS_URL="ws://localhost:3848/ws" \
.build/debug/Anchor
```

#### Via Xcode Scheme

1. Click on the scheme selector (Anchor scheme dropdown)
2. Select "Edit Scheme..."
3. Go to the "Run" tab
4. Expand "Arguments"
5. In "Environment Variables" section, add:
   - `ANCHOR_API_URL` = `http://localhost:3848/api`
   - `ANCHOR_WS_URL` = `ws://localhost:3848/ws`
   - `ANCHOR_DEFAULT_MODEL` = `claude-sonnet-4-20250514`

6. Click "Close" and run normally (⌘R)

#### Via Shell Profile (.zshrc / .bashrc)

Add to your shell profile for persistent configuration across all terminal sessions:

```bash
# Add to ~/.zshrc or ~/.bashrc
export ANCHOR_API_URL="http://localhost:3848/api"
export ANCHOR_WS_URL="ws://localhost:3848/ws"
export ANCHOR_DEFAULT_MODEL="claude-sonnet-4-20250514"
```

Then reload your shell:
```bash
source ~/.zshrc  # for zsh
# or
source ~/.bashrc # for bash
```

### Example Configurations

**Local Development (Default)**
```bash
# These are the defaults - no configuration needed
ANCHOR_API_URL="http://localhost:3848/api"
ANCHOR_WS_URL="ws://localhost:3848/ws"
ANCHOR_DEFAULT_MODEL="gpt-5-mini"
```

**Remote Production Server**
```bash
ANCHOR_API_URL="https://api.myserver.com/api"
ANCHOR_WS_URL="wss://api.myserver.com/ws"
ANCHOR_DEFAULT_MODEL="claude-sonnet-4-20250514"
```

**Using Claude Model**
```bash
ANCHOR_DEFAULT_MODEL="claude-sonnet-4-20250514"
```

## Troubleshooting

### Window not appearing with `swift run`

SwiftUI macOS apps built with SPM sometimes have issues displaying windows when run via `swift run`. Try these solutions:

1. **Run the executable directly:**
   ```bash
   swift build && .build/debug/Anchor
   ```

2. **Use Xcode instead:**
   ```bash
   open Package.swift
   ```
   Then run from Xcode with ⌘R

3. **Check the Dock:** The app may be running but not in the foreground. Look for the Anchor icon in the Dock and click it.

### `swift package generate-xcodeproj` not working

This command was deprecated in Swift 5.6. Use one of these alternatives:

- **Open Package.swift directly in Xcode** (recommended):
  ```bash
  open Package.swift
  ```

- **Use xcodegen** (if you need a traditional .xcodeproj):
  ```bash
  brew install xcodegen
  xcodegen generate
  ```

## Project Structure

```
frontend/
├── Package.swift           # Swift Package Manager manifest
├── Sources/
│   ├── AnchorApp.swift     # App entry point
│   ├── AppState.swift      # Global state management
│   ├── Models/
│   │   └── Models.swift    # Data models
│   ├── Services/
│   │   ├── NetworkService.swift    # HTTP API client
│   │   └── WebSocketService.swift  # WebSocket client
│   └── Views/
│       ├── MainWindowView.swift    # Main window container
│       ├── SidebarView.swift       # Conversation list
│       ├── ChatView.swift          # Chat container
│       ├── ChatHeaderView.swift    # Chat header with model selector
│       ├── MessageListView.swift   # Message display
│       └── MessageInputView.swift  # Message input
└── README.md
```

## Dependencies

- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) - Markdown rendering

## Features

- Native macOS interface with sidebar navigation
- Real-time message streaming via WebSocket
- Markdown rendering for assistant responses
- Conversation management (create, rename, delete)
- Model selection dropdown
- Copy messages to clipboard with visual feedback
- Keyboard shortcuts (Enter to send, Shift+Enter for newline)

## WebSocket Connection

The `WebSocketService` manages real-time communication with the backend:

### Connection States

| State | Description |
|-------|-------------|
| `disconnected` | No active connection |
| `connecting` | Connection in progress |
| `connected` | Connected and ready (confirmed by server's `session:idle` event) |
| `reconnecting(attempt)` | Attempting to reconnect (1-5 attempts with exponential backoff) |

### Features

- **Server-confirmed connection**: `isConnected` only becomes `true` after receiving `session:idle` from server
- **Automatic reconnection**: Exponential backoff (2s, 4s, 8s, 16s, 32s) up to 5 attempts
- **Keep-alive ping**: Sends ping every 30 seconds to detect stale connections
- **Clean conversation switching**: Properly closes old connections before opening new ones

## Backend Connection

The frontend connects to the backend at:
- HTTP: `http://localhost:3848/api` (development) or `http://localhost:3847/api` (production)
- WebSocket: `ws://localhost:3848/ws` (development) or `ws://localhost:3847/ws` (production)

Make sure the backend is running before launching the frontend.
