import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// A switch with its caption and, optionally, a line explaining what it
/// changes.
///
/// **Not in the canvas** — no artboard draws a toggle. It is here because
/// 23.5 calls for one and the settings screens will need it; the treatment
/// follows the neighbouring form rows (14px caption, 12px secondary
/// description) rather than inventing a shape.
class AdminLabeledToggle extends StatelessWidget {
  final String label;

  /// One line under the label, for the consequence of switching it.
  final String? description;

  final bool value;

  /// `null` renders the switch disabled, matching `fluent_ui`'s convention.
  final ValueChanged<bool>? onChanged;

  const AdminLabeledToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final enabled = onChanged != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AdminTypography.body.copyWith(
                  color: enabled ? colors.text : colors.textTertiary,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: AdminSpacing.x2),
                Text(
                  description!,
                  style: AdminTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AdminSpacing.x12),
        ToggleSwitch(checked: value, onChanged: onChanged),
      ],
    );
  }
}
