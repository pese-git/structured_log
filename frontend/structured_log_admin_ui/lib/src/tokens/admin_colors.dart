import 'package:flutter/widgets.dart';

/// The palette every component in this package draws from.
///
/// Values are transcribed from the "Structured Log Admin UI" design canvas,
/// where all 26 artboards share one `:root` block (`--fl-*`). The names here
/// keep that vocabulary so a colour can be traced back to the mockup it came
/// from without a lookup table.
///
/// The canvas is light-only — it has no dark artboards — so [dark] is not
/// transcribed but derived: the same roles, re-tuned for a dark surface. Any
/// future dark mockup wins over what is here.
@immutable
class AdminColors {
  /// Primary accent — Fluent's default blue, used for the active nav rail,
  /// accent buttons, focus and the quota fill.
  final Color accent;

  /// Pressed/heavier accent, and accent-coloured text on a tinted ground.
  final Color accentDark;

  /// The wash behind an active nav item or a selected list row.
  final Color accentTint;

  /// The window ground the app shell sits on.
  final Color pageBg;

  /// Cards and secondary strips — a half-step off [surface].
  final Color cardBg;

  /// Content surfaces: panes, dialogs, inputs.
  final Color surface;

  /// Hairline separators between regions.
  final Color border;

  /// The visible outline of an interactive control.
  final Color borderStrong;

  /// Primary text.
  final Color text;

  /// Supporting text — captions, secondary rows, inactive nav items.
  final Color textSecondary;

  /// The quietest text: section headers in the nav, metadata.
  final Color textTertiary;

  final Color errorFg;
  final Color errorBg;
  final Color successFg;
  final Color successBg;
  final Color warnFg;
  final Color warnBg;

  /// The live-feed pill while the subscription is following.
  ///
  /// Its own green, not [successFg]/[successBg]: `LogBrowser.dc.html` states
  /// these inline rather than through the shared `:root` block, and they are
  /// a step brighter than the status green the rest of the canvas uses.
  /// Transcribed as drawn — "live" and "active" are not the same claim, and
  /// flattening them here would decide that for the canvas.
  final Color liveFg;
  final Color liveBg;

  const AdminColors({
    required this.accent,
    required this.accentDark,
    required this.accentTint,
    required this.pageBg,
    required this.cardBg,
    required this.surface,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.errorFg,
    required this.errorBg,
    required this.successFg,
    required this.successBg,
    required this.warnFg,
    required this.warnBg,
    required this.liveFg,
    required this.liveBg,
  });

  /// Transcribed verbatim from the canvas `:root` block.
  static const light = AdminColors(
    accent: Color(0xFF0078D4),
    accentDark: Color(0xFF0066B4),
    accentTint: Color(0xFFE0EFFA),
    pageBg: Color(0xFFF3F3F3),
    cardBg: Color(0xFFFBFBFB),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE5E5E5),
    borderStrong: Color(0xFFC7C6C4),
    text: Color(0xFF1B1B1B),
    textSecondary: Color(0xFF5C5C5C),
    textTertiary: Color(0xFF8A8886),
    errorFg: Color(0xFFC42B1C),
    errorBg: Color(0xFFFDE7E9),
    successFg: Color(0xFF0F7B0F),
    successBg: Color(0xFFDFF6DD),
    warnFg: Color(0xFF9D5D00),
    warnBg: Color(0xFFFFF4CE),
    liveFg: Color(0xFF16A34A),
    liveBg: Color(0xFFDAF0E2),
  );

  /// Derived, not transcribed — see the class doc. Each role keeps its light
  /// counterpart's hue and swaps figure for ground, so a component reads the
  /// same way in either theme without a second set of rules.
  static const dark = AdminColors(
    accent: Color(0xFF4CA0E0),
    accentDark: Color(0xFF6FB6EA),
    accentTint: Color(0xFF12293C),
    pageBg: Color(0xFF1B1B1B),
    cardBg: Color(0xFF242424),
    surface: Color(0xFF2B2B2B),
    border: Color(0xFF3A3A3A),
    borderStrong: Color(0xFF565656),
    text: Color(0xFFF2F2F2),
    textSecondary: Color(0xFFBDBDBD),
    textTertiary: Color(0xFF969696),
    errorFg: Color(0xFFFF99A4),
    errorBg: Color(0xFF442726),
    successFg: Color(0xFF6CCB70),
    successBg: Color(0xFF223A22),
    warnFg: Color(0xFFFCE100),
    warnBg: Color(0xFF433519),
    liveFg: Color(0xFF5CD68A),
    liveBg: Color(0xFF18331F),
  );

  static AdminColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
