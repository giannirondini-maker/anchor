# Anchor vs IssueCrush — Copilot SDK Integration Comparison

> Comparison between **Anchor** (this repo) and **IssueCrush**, the demo app from the GitHub blog article
> [Building AI-powered GitHub issue triage with the Copilot SDK](https://github.blog/ai-and-ml/github-copilot/building-ai-powered-github-issue-triage-with-the-copilot-sdk/) (March 2026, by Andrea Griffiths).
>
> Source: [AndreaGriffiths11/IssueCrush](https://github.com/AndreaGriffiths11/IssueCrush)

---

## 1. Project Profiles

| Dimension | Anchor | IssueCrush |
|-----------|--------|------------|
| **Purpose** | General-purpose Copilot chat client (ChatGPT-like UX) | Single-purpose issue triage tool (swipeable cards + AI summary) |
| **Frontend** | Native macOS SwiftUI app | React Native (cross-platform mobile) |
| **Backend** | Node.js / TypeScript / Express / WebSocket | Node.js / Express (REST only) |
| **Persistence** | SQLite via `better-sqlite3` (conversations, messages, tags) | None (in-memory state on client only) |
| **SDK package** | `@github/copilot-sdk ^0.1.19` | `@github/copilot-sdk ^0.1.14` |
| **Communication** | HTTP REST + WebSocket streaming | HTTP REST only |
| **Distribution** | `.app` bundle with embedded Node.js runtime | Standard React Native app + standalone server |

---

## 2. Architectural Similarities

Both projects converge on the same foundational pattern, which validates several design decisions made independently.

### 2.1 Server-Side SDK Hosting

Both chose to run the Copilot SDK on a backend Node.js server, not in the client. The reasoning is identical:

- The SDK requires the Copilot CLI binary in `PATH` and a Node.js runtime.
- Credentials stay server-side; they never reach the client.
- A single `CopilotClient` instance is shared across requests.

**Anchor** (`copilot.service.ts:67-74`):
```typescript
this.client = new CopilotClient({
  logLevel: config.sdk.logLevel,
  autoStart: true,
  autoRestart: true,
});
await this.client.start();
```

**IssueCrush** (article code):
```typescript
client = new CopilotClient();
await client.start();
```

### 2.2 Session-Based Model

Both respect the SDK's `start() → createSession() → send/sendAndWait() → destroy/disconnect() → stop()` lifecycle. Sessions are the atomic unit of LLM interaction.

### 2.3 Express as HTTP Layer

Both use Express for routing. Both expose a `/health` endpoint that reports backend + SDK status back to the client, enabling the frontend to adapt its UI to availability.

### 2.4 Client-Side Service Abstraction

Both wrap backend calls in a dedicated service class on the client:

| | Anchor | IssueCrush |
|--|--------|------------|
| Class | `NetworkService.swift` + `WebSocketService.swift` | `CopilotService` (TypeScript) |
| Pattern | Singleton via `AppState` | Singleton export (`export const copilotService`) |
| Health check | On launch, polls `/api/health` | On launch, calls `/health` and stores `copilotMode` |

### 2.5 Error Code Awareness

Both define structured error codes and surface them to the client. Anchor uses an `ErrorCodes` const object with ~20 codes; IssueCrush uses HTTP status codes (403 for subscription issues) with a `requiresCopilot` flag.

### 2.6 Singleton Service Export

Both export the service as a module-level singleton:

```typescript
// Anchor
export const copilotService = new CopilotService();

// IssueCrush
export const copilotService = new CopilotService();
```

---

## 3. Architectural Differences

### 3.1 Session Lifecycle Strategy

This is the most significant divergence.

| Aspect | Anchor | IssueCrush |
|--------|--------|------------|
| **Session lifetime** | Long-lived, cached in a `Map<string, SessionWrapper>` | Ephemeral — created per request, destroyed in `finally` |
| **Idle management** | 30-min timeout + periodic cleanup interval (10 min) | N/A — no session persistence |
| **Session resumption** | `resumeSession()` with SDK `resumeSession()` + context injection fallback | N/A |
| **Context window** | Infinite sessions with background compaction (`infiniteSessions.enabled: true`) | Single prompt per session |

Anchor manages multi-turn conversations and must keep context alive across messages. IssueCrush performs stateless, one-shot summarizations, so ephemeral sessions are appropriate.

**Implication**: Anchor's `SessionWrapper` pattern — wrapping `CopilotSession` with metadata (`model`, `createdAt`, `lastActiveAt`, `messageCount`) — is a production pattern the article doesn't address. It's needed for any multi-turn use case.

### 3.2 Streaming vs Request-Response

| | Anchor | IssueCrush |
|--|--------|------------|
| **Delivery** | WebSocket streaming (token-by-token) | `sendAndWait()` — returns full response |
| **Events** | `message:delta`, `message:complete`, `session:idle`, `tool:start`, `tool:complete` | N/A |
| **Tool calls** | Handled — multi-turn tool invocations tracked via `assistant.message` with `toolRequests` | Not addressed |

Anchor subscribes to the SDK's event system (`session.on()`) and handles `assistant.message_delta`, `assistant.message`, `tool.execution_start`, `tool.execution_complete`, and `session.idle`. The article only uses `sendAndWait()`, which abstracts away all of this.

### 3.3 Persistence Layer

| | Anchor | IssueCrush |
|--|--------|------------|
| **Storage** | SQLite — conversations, messages, tags, session metadata | None (client-side `useState` cache only) |
| **History injection** | On session resume, injects last N messages (`MAX_HISTORY_MESSAGES = 50`) via `injectMessages()` | N/A |
| **Attachments** | File upload pipeline with staging, validation, text extraction (PDF), context building | N/A |

### 3.4 Model Selection

| | Anchor | IssueCrush |
|--|--------|------------|
| **Discovery** | Calls `client.listModels()`, transforms SDK `ModelInfo` to `ModelInfoSimple` with billing/capability metadata | Hard-coded to `gpt-4.1` |
| **Switching** | `updateSessionModel()` — destroys session, creates new one with same ID, re-injects history | N/A |
| **Vision support** | Tracks `supportsVision` per model for image attachments | N/A |

### 3.5 Client Initialization Options

Anchor configures `CopilotClient` with `autoStart`, `autoRestart`, and `logLevel`. IssueCrush uses the zero-config default constructor. Anchor also calls `client.ping()` to verify connectivity post-start.

### 3.6 Graceful Shutdown

Anchor implements full graceful shutdown: SIGINT/SIGTERM handlers that destroy all sessions, stop the cleanup interval, close the HTTP server, and call `client.stop()` (with `forceStop()` fallback). IssueCrush cleans up per-request in `finally` blocks but has no process-level shutdown logic.

---

## 4. Graceful Degradation — Compared

Both implement fallback strategies, but at different layers.

| | Anchor | IssueCrush |
|--|--------|------------|
| **Health check** | `/api/health` returns `healthy/unhealthy` + SDK connection state; frontend shows connection indicator | `/health` returns `copilotMode`; client hides AI button if unavailable |
| **SDK failure** | Server won't start if SDK init fails (`process.exit(1)`) — strict dependency | Server starts even if SDK fails (dynamic `import()`) — soft dependency |
| **Per-request fallback** | Error propagated to client via WebSocket `message:error` event | Falls back to `generateFallbackSummary()` built from issue metadata |
| **Auth errors** | Structured `ErrorCodes.SDK_NOT_AUTHENTICATED` | HTTP 403 with `requiresCopilot: true` |

The article's approach of using `await import('@github/copilot-sdk')` (dynamic import) to allow the server to start without the SDK is a pattern Anchor does not use. Anchor treats the SDK as a hard dependency.

---

## 5. What the Article Validates About Anchor's Design

These are patterns the article presents as "lessons learned" that Anchor already implements:

| Article Lesson | Anchor Implementation |
|----------------|----------------------|
| "Server-side is the right call" | Identical architecture since inception |
| "Always have a fallback" | Health endpoint + WebSocket error events |
| "Clean up your sessions" — `try/finally` | `destroySession()` + periodic `cleanupIdleSessions()` + `shutdown()` |
| "Cache the results" | SQLite persistence — messages never re-fetched from LLM |
| "Single SDK instance shared across all clients" | Singleton `CopilotService` with shared `CopilotClient` |
| Health endpoint signals AI availability | `/api/health` with `sdk.connected` and `sdk.authenticated` |

---

## 6. What the Article Introduces Beyond Anchor

| Concept | Details | Relevance to Anchor |
|---------|---------|---------------------|
| **Dynamic SDK import** | `await import('@github/copilot-sdk')` instead of top-level `import` | Could allow Anchor to start in offline/degraded mode without crashing |
| **Metadata-based fallback summary** | `generateFallbackSummary()` extracts title + labels + first sentence when AI is down | Anchor could apply this to generate conversation previews without LLM calls |
| **Prompt structuring** | Explicit structured metadata (title, labels, author, state) in the prompt template | Anchor sends raw user input; no server-side prompt augmentation with structured metadata |
| **HTTP 403 for subscription errors** | Differentiating "no Copilot subscription" from generic errors | Anchor has `SDK_NOT_AUTHENTICATED` but doesn't distinguish subscription-level access |

---

## 7. What Anchor Has That the Article Doesn't Cover

These are production-grade patterns in Anchor that go well beyond the article's scope:

| Feature | Anchor Detail |
|---------|---------------|
| **WebSocket streaming** | Token-by-token delivery via `message:delta` events; per-conversation client multiplexing |
| **Multi-turn conversations** | Session persistence, history injection, context compaction (`infiniteSessions`) |
| **Tool use handling** | Detects `toolRequests` in `assistant.message`, tracks `tool.execution_start/complete` events |
| **Model switching** | Destroy-and-recreate pattern with history preservation via `updateSessionModel()` |
| **Session resumption** | SDK `resumeSession()` with fallback to new session + context injection |
| **File attachments** | Upload pipeline (staging, MIME validation, PDF text extraction, context block building) |
| **Rate limiting** | Express middleware (`apiLimiter`, `healthLimiter`, `messageLimiter`) |
| **Request validation** | Zod schemas (`SendMessageSchema`, `RetryMessageSchema`) |
| **Conversation tagging** | SQLite-backed tag system for organizing conversations |
| **Session statistics** | `getSessionStats()` — idle time, message count, model, timestamps |
| **Periodic cleanup** | 10-min interval auto-cleans sessions idle > 30 min |
| **Message retry** | Dedicated retry flow (`RetryMessageSchema`) |
| **Abort support** | `session.abort()` for cancelling in-flight LLM responses |
| **Embedded runtime** | Production `.app` bundles Node.js runtime; no external server dependency |
| **WAL mode SQLite** | `journal_mode = WAL` for concurrent reads during writes |

---

## 8. SDK API Surface Comparison

| SDK Method | Anchor | IssueCrush |
|------------|--------|------------|
| `new CopilotClient(options)` | ✅ (with config) | ✅ (default) |
| `client.start()` | ✅ | ✅ |
| `client.stop()` | ✅ (+ `forceStop()` fallback) | ✅ |
| `client.ping()` | ✅ | ✗ |
| `client.getAuthStatus()` | ✅ | ✗ |
| `client.listModels()` | ✅ | ✗ |
| `client.listSessions()` | ✅ | ✗ |
| `client.createSession(opts)` | ✅ (streaming, infiniteSessions) | ✅ (model, onPermissionRequest) |
| `client.resumeSession(id)` | ✅ | ✗ |
| `client.deleteSession(id)` | ✅ | ✗ |
| `session.send(prompt)` | ✅ | ✗ |
| `session.sendAndWait(prompt)` | ✅ | ✅ |
| `session.on(callback)` | ✅ (full event handling) | ✗ |
| `session.abort()` | ✅ | ✗ |
| `session.destroy()` | ✅ | ✗ (uses `disconnect()`) |
| `session.getMessages()` | ✅ | ✗ |
| `session.injectMessages()` | ✅ (with capability check) | ✗ |
| `approveAll` | ✗ | ✅ |

---

## 9. Key Takeaways

1. **Same core pattern, different complexity tiers.** Both apps prove that the `Node.js server → CopilotClient singleton → session-per-interaction` architecture is the canonical way to integrate the SDK. IssueCrush is a minimal viable example; Anchor is a full production implementation.

2. **Streaming is the differentiator.** The article uses `sendAndWait()` exclusively, which is fine for one-shot summaries. Anchor's event-driven streaming via `session.on()` is required for real-time chat UX and is significantly more complex to implement correctly (especially with tool call intermediary messages).

3. **Session management at scale needs explicit design.** The article acknowledges "clean up your sessions" but handles it per-request. Anchor's approach — `SessionWrapper` metadata, idle timeouts, periodic cleanup, resume-with-injection — addresses the real-world problem of long-running multi-turn conversations.

4. **Dynamic import is worth adopting.** IssueCrush's `await import('@github/copilot-sdk')` pattern is a simple change that would let Anchor start in degraded mode when the SDK or CLI is unavailable, improving resilience.

5. **Fallback summaries are a useful pattern.** Generating basic responses from existing metadata when AI is unavailable is applicable to Anchor — e.g., generating conversation titles or previews without an LLM call.

---

*Generated: April 2026*
