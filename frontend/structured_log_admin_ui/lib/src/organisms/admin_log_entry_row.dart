import 'package:fluent_ui/fluent_ui.dart';

import '../atoms/atoms.dart';
import '../tokens/tokens.dart';

/// One line in the log feed: level, time, event, and the category it came
/// from.
///
/// Takes primitives rather than an entry object — `time` arrives already
/// formatted, because how much of a timestamp to show depends on the range on
/// screen, and that is the screen's decision (design.md decision 39).
class AdminLogEntryRow extends StatelessWidget {
  final AdminLogLevel level;

  /// Already formatted, e.g. `09:12:55`.
  final String time;

  final String event;

  /// Omitted when the entry carried none; the canvas simply leaves the chip
  /// out rather than showing an empty one.
  final String? category;

  /// Highlights the row whose entry the detail pane is showing.
  final bool selected;

  final VoidCallback? onPressed;

  const AdminLogEntryRow({
    super.key,
    required this.level,
    required this.time,
    required this.event,
    this.category,
    this.selected = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) {
        final background = selected
            ? colors.accentTint
            : (states.isHovered ? colors.cardBg : Colors.transparent);
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AdminSpacing.x12,
            vertical: AdminSpacing.x8,
          ),
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminLogLevelBadge(level: level),
              const SizedBox(width: AdminSpacing.x10),
              // Monospaced and fixed-width so a column of timestamps lines up
              // and the events beside them start at the same place.
              Text(
                time,
                style: AdminTypography.monoSmall.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: AdminSpacing.x10),
              Expanded(
                child: Text(
                  event,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTypography.bodySmall.copyWith(color: colors.text),
                ),
              ),
              if (category != null) ...[
                const SizedBox(width: AdminSpacing.x8),
                AdminTag(label: category!),
              ],
            ],
          ),
        );
      },
    );
  }
}
