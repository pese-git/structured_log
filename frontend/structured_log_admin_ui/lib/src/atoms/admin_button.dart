import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// Which of the canvas's three button treatments to paint.
enum AdminButtonVariant {
  /// Filled with the accent — the one primary action on a screen.
  accent,

  /// Outlined, on a surface: the toolbar's secondary actions.
  standard,

  /// The same outline two pixels shorter, as the artboards use inside cards
  /// and list rows where a full-height button would crowd the row.
  tonal,
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

  const AdminButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AdminButtonVariant.standard,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final isAccent = variant == AdminButtonVariant.accent;
    final height = variant == AdminButtonVariant.tonal
        ? AdminSizes.tonalButtonHeight
        : AdminSizes.buttonHeight;

    return SizedBox(
      height: height,
      child: Button(
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.isDisabled) {
              return isAccent ? colors.borderStrong : colors.cardBg;
            }
            if (isAccent) {
              return states.isPressed || states.isHovered
                  ? colors.accentDark
                  : colors.accent;
            }
            return states.isPressed || states.isHovered
                ? colors.cardBg
                : colors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.isDisabled) return colors.textTertiary;
            return isAccent ? colors.surface : colors.text;
          }),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: AdminSpacing.x12),
          ),
          shape: WidgetStateProperty.resolveWith((states) {
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminRadius.control),
              // The accent button carries no outline in any artboard; the
              // other two are defined by theirs.
              side: isAccent
                  ? BorderSide.none
                  : BorderSide(color: colors.borderStrong),
            );
          }),
          textStyle: WidgetStateProperty.all(AdminTypography.bodySmall),
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
