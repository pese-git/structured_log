import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart';

/// The single source of truth for [LogLevel] indicator colors across this
/// package's widgets — every place that needs a level color calls this
/// rather than hard-coding its own copy of the palette, so the mapping
/// can't drift between widgets.
///
/// Uses the same hex values as `structured_log_material`'s `logLevelColor`
/// (a deliberate, duplicated copy — see this package's design notes: the
/// palette is small and stable, and extracting it into
/// `structured_log_flutter` was deferred until a third skin needs it too).
/// Each level keeps the same hue between themes, tuned lighter for
/// [Brightness.dark] so it stays legible against a dark background.
Color logLevelColor(LogLevel level, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  switch (level) {
    case LogLevel.trace:
      return isDark ? const Color(0xFFB4C2D6) : const Color(0xFF94A3B8);
    case LogLevel.debug:
      return isDark ? const Color(0xFF22D3EE) : const Color(0xFF06B6D4);
    case LogLevel.info:
      return isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    case LogLevel.warning:
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    case LogLevel.error:
      return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    case LogLevel.critical:
      return isDark ? const Color(0xFFE879F9) : const Color(0xFFC026D3);
  }
}

/// A short, upper-case abbreviation for [level] (`TRC`, `DBG`, `INF`,
/// `WRN`, `ERR`, `CRT`), used in the compact level badge next to each
/// entry — matching the density expected of a desktop list row.
String logLevelAbbreviation(LogLevel level) {
  switch (level) {
    case LogLevel.trace:
      return 'TRC';
    case LogLevel.debug:
      return 'DBG';
    case LogLevel.info:
      return 'INF';
    case LogLevel.warning:
      return 'WRN';
    case LogLevel.error:
      return 'ERR';
    case LogLevel.critical:
      return 'CRT';
  }
}
