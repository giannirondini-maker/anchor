# CLAUDE.md — Anchor

**Anchor** is a native macOS chat client for GitHub Copilot, providing a ChatGPT-like experience. It consists of a SwiftUI frontend, a Node.js/TypeScript backend, and SQLite for local conversation persistence.

---

## Stack

| Layer | Tech |
|-------|------|
| Frontend | SwiftUI, macOS 14+, Swift 5.9+ |
| Backend | Node.js 22.x LTS, TypeScript, Express, WebSocket (`ws`) |
| Database | SQLite via `better-sqlite3` (synchronous) |
| LLM | GitHub Copilot SDK (`@github/copilot-sdk`) via Copilot CLI |
| Build | Swift Package Manager, npm/tsx, shell scripts |

---

## Project Structure

```
Anchor/
├── backend/src/
│   ├── index.ts                    # Bootstrap
│   ├── server.ts                   # Express + WebSocket setup
│   ├── config.ts                   # Config / env management
│   ├── routes/                     # HTTP route handlers
│   ├── services/
│   │   ├── copilot.service.ts      # Copilot SDK wrapper
│   │   ├── database.service.ts     # SQLite operations
│   │   └── attachment.service.ts   # File upload/context building
│   ├── middleware/
│   ├── types/index.ts              # Shared TypeScript types + ErrorCodes enum
│   └── websocket/
├── backend/tests/                  # Vitest tests (api.integration.test.ts)
│
├── frontend/Sources/
│   ├── AnchorApp.swift             # Entry point
│   ├── AppState.swift              # ObservableObject global state
│   ├── Configuration.swift         # Port/URL config
│   ├── Models.swift                # Data models
│   ├── Services/
│   │   ├── NetworkService.swift    # HTTP client
│   │   └── WebSocketService.swift  # WS client
│   └── Views/                      # SwiftUI views
├── frontend/Tests/                 # Swift Testing files
│
├── scripts/
│   ├── build-unified.sh            # Creates .app bundle
│   └── create-dmg.sh               # Creates DMG installer
└── assets/                         # App icons
```

---

## Environments

| Aspect | Development | Production |
|--------|-------------|------------|
| Port | 3848 | 3847 |
| DB | `~/Library/Application Support/Anchor-Dev/data.sqlite` | `~/Library/Application Support/Anchor/data.sqlite` |
| Backend | Started manually (`npm run dev`) | Embedded in `.app` bundle |
| Detection | Bundle path has `DerivedData`, `.build`, or `Build/Products` | Bundled `.app` |

**Env var overrides**: `ANCHOR_ENV`, `PORT`, `DATABASE_PATH`, `ANCHOR_PORT`, `ANCHOR_API_URL`, `ANCHOR_WS_URL`

---

## Key Commands

```bash
# Backend (dev)
cd backend
nvm use          # ALWAYS run first — must be Node 22.x
npm install
npm run dev      # hot reload on port 3848
npm test         # Vitest
npm run build    # tsc → dist/

# Frontend
cd frontend
swift build
swift run
swift test \
  -Xswiftc -F -Xswiftc "/Library/Developer/CommandLineTools/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "/Library/Developer/CommandLineTools/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

# Production build
nvm use
./scripts/build-unified.sh   # creates build/dist/Anchor.app
./scripts/create-dmg.sh      # creates Anchor-*.dmg
```

---

## WebSocket Protocol

**Client → Server**:
```typescript
{ type: "chat", sessionId: string, content: string }
{ type: "ping" }
```

**Server → Client**:
```typescript
{ type: "chunk", content: string }       // streaming token
{ type: "done", fullContent: string }    // stream complete
{ type: "error", error: string, code?: string }
{ type: "pong" }
```

WebSocket events from README (actual protocol):
- `session:idle` — ready
- `message:start` / `message:delta` / `message:complete` / `message:error`

---

## API Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/api/status` | Copilot connection status |
| GET | `/api/models` | Available LLM models |
| POST | `/api/sessions` | Create session |
| DELETE | `/api/sessions/:id` | End session |
| GET/POST | `/api/conversations` | List / create |
| PUT/DELETE | `/api/conversations/:id` | Update / delete |
| GET | `/api/tags` | List tags |
| POST | `/api/tags` | Create tag |
| POST | `/api/attachments` | Upload file |
| PUT | `/api/attachments/:id` | Rename |
| DELETE | `/api/attachments/:id` | Delete |

---

## Attachments

- **Backend**: `attachment.service.ts` stages on disk, builds a text context block for prompts
- **Supported**: text, markdown, CSV, JSON, PDF (`pdf-parse` — call `destroy()` after extraction), images
- **Disabled**: Excel formats
- **Frontend**: `NSOpenPanel` + `startAccessingSecurityScopedResource()` to read/upload; pending attachments live in `ChatViewModel.pendingAttachments`

---

## Code Style

**TypeScript**: `async/await`, singleton exports, `strict: true`, JSDoc on public methods.

**Swift**: `@Observable` macro (macOS 14+), `async/await`, `@MainActor` for UI code.

---

## Critical Requirements

1. **Node.js 22.x** — native modules (`better-sqlite3`) must match the bundled runtime. Run `nvm use` before any npm command.
2. **Copilot CLI v1.0.34+** — required for SDK protocol version 3.
3. **macOS 14.0+** — minimum for SwiftUI features used.

---

## Adding New Features (Checklist)

**New API endpoint**:
1. Add types in `backend/src/types/index.ts`
2. Add route in `backend/src/routes/`
3. Register in `backend/src/server.ts`
4. Add method in `frontend/Sources/Services/NetworkService.swift`
5. Write tests in `backend/tests/`

**New SwiftUI view**:
1. Create in `frontend/Sources/Views/`
2. Wire into `MainWindowView` or parent
3. Update `AppState` if new state is needed
4. Write tests in `frontend/Tests/`

**Schema change**:
1. Update `database.service.ts`
2. Add migration logic for existing users
3. Update `backend/src/types/`
4. Update `frontend/Sources/Models.swift`

---

## Testing

```bash
# Backend
cd backend && npm test              # all tests
cd backend && npm run test:coverage # coverage

# Frontend — Swift Testing (Xcode NOT required, CLI tools only)
cd frontend && swift test \
  -Xswiftc -F -Xswiftc "/Library/Developer/CommandLineTools/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "/Library/Developer/CommandLineTools/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
```

Test files: `backend/tests/*.test.ts` — key file is `api.integration.test.ts` (uses in-memory DB).

Frontend tests use **Swift Testing** (`import Testing`), not XCTest. Test structs use `@Test` functions and `#expect()` assertions. See repo memory `anchor-swift-testing.md` for type disambiguation and flag details.

---

## Error Codes (`backend/src/types/index.ts`)

```typescript
SESSION_NOT_FOUND | MODEL_NOT_AVAILABLE | AUTHENTICATION_REQUIRED |
RATE_LIMITED | SDK_ERROR | DATABASE_ERROR
```

---

## Release

1. Bump version in `backend/package.json`, `scripts/build-unified.sh`, `scripts/create-dmg.sh`
2. `./scripts/build-unified.sh && ./scripts/create-dmg.sh`
3. Test DMG on a clean system
4. GitHub release with DMG + `checksums.txt` + release notes
