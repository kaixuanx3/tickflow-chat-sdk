import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

void main() {
  Future<TickflowChatLocalizations> resolve(
    WidgetTester tester,
    Locale locale,
  ) async {
    late TickflowChatLocalizations l10n;
    await tester.pumpWidget(
      Localizations(
        locale: locale,
        delegates: const [
          TickflowChatLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Builder(
          builder: (context) {
            l10n = TickflowChatLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return l10n;
  }

  testWidgets('delegate loads English', (tester) async {
    final l10n = await resolve(tester, const Locale('en'));
    expect(l10n.composerHint, 'Message');
    expect(l10n.sendButtonLabel, 'Send');
    expect(l10n.tapToRetry, contains('retry'));
  });

  testWidgets('delegate loads 中文', (tester) async {
    final l10n = await resolve(tester, const Locale('zh'));
    expect(l10n.composerHint, '输入消息');
    expect(l10n.sendButtonLabel, '发送');
    expect(
      l10n.escalatedNotice,
      contains('邮件'),
      reason: 'the async email follow-up promise is localized',
    );
  });

  testWidgets('of() falls back to English when the delegate is absent', (
    tester,
  ) async {
    late TickflowChatLocalizations l10n;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          l10n = TickflowChatLocalizations.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(l10n.composerHint, 'Message');
  });

  test('supported locales cover the app locales (en + zh)', () {
    expect(
      TickflowChatLocalizations.supportedLocales,
      containsAll(const [Locale('en'), Locale('zh')]),
    );
    expect(
      TickflowChatLocalizations.delegate.isSupported(const Locale('zh')),
      isTrue,
    );
    expect(
      TickflowChatLocalizations.delegate.isSupported(const Locale('ja')),
      isFalse,
    );
  });
}
