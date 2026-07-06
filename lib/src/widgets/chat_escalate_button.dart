import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_role.dart';
import '../riverpod/chat_providers.dart';
import 'tickflow_chat_localizations.dart';

/// The user-initiated escalation affordance — the design's header
/// person-button — as a drop-in action for the host's AppBar:
///
/// ```dart
/// AppBar(
///   title: Text(...),
///   actions: [ChatEscalateButton(sessionId: session.id)],
/// )
/// ```
///
/// Tapping asks for confirmation, then hands the session to human support
/// (`POST /escalate`, idempotent server-side); [ChatView] then shows the
/// "we'll follow up by email" notice. Disabled once the session is
/// escalated. Icon-only, so it carries a localized tooltip/semantic label
/// (recorded a11y delta).
class ChatEscalateButton extends ConsumerWidget {
  const ChatEscalateButton({super.key, required this.sessionId});

  final String sessionId;

  Future<void> _confirmAndEscalate(BuildContext context, WidgetRef ref) async {
    final l10n = TickflowChatLocalizations.of(context);
    // A handoff files real support work — never fire it on a stray tap.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.escalateConfirmTitle),
        content: Text(l10n.escalateConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.talkToPerson),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(chatSessionProvider(sessionId).notifier).escalate();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      chatSessionProvider(sessionId).select((s) => s.session.status),
    );
    final escalated = status == SessionStatus.escalated;
    return IconButton(
      tooltip: TickflowChatLocalizations.of(context).talkToPerson,
      onPressed: escalated ? null : () => _confirmAndEscalate(context, ref),
      icon: const Icon(Icons.support_agent),
    );
  }
}
