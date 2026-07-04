import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Strings for the default chat UI, English and 简体中文 (matching the host
/// app's locales). Hand-written rather than gen-l10n: consumers pull this
/// package as a git dependency and never run codegen.
///
/// Install in the host's `MaterialApp`:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: [
///     TickflowChatLocalizations.delegate,
///     ...AppLocalizations.localizationsDelegates,
///   ],
/// )
/// ```
///
/// Without the delegate, [of] falls back to English so the widget never
/// throws over a missing localization.
abstract class TickflowChatLocalizations {
  const TickflowChatLocalizations();

  static const LocalizationsDelegate<TickflowChatLocalizations> delegate =
      _TickflowChatLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en'), Locale('zh')];

  static TickflowChatLocalizations of(BuildContext context) =>
      Localizations.of<TickflowChatLocalizations>(
        context,
        TickflowChatLocalizations,
      ) ??
      const TickflowChatLocalizationsEn();

  /// Thread header title while the assistant handles the session.
  String get assistantTitle;

  /// Header status line: AI available.
  String get statusOnline;

  /// Header status line: escalated, no agent yet (async email follow-up).
  String get statusWaiting;

  /// Header title once a human agent is present.
  String get humanSupport;

  /// The escalation affordance.
  String get talkToPerson;

  /// Composer placeholder.
  String get composerHint;

  /// Semantic label / tooltip for the icon-only send button.
  String get sendButtonLabel;

  /// Empty thread state.
  String get emptyTitle;
  String get emptySubtitle;

  /// Under a bubble that failed to send; the whole row is the retry target.
  String get tapToRetry;

  /// Under the optimistic echo before the server confirms it.
  String get sending;

  /// Rate-limit banner (per-user daily cap; resets at midnight ET).
  String get rateLimitBanner;

  /// System notice once a session is escalated: async follow-up promise.
  String get escalatedNotice;

  /// Small-print reminder that answers are AI-generated.
  String get aiDisclaimer;

  /// Inbox greeting card.
  String get greetTitle;
  String get greetSubtitle;

  /// The greeting card's start-a-conversation CTA.
  String get askAssistant;
  String get repliesInstantly;

  /// Inbox section header above the thread list.
  String get recentConversations;

  /// Generic retry action (inbox load failure and the like).
  String get retryLabel;
}

class TickflowChatLocalizationsEn extends TickflowChatLocalizations {
  const TickflowChatLocalizationsEn();

  @override
  String get assistantTitle => 'Tickflow Assistant';
  @override
  String get statusOnline => 'AI · online';
  @override
  String get statusWaiting => 'Waiting for an agent…';
  @override
  String get humanSupport => 'Human support';
  @override
  String get talkToPerson => 'Talk to a person';
  @override
  String get composerHint => 'Message';
  @override
  String get sendButtonLabel => 'Send';
  @override
  String get emptyTitle => 'Ask about your account';
  @override
  String get emptySubtitle =>
      'Orders, deposits, verification, fees — start with a question below.';
  @override
  String get tapToRetry => "Couldn't send · tap to retry";
  @override
  String get sending => 'Sending…';
  @override
  String get rateLimitBanner =>
      "You've reached today's message limit. It resets at midnight ET.";
  @override
  String get escalatedNotice =>
      "You're in the queue. We'll follow up here and by email once it's "
      'resolved.';
  @override
  String get aiDisclaimer => 'Answers are AI-generated and may be inaccurate.';
  @override
  String get greetTitle => 'How can we help?';
  @override
  String get greetSubtitle =>
      'Ask our assistant anything — most issues are solved in a minute.';
  @override
  String get askAssistant => 'Ask Tickflow Assistant';
  @override
  String get repliesInstantly => 'AI · replies instantly';
  @override
  String get recentConversations => 'Recent conversations';
  @override
  String get retryLabel => 'Retry';
}

class TickflowChatLocalizationsZh extends TickflowChatLocalizations {
  const TickflowChatLocalizationsZh();

  @override
  String get assistantTitle => 'Tickflow 助手';
  @override
  String get statusOnline => 'AI · 在线';
  @override
  String get statusWaiting => '正在等待客服…';
  @override
  String get humanSupport => '人工客服';
  @override
  String get talkToPerson => '联系人工客服';
  @override
  String get composerHint => '输入消息';
  @override
  String get sendButtonLabel => '发送';
  @override
  String get emptyTitle => '咨询您的账户';
  @override
  String get emptySubtitle => '订单、存款、验证、费用——从下面的问题开始。';
  @override
  String get tapToRetry => '发送失败 · 点按重试';
  @override
  String get sending => '发送中…';
  @override
  String get rateLimitBanner => '您已达到今日消息上限，将于美东午夜重置。';
  @override
  String get escalatedNotice => '您已进入队列。解决后我们将在此并通过邮件与您联系。';
  @override
  String get aiDisclaimer => '回答由 AI 生成，可能不准确。';
  @override
  String get greetTitle => '需要什么帮助？';
  @override
  String get greetSubtitle => '向助手咨询任何问题——大多数问题一分钟内即可解决。';
  @override
  String get askAssistant => '咨询 Tickflow 助手';
  @override
  String get repliesInstantly => 'AI · 即时回复';
  @override
  String get recentConversations => '最近的对话';
  @override
  String get retryLabel => '重试';
}

class _TickflowChatLocalizationsDelegate
    extends LocalizationsDelegate<TickflowChatLocalizations> {
  const _TickflowChatLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  Future<TickflowChatLocalizations> load(Locale locale) => SynchronousFuture(
    locale.languageCode == 'zh'
        ? const TickflowChatLocalizationsZh()
        : const TickflowChatLocalizationsEn(),
  );

  @override
  bool shouldReload(_TickflowChatLocalizationsDelegate old) => false;
}
