# tickflow_chat

Client-side Flutter chat SDK for [Tickflow](https://github.com/kaixuanx3/Tickflow): an AI-first in-app support assistant (streamed over SSE) that escalates to human support on the same thread (WebSocket live chat, or async email follow-up).

Headless core + optional widget, three public barrels:

- `tickflow_chat.dart` — pure-Dart core: client, session engine, transports, models
- `tickflow_chat_riverpod.dart` — Riverpod 3 `Notifier` bindings
- `tickflow_chat_widgets.dart` — default Material chat UI (en / 中文, themeable)

The SDK talks only to the Tickflow backend — it never holds an LLM key or credentials (JWT comes from an injected `tokenProvider`).

Consumed by the app as a path dependency during development and a pinned git tag for releases. See `CLAUDE.md` for architecture, the backend contract, and the build roadmap.

## Status

Pre-1.0, under active development (Phase 0 — walking skeleton).

## Development

```bash
flutter pub get
flutter analyze
flutter test
```
