import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/tickflow_chat.dart';
import 'package:tickflow_chat/tickflow_chat_riverpod.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

const twoSessions =
    '{"sessions":['
    '{"id":"s2","mode":"ai","status":"open","updatedAt":"2026-07-05T02:00:00.000Z"},'
    '{"id":"s1","mode":"ai","status":"escalated","updatedAt":"2026-07-04T02:00:00.000Z"}'
    ']}';

class _FixedMarks implements ChatReadMarks {
  _FixedMarks(this.marks);

  final Map<String, DateTime> marks;

  @override
  DateTime? lastReadAt(String sessionId) => marks[sessionId];

  @override
  Future<void> markRead(String sessionId, DateTime at) async {}
}

Widget app(
  Future<http.Response> Function() onList, {
  ChatReadMarks? marks,
  void Function(ChatSession)? onOpen,
  VoidCallback? onStart,
}) => ProviderScope(
  overrides: [
    chatConfigProvider.overrideWithValue(
      TickflowChatConfig(
        apiBaseUrl: Uri.parse('https://api.test'),
        tokenProvider: () async => 'jwt',
        httpClientFactory: () => MockClient((req) => onList()),
      ),
    ),
    if (marks != null) chatReadMarksProvider.overrideWithValue(marks),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: ChatInboxView(
        onOpenSession: onOpen ?? (_) {},
        onStartConversation: onStart ?? () {},
      ),
    ),
  ),
);

Future<void> settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  testWidgets('lists sessions newest-first and opens one on tap', (
    tester,
  ) async {
    await tester.runAsync(() async {
      ChatSession? opened;
      await tester.pumpWidget(
        app(
          () async => http.Response(twoSessions, 200),
          onOpen: (s) => opened = s,
        ),
      );
      await settle(tester);

      expect(find.text('Recent conversations'), findsOneWidget);
      expect(find.text('Tickflow Assistant'), findsOneWidget);
      expect(
        find.text('Human support'),
        findsOneWidget,
        reason: 'escalated sessions read as human support',
      );

      await tester.tap(find.text('Tickflow Assistant'));
      expect(opened?.id, 's2');
    });
  });

  testWidgets('the greeting CTA starts a conversation', (tester) async {
    await tester.runAsync(() async {
      var started = false;
      await tester.pumpWidget(
        app(
          () async => http.Response('{"sessions":[]}', 200),
          onStart: () => started = true,
        ),
      );
      await settle(tester);

      expect(
        find.text('Recent conversations'),
        findsNothing,
        reason: 'empty inbox keeps just the greeting card',
      );
      await tester.tap(find.text('Ask Tickflow Assistant'));
      expect(started, isTrue);
    });
  });

  testWidgets('unread dots show only for activity newer than the mark', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        app(
          () async => http.Response(twoSessions, 200),
          // s1 was read after its last activity; s2 never read.
          marks: _FixedMarks({'s1': DateTime.utc(2026, 7, 5)}),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('tickflow-unread-s2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tickflow-unread-s1')), findsNothing);
    });
  });

  testWidgets('a failed load offers retry and recovers', (tester) async {
    await tester.runAsync(() async {
      var calls = 0;
      await tester.pumpWidget(
        app(() async {
          calls++;
          return calls == 1
              ? http.Response('{"error":"boom"}', 500)
              : http.Response(twoSessions, 200);
        }),
      );
      await settle(tester);

      expect(find.text('boom'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);

      expect(find.text('Tickflow Assistant'), findsOneWidget);
    });
  });
}
