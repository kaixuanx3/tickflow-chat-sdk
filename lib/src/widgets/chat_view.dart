import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/chat_role.dart';
import '../riverpod/chat_providers.dart';
import 'tickflow_chat_theme.dart';

/// Barebones default chat screen: message list, error line, composer.
///
/// Phase 0 scope — AI happy path, English, inherits the ambient
/// [ThemeData]. The full design (theming extension, l10n, slots,
/// escalation UI) lands in Phase 4.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(chatSessionProvider(widget.sessionId).notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatSessionProvider(widget.sessionId));

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: chat.messages.length,
              itemBuilder: (context, index) => _MessageBubble(
                message: chat.messages[chat.messages.length - 1 - index],
              ),
            ),
          ),
          if (chat.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                chat.error!.message,
                style: TextStyle(color: TickflowChatTheme.of(context).danger),
              ),
            ),
          _Composer(
            controller: _controller,
            enabled: !chat.isStreaming,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final t = TickflowChatTheme.of(context);
    final isUser = message.role == ChatRole.user;
    final failed = message.status == MessageStatus.failed;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          // A failed send drops to a bordered neutral fill so the state
          // reads without relying on color alone (the border + retry
          // affordance carry it; retry UI lands with the full P4 build).
          color: failed
              ? t.surfaceVariant
              : (isUser ? t.userBubble : t.assistantBubble),
          borderRadius: isUser ? t.userBubbleRadius : t.assistantBubbleRadius,
          border: failed
              ? Border.all(color: t.danger)
              : (isUser ? null : Border.all(color: t.outline)),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: failed || !isUser ? t.foreground : t.onUserBubble,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: enabled ? (_) => onSend() : null,
              decoration: const InputDecoration(
                hintText: 'Message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
