import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/src/transport/http_gateway.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

const sessionJson = '{"id":"s1","mode":"ai","status":"open"}';
const sseBody =
    'data: {"delta":"Hi"}\n\nevent: done\ndata: {"done":true,"escalated":false}\n\n';

TickflowChatConfig config({
  TokenProvider? token,
  required http.Client client,
}) => TickflowChatConfig(
  apiBaseUrl: Uri.parse('https://api.test'),
  tokenProvider: token ?? () async => 'jwt-1',
  httpClientFactory: () => client,
);

void main() {
  test(
    'null token short-circuits to ChatAuthException without network',
    () async {
      var calls = 0;
      final gateway = HttpGateway(
        config(
          token: () async => null,
          client: MockClient((req) async {
            calls++;
            return http.Response(sessionJson, 200);
          }),
        ),
      );
      await expectLater(
        gateway.createSession(),
        throwsA(isA<ChatAuthException>()),
      );
      expect(calls, 0);
    },
  );

  test('createSession sends Bearer token and parses the session', () async {
    late http.Request seen;
    final gateway = HttpGateway(
      config(
        client: MockClient((req) async {
          seen = req;
          return http.Response(sessionJson, 201);
        }),
      ),
    );
    final session = await gateway.createSession();
    expect(seen.url.path, '/chat/sessions');
    expect(seen.headers['Authorization'], 'Bearer jwt-1');
    expect(session.id, 's1');
    expect(session.mode, SessionMode.ai);
  });

  test('401 retries exactly once with a fresh token', () async {
    final tokens = ['stale', 'fresh'];
    final authsSeen = <String?>[];
    final gateway = HttpGateway(
      config(
        token: () async => tokens.removeAt(0),
        client: MockClient((req) async {
          authsSeen.add(req.headers['Authorization']);
          return req.headers['Authorization'] == 'Bearer fresh'
              ? http.Response(sessionJson, 200)
              : http.Response('{"error":"unauthorized"}', 401);
        }),
      ),
    );
    final session = await gateway.createSession();
    expect(session.id, 's1');
    expect(authsSeen, ['Bearer stale', 'Bearer fresh']);
  });

  test(
    '401 with an unchanged token fails fast as expired (no second call)',
    () async {
      var calls = 0;
      final gateway = HttpGateway(
        config(
          token: () async => 'same',
          client: MockClient((req) async {
            calls++;
            return http.Response('{"error":"unauthorized"}', 401);
          }),
        ),
      );
      await expectLater(
        gateway.createSession(),
        throwsA(isA<ChatAuthException>()),
      );
      expect(
        calls,
        1,
        reason: 'no refresh exists — retrying the same token is pointless',
      );
    },
  );

  test('429 maps to ChatRateLimitException carrying Retry-After', () async {
    final gateway = HttpGateway(
      config(
        client: MockClient(
          (req) async => http.Response(
            '{"error":"daily limit reached"}',
            429,
            headers: {'retry-after': '90'},
          ),
        ),
      ),
    );
    await expectLater(
      gateway.createSession(),
      throwsA(
        isA<ChatRateLimitException>()
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 90),
            )
            .having((e) => e.message, 'message', 'daily limit reached'),
      ),
    );
  });

  test('404 maps to ChatNotFoundException', () async {
    final gateway = HttpGateway(
      config(
        client: MockClient(
          (req) async => http.Response('{"error":"session gone"}', 404),
        ),
      ),
    );
    await expectLater(
      gateway.createSession(),
      throwsA(isA<ChatNotFoundException>()),
    );
  });

  test('transport-level failure maps to ChatNetworkException', () async {
    final gateway = HttpGateway(
      config(
        client: MockClient(
          (req) async => throw http.ClientException('connection refused'),
        ),
      ),
    );
    await expectLater(
      gateway.createSession(),
      throwsA(isA<ChatNetworkException>()),
    );
  });

  test('openMessageStream posts the turn and yields parsed events', () async {
    late http.BaseRequest seen;
    late String body;
    final gateway = HttpGateway(
      config(
        client: MockClient.streaming((req, bodyStream) async {
          seen = req;
          body = await bodyStream.bytesToString();
          return http.StreamedResponse(Stream.value(utf8.encode(sseBody)), 200);
        }),
      ),
    );
    final events = await gateway
        .openMessageStream(sessionId: 's1', text: 'hello', clientTag: 'tag-1')
        .then((s) => s.toList());
    expect(seen.url.path, '/chat/messages');
    expect(jsonDecode(body), {
      'sessionId': 's1',
      'text': 'hello',
      'clientTag': 'tag-1',
    });
    expect((events[0] as TokenDelta).delta, 'Hi');
    expect(events[1], isA<StreamDone>());
  });

  test(
    'openMessageStream maps a non-200 before any event is emitted',
    () async {
      final gateway = HttpGateway(
        config(
          client: MockClient.streaming(
            (req, bodyStream) async => http.StreamedResponse(
              Stream.value(utf8.encode('{"error":"daily limit reached"}')),
              429,
            ),
          ),
        ),
      );
      await expectLater(
        gateway.openMessageStream(sessionId: 's1', text: 'x', clientTag: 't'),
        throwsA(isA<ChatRateLimitException>()),
      );
    },
  );

  test('fetchHistory GETs the messages endpoint and parses the envelope', () async {
    late http.Request seen;
    final gateway = HttpGateway(
      config(
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            '{"messages":['
            '{"id":"m1","sessionId":"s1","role":"user","content":"hi","createdAt":"2026-07-01T10:00:00.000Z"},'
            '{"id":"m2","sessionId":"s1","role":"assistant","content":"hello","createdAt":"2026-07-01T10:00:01.000Z"}'
            ']}',
            200,
          );
        }),
      ),
    );
    final messages = await gateway.fetchHistory('s1');
    expect(seen.method, 'GET');
    expect(seen.url.path, '/chat/sessions/s1/messages');
    expect(seen.headers['Authorization'], 'Bearer jwt-1');
    expect(messages, hasLength(2));
    expect(messages[0].role, ChatRole.user);
    expect(messages[1].content, 'hello');
    expect(
      messages[0].status,
      MessageStatus.sent,
      reason: 'persisted history is settled',
    );
  });

  test('fetchHistory maps 404 to ChatNotFoundException', () async {
    final gateway = HttpGateway(
      config(
        client: MockClient(
          (req) async => http.Response('{"error":"session not found"}', 404),
        ),
      ),
    );
    await expectLater(
      gateway.fetchHistory('nope'),
      throwsA(isA<ChatNotFoundException>()),
    );
  });
}
