import 'package:flutter/material.dart';

/// Design tokens for the default chat UI, as a [ThemeExtension] so hosts can
/// override any of them via `ThemeData(extensions: [...])`:
///
/// ```dart
/// ThemeData(extensions: const [
///   TickflowChatTheme.light, // or .dark, or copyWith(...) overrides
/// ])
/// ```
///
/// Unset hosts get the Tickflow support palette matching the ambient
/// [Theme] brightness. Values come from the design prototype, with one
/// deliberate correction: the prototype's dark-mode user bubble (#3B6EF0)
/// leaves white text below 4.5:1, so dark mode reuses the light-mode blue
/// (#2E64F0, ≈5.0:1) — see the contrast regression test.
@immutable
class TickflowChatTheme extends ThemeExtension<TickflowChatTheme> {
  const TickflowChatTheme({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.userBubble,
    required this.onUserBubble,
    required this.assistantBubble,
    required this.foreground,
    required this.muted,
    required this.faint,
    required this.outline,
    required this.brand,
    required this.brandSecondary,
    required this.danger,
    required this.warning,
    required this.warningBackground,
    required this.warningOutline,
    required this.agentAccent,
    required this.success,
    required this.userBubbleRadius,
    required this.assistantBubbleRadius,
  });

  /// Thread scroll background.
  final Color background;

  /// Composer bar and card surfaces.
  final Color surface;

  /// Pills, disabled send button, failed-bubble fill.
  final Color surfaceVariant;

  /// Filled user bubble; [onUserBubble] must keep ≥4.5:1 on it.
  final Color userBubble;
  final Color onUserBubble;

  /// Assistant/agent bubble fill (bordered with [outline]).
  final Color assistantBubble;

  /// Primary text on [surface]/[assistantBubble].
  final Color foreground;

  /// Secondary text (status line, system pills, typing dots).
  final Color muted;

  /// Tertiary text (timestamps, "Sending…").
  final Color faint;

  /// Hairline borders and dividers.
  final Color outline;

  /// Brand accent (send button, streaming caret, avatar gradient start).
  final Color brand;

  /// Avatar gradient end.
  final Color brandSecondary;

  /// Failed sends and the retry affordance.
  final Color danger;

  /// Rate-limit banner text/icon, "waiting for agent" dot.
  final Color warning;
  final Color warningBackground;
  final Color warningOutline;

  /// Human-agent identity (name label, avatar gradient).
  final Color agentAccent;

  /// Positive accents (the "replies instantly" line, presence). Darkened
  /// from the prototype's #12B76A, which fails AA on white.
  final Color success;

  /// Tail bottom-right (18/18/5/18 in the prototype).
  final BorderRadius userBubbleRadius;

  /// Tail bottom-left (16/16/16/5 in the prototype).
  final BorderRadius assistantBubbleRadius;

  static const TickflowChatTheme light = TickflowChatTheme(
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEEF0F3),
    userBubble: Color(0xFF2E64F0),
    onUserBubble: Color(0xFFFFFFFF),
    assistantBubble: Color(0xFFFFFFFF),
    foreground: Color(0xFF14161A),
    muted: Color(0xFF667085),
    faint: Color(0xFF98A2B3),
    outline: Color(0xFFE7E9EE),
    brand: Color(0xFF2E64F0),
    brandSecondary: Color(0xFF5B8DEF),
    danger: Color(0xFFE5484D),
    warning: Color(0xFFB54708),
    warningBackground: Color(0xFFFFFAEB),
    warningOutline: Color(0xFFFEDF89),
    agentAccent: Color(0xFFDC6803),
    success: Color(0xFF027A48),
    userBubbleRadius: _userRadius,
    assistantBubbleRadius: _assistantRadius,
  );

  static const TickflowChatTheme dark = TickflowChatTheme(
    background: Color(0xFF0D0F14),
    surface: Color(0xFF151922),
    surfaceVariant: Color(0xFF1C2230),
    // Prototype used #3B6EF0 (< 4.5:1 with white); kept at the light-mode
    // blue for AA contrast.
    userBubble: Color(0xFF2E64F0),
    onUserBubble: Color(0xFFFFFFFF),
    assistantBubble: Color(0xFF1B2130),
    foreground: Color(0xFFE9ECF2),
    muted: Color(0xFF98A2B3),
    faint: Color(0xFF5B6675),
    outline: Color(0xFF252C39),
    brand: Color(0xFF5B8DEF),
    brandSecondary: Color(0xFF7BA4F5),
    danger: Color(0xFFFF6B6B),
    warning: Color(0xFFFEC84B),
    warningBackground: Color(0xFF2A2412),
    warningOutline: Color(0xFF4A3E1A),
    agentAccent: Color(0xFFF79009),
    success: Color(0xFF027A48),
    userBubbleRadius: _userRadius,
    assistantBubbleRadius: _assistantRadius,
  );

  static const BorderRadius _userRadius = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(5),
  );

  static const BorderRadius _assistantRadius = BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(5),
    bottomRight: Radius.circular(16),
  );

  /// The host's override when installed, else the default palette for the
  /// ambient [Theme] brightness.
  static TickflowChatTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<TickflowChatTheme>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  TickflowChatTheme copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? userBubble,
    Color? onUserBubble,
    Color? assistantBubble,
    Color? foreground,
    Color? muted,
    Color? faint,
    Color? outline,
    Color? brand,
    Color? brandSecondary,
    Color? danger,
    Color? warning,
    Color? warningBackground,
    Color? warningOutline,
    Color? agentAccent,
    Color? success,
    BorderRadius? userBubbleRadius,
    BorderRadius? assistantBubbleRadius,
  }) => TickflowChatTheme(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    userBubble: userBubble ?? this.userBubble,
    onUserBubble: onUserBubble ?? this.onUserBubble,
    assistantBubble: assistantBubble ?? this.assistantBubble,
    foreground: foreground ?? this.foreground,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    outline: outline ?? this.outline,
    brand: brand ?? this.brand,
    brandSecondary: brandSecondary ?? this.brandSecondary,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
    warningBackground: warningBackground ?? this.warningBackground,
    warningOutline: warningOutline ?? this.warningOutline,
    agentAccent: agentAccent ?? this.agentAccent,
    success: success ?? this.success,
    userBubbleRadius: userBubbleRadius ?? this.userBubbleRadius,
    assistantBubbleRadius: assistantBubbleRadius ?? this.assistantBubbleRadius,
  );

  @override
  TickflowChatTheme lerp(TickflowChatTheme? other, double t) {
    if (other == null) return this;
    return TickflowChatTheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      onUserBubble: Color.lerp(onUserBubble, other.onUserBubble, t)!,
      assistantBubble: Color.lerp(assistantBubble, other.assistantBubble, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandSecondary: Color.lerp(brandSecondary, other.brandSecondary, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      warningOutline: Color.lerp(warningOutline, other.warningOutline, t)!,
      agentAccent: Color.lerp(agentAccent, other.agentAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      userBubbleRadius: BorderRadius.lerp(
        userBubbleRadius,
        other.userBubbleRadius,
        t,
      )!,
      assistantBubbleRadius: BorderRadius.lerp(
        assistantBubbleRadius,
        other.assistantBubbleRadius,
        t,
      )!,
    );
  }
}
