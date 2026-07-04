import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_exception.dart';
import '../models/chat_role.dart';
import '../models/chat_session.dart';
import '../riverpod/chat_providers.dart';
import 'tickflow_chat_localizations.dart';
import 'tickflow_chat_theme.dart';

/// The support home from the design: a greeting card with the
/// start-a-conversation CTA, the recent-conversations list with unread
/// dots, and the AI disclaimer. Pull down to re-list.
///
/// Hosts own the surrounding Scaffold/AppBar and all navigation:
/// [onStartConversation] should create a session and open its thread;
/// [onOpenSession] opens an existing one (whose [ChatView] hydrates history
/// and clears the unread mark).
class ChatInboxView extends ConsumerWidget {
  const ChatInboxView({
    super.key,
    required this.onOpenSession,
    required this.onStartConversation,
  });

  final void Function(ChatSession session) onOpenSession;
  final VoidCallback onStartConversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = TickflowChatTheme.of(context);
    final l10n = TickflowChatLocalizations.of(context);
    final inbox = ref.watch(chatInboxProvider);
    final marks = ref.watch(chatReadMarksProvider);

    return ColoredBox(
      color: t.background,
      child: SafeArea(
        child: inbox.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: t.brand)),
          error: (error, _) => _LoadFailed(
            theme: t,
            l10n: l10n,
            message: error is ChatException ? error.message : '$error',
            onRetry: () => ref.invalidate(chatInboxProvider),
          ),
          data: (sessions) => RefreshIndicator(
            color: t.brand,
            onRefresh: () => ref.refresh(chatInboxProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _GreetingCard(
                  theme: t,
                  l10n: l10n,
                  onStart: onStartConversation,
                ),
                if (sessions.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
                    child: Text(
                      l10n.recentConversations,
                      style: TextStyle(
                        color: t.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  for (final session in sessions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SessionRow(
                        session: session,
                        unread: chatSessionIsUnread(marks, session),
                        theme: t,
                        l10n: l10n,
                        onTap: () => onOpenSession(session),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    l10n.aiDisclaimer,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.faint, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.theme,
    required this.l10n,
    required this.onStart,
  });

  final TickflowChatTheme theme;
  final TickflowChatLocalizations l10n;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    // The CTA stays a light card in both themes, per the prototype — so its
    // colors come from the light palette explicitly.
    const ctaSurface = TickflowChatTheme.light;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.brand, t.brandSecondary],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.greetTitle,
            style: TextStyle(
              color: t.onUserBubble,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            l10n.greetSubtitle,
            style: TextStyle(
              color: t.onUserBubble.withValues(alpha: 0.9),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: ctaSurface.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onStart,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [t.brand, t.brandSecondary],
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: t.onUserBubble,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.askAssistant,
                            style: TextStyle(
                              color: ctaSurface.foreground,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            l10n.repliesInstantly,
                            style: TextStyle(
                              color: t.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: ctaSurface.faint),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.unread,
    required this.theme,
    required this.l10n,
    required this.onTap,
  });

  final ChatSession session;
  final bool unread;
  final TickflowChatTheme theme;
  final TickflowChatLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final human =
        session.mode == SessionMode.human ||
        session.status == SessionStatus.escalated;
    final updatedAt = session.updatedAt;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: t.outline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _InboxAvatar(theme: t, human: human),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        human ? l10n.humanSupport : l10n.assistantTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.foreground,
                          fontSize: 15,
                          // Weight + dot together, so unread never reads by
                          // color alone.
                          fontWeight: unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (unread)
                      Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: ExcludeSemantics(
                          child: Container(
                            key: ValueKey('tickflow-unread-${session.id}'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: t.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (updatedAt != null)
                Text(
                  _timeLabel(context, updatedAt),
                  style: TextStyle(color: t.faint, fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Same-day activity shows the time, anything older the short date — both
  /// via [MaterialLocalizations], so the label follows the app locale.
  String _timeLabel(BuildContext context, DateTime updatedAtUtc) {
    final local = updatedAtUtc.toLocal();
    final now = DateTime.now();
    final ml = MaterialLocalizations.of(context);
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay
        ? ml.formatTimeOfDay(TimeOfDay.fromDateTime(local))
        : ml.formatShortDate(local);
  }
}

class _InboxAvatar extends StatelessWidget {
  const _InboxAvatar({required this.theme, required this.human});

  final TickflowChatTheme theme;
  final bool human;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      width: 42,
      height: 42,
      decoration: human
          ? BoxDecoration(color: t.agentAccent, shape: BoxShape.circle)
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.brand, t.brandSecondary],
              ),
              borderRadius: BorderRadius.circular(13),
            ),
      child: Icon(
        human ? Icons.person : Icons.auto_awesome,
        size: 19,
        color: t.onUserBubble,
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({
    required this.theme,
    required this.l10n,
    required this.message,
    required this.onRetry,
  });

  final TickflowChatTheme theme;
  final TickflowChatLocalizations l10n;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.brand,
                foregroundColor: t.onUserBubble,
              ),
              onPressed: onRetry,
              child: Text(l10n.retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
