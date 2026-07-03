# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`tickflow_chat` — a client-side Flutter/Dart chat SDK for the Tickflow app (https://github.com/kaixuanx3/Tickflow): an AI-first in-app support assistant (streamed over SSE) that escalates to human support (over WebSocket, or async email follow-up) on the same thread. Client-side only: the SDK speaks the Tickflow backend contract, never an LLM provider, and never holds an LLM key or credentials.

The repo is currently a bare `flutter create --template=package` scaffold. The build follows three source-of-truth documents (in precedence order for client architecture):

1. **Design spec (authority for this repo)**: `/Users/kaixuanx3/Downloads/tickflow_chat SDK Design.pdf` — package structure, public API, transport, state machine, error taxonomy, roadmap P0–P5.
2. **Full-stack plan**: `.../local-agent-mode-sessions/fc2b4cb5-.../outputs/tickflow-chat-sdk-plan.md` — backend endpoints, Prisma models, Gemini provider choice. Backend code lands in the Tickflow repo (`tick-flow-backend/`), not here.
3. **UI prototype**: `/Users/kaixuanx3/Downloads/flutter-dart-chat-sdk-design-1-overview-design-goals-product/project/Tickflow Support Chat.dc.html` — visual reference for the default widget (inbox + thread, light/dark, en/zh). Recreate the visuals in Flutter; don't copy its DOM structure.

## Decisions that OVERRIDE the design docs

Corrections from reviewing the docs against the real Tickflow codebase (July 2026). When a doc conflicts with this list, this list wins:

- **Riverpod 3, not 2.5.** The app uses `flutter_riverpod: ^3.3.2`; the PDF's dependency table (`^2.5`) is stale. Target Riverpod 3.x APIs. No `riverpod_generator`/`build_runner` — consumers pull this as a git/path dep and won't run codegen. Hand-write `Notifier` classes and `NotifierProvider.family` wiring.
- **Web streaming is Phase 0, not Phase 5.** The Tickflow app is web-first; `package:http`'s BrowserClient buffers responses and kills incremental SSE. Use a conditional import: streaming fetch-based client on web (e.g. `package:fetch_client`), `IOClient` elsewhere, behind the same `httpClientFactory` seam.
- **Package name**: rename the scaffold's `tickflow_chat_sdk` → `tickflow_chat` in `pubspec.yaml` (both docs use `tickflow_chat`; imports become `package:tickflow_chat/...`).
- **Inbox uses a real endpoint.** The PDF works around a missing session-list endpoint with a client-side index; instead add `GET /chat/sessions` to the backend (we own it). Unread counts may stay client-side (`lastReadAt` locally) for v1.
- **PDF open questions are resolved:**
  - Q1 (429): per-user daily cap, enforced in Redis server-side; response carries `Retry-After` seconds. SDK surfaces `ChatRateLimitException` with `retryAt`.
  - Q2 (WS envelope): a separate `/ws/chat` path on the backend reusing the existing first-frame auth pattern — NOT multiplexed onto the tick socket's closed message union. Frames are scoped server-side by the socket's authenticated user; the client never sends a userId.
  - Q3 (escalate): idempotent — escalating an already-escalated session returns 200 with current state.
  - Q4 (token refresh): moot. Tickflow has NO refresh tokens — a 7-day JWT, and a rejected token means re-login. The gateway's 401→retry-once via `tokenProvider` stays (harmless), but the second 401 must surface `ChatAuthException` for the host to route to login.
- **`[[ESCALATE]]` never reaches the client.** The backend strips it from deltas and persisted content; escalation is signaled only via the `done` frame's `escalated: true`. (The .md plan's sample handler streams it visibly — do not copy that.)

## Commands

```bash
flutter pub get
flutter analyze
flutter test                                   # all tests
flutter test test/src/transport/sse_parser_test.dart   # one file
flutter test --plain-name "handles CRLF"       # one test by name
dart format lib test
```

Pure-Dart core tests (engine/transport/models) must run without a widget tree; only `tickflow_chat_widgets` tests may pump widgets.

## Architecture (from the design spec)

Three public barrels, strict downward layering — widgets → riverpod → core, nothing re-exports upward. Everything real lives under `lib/src/` (package-private):

- `tickflow_chat.dart` — pure-Dart core: `TickflowChatConfig` (injected `tokenProvider`, `apiBaseUrl`, `wsBaseUrl`, `httpClientFactory`/`humanChannelFactory` test seams), `TickflowChatClient` (stateless facade: create/resume session, history, escalate), `ChatSessionEngine` (the state machine: `Stream<ChatSessionState>` of immutable snapshots), models (sealed `ChatStreamEvent` union, `ChatRole.fromWire` with `unknown` fallback — never throw on new wire values), sealed `ChatException` tree, `ChatTransport` interface.
- `tickflow_chat_riverpod.dart` — `ChatSessionNotifier` mirroring the engine's stream into Riverpod state; inbox provider.
- `tickflow_chat_widgets.dart` — `ChatView` + slot builders (`messageBuilder`, `composerBuilder`, empty/loading/escalated), `TickflowChatTheme` ThemeExtension, `TickflowChatLocalizations` delegate (en + zh ARBs).

Core invariants:
- **Escalation = transport swap, same session.** SSE transport closes, WS-backed `HumanChannel` opens; session id and message list never change. "Human" may be async: `status == escalated && !presence.agentPresent` renders "we'll follow up by email", not "agent is typing".
- **SSE parsing** composes `utf8.decoder → LineSplitter → SseEventFramer`; must survive arbitrary chunk boundaries (table-driven tests split a valid stream at every byte offset).
- **Optimistic send**: user bubble appended immediately with a `clientTag` (also sent as the idempotency key); token deltas coalesce and flush ~once per frame; on failure keep partial assistant text and retry under the same `clientTag`.
- **Lifecycle**: Notifier is autoDispose; dispose cancels the in-flight HTTP stream. AI replies are never auto-replayed; WS reconnects with capped exponential backoff + full jitter and re-auths each attempt.

## Backend contract (fixed; server code lives in Tickflow's `tick-flow-backend/`)

- REST: `POST /chat/sessions`, `GET /chat/sessions`, `GET /chat/sessions/:id/messages`, `POST /chat/sessions/:id/escalate`. Errors are always `{error: string}` with a proper status (401/404/429...). Auth: `Authorization: Bearer <JWT>` (HS256, `sub` = userId, 7d TTL).
- `POST /chat/messages` → `text/event-stream`: default events `data: {"delta": "..."}`, then `event: done` / `data: {"done": true, "escalated": bool}`; failures as `event: error` / `data: {"message": "..."}`. Heartbeat comment lines (`:`) must be ignored.
- WS `/ws/chat`: first frame `{type:"auth", token}` within 5s or the server closes with code 4401; token is NEVER in the URL query string (existing repo rule).
- Backend-side requirements the SDK relies on (implement there, test there): ownership check (`WHERE id = :sessionId AND userId = :authedUser`) on every session lookup — the plan.md sample omits it; per-user Redis rate limit + max message length, live from the first deployed endpoint; zod-validated bodies; `GEMINI_API_KEY` as an optional env var following the existing 503-until-configured pattern.

## Tickflow app integration facts (verified in that repo)

- Token: `flutter_secure_storage` key `tickflow_jwt` via `TokenStorage.readToken()` — this is the SDK's `tokenProvider`. On 401 the app fires `sessionExpiredProvider` → router lands on login.
- App HTTP is dio; the SDK deliberately uses `package:http` + fetch shim instead (no dio version coupling). Base URL comes from the app's `Env.apiUrl` (dart-define).
- App WS reference implementation: `tick_flow_frontend/lib/data/ws/tick_socket_service.dart` (backoff, re-auth, 4401 → onAuthFailed) — mirror its conventions for the `HumanChannel` adapter.
- L10n: gen-l10n, en + zh; Material 3 theming; `flutter_lints` 6; SDK strings must go through the localization delegate (both locales), never hardcoded.
- Consumption: path dependency during development, git tag pin for releases. Semver is defined by the three barrels; anything under `src/` moves freely.

## Design deltas (apply in the widget phase, P4)

From the UI/UX review of the prototype (`Tickflow Support Chat.dc.html`) — the prototype is the visual reference, these corrections win:

- Darken the dark-theme user bubble: white on `#3B6EF0` is ≈4.49:1, borderline AA fail (light theme `#2E64F0` ≈5.0:1 passes).
- Hit areas ≥44px everywhere; the prototype's 38px header buttons and ~31px chips are visuals only.
- Composer is a multiline `TextField` (prototype is a single-line input).
- Icon-only buttons (escalate person icon, send) need tooltips/semantic labels.
- Announce a completed reply to screen readers once on settle — never per token.
- Respect `MediaQuery.disableAnimations` (caret blink, typing dots, entrance fades) and the system text scale (prototype uses fixed px).
- Fonts in the prototype (Manrope/IBM Plex) are illustrative; the widget inherits `Theme.of(context)`.

## Working notes

- Roadmap: P0 walking skeleton (config → gateway → SSE parser → engine → minimal Notifier → bare ChatView, **including the web streaming client**) → P1 errors/history/tests → P2 human fallback → P3 inbox/reconnect → P4 widget polish + i18n/theming → P5 hardening/1.0. Rate limiting and session-ownership checks land backend-side with P0, not in a later "safety" phase.
- No agent-side product exists yet (no role field on `User`, no support dashboard). v1 escalation = notify + async email follow-up; a minimal agent reply path is its own later project. Don't design SDK features that assume live agents are always present.
- This directory is not yet a git repository — `git init` before the first commit.
