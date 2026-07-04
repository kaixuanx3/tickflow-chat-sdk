import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/chat_session_state.dart';
import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_role.dart';
import '../riverpod/chat_providers.dart';
import 'tickflow_chat_localizations.dart';
import 'tickflow_chat_theme.dart';

/// The default support-chat screen body: message thread, status banners and
/// composer, drawn from [TickflowChatTheme] tokens and
/// [TickflowChatLocalizations] strings (en/中文). Hosts own the surrounding
/// app bar and routing; slot builders for deeper customization arrive later
/// in P4.
///
/// Accessibility: a completed reply is announced to screen readers once, on
/// settle (never per token); motion (entrance rise, typing dots, streaming
/// caret) is disabled under [MediaQuery.disableAnimationsOf]; every tap
/// target is at least 44px.
/// Replaces the default row for one message (bubble, status caption, retry
/// affordance). The default layout still renders every other message.
typedef ChatMessageBuilder =
    Widget Function(BuildContext context, ChatMessage message);

/// Replaces the default composer; see [ChatComposerDetails] for what the
/// thread hands a custom composer.
typedef ChatComposerBuilder =
    Widget Function(BuildContext context, ChatComposerDetails details);

/// What a custom composer needs from the thread: whether a reply is in
/// flight ([busy]), the rate-limit cooldown deadline ([retryAt], null when
/// none is running), and [onSubmit] to run one optimistic send.
@immutable
class ChatComposerDetails {
  const ChatComposerDetails({
    required this.busy,
    required this.retryAt,
    required this.onSubmit,
  });

  final bool busy;
  final DateTime? retryAt;
  final ValueChanged<String> onSubmit;
}

class ChatView extends ConsumerStatefulWidget {
  const ChatView({
    super.key,
    required this.sessionId,
    this.messageBuilder,
    this.composerBuilder,
    this.emptyBuilder,
    this.loadingBuilder,
    this.escalatedBuilder,
  });

  final String sessionId;

  /// Slot builders — each replaces one region of the default UI while the
  /// rest keeps working (state wiring, retry, cooldowns, a11y).
  final ChatMessageBuilder? messageBuilder;
  final ChatComposerBuilder? composerBuilder;

  /// Replaces the empty-thread state.
  final WidgetBuilder? emptyBuilder;

  /// Replaces the history-loading spinner.
  final WidgetBuilder? loadingBuilder;

  /// Replaces the escalated "we'll follow up by email" notice.
  final WidgetBuilder? escalatedBuilder;

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

  void _retry(String clientTag) =>
      ref.read(chatSessionProvider(widget.sessionId).notifier).retry(clientTag);

  /// One optimistic send, for custom composers (the default composer owns
  /// its own controller and goes through [_send]).
  void _submit(String text) =>
      ref.read(chatSessionProvider(widget.sessionId).notifier).send(text);

  @override
  Widget build(BuildContext context) {
    // Announce the finished reply once on settle — never per token
    // (recorded a11y delta).
    ref.listen(chatSessionProvider(widget.sessionId), (previous, next) {
      if ((previous?.isStreaming ?? false) &&
          !next.isStreaming &&
          next.messages.isNotEmpty) {
        final last = next.messages.last;
        if (last.role != ChatRole.user && last.status == MessageStatus.sent) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            last.content,
            Directionality.of(context),
          );
        }
      }
    });

    final chat = ref.watch(chatSessionProvider(widget.sessionId));
    final t = TickflowChatTheme.of(context);
    final l10n = TickflowChatLocalizations.of(context);
    final showTyping = chat.isAwaitingReply && !chat.isStreaming;

    return ColoredBox(
      color: t.background,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: _thread(chat, showTyping, t, l10n)),
            if (chat.error is ChatRateLimitException)
              _Banner(
                icon: Icons.error_outline,
                text: l10n.rateLimitBanner,
                foreground: t.warning,
                background: t.warningBackground,
                outline: t.warningOutline,
              )
            else if (chat.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  chat.error!.message,
                  style: TextStyle(color: t.danger, fontSize: 12.5),
                ),
              ),
            if (chat.session.status == SessionStatus.escalated)
              widget.escalatedBuilder?.call(context) ??
                  _Banner(
                    icon: Icons.mark_email_read_outlined,
                    text: l10n.escalatedNotice,
                    foreground: t.muted,
                    background: t.surfaceVariant,
                    outline: t.outline,
                  ),
            if (widget.composerBuilder != null)
              widget.composerBuilder!(
                context,
                ChatComposerDetails(
                  busy: chat.isStreaming || showTyping,
                  retryAt: chat.retryAt,
                  onSubmit: _submit,
                ),
              )
            else
              _Composer(
                controller: _controller,
                busy: chat.isStreaming || showTyping,
                retryAt: chat.retryAt,
                onSend: _send,
              ),
          ],
        ),
      ),
    );
  }

  Widget _thread(
    ChatSessionState chat,
    bool showTyping,
    TickflowChatTheme t,
    TickflowChatLocalizations l10n,
  ) {
    if (chat.isLoading && chat.messages.isEmpty) {
      return widget.loadingBuilder?.call(context) ??
          Center(child: CircularProgressIndicator(color: t.brand));
    }
    if (chat.messages.isEmpty && !showTyping) {
      return widget.emptyBuilder?.call(context) ??
          _EmptyState(theme: t, l10n: l10n);
    }
    final count = chat.messages.length + (showTyping ? 1 : 0);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      itemCount: count,
      itemBuilder: (context, index) {
        if (showTyping && index == 0) return _TypingIndicator(theme: t);
        final i = showTyping ? index - 1 : index;
        final message = chat.messages[chat.messages.length - 1 - i];
        return widget.messageBuilder?.call(context, message) ??
            _MessageRow(
              message: message,
              theme: t,
              l10n: l10n,
              onRetry: _retry,
            );
      },
    );
  }
}

/// One thread entry, laid out per role. Entrance motion runs only for
/// content born on this screen (sending/streaming) — settled history renders
/// static, so recycling while scrolling never re-animates old bubbles.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.theme,
    required this.l10n,
    required this.onRetry,
  });

  final ChatMessage message;
  final TickflowChatTheme theme;
  final TickflowChatLocalizations l10n;
  final void Function(String clientTag) onRetry;

  @override
  Widget build(BuildContext context) {
    final fresh =
        message.status == MessageStatus.sending ||
        message.status == MessageStatus.streaming;
    final animate = fresh && !MediaQuery.disableAnimationsOf(context);
    final child = switch (message.role) {
      ChatRole.user => _user(context),
      ChatRole.system => _system(),
      // Assistant, agent and forward-compatible unknown roles share the
      // left-aligned avatar+bubble layout.
      _ => _assistant(context),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: _Entrance(animate: animate, child: child),
    );
  }

  Widget _user(BuildContext context) {
    final t = theme;
    final failed = message.status == MessageStatus.failed;
    final sending = message.status == MessageStatus.sending;
    final tag = message.clientTag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              // Failed sends drop to a bordered neutral fill so the state
              // reads without relying on color alone.
              color: failed ? t.surfaceVariant : t.userBubble,
              borderRadius: t.userBubbleRadius,
              border: failed ? Border.all(color: t.danger) : null,
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: failed ? t.foreground : t.onUserBubble,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
        ),
        if (failed && tag != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Semantics(
              button: true,
              label: l10n.tapToRetry,
              child: InkWell(
                onTap: () => onRetry(tag),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  // Keeps the visible row small while the tap target stays
                  // comfortably above 44px with the bubble edge.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: t.danger),
                      const SizedBox(width: 5),
                      Text(
                        l10n.tapToRetry,
                        style: TextStyle(
                          color: t.danger,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (sending)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 4),
            child: Text(
              l10n.sending,
              style: TextStyle(color: t.faint, fontSize: 10.5),
            ),
          ),
      ],
    );
  }

  Widget _system() {
    final t = theme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: t.surfaceVariant,
          border: Border.all(color: t.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: TextStyle(color: t.muted, fontSize: 11.5, height: 1.4),
        ),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    final t = theme;
    final isAgent = message.role == ChatRole.agent;
    final streaming = message.status == MessageStatus.streaming;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(theme: t, isAgent: isAgent),
        const SizedBox(width: 9),
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                color: t.assistantBubble,
                borderRadius: t.assistantBubbleRadius,
                border: Border.all(color: t.outline),
              ),
              child: Text.rich(
                TextSpan(
                  text: message.content,
                  children: [
                    if (streaming)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: _StreamingCaret(color: t.brand),
                        ),
                      ),
                  ],
                ),
                style: TextStyle(
                  color: t.foreground,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.theme, required this.isAgent});

  final TickflowChatTheme theme;
  final bool isAgent;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.only(top: 2),
      decoration: isAgent
          ? BoxDecoration(color: t.agentAccent, shape: BoxShape.circle)
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.brand, t.brandSecondary],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
      child: Icon(
        isAgent ? Icons.person : Icons.auto_awesome,
        size: 15,
        color: t.onUserBubble,
      ),
    );
  }
}

/// One-shot rise-and-fade for content born on this screen. Static when
/// [animate] is false (settled history, reduced motion).
class _Entrance extends StatelessWidget {
  const _Entrance({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Blinking block caret at the end of a streaming reply; solid under
/// reduced motion.
class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret({required this.color});

  final Color color;

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blink.stop();
      _blink.value = 0;
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(
        opacity: _blink.value < 0.5 ? 1 : 0,
        child: Container(
          width: 7,
          height: 15,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

/// Assistant-side "thinking" bubble shown between a sent turn and its first
/// token; dots hold still under reduced motion.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.theme})
    : super(key: const ValueKey('tickflow-typing'));

  final TickflowChatTheme theme;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _cycle.stop();
      _cycle.value = 0;
    } else if (!_cycle.isAnimating) {
      _cycle.repeat();
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final still = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(theme: t, isAgent: false),
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: t.assistantBubble,
              borderRadius: t.assistantBubbleRadius,
              border: Border.all(color: t.outline),
            ),
            child: AnimatedBuilder(
              animation: _cycle,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _dot(still ? 0.7 : _phase(i), t.muted),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 0..1 emphasis for dot [i]: a staggered pulse matching the prototype's
  /// 1.2s cycle with 0.2s offsets.
  double _phase(int i) {
    final p = (_cycle.value - i * (0.2 / 1.2)) % 1.0;
    if (p < 0 || p > 0.3) return 0.35;
    return 0.35 + 0.65 * math.sin(p / 0.3 * math.pi);
  }

  Widget _dot(double emphasis, Color color) => Transform.translate(
    offset: Offset(0, -4 * ((emphasis - 0.35) / 0.65).clamp(0, 1)),
    child: Opacity(
      opacity: emphasis.clamp(0.35, 1),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme, required this.l10n});

  final TickflowChatTheme theme;
  final TickflowChatLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [t.brand, t.brandSecondary],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.auto_awesome, size: 28, color: t.onUserBubble),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.emptyTitle,
              style: TextStyle(
                color: t.foreground,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                l10n.emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.foreground,
    required this.background,
    required this.outline,
  });

  final IconData icon;
  final String text;
  final Color foreground;
  final Color background;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Multiline composer (recorded delta: the prototype's single-line input)
/// with a ≥44px send target. Sending is blocked while a reply is in flight
/// and while a rate-limit cooldown ([retryAt]) is running; a timer re-enables
/// the button the moment the cooldown passes.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.retryAt,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final DateTime? retryAt;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  Timer? _cooldown;

  bool get _coolingDown {
    final at = widget.retryAt;
    return at != null && DateTime.now().isBefore(at);
  }

  @override
  void initState() {
    super.initState();
    _armCooldown();
  }

  @override
  void didUpdateWidget(_Composer old) {
    super.didUpdateWidget(old);
    if (old.retryAt != widget.retryAt) _armCooldown();
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  void _armCooldown() {
    _cooldown?.cancel();
    final at = widget.retryAt;
    if (at == null) return;
    final left = at.difference(DateTime.now());
    if (left <= Duration.zero) return;
    _cooldown = Timer(left + const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = TickflowChatTheme.of(context);
    final l10n = TickflowChatLocalizations.of(context);
    final canSend = !widget.busy && !_coolingDown;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.outline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: TextStyle(color: t.foreground, fontSize: 15),
              decoration: InputDecoration(
                hintText: l10n.composerHint,
                hintStyle: TextStyle(color: t.faint),
                filled: true,
                fillColor: t.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(22)),
                  borderSide: BorderSide(color: t.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(22)),
                  borderSide: BorderSide(color: t.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(22)),
                  borderSide: BorderSide(color: t.brand),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: l10n.sendButtonLabel,
            style: IconButton.styleFrom(
              backgroundColor: t.brand,
              foregroundColor: t.onUserBubble,
              disabledBackgroundColor: t.surfaceVariant,
              disabledForegroundColor: t.faint,
              minimumSize: const Size(44, 44),
            ),
            onPressed: canSend ? widget.onSend : null,
            icon: const Icon(Icons.send_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
