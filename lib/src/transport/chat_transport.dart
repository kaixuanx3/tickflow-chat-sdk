import '../models/stream_event.dart';

/// The seam the engine talks through, whatever the wire.
///
/// AI mode is SSE (request-per-reply); human mode (Phase 2) is a WebSocket.
/// The engine never branches on which one is behind this interface —
/// escalation is a transport swap under an unchanged session.
abstract interface class ChatTransport {
  /// Broadcast, session-scoped. Subscribe before calling [send].
  Stream<ChatStreamEvent> get inbound;

  /// SSE: no-op. WS: connect + authenticate.
  Future<void> open();

  /// Starts one turn. Initiation problems (auth, quota, missing session)
  /// throw a typed [Exception] here; everything after the wire opens arrives
  /// as [inbound] events.
  ///
  /// [clientTag] reconciles the optimistic echo and doubles as the
  /// idempotency key on retries.
  Future<void> send(String text, {required String clientTag});

  /// Aborts the in-flight turn, keeping whatever already arrived.
  void cancelInFlight();

  Future<void> close();
}
