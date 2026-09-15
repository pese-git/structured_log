import 'package:flutter/widgets.dart';

import 'admin_colors.dart';

/// The log levels the admin client can display.
///
/// Declared here rather than imported from `structured_log` on purpose: this
/// package depends on nothing but the Flutter SDK and `fluent_ui`
/// (design.md decision 39), and the client maps the API's level strings onto
/// this enum at its own boundary. The order is the server's severity order.
enum AdminLogLevel { trace, debug, info, warning, error, critical }

/// Level colours and their badge treatment.
///
/// The four levels the canvas actually draws (`DBG`/`INF`/`WRN`/`ERR`) are
/// transcribed from it exactly; `trace` and `critical` never appear in a
/// mockup, so they continue the same palette at the ends of the scale.
///
/// This mapping is deliberately this package's own copy rather than an import
/// from `structured_log_flutter` — the admin client shares no code with the
/// embeddable viewer skins (decision 39, the same call `structured_log_fluent`
/// and `structured_log_material` already made between themselves).
abstract final class AdminLogLevelColors {
  /// Foreground: the badge's text, and the level dot in a dense row.
  static Color foreground(AdminLogLevel level, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    switch (level) {
      case AdminLogLevel.trace:
        return isDark ? const Color(0xFFB4C2D6) : const Color(0xFF94A3B8);
      case AdminLogLevel.debug:
        return isDark ? const Color(0xFF22D3EE) : const Color(0xFF06B6D4);
      case AdminLogLevel.info:
        return isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
      case AdminLogLevel.warning:
        return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
      case AdminLogLevel.error:
        return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      case AdminLogLevel.critical:
        return isDark ? const Color(0xFFE879F9) : const Color(0xFFC026D3);
    }
  }

  /// The tint behind the badge.
  ///
  /// Not a second hand-picked table: the canvas's badge grounds are exactly
  /// the foreground laid over the surface at [_tintOpacity], so the rule is
  /// applied here instead of the four literals it produces — which is what
  /// lets `trace` and `critical`, absent from every mockup, come out
  /// consistent with the levels that were drawn. `admin_log_level_test.dart`
  /// pins the result against the canvas hexes.
  static Color background(AdminLogLevel level, Brightness brightness) {
    final colors = AdminColors.of(brightness);
    return Color.alphaBlend(
      foreground(level, brightness).withValues(alpha: _tintOpacity),
      colors.surface,
    );
  }

  static const _tintOpacity = 0.16;

  /// The three-letter badge text — the canvas never spells a level out.
  static String abbreviation(AdminLogLevel level) {
    switch (level) {
      case AdminLogLevel.trace:
        return 'TRC';
      case AdminLogLevel.debug:
        return 'DBG';
      case AdminLogLevel.info:
        return 'INF';
      case AdminLogLevel.warning:
        return 'WRN';
      case AdminLogLevel.error:
        return 'ERR';
      case AdminLogLevel.critical:
        return 'CRT';
    }
  }
}
