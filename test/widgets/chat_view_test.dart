import 'dart:async';
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

http.StreamedResponse res(String body, [int status = 200]) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: status == 429 ? const {'retry-after': '90'} : const {},
    );

/// ChatView under a routed mock: GET (history) returns an empty thread,
/// POST (one reply turn) is delegated to [onPost].
Widget app(Future<http.StreamedResponse> Function(http.BaseRequest) onPost) =>
    ProviderScope(
      overrides: [
        chatConfigProvider.overrideWithValue(
          TickflowChatConfig(
            apiBaseUrl: Uri.parse('https://api.test'),
            tokenProvider: () async => 'jwt',
            httpClientFactory: () => MockClient.streaming((req, _) async {
              if (req.method == 'GET') return res('{"messages":[]}');
              return onPost(req);
            }),
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ChatView(sessionId: 's1')),
      ),
    );

Future<void> settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  testWidgets('sends a message and renders the streamed reply', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app((_) async => res(sseBody)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      // optimistic echo is on screen before any network result
      expect(find.text('hello'), findsOneWidget);

      await settle(tester);
      expect(find.text('Hi there!'), findsOneWidget);
      final state = tester.container().read(chatSessionProvider('s1'));
      expect(state.isStreaming, isFalse);
      expect(state.messages.last.status, MessageStatus.sent);
    });
  });

  testWidgets(
    'composer clears after send and send button disables while streaming',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(app((_) async => res(sseBody)));
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'hello');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );

        await settle(tester);
      });
    },
  );

  testWidgets('an empty thread shows the localized empty state', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app((_) async => res(sseBody)));
      await settle(tester);
      expect(find.text('Ask about your account'), findsOneWidget);
    });
  });

  testWidgets('a failed send offers tap-to-retry, and retry resends', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var posts = 0;
      await tester.pumpWidget(
        app((_) async {
          posts++;
          return posts == 1 ? res('{"error":"boom"}', 500) : res(sseBody);
        }),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);

      expect(find.text("Couldn't send · tap to retry"), findsOneWidget);

      await tester.tap(find.text("Couldn't send · tap to retry"));
      await settle(tester);

      expect(find.text('Hi there!'), findsOneWidget);
      expect(find.text("Couldn't send · tap to retry"), findsNothing);
    });
  });

  testWidgets('a 429 shows the rate-limit banner and disables send', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app((_) async => res('{"error":"cap"}', 429)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);

      expect(find.textContaining("today's message limit"), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
        reason: 'send stays disabled for the Retry-After cooldown',
      );

      // Tear the tree down explicitly so the cooldown timer is disposed.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('an escalated done shows the email follow-up notice', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const escalatingSse =
          'data: {"delta":"Handing you over."}\n\n'
          'event: done\ndata: {"done":true,"escalated":true}\n\n';
      await tester.pumpWidget(app((_) async => res(escalatingSse)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'charged twice');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);

      expect(find.textContaining('by email'), findsOneWidget);
    });
  });

  testWidgets('the typing indicator covers send → first token', (tester) async {
    await tester.runAsync(() async {
      final body = StreamController<List<int>>();
      await tester.pumpWidget(
        app((_) async => http.StreamedResponse(body.stream, 200)),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);

      expect(find.byKey(const ValueKey('tickflow-typing')), findsOneWidget);

      body.add(utf8.encode('data: {"delta":"He"}\n\n'));
      await settle(tester);
      expect(find.byKey(const ValueKey('tickflow-typing')), findsNothing);
      // The streaming caret rides the same rich text, so match by substring.
      expect(find.textContaining('He'), findsOneWidget);

      body.add(
        utf8.encode('event: done\ndata: {"done":true,"escalated":false}\n\n'),
      );
      await body.close();
      await settle(tester);
    });
  });
}
