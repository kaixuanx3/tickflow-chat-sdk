import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../client/chat_client.dart';
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
    _engine = client.engineFor(ChatSession.stub(sessionId));
    final sub = _engine.changes.listen((s) => state = s);
    ref.onDispose(() {
      sub.cancel();
      _engine.dispose();
    });
    return _engine.state;
  }

  Future<void> send(String text) => _engine.send(text);

  Future<void> retry(String clientTag) => _engine.retry(clientTag);

  void cancelInFlight() => _engine.cancelInFlight();
}

final chatSessionProvider = NotifierProvider.autoDispose
    .family<ChatSessionNotifier, ChatSessionState, String>(
      ChatSessionNotifier.new,
    );
