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
    this.isStreaming = false,
    this.error,
  });

  final ChatSession session;

  /// Includes the optimistic echo and the in-progress streaming reply.
  final List<ChatMessage> messages;

  /// True while history is being hydrated on resume.
  final bool isLoading;

  /// True while an AI reply is mid-stream.
  final bool isStreaming;

  /// Last transient failure, for a banner/inline treatment. Cleared on the
  /// next send.
  final ChatException? error;

  ChatSessionState copyWith({
    ChatSession? session,
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isStreaming,
    ChatException? error,
    bool clearError = false,
  }) => ChatSessionState(
    session: session ?? this.session,
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isStreaming: isStreaming ?? this.isStreaming,
    error: clearError ? null : (error ?? this.error),
  );
}
