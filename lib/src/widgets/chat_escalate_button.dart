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
/// Tapping hands the session to human support (`POST /escalate`, idempotent
/// server-side); [ChatView] then shows the "we'll follow up by email"
/// notice. Disabled once the session is escalated. Icon-only, so it carries
/// a localized tooltip/semantic label (recorded a11y delta).
class ChatEscalateButton extends ConsumerWidget {
  const ChatEscalateButton({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      chatSessionProvider(sessionId).select((s) => s.session.status),
    );
    final escalated = status == SessionStatus.escalated;
    return IconButton(
      tooltip: TickflowChatLocalizations.of(context).talkToPerson,
      onPressed: escalated
          ? null
          : () => ref.read(chatSessionProvider(sessionId).notifier).escalate(),
      icon: const Icon(Icons.support_agent),
    );
  }
}
