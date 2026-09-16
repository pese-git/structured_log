import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// How a button is filled — the canvas uses exactly three treatments.
enum AdminButtonVariant {
  /// Filled with the accent: the one primary action on a screen.
  accent,

  /// Outlined, on a surface: secondary actions.
  standard,

  /// Filled with the error colour, for the confirming half of a destructive
  /// dialog. Never used outside one in the artboards.
  danger,
}

/// How tall a button is. The canvas sizes by context rather than on one
/// scale, and the three heights are consistent across the artboards.
enum AdminButtonSize {
  /// 28 — inside a card or a list row, where a full-height button crowds.
  tonal,

  /// 30 — a screen toolbar.
  toolbar,

  /// 32, with a larger face — a dialog's footer.
  dialog,
}

/// A button in the admin client's vocabulary.
///
/// Wraps `fluent_ui`'s [Button] rather than re-implementing one — the pressed,
/// hovered, focused and disabled behaviour all come from Fluent; only the
/// metrics and colours the canvas pins down are overridden here.
class AdminButton extends StatelessWidget {
  final String label;

  /// Leading glyph, drawn at the label's size with [AdminSpacing.x6] between
  /// them, as in the artboards.
  final IconData? icon;

  /// `null` disables the button — the same convention `fluent_ui` uses.
  final VoidCallback? onPressed;

  final AdminButtonVariant variant;
  final AdminButtonSize size;

  const AdminButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AdminButtonVariant.standard,
    this.size = AdminButtonSize.toolbar,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final isFilled = variant != AdminButtonVariant.standard;
    final fill =
        variant == AdminButtonVariant.danger ? colors.errorFg : colors.accent;
    final fillPressed = variant == AdminButtonVariant.danger
        ? colors.errorFg
        : colors.accentDark;
    final (height, textStyle, padding) = switch (size) {
      AdminButtonSize.tonal => (
          AdminSizes.tonalButtonHeight,
          AdminTypography.bodySmall,
          AdminSpacing.x12,
        ),
      AdminButtonSize.toolbar => (
          AdminSizes.buttonHeight,
          AdminTypography.bodySmall,
          AdminSpacing.x12,
        ),
      AdminButtonSize.dialog => (
          AdminSizes.dialogButtonHeight,
          AdminTypography.body,
          16.0,
        ),
    };

    return SizedBox(
      height: height,
      child: Button(
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.isDisabled) {
              return isFilled ? colors.borderStrong : colors.cardBg;
            }
            if (isFilled) {
              return states.isPressed || states.isHovered ? fillPressed : fill;
            }
            return states.isPressed || states.isHovered
                ? colors.cardBg
                : colors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.isDisabled) return colors.textTertiary;
            return isFilled ? colors.surface : colors.text;
          }),
          padding: WidgetStateProperty.all(
            EdgeInsets.symmetric(horizontal: padding),
          ),
          shape: WidgetStateProperty.resolveWith((states) {
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminRadius.control),
              // A filled button carries no outline in any artboard; the
              // standard one is defined by its own.
              side: isFilled
                  ? BorderSide.none
                  : BorderSide(color: colors.borderStrong),
            );
          }),
          textStyle: WidgetStateProperty.all(textStyle),
        ),
        child: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14),
                  const SizedBox(width: AdminSpacing.x6),
                  Text(label),
                ],
              ),
      ),
    );
  }
}
