import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../client/chat_client.dart';
import '../client/chat_read_marks.dart';
import '../config/chat_config.dart';
import '../engine/chat_session_engine.dart';
import '../engine/chat_session_state.dart';
import '../models/chat_session.dart';

/// The host app must override this with its real config:
///
/// ```dart
/// ProviderScope(overrides: [
///   chatConfigProvider.overrideWithValue(TickflowChatConfig(
///     apiBaseUrl: Uri.parse(Env.apiUrl),
///     tokenProvider: tokenStorage.readToken,
///     onAuthFailure: onSessionExpired, // host routes to login on a dead token
///   )),
/// ], child: ...)
/// ```
final chatConfigProvider = Provider<TickflowChatConfig>(
  (ref) => throw UnimplementedError(
    'Override chatConfigProvider with your TickflowChatConfig at the ProviderScope root.',
  ),
);

final chatClientProvider = Provider<TickflowChatClient>((ref) {
  final client = TickflowChatClient(ref.watch(chatConfigProvider));
  ref.onDispose(client.dispose);
  return client;
});

/// Mirrors the engine's state stream into Riverpod; intents pass through.
///
/// autoDispose: navigating away cancels the subscription and disposes the
/// engine, which closes the transport and aborts any in-flight reply.
class ChatSessionNotifier extends Notifier<ChatSessionState> {
  ChatSessionNotifier(this.sessionId);

  final String sessionId;

  late ChatSessionEngine _engine;

  @override
  ChatSessionState build() {
    final client = ref.watch(chatClientProvider);
    // Resume, not just attach: history hydrates in the background
    // (state.isLoading) while the engine is immediately usable for sending.
    _engine = client.resumeSession(ChatSession.stub(sessionId));
    final sub = _engine.changes.listen((s) => state = s);
    // Opening and leaving the thread both clear its unread badge — the
    // dispose mark covers replies that arrived while the user was reading.
    final marks = ref.watch(chatReadMarksProvider);
    unawaited(marks.markRead(sessionId, DateTime.now()));
    ref.onDispose(() {
      sub.cancel();
      _engine.dispose();
      unawaited(marks.markRead(sessionId, DateTime.now()));
    });
    return _engine.state;
  }

  Future<void> send(String text) => _engine.send(text);

  Future<void> retry(String clientTag) => _engine.retry(clientTag);

  Future<void> escalate() => _engine.escalate();

  void cancelInFlight() => _engine.cancelInFlight();
}

final chatSessionProvider = NotifierProvider.autoDispose
    .family<ChatSessionNotifier, ChatSessionState, String>(
      ChatSessionNotifier.new,
    );

/// The user's support threads for the inbox, newest activity first (the
/// backend orders by `updatedAt`). Refresh with
/// `ref.invalidate(chatInboxProvider)` — e.g. after returning from a thread.
///
/// Riverpod 3's automatic retry is disabled: while it retries, the state
/// reads as loading, which would pin the inbox on a spinner (and hammer the
/// backend) instead of surfacing the typed error. Recovery is explicit —
/// the retry button and pull-to-refresh.
final chatInboxProvider = FutureProvider.autoDispose<List<ChatSession>>(
  retry: (retryCount, error) => null,
  (ref) => ref.watch(chatClientProvider).listSessions(),
);

/// Where per-session read marks live. Defaults to process-lifetime memory;
/// hosts override with a persistent store so unread badges survive
/// restarts:
///
/// ```dart
/// chatReadMarksProvider.overrideWithValue(MyPrefsBackedReadMarks(prefs))
/// ```
final chatReadMarksProvider = Provider<ChatReadMarks>(
  (ref) => InMemoryChatReadMarks(),
);

/// True when [session] has activity newer than its local read mark. Marks
/// are compared against the server's `updatedAt`; sessions without one
/// never badge.
bool chatSessionIsUnread(ChatReadMarks marks, ChatSession session) {
  final updatedAt = session.updatedAt;
  if (updatedAt == null) return false;
  final readAt = marks.lastReadAt(session.id);
  return readAt == null || updatedAt.isAfter(readAt);
}
