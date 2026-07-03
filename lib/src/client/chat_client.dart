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

  Future<void> dispose() async => _gateway.dispose();
}
