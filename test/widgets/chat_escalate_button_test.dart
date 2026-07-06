import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/tickflow_chat.dart';
import 'package:tickflow_chat/tickflow_chat_riverpod.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

http.StreamedResponse res(String body) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), 200);

Widget app() => ProviderScope(
  overrides: [
    chatConfigProvider.overrideWithValue(
      TickflowChatConfig(
        apiBaseUrl: Uri.parse('https://api.test'),
        tokenProvider: () async => 'jwt',
        httpClientFactory: () => MockClient.streaming((req, _) async {
          if (req.method == 'GET') return res('{"messages":[]}');
          if (req.url.path.endsWith('/escalate')) {
            return res('{"id":"s1","mode":"ai","status":"escalated"}');
          }
          fail('unexpected request: ${req.method} ${req.url.path}');
        }),
      ),
    ),
  ],
  child: MaterialApp(
    home: Scaffold(
      appBar: AppBar(actions: const [ChatEscalateButton(sessionId: 's1')]),
      body: const ChatView(sessionId: 's1'),
    ),
  ),
);

Future<void> settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  testWidgets(
    'confirming the dialog escalates, shows the notice and disables itself',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(app());
        await settle(tester);

        await tester.tap(find.byTooltip('Talk to a person'));
        await settle(tester);
        expect(find.text('Talk to a person?'), findsOneWidget);

        // The dialog's confirming action carries the affordance text.
        await tester.tap(find.widgetWithText(FilledButton, 'Talk to a person'));
        await settle(tester);

        // ChatView reacts: the async email follow-up notice appears.
        expect(find.textContaining('by email'), findsOneWidget);
        // The session is escalated and the button reads as spent.
        final state = tester.container().read(chatSessionProvider('s1'));
        expect(state.session.status, SessionStatus.escalated);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.support_agent),
              )
              .onPressed,
          isNull,
        );
      });
    },
  );

  testWidgets('cancelling the dialog leaves the session untouched', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.byTooltip('Talk to a person'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(find.textContaining('by email'), findsNothing);
      final state = tester.container().read(chatSessionProvider('s1'));
      expect(state.session.status, SessionStatus.open);
    });
  });
}
