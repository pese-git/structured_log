import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';

/// The single source of truth for [LogLevel] indicator colors across this
/// package's widgets (the list row's dot, the detail sheet's level chip,
/// ...) — every place that needs a level color calls this rather than
/// hard-coding its own copy of the palette, so the mapping can't drift
/// between widgets.
///
/// Chosen to read clearly on both light and dark Material surfaces: each
/// level keeps the same hue between themes, tuned lighter for [Brightness.dark]
/// so it stays legible against a dark background.
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
