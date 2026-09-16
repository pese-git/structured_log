import 'package:fluent_ui/fluent_ui.dart';

import 'admin_colors.dart';
import 'admin_typography.dart';

/// The `FluentThemeData` the admin client hands to `FluentApp`.
///
/// Exported as a preset rather than applied inside each component so the whole
/// application — including the `fluent_ui` widgets this package does not wrap —
/// inherits the canvas palette from one place.
///
/// The canvas accent (`#0078D4`, with `#0066B4` pressed and `#005494` deeper)
/// is Fluent's own blue swatch value for value, so [Colors.blue] is used
/// directly: re-declaring the same seven shades by hand would only create
/// something to drift.
abstract final class AdminTheme {
  static FluentThemeData light() => _build(Brightness.light);

  static FluentThemeData dark() => _build(Brightness.dark);

  static FluentThemeData of(Brightness brightness) => _build(brightness);

  static FluentThemeData _build(Brightness brightness) {
    final colors = AdminColors.of(brightness);
    return FluentThemeData(
      brightness: brightness,
      accentColor: Colors.blue,
      fontFamily: AdminTypography.fontFamily,
      scaffoldBackgroundColor: colors.pageBg,
      cardColor: colors.cardBg,
      menuColor: colors.surface,
      dividerTheme: DividerThemeData(
        decoration: BoxDecoration(color: colors.border),
      ),
    );
  }
}
