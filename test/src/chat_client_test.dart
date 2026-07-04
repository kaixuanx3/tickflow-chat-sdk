import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

void main() {
  test(
    'resumeSession returns a loading engine, then hydrates it from history',
    () async {
      final config = TickflowChatConfig(
        apiBaseUrl: Uri.parse('https://api.test'),
        tokenProvider: () async => 'jwt-1',
        httpClientFactory: () => MockClient((req) async {
          expect(req.url.path, '/chat/sessions/s1/messages');
          return http.Response(
            '{"messages":[{"id":"m1","sessionId":"s1","role":"user",'
            '"content":"hi","createdAt":"2026-07-01T10:00:00.000Z"}]}',
            200,
          );
        }),
      );
      final client = TickflowChatClient(config);
      addTearDown(client.dispose);

      const session = ChatSession(
        id: 's1',
        mode: SessionMode.ai,
        status: SessionStatus.open,
      );
      final engine = client.resumeSession(session);
      addTearDown(engine.dispose);

      expect(
        engine.state.isLoading,
        isTrue,
        reason: 'returned synchronously, mid-load',
      );
      final loaded = await engine.changes.firstWhere((s) => !s.isLoading);
      expect(loaded.messages.single.content, 'hi');
      expect(loaded.error, isNull);
    },
  );
}
