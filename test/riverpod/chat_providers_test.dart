import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/tickflow_chat.dart';
import 'package:tickflow_chat/tickflow_chat_riverpod.dart';

const sseBody =
    'data: {"delta":"Hi "}\n\ndata: {"delta":"there"}\n\n'
    'event: done\ndata: {"done":true,"escalated":false}\n\n';

TickflowChatConfig testConfig() => TickflowChatConfig(
  apiBaseUrl: Uri.parse('https://api.test'),
  tokenProvider: () async => 'jwt',
  httpClientFactory: () => MockClient.streaming((req, _) async {
    // the notifier hydrates history on build
    if (req.method == 'GET') {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"messages":[]}')),
        200,
      );
    }
    return http.StreamedResponse(Stream.value(utf8.encode(sseBody)), 200);
  }),
);

class _RecordingMarks implements ChatReadMarks {
  _RecordingMarks(this.recorded);

  final List<String> recorded;

  @override
  DateTime? lastReadAt(String sessionId) => null;

  @override
  Future<void> markRead(String sessionId, DateTime at) async {
    recorded.add(sessionId);
  }
}

void main() {
  test('chatConfigProvider throws until the host overrides it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(chatClientProvider),
      // riverpod 3 wraps the UnimplementedError in a ProviderException
      throwsA(
        predicate((e) => e.toString().contains('Override chatConfigProvider')),
      ),
    );
  });

  test('notifier mirrors a full engine turn into Riverpod state', () async {
    final container = ProviderContainer(
      overrides: [chatConfigProvider.overrideWithValue(testConfig())],
    );
    addTearDown(container.dispose);

    // keep the autoDispose family instance alive for the test's duration
    final sub = container.listen(chatSessionProvider('s1'), (_, _) {});
    addTearDown(sub.close);

    expect(container.read(chatSessionProvider('s1')).messages, isEmpty);

    await container.read(chatSessionProvider('s1').notifier).send('hello');
    await pumpEventQueue();

    final state = container.read(chatSessionProvider('s1'));
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, ChatRole.user);
    expect(state.messages[0].status, MessageStatus.sent);
    expect(state.messages[1].content, 'Hi there');
    expect(state.messages[1].status, MessageStatus.sent);
    expect(state.isStreaming, isFalse);
  });

  test('disposing the provider tears the engine down without leaks', () async {
    final container = ProviderContainer(
      overrides: [chatConfigProvider.overrideWithValue(testConfig())],
    );
    final sub = container.listen(chatSessionProvider('s1'), (_, _) {});
    await container.read(chatSessionProvider('s1').notifier).send('hello');
    await pumpEventQueue();
    sub.close(); // autoDispose → onDispose → engine.dispose → transport.close
    await pumpEventQueue();
    container.dispose();
  });

  test('chatInboxProvider lists the user sessions', () async {
    final container = ProviderContainer(
      overrides: [
        chatConfigProvider.overrideWithValue(
          TickflowChatConfig(
            apiBaseUrl: Uri.parse('https://api.test'),
            tokenProvider: () async => 'jwt',
            httpClientFactory: () => MockClient(
              (req) async => http.Response(
                '{"sessions":['
                '{"id":"s2","mode":"ai","status":"open","updatedAt":"2026-07-04T02:00:00.000Z"},'
                '{"id":"s1","mode":"ai","status":"escalated"}'
                ']}',
                200,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sessions = await container.read(chatInboxProvider.future);
    expect(sessions, hasLength(2));
    expect(sessions.first.id, 's2', reason: 'newest first, per server order');
    expect(sessions[1].status, SessionStatus.escalated);
  });

  test('build hydrates existing history into state', () async {
    const historyJson =
        '{"messages":[{"id":"m1","sessionId":"s1","role":"assistant",'
        '"content":"earlier answer","createdAt":"2026-07-01T10:00:00.000Z"}]}';
    final container = ProviderContainer(
      overrides: [
        chatConfigProvider.overrideWithValue(
          TickflowChatConfig(
            apiBaseUrl: Uri.parse('https://api.test'),
            tokenProvider: () async => 'jwt',
            httpClientFactory: () =>
                MockClient((req) async => http.Response(historyJson, 200)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(chatSessionProvider('s1'), (_, _) {});
    addTearDown(sub.close);

    expect(container.read(chatSessionProvider('s1')).isLoading, isTrue);
    await pumpEventQueue();

    final state = container.read(chatSessionProvider('s1'));
    expect(state.isLoading, isFalse);
    expect(state.messages.single.content, 'earlier answer');
  });

  test('opening and leaving a thread records read marks', () async {
    final recorded = <String>[];
    final container = ProviderContainer(
      overrides: [
        chatConfigProvider.overrideWithValue(testConfig()),
        chatReadMarksProvider.overrideWithValue(_RecordingMarks(recorded)),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(chatSessionProvider('s1'), (_, _) {});
    await pumpEventQueue();
    expect(recorded, ['s1'], reason: 'opening the thread marks it read');

    sub.close();
    await pumpEventQueue();
    expect(recorded, [
      's1',
      's1',
    ], reason: 'leaving marks again, covering replies read while open');
  });

  test('chatSessionIsUnread compares updatedAt to the local mark', () async {
    final marks = InMemoryChatReadMarks();
    final session = ChatSession.fromJson(const {
      'id': 's1',
      'mode': 'ai',
      'status': 'open',
      'updatedAt': '2026-07-05T10:00:00.000Z',
    });

    expect(chatSessionIsUnread(marks, session), isTrue, reason: 'never read');

    await marks.markRead('s1', DateTime.utc(2026, 7, 5, 11));
    expect(chatSessionIsUnread(marks, session), isFalse);

    await marks.markRead('s1', DateTime.utc(2026, 7, 5, 9));
    expect(
      chatSessionIsUnread(marks, session),
      isTrue,
      reason: 'activity newer than the mark badges again',
    );

    expect(
      chatSessionIsUnread(marks, ChatSession.stub('x')),
      isFalse,
      reason: 'no updatedAt on the wire → never badges',
    );
  });
}
