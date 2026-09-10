import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_level_colors.dart';

/// A single row in [FluentLogViewerPage]'s master list: a level badge, the
/// entry's `event` text, a formatted timestamp, and — if the entry has a
/// `category` context key — a category tag underneath.
///
/// Selecting the tile calls [onTap]; [FluentLogViewerPage] uses that to
/// show this [entry] in its detail pane. [selected] highlights the row
/// (accent-colored left border and tint) while its entry is the one shown
/// in the detail pane — the master-detail split view's selection state.
class LogEntryTile extends StatelessWidget {
  const LogEntryTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The raw log entry this tile renders, in the `Map<String, dynamic>`
  /// shape structured_log produces (`event`, `level`, `timestamp`, and any
  /// context keys).
  final Map<String, dynamic> entry;

  /// Whether this entry is the one currently shown in the detail pane.
  final bool selected;

  /// Called when the tile is selected.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final level = logLevelOf(entry);
    final badgeColor = level != null
        ? logLevelColor(level, theme.brightness)
        : theme.resources.textFillColorSecondary;
    final event = entry['event']?.toString() ?? '';
    final time = formatEntryTime(entry['timestamp']);
    final category = entry['category'];

    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return Container(
          decoration: BoxDecoration(
            color: selected
                ? theme.accentColor.withValues(alpha: 0.12)
                : hovered
                    ? theme.resources.subtleFillColorSecondary
                    : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? theme.accentColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LevelBadge(
                    text: level != null ? logLevelAbbreviation(level) : '',
                    color: badgeColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      event,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ),
              if (category is String) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.resources.controlFillColorDefault,
                      border: Border.all(
                        color: theme.resources.controlStrokeColorDefault,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      category,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: FluentTheme.of(context).typography.caption?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

/// Formats a log entry's `timestamp` value (an ISO-8601 string, as produced
/// by `structured_log`) as a local `HH:mm:ss` time. Returns the raw value's
/// string form unchanged if it isn't a parseable timestamp.
String formatEntryTime(Object? raw) {
  if (raw is! String) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
