import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// A project's usage against one of its limits.
///
/// Usage and limit are shown as a single quantity — "842 / 1 000" — rather
/// than as two facts side by side, which is how the project screen states it
/// and what makes the number answer "how close am I?" at a glance.
///
/// The caller formats both sides: bytes want "128 МБ", entries want a grouped
/// integer, and neither rule belongs to a widget that cannot know the unit.
class AdminQuotaBar extends StatelessWidget {
  /// e.g. `Записей (max_entries)`.
  final String label;

  /// Already formatted, e.g. `842`.
  final String usageLabel;

  /// Already formatted, e.g. `1 000`. `null` means the quota is unset — the
  /// track is then dropped rather than drawn full or empty, since neither
  /// would be true.
  final String? limitLabel;

  /// 0..1, used only for the track. Ignored when [limitLabel] is `null`.
  final double? fraction;

  const AdminQuotaBar({
    super.key,
    required this.label,
    required this.usageLabel,
    this.limitLabel,
    this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final unlimited = limitLabel == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AdminTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Text(
              unlimited ? usageLabel : '$usageLabel / $limitLabel',
              style: AdminTypography.caption.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x8),
        if (!unlimited)
          ClipRRect(
            borderRadius: BorderRadius.circular(AdminRadius.rail),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  ColoredBox(
                    color: colors.border,
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: (fraction ?? 0).clamp(0.0, 1.0),
                    child: ColoredBox(color: colors.accent),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
