import 'package:flutter/widgets.dart';

/// The type scale, transcribed from the canvas.
///
/// Styles carry no colour: a component picks one from [AdminColors] for the
/// role it is painting, so the same style can be primary text in one place and
/// secondary in another without a second style for each colour.
abstract final class AdminTypography {
  /// The canvas sets `'Segoe UI', -apple-system, 'SF Pro Text', system-ui`.
  /// Naming Segoe UI as the family and the rest as fallbacks reproduces that
  /// on Windows and degrades to the platform UI face elsewhere, which is what
  /// the CSS list does.
  static const fontFamily = 'Segoe UI';
  static const fontFamilyFallback = <String>[
    '.SF Pro Text',
    'SF Pro Text',
    'Roboto',
  ];

  /// For values that must line up or be read character by character: ids,
  /// secret keys, timestamps, `context` payloads.
  static const monoFontFamily = 'Cascadia Code';
  static const monoFontFamilyFallback = <String>[
    'Consolas',
    'Menlo',
    'monospace',
  ];

  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 28,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  /// The heading of an empty state — between [sectionTitle] and [label].
  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  /// Card headings, field labels, the active nav item.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
  );

  /// Controls: button faces, filter boxes, list rows.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
  );

  /// Metadata, nav section headers, quota counters.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
  );

  /// The live-status pill.
  static const TextStyle captionStrong = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  /// The level badge: small, heavy and letter-spaced so three capitals stay
  /// legible at 11px.
  static const TextStyle badge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFamilyFallback,
    fontSize: 13,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFamilyFallback,
    fontSize: 12,
  );
}
