import 'dart:async';

import '../config/chat_config.dart';
import '../engine/chat_session_engine.dart';
import '../models/chat_session.dart';
import '../transport/http_gateway.dart';
import '../transport/sse_transport.dart';

/// Stateless facade over the Tickflow chat contract: sessions in, engines
/// out. One instance per app; engines are per-conversation and own their
/// transport.
class TickflowChatClient {
  TickflowChatClient(this.config) : _gateway = HttpGateway(config);

  final TickflowChatConfig config;
  final HttpGateway _gateway;

  Future<ChatSession> createSession() => _gateway.createSession();

  ChatSessionEngine engineFor(ChatSession session) => ChatSessionEngine(
    session: session,
    transport: SseTransport(gateway: _gateway, sessionId: session.id),
  );

  /// Resumes an existing session: builds its engine and starts hydrating
  /// history. Returns immediately with the engine in a loading state — watch
  /// [ChatSessionEngine.changes] for the populated snapshot.
  ///
  /// The caller supplies the [ChatSession] (from the inbox list or a prior
  /// create) because the history endpoint returns only messages, not session
  /// mode/status; use [ChatSession.stub] for an id-only resume.
  ChatSessionEngine resumeSession(ChatSession session) {
    final engine = engineFor(session);
    unawaited(engine.load(() => _gateway.fetchHistory(session.id)));
    return engine;
  }

  Future<void> dispose() async => _gateway.dispose();
}
