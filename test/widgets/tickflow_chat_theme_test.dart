import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

/// WCAG relative-luminance contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('bubble text meets WCAG AA (4.5:1) in both palettes', () {
    // Regression for the recorded design delta: the prototype's dark user
    // bubble (#3B6EF0) fell below AA with white text.
    for (final t in [TickflowChatTheme.light, TickflowChatTheme.dark]) {
      expect(contrast(t.userBubble, t.onUserBubble), greaterThanOrEqualTo(4.5));
      expect(
        contrast(t.assistantBubble, t.foreground),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('of() falls back to the palette matching Theme brightness', (
    tester,
  ) async {
    late TickflowChatTheme resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            resolved = TickflowChatTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved.background, TickflowChatTheme.dark.background);
  });

  testWidgets('a host override installed as a ThemeExtension wins', (
    tester,
  ) async {
    final custom = TickflowChatTheme.light.copyWith(
      userBubble: const Color(0xFF123456),
    );
    late TickflowChatTheme resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [custom]),
        home: Builder(
          builder: (context) {
            resolved = TickflowChatTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved.userBubble, const Color(0xFF123456));
  });

  test('lerp interpolates between the palettes', () {
    final end = TickflowChatTheme.light.lerp(TickflowChatTheme.dark, 1.0);
    expect(end.background, TickflowChatTheme.dark.background);
    expect(
      TickflowChatTheme.light.lerp(null, 0.5).surface,
      TickflowChatTheme.light.surface,
    );
  });
}
