/// One streamed increment of an AI reply turn.
///
/// A sealed union so the engine's handling is exhaustive at compile time.
/// Human-mode events (agent messages, presence) join this union in Phase 2.
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

class TokenDelta extends ChatStreamEvent {
  const TokenDelta(this.delta);
  final String delta;
}

class StreamDone extends ChatStreamEvent {
  const StreamDone({required this.escalated});

  /// True when the backend decided this session hands off to a human.
  final bool escalated;
}

class StreamFailure extends ChatStreamEvent {
  const StreamFailure(this.message);
  final String message;
}
