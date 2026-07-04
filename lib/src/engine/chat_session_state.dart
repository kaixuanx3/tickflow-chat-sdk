import 'package:meta/meta.dart';

import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

/// The single immutable snapshot every transport event reduces into.
/// The UI renders this and nothing else.
@immutable
class ChatSessionState {
  const ChatSessionState({
    required this.session,
    this.messages = const [],
    this.isLoading = false,
    this.isAwaitingReply = false,
    this.isStreaming = false,
    this.error,
    this.retryAt,
  });

  final ChatSession session;

  /// Includes the optimistic echo and the in-progress streaming reply.
  final List<ChatMessage> messages;

  /// True while history is being hydrated on resume.
  final bool isLoading;

  /// True from a dispatched send until the reply's first token (or its
  /// failure) — the window the typing indicator covers.
  final bool isAwaitingReply;

  /// True while an AI reply is mid-stream.
  final bool isStreaming;

  /// Last transient failure, for a banner/inline treatment. Cleared on the
  /// next send.
  final ChatException? error;

  /// When rate-limited (a 429 carrying a Retry-After), the UTC instant the
  /// composer may send again — null otherwise. The widget derives the
  /// countdown and re-enables once it passes; a value already in the past
  /// means no active cooldown. Cleared on the next send.
  final DateTime? retryAt;

  ChatSessionState copyWith({
    ChatSession? session,
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isAwaitingReply,
    bool? isStreaming,
    ChatException? error,
    bool clearError = false,
    DateTime? retryAt,
    bool clearRetryAt = false,
  }) => ChatSessionState(
    session: session ?? this.session,
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isAwaitingReply: isAwaitingReply ?? this.isAwaitingReply,
    isStreaming: isStreaming ?? this.isStreaming,
    error: clearError ? null : (error ?? this.error),
    retryAt: clearRetryAt ? null : (retryAt ?? this.retryAt),
  );
}
