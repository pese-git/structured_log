import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// One control in a filter bar: "Категория: payments", "Warning and above".
///
/// The canvas draws these as its `.box` — the same outlined 32-high shape as a
/// filter input, not as a rounded pill. A chip that opens a picker carries a
/// chevron; one that is already narrowing the query carries a clear button.
class AdminFilterChip extends StatelessWidget {
  /// The dimension being filtered, e.g. `Категория`. Omitted for a chip whose
  /// value speaks for itself.
  final String? label;

  final String value;

  /// Draws the chip in the accent tint, for a filter that is actually applied
  /// rather than offered.
  final bool selected;

  /// Shows the chevron that says tapping opens a picker.
  final bool hasMenu;

  final VoidCallback? onPressed;

  /// When given, the chip carries a clear button that removes this filter.
  final VoidCallback? onCleared;

  const AdminFilterChip({
    super.key,
    required this.value,
    this.label,
    this.selected = false,
    this.hasMenu = false,
    this.onPressed,
    this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final text = label == null ? value : '$label: $value';

    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) {
        final background = selected
            ? colors.accentTint
            : (states.isHovered ? colors.cardBg : colors.surface);
        return Container(
          height: AdminSizes.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x10),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: selected ? colors.accent : colors.borderStrong,
            ),
            borderRadius: BorderRadius.circular(AdminRadius.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: AdminTypography.bodySmall.copyWith(
                  color: selected ? colors.accentDark : colors.text,
                ),
              ),
              if (hasMenu) ...[
                const SizedBox(width: AdminSpacing.x6),
                Icon(
                  FluentIcons.chevron_down,
                  size: 10,
                  color: colors.textSecondary,
                ),
              ],
              if (onCleared != null) ...[
                const SizedBox(width: AdminSpacing.x6),
                IconButton(
                  icon: const Icon(FluentIcons.clear, size: 9),
                  onPressed: onCleared,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
