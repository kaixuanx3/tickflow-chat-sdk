import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/tickflow_chat.dart';
import 'package:tickflow_chat/tickflow_chat_riverpod.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

/// A settled thread exercising every role's layout: user + assistant turn,
/// system pill, agent reply. History hydrates as `sent`, so no animation
/// runs and the frame is deterministic (flutter_test's Ahem font).
const _history =
    '{"messages":['
    '{"id":"m1","sessionId":"s1","role":"user","content":"I was charged twice for my deposit.","createdAt":"2026-07-01T10:00:00.000Z"},'
    '{"id":"m2","sessionId":"s1","role":"assistant","content":"I am sorry about that - this needs our payments team. I have escalated it for you.","createdAt":"2026-07-01T10:00:05.000Z"},'
    '{"id":"m3","sessionId":"s1","role":"system","content":"Connected to Tickflow support.","createdAt":"2026-07-01T10:00:06.000Z"},'
    '{"id":"m4","sessionId":"s1","role":"agent","content":"Hi, this is Mei. I found the duplicate and issued a refund.","createdAt":"2026-07-01T10:01:00.000Z"}'
    ']}';

Widget app(Brightness brightness) => ProviderScope(
  overrides: [
    chatConfigProvider.overrideWithValue(
      TickflowChatConfig(
        apiBaseUrl: Uri.parse('https://api.test'),
        tokenProvider: () async => 'jwt',
        httpClientFactory: () => MockClient.streaming(
          (req, _) async =>
              http.StreamedResponse(Stream.value(utf8.encode(_history)), 200),
        ),
      ),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: const Scaffold(body: ChatView(sessionId: 's1')),
  ),
);

void main() {
  Future<void> pumpThread(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(380, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(app(brightness));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  testWidgets('thread renders the design — light', (tester) async {
    await pumpThread(tester, Brightness.light);
    await expectLater(
      find.byType(ChatView),
      matchesGoldenFile('goldens/thread_light.png'),
    );
  });

  testWidgets('thread renders the design — dark', (tester) async {
    await pumpThread(tester, Brightness.dark);
    await expectLater(
      find.byType(ChatView),
      matchesGoldenFile('goldens/thread_dark.png'),
    );
  });
}
