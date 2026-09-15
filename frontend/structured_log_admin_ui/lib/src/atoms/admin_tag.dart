import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// A small outlined label: a role beside a group name, a category on a log
/// row, a key's state.
///
/// Read-only by design — the filter chip that can be selected and cleared is a
/// molecule, because it combines this with an interaction.
class AdminTag extends StatelessWidget {
  final String label;

  /// Overrides the text colour only; the outline and ground stay neutral, as
  /// in the artboards where a role tag is accent-coloured text in an otherwise
  /// plain chip.
  final Color? foreground;

  const AdminTag({super.key, required this.label, this.foreground});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Container(
      height: AdminSizes.badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x8),
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border.all(color: colors.borderStrong),
        borderRadius: BorderRadius.circular(AdminRadius.control),
      ),
      // `widthFactor: 1` keeps the tag the width of its label. A Container
      // given `alignment` and no width expands to its constraints instead,
      // which inside a Wrap or a stretched column means a full-width bar.
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: AdminTypography.caption.copyWith(
            color: foreground ?? colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
