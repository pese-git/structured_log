import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// Whether the feed behind the pill is running or held.
enum AdminLiveTone {
  /// Following the newest entries.
  live,

  /// Explicitly paused by the reader. Entries keep arriving; the list is
  /// frozen.
  paused,
}

/// The dot-and-label pill that says whether a feed is live.
///
/// Sits at the end of the filter row in `LogBrowser.dc.html`, next to the
/// button that toggles it. Reports state only — the pill is not the control,
/// which is why it takes no callback.
class AdminLivePill extends StatelessWidget {
  final String label;
  final AdminLiveTone tone;

  const AdminLivePill({
    super.key,
    required this.label,
    this.tone = AdminLiveTone.live,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final (background, foreground) = switch (tone) {
      AdminLiveTone.live => (colors.liveBg, colors.liveFg),
      AdminLiveTone.paused => (colors.warnBg, colors.warnFg),
    };

    return Container(
      height: AdminSizes.pillHeight,
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AdminRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminLiveDot(color: foreground),
          const SizedBox(width: AdminSpacing.x7),
          Text(
            label,
            style: AdminTypography.captionStrong.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// The 7px dot the canvas puts before a live label — in the pill, and again
/// in the strip under the feed.
class AdminLiveDot extends StatelessWidget {
  final Color color;

  const AdminLiveDot({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AdminSpacing.x7,
      height: AdminSpacing.x7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
