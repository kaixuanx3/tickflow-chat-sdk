# Changelog

## 1.0.0

First stable release. Semver applies to the three public barrels
(`tickflow_chat`, `tickflow_chat_riverpod`, `tickflow_chat_widgets`);
anything under `src/` moves freely.

### Core (`tickflow_chat`)

* `TickflowChatConfig` — injected `tokenProvider`, `apiBaseUrl`, test seams
  (`httpClientFactory`), `onAuthFailure` (401 → host login) and
  `onTelemetry` hooks.
* `TickflowChatClient` — create/list/resume sessions; engines own their
  transport.
* `ChatSessionEngine` — optimistic echo with `clientTag` idempotency,
  token streaming, retry of failed sends under the original tag, history
  hydration with a stale-guard, rate-limit cooldown (`retryAt`),
  escalation, typed telemetry (`ChatTelemetryEvent`).
* Wire models with `fromWire` unknown-fallbacks; sealed `ChatStreamEvent`
  and `ChatException` unions.
* SSE pipeline proven invariant under arbitrary chunk boundaries, fuzzed
  (chunking/garbage/truncation/corrupt frames), malformed-UTF-8 tolerant;
  a clean close before `done` settles the turn instead of hanging.
* `X-Client-Version` header on every request.
* `ChatReadMarks` — local last-read marks behind a replaceable store.

### Riverpod (`tickflow_chat_riverpod`)

* `chatConfigProvider` override point, `chatClientProvider`.
* `chatSessionProvider` — autoDispose family notifier; resumes (hydrates
  history) on build and records read marks on open/leave.
* `chatInboxProvider` (auto-retry disabled so error states render) and
  `chatSessionIsUnread`.

### Widgets (`tickflow_chat_widgets`)

* `ChatView` — the design-spec thread: role bubbles, typing indicator,
  streaming caret, tap-to-retry, rate-limit banner with cooldown,
  escalated notice, multiline composer; slot builders
  (`messageBuilder`, `composerBuilder`, empty/loading/escalated).
* `ChatInboxView` — greeting CTA, recent threads with unread dots,
  pull-to-refresh.
* `ChatEscalateButton` — hand the session to human support.
* `TickflowChatTheme` ThemeExtension (light/dark, WCAG-AA locked by test)
  and `TickflowChatLocalizations` (en/中文, English fallback).
* Accessibility: reply announced once on settle, ≥44px targets, labeled
  icon buttons, reduced-motion honored; goldens for light/dark.

## 0.1.0

Phase 0 — walking skeleton, AI happy path end to end:

* Core barrel: config (injected `tokenProvider`), immutable wire models with
  `fromWire`/unknown fallbacks, sealed `ChatStreamEvent` + `ChatException`.
* SSE parser proven invariant under arbitrary chunk boundaries.
* `HttpGateway` (typed errors, 401 retry-once) + `SseTransport`;
  fetch-backed streaming client on web.
* `ChatSessionEngine`: optimistic echo, token streaming, done/failure
  settling with partial-text retention, escalation flag.
* Riverpod 3 barrel: `chatConfigProvider` override point +
  `ChatSessionNotifier` (`autoDispose.family`).
* Widgets barrel: barebones `ChatView` (list, error line, composer).
