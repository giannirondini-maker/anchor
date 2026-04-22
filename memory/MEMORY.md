# Anchor — Session Memory

## Project Summary
Native macOS chat client for GitHub Copilot. SwiftUI frontend + Node.js/TypeScript backend + SQLite. Backend wraps the GitHub Copilot SDK and streams responses to the frontend via WebSocket.

## Key Paths
- Backend entry: `backend/src/index.ts`
- Server setup: `backend/src/server.ts`
- Copilot SDK wrapper: `backend/src/services/copilot.service.ts`
- DB service: `backend/src/services/database.service.ts`
- Attachment service: `backend/src/services/attachment.service.ts`
- Types + ErrorCodes: `backend/src/types/index.ts`
- Frontend state: `frontend/Sources/AppState.swift`
- Frontend config: `frontend/Sources/Configuration.swift`
- Frontend models: `frontend/Sources/Models.swift`
- HTTP client: `frontend/Sources/Services/NetworkService.swift`
- WS client: `frontend/Sources/Services/WebSocketService.swift`
- Build script: `scripts/build-unified.sh`
- DMG script: `scripts/create-dmg.sh`

## Critical Constraints
- Always `nvm use` before any npm command — must be Node 22.x
- Copilot CLI must be v0.0.400+ for SDK protocol v2
- `better-sqlite3` is synchronous; in-memory DB (`:memory:`) used in tests
- PDF parsing: use `PDFParse` from `pdf-parse`, call `destroy()` after extraction
- Excel attachments are intentionally disabled

## Ports
- Dev: 3848 (HTTP + WS)
- Prod: 3847

## User Preferences
- First conversation — no specific preferences recorded yet
