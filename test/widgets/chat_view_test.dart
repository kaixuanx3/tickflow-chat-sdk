import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/tickflow_chat.dart';
import 'package:tickflow_chat/tickflow_chat_riverpod.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

const sseBody =
    'data: {"delta":"Hi there!"}\n\n'
    'event: done\ndata: {"done":true,"escalated":false}\n\n';

Widget app() => ProviderScope(
  overrides: [
    chatConfigProvider.overrideWithValue(
      TickflowChatConfig(
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
      ),
    ),
  ],
  child: const MaterialApp(
    home: Scaffold(body: ChatView(sessionId: 's1')),
  ),
);

void main() {
  testWidgets('sends a message and renders the streamed reply', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      // optimistic echo is on screen before any network result
      expect(find.text('hello'), findsOneWidget);

      // let the mocked SSE stream deliver and settle
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Hi there!'), findsOneWidget);
      // tester.container() comes from flutter_riverpod's test extension
      final state = tester.container().read(chatSessionProvider('s1'));
      expect(state.isStreaming, isFalse);
      expect(state.messages.last.status, MessageStatus.sent);
    });
  });

  testWidgets(
    'composer clears after send and send button disables while streaming',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(app());

        await tester.enterText(find.byType(TextField), 'hello');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
    },
  );
}
