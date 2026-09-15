import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// What a status tag is saying.
enum AdminStatusTone {
  /// Nothing is wrong and nothing is notable — the default state of a row.
  neutral,

  /// Active, verified, healthy.
  success,

  /// Needs attention but still works: a quota nearly spent, a temporary
  /// password.
  warning,

  /// Blocked, deleted, failed.
  error,
}

/// The state of an account or a resource, as a filled tag.
///
/// The canvas draws the blocked case as its `.tag` recoloured to the error
/// pair with the outline dropped — a filled marker rather than the outlined
/// [AdminTag] used for neutral labels. The other tones follow the same rule
/// against their own pair, which is what keeps "Заблокирован" and "Активен"
/// reading as the same kind of statement.
class AdminStatusTag extends StatelessWidget {
  final String label;
  final AdminStatusTone tone;

  const AdminStatusTag({
    super.key,
    required this.label,
    this.tone = AdminStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final (background, foreground) = switch (tone) {
      AdminStatusTone.neutral => (colors.cardBg, colors.textSecondary),
      AdminStatusTone.success => (colors.successBg, colors.successFg),
      AdminStatusTone.warning => (colors.warnBg, colors.warnFg),
      AdminStatusTone.error => (colors.errorBg, colors.errorFg),
    };

    return Container(
      height: AdminSizes.badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AdminRadius.control),
      ),
      child: Text(
        label,
        style: AdminTypography.caption.copyWith(color: foreground),
      ),
    );
  }
}
