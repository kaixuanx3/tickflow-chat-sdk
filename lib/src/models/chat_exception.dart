/// Every SDK failure is one of these — no raw strings, no bare [Exception] —
/// so UI code can switch exhaustively and design each recovery.
sealed class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Offline, DNS failure, timeout — anything before an HTTP status existed.
class ChatNetworkException extends ChatException {
  const ChatNetworkException(super.message);
}

/// No token available, or the backend rejected it twice (host must re-login).
class ChatAuthException extends ChatException {
  const ChatAuthException.missing() : super('no auth token available');
  const ChatAuthException.expired() : super('auth token rejected');
}

/// Session gone (404) — offer to start a new conversation.
class ChatNotFoundException extends ChatException {
  const ChatNotFoundException(super.message);
}

/// Daily message cap hit (429). [retryAfter] comes from the Retry-After
/// header when the backend sent one.
class ChatRateLimitException extends ChatException {
  const ChatRateLimitException(super.message, {this.retryAfter});
  final Duration? retryAfter;
}

/// The reply stream broke mid-generation; [partialText] keeps whatever
/// tokens already arrived so the UI can retain and retry.
class ChatStreamException extends ChatException {
  const ChatStreamException(super.message, {this.partialText});
  final String? partialText;
}

/// Any other non-2xx the contract doesn't give a designed recovery for.
class ChatApiException extends ChatException {
  const ChatApiException(this.statusCode, super.message);
  final int? statusCode;
}
