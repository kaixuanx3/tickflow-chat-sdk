import 'dart:async';

import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_role.dart';
import '../models/chat_session.dart';
import '../models/stream_event.dart';
import '../transport/chat_transport.dart';
import '../util/ids.dart';
import 'chat_session_state.dart';

/// The state machine of one conversation, plain Dart.
///
/// Reduces every [ChatStreamEvent] into an immutable [ChatSessionState] and
/// publishes it on [changes]. Owns its transport: disposing the engine tears
/// down the wire, so nothing outlives the screen that watches it.
class ChatSessionEngine {
  ChatSessionEngine({required ChatSession session, required ChatTransport transport})
      : _transport = transport,
        _state = ChatSessionState(session: session) {
    _inboundSub = _transport.inbound.listen(_onEvent);
  }

  final ChatTransport _transport;
  late final StreamSubscription<ChatStreamEvent> _inboundSub;
  final _changes = StreamController<ChatSessionState>.broadcast();

  ChatSessionState _state;
  ChatSessionState get state => _state;

  /// Broadcast; every new listener first receives the current snapshot.
  Stream<ChatSessionState> get changes async* {
    yield _state;
    yield* _changes.stream;
  }

  /// Index of the assistant message currently streaming, if any.
  int? _streamingIndex;

  /// clientTag of the user message awaiting its reply, if any.
  String? _pendingTag;

  /// Optimistic echo, then one streamed reply turn.
  ///
  /// No-op while a reply is already streaming (the composer is disabled in
  /// that state); queueing sends is a later phase. Initiation failures mark
  /// the echo `failed` and surface as [ChatSessionState.error].
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _state.isStreaming || _pendingTag != null) return;

    final tag = newClientTag();
    _pendingTag = tag;
    _emit(_state.copyWith(
      messages: [
        ..._state.messages,
        ChatMessage(
          id: '',
          sessionId: _state.session.id,
          role: ChatRole.user,
          content: trimmed,
          createdAt: DateTime.now().toUtc(),
          status: MessageStatus.sending,
          clientTag: tag,
        ),
      ],
      clearError: true,
    ));

    try {
      await _transport.send(trimmed, clientTag: tag);
    } on Exception catch (e) {
      final error =
          e is ChatException ? e : ChatApiException(null, e.toString());
      _pendingTag = null;
      _emit(_state.copyWith(
        messages: _withStatus(tag, MessageStatus.failed),
        error: error,
      ));
    }
  }

  /// Stops the in-flight reply, keeping any partial text. The partial is
  /// finalized as `sent` — an explicit user intent, not a failure.
  void cancelInFlight() {
    if (_streamingIndex == null && _pendingTag == null) return;
    _transport.cancelInFlight();
    _settleTurn(assistantStatus: MessageStatus.sent);
  }

  Future<void> dispose() async {
    await _inboundSub.cancel();
    await _transport.close();
    await _changes.close();
  }

  void _onEvent(ChatStreamEvent event) {
    switch (event) {
      case TokenDelta(:final delta):
        _onDelta(delta);
      case StreamDone(:final escalated):
        _settleTurn(assistantStatus: MessageStatus.sent);
        if (escalated) {
          _emit(_state.copyWith(
            session: _state.session.copyWith(status: SessionStatus.escalated),
          ));
        }
      case StreamFailure(:final message):
        _onFailure(message);
    }
  }

  void _onDelta(String delta) {
    final messages = [..._state.messages];
    if (_streamingIndex == null) {
      // First token: confirm the echo, open the streaming reply bubble.
      if (_pendingTag != null) {
        final i = _indexOfTag(_pendingTag!);
        if (i != null) messages[i] = messages[i].copyWith(status: MessageStatus.sent);
      }
      messages.add(ChatMessage(
        id: '',
        sessionId: _state.session.id,
        role: ChatRole.assistant,
        content: delta,
        createdAt: DateTime.now().toUtc(),
        status: MessageStatus.streaming,
      ));
      _streamingIndex = messages.length - 1;
      _emit(_state.copyWith(messages: messages, isStreaming: true));
      return;
    }
    final i = _streamingIndex!;
    messages[i] = messages[i].copyWith(content: messages[i].content + delta);
    _emit(_state.copyWith(messages: messages));
  }

  void _onFailure(String message) {
    final partialIndex = _streamingIndex;
    final partial =
        partialIndex == null ? null : _state.messages[partialIndex].content;
    // No reply arrived → the user message itself failed and can be retried;
    // with a partial, the echo stands and the reply is what failed.
    final echoStatus =
        partial == null ? MessageStatus.failed : MessageStatus.sent;
    var messages = _pendingTag == null
        ? _state.messages
        : _withStatus(_pendingTag!, echoStatus);
    if (partialIndex != null) {
      messages = [...messages];
      messages[partialIndex] =
          messages[partialIndex].copyWith(status: MessageStatus.failed);
    }
    _pendingTag = null;
    _streamingIndex = null;
    _emit(_state.copyWith(
      messages: messages,
      isStreaming: false,
      error: ChatStreamException(message, partialText: partial),
    ));
  }

  void _settleTurn({required MessageStatus assistantStatus}) {
    var messages = _pendingTag == null
        ? _state.messages
        : _withStatus(_pendingTag!, MessageStatus.sent);
    final i = _streamingIndex;
    if (i != null) {
      messages = [...messages];
      messages[i] = messages[i].copyWith(status: assistantStatus);
    }
    _pendingTag = null;
    _streamingIndex = null;
    _emit(_state.copyWith(messages: messages, isStreaming: false));
  }

  int? _indexOfTag(String tag) {
    final i = _state.messages.indexWhere((m) => m.clientTag == tag);
    return i == -1 ? null : i;
  }

  List<ChatMessage> _withStatus(String tag, MessageStatus status) {
    final messages = [..._state.messages];
    final i = messages.indexWhere((m) => m.clientTag == tag);
    if (i != -1) messages[i] = messages[i].copyWith(status: status);
    return messages;
  }

  void _emit(ChatSessionState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }
}
