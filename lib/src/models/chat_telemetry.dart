/// Lifecycle signals for host analytics and logging (P5), delivered to
/// [TickflowChatConfig.onTelemetry]. Sealed: hosts can switch exhaustively.
///
/// Events fire synchronously on the engine's thread; a throwing handler is
/// swallowed so telemetry can never break a conversation.
sealed class ChatTelemetryEvent {
  const ChatTelemetryEvent(this.sessionId);

  final String sessionId;
}

/// A user turn was dispatched (send or retry).
final class ChatTurnStarted extends ChatTelemetryEvent {
  const ChatTurnStarted(super.sessionId);
}

/// The reply's first token arrived; [latency] measures from dispatch — the
/// number that decides whether the assistant feels instant.
final class ChatFirstToken extends ChatTelemetryEvent {
  const ChatFirstToken(super.sessionId, {required this.latency});

  final Duration latency;
}

/// The reply settled successfully. [escalated] mirrors the done frame.
final class ChatTurnCompleted extends ChatTelemetryEvent {
  const ChatTurnCompleted(
    super.sessionId, {
    required this.duration,
    required this.escalated,
  });

  final Duration duration;
  final bool escalated;
}

/// The turn failed — at initiation or mid-stream. [errorType] is the
/// [ChatException] subtype name (e.g. `ChatRateLimitException`), never
/// message content.
final class ChatTurnFailed extends ChatTelemetryEvent {
  const ChatTurnFailed(super.sessionId, {required this.errorType});

  final String errorType;
}

/// The user handed the session to human support.
final class ChatSessionEscalatedEvent extends ChatTelemetryEvent {
  const ChatSessionEscalatedEvent(super.sessionId);
}
