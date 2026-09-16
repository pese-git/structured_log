import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// A labelled input, as the forms in the canvas draw them: caption above, box
/// below, and room on the caption's line for a link like "Забыли пароль?".
class AdminTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? placeholder;

  /// Sits at the end of the label's line — the artboards put a link there.
  final Widget? labelAction;

  /// Masks input, for a password.
  final bool obscure;

  /// `false` greys the field out while a request is in flight.
  final bool enabled;

  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Fired by the keyboard's confirm action, so a form can be sent without
  /// reaching for the mouse.
  final VoidCallback? onSubmitted;

  /// Shown under the field in the error colour. A field carrying one also
  /// draws its outline in that colour.
  final String? errorText;

  const AdminTextField({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder,
    this.labelAction,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: AdminTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (labelAction != null) labelAction!,
          ],
        ),
        const SizedBox(height: AdminSpacing.x6),
        TextBox(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscure,
          enabled: enabled,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          style: AdminTypography.body.copyWith(
            color: enabled ? colors.text : colors.textTertiary,
          ),
          placeholderStyle: AdminTypography.body.copyWith(
            color: colors.textTertiary,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AdminSpacing.x10,
            vertical: AdminSpacing.x8,
          ),
          decoration: WidgetStateProperty.all(
            BoxDecoration(
              color: enabled ? colors.surface : colors.cardBg,
              border: Border.all(
                color: hasError ? colors.errorFg : colors.borderStrong,
              ),
              borderRadius: BorderRadius.circular(AdminRadius.control),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AdminSpacing.x4),
          Text(
            errorText!,
            style: AdminTypography.caption.copyWith(color: colors.errorFg),
          ),
        ],
      ],
    );
  }
}
