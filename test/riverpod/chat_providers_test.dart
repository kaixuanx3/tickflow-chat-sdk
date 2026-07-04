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
  httpClientFactory: () => MockClient.streaming(
    (req, _) async =>
        http.StreamedResponse(Stream.value(utf8.encode(sseBody)), 200),
  ),
);

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
}
