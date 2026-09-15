import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The three-letter level marker that opens every row in the log feed.
///
/// Fixed width so a column of badges aligns down the list regardless of which
/// levels are present — `LogBrowser.dc.html` sets `width:34px` for exactly
/// that reason.
class AdminLogLevelBadge extends StatelessWidget {
  final AdminLogLevel level;

  const AdminLogLevelBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final brightness = FluentTheme.of(context).brightness;
    return Container(
      width: AdminSizes.levelBadgeWidth,
      padding: const EdgeInsets.symmetric(vertical: AdminSpacing.x2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AdminLogLevelColors.background(level, brightness),
        borderRadius: BorderRadius.circular(AdminRadius.control),
      ),
      child: Text(
        AdminLogLevelColors.abbreviation(level),
        style: AdminTypography.badge.copyWith(
          color: AdminLogLevelColors.foreground(level, brightness),
        ),
      ),
    );
  }
}
