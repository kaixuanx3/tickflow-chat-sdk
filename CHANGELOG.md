## 0.1.0 (unreleased)

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
