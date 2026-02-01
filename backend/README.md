# Anchor Backend

Backend service for Anchor - a native macOS Chat Client for GitHub Copilot.

## Prerequisites

- **Node.js 20.20.0** (managed via NVM - see below)
- GitHub Copilot CLI v0.0.400+ installed and authenticated
- GitHub Copilot subscription

### ⚠️ Node.js Version Requirements

The bundled app uses Node.js 20.20.0 with native dependencies (`better-sqlite3`). You **must** use the same version when developing to avoid runtime crashes.

```bash
# Install NVM if you haven't already
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Install and use the correct Node version
nvm install 20.20.0
nvm use 20.20.0

# Verify
node --version  # Should show v20.20.0
```

A `.nvmrc` file exists at the project root, so you can simply run `nvm use` from the project directory.

## Setup

1. **Ensure correct Node.js version:**
   ```bash
   nvm use
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Install and authenticate Copilot CLI:
   ```bash
   npm install -g @github/copilot
   copilot auth login
   
   # Verify version (must be 0.0.400+)
   copilot --version
   ```

4. Start the development server:
   ```bash
   npm run dev
   ```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/auth/status` | Check authentication status |
| GET | `/api/models` | List available LLM models |
| GET | `/api/agents` | List available custom agents |
| GET | `/api/conversations` | List all conversations |
| GET | `/api/conversations?q=<query>` | Search conversations by title or tag |
| POST | `/api/conversations` | Create new conversation |
| GET | `/api/conversations/:id` | Get conversation details |
| PUT | `/api/conversations/:id` | Update conversation |
| DELETE | `/api/conversations/:id` | Delete conversation |
| POST | `/api/conversations/:id/tags` | Add tag to conversation |
| DELETE | `/api/conversations/:id/tags/:tagId` | Remove tag from conversation |
| GET | `/api/conversations/:id/messages` | Get messages |
| POST | `/api/conversations/:id/messages` | Send message (triggers streaming) |


**Model selection behavior when creating conversations**

- When creating a conversation without specifying a model the backend will:
  1. Use the provided `model` if present in the request.
  2. Prefer the configured default model (`DEFAULT_MODEL`) **if it appears in the SDK-provided list**.
  3. If the configured default is missing, pick the **first SDK model with `multiplier === 0`** (free/no-cost models) when available.
  4. If no free model exists, fall back to the first model in the SDK list.
  5. If listing models fails, fall back to the configured default model.

- Note: multipliers are reported by the SDK (billing info) and are not altered by the backend.

## WebSocket

Connect to `ws://localhost:3000/ws?conversationId=<id>` to receive streaming responses.

### Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `session:idle` | Server → Client | Connection confirmed, session is ready |
| `message:start` | Server → Client | Response generation started |
| `message:delta` | Server → Client | Streaming token received |
| `message:complete` | Server → Client | Response complete |
| `message:error` | Server → Client | Error occurred |
| `pong` | Server → Client | Response to application-level ping |

### Connection Lifecycle

1. Client connects to `ws://localhost:3000/ws?conversationId=<id>`
2. Server sends `session:idle` to confirm connection
3. Client can now send messages via HTTP POST (responses streamed via WebSocket)
4. Client sends periodic pings (every 30s) to detect stale connections
5. Server responds to WebSocket-level pings automatically
6. On disconnect, client attempts reconnection with exponential backoff

## Tags API

Tags allow organizing conversations with labels. Tags are created automatically when first used and can be reused across conversations.

### Add Tag to Conversation

```bash
POST /api/conversations/:id/tags
Content-Type: application/json

{
  "name": "Important",
  "color": "#FF5733"  // optional, hex color
}
```

- If a tag with the same name exists (case-insensitive), it will be reused
- Returns the updated conversation with all tags

### Remove Tag from Conversation

```bash
DELETE /api/conversations/:id/tags/:tagId
```

- Returns the updated conversation with remaining tags

### Search by Tag

Conversations can be searched by tag name using the query parameter:

```bash
GET /api/conversations?q=important
```

This will return conversations where:
- The title contains "important", OR
- Any associated tag name contains "important"

## Directory Structure

```
src/
├── index.ts           # Entry point
├── server.ts          # HTTP/WS server setup
├── config.ts          # Configuration
├── types/
│   └── index.ts       # Type definitions
├── routes/
│   ├── health.ts      # Health check routes
│   ├── auth.ts        # Auth status routes
│   ├── models.ts      # Models routes
│   ├── agents.ts      # Agents routes
│   ├── conversations.ts # Conversation CRUD
│   └── messages.ts    # Message handling
├── services/
│   ├── copilot.service.ts  # LLM integration
│   └── database.service.ts # SQLite operations
├── websocket/
│   └── handler.ts     # WebSocket handling
└── middleware/
    └── errorHandler.ts # Error handling
```

## Development

```bash
# Start dev server with hot reload
npm run dev

# Build for production
npm run build

# Start production server
npm start
```
