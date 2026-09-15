import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// "There is nothing here yet" — centred in the pane that would have held the
/// list.
///
/// The artboards distinguish two of these and so does every screen that uses
/// one: a collection that is genuinely empty, and a filter that matched
/// nothing. That distinction is the caller's to make; this atom only draws
/// whichever wording it is handed.
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  /// One line saying what would fill this space, or how to get there.
  final String? description;

  /// The action that would resolve the emptiness, when there is one.
  final Widget? action;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 64,
          horizontal: AdminSpacing.x24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.cardBg,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(AdminRadius.card),
              ),
              child: Icon(icon, size: 24, color: colors.textSecondary),
            ),
            const SizedBox(height: AdminSpacing.x14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AdminTypography.subtitle.copyWith(color: colors.text),
            ),
            if (description != null) ...[
              const SizedBox(height: AdminSpacing.x4),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AdminTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AdminSpacing.x14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
