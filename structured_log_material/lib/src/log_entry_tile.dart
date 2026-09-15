import 'package:flutter/material.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

/// A single row in [MaterialLogViewerPage]'s list: a colored dot for the
/// entry's level, its `event` text, a formatted timestamp, and — if the
/// entry has a `category` context key — a category tag underneath.
///
/// Tapping the tile calls [onTap]; [MaterialLogViewerPage] uses that to
/// open a [LogEntryDetailSheet] for this [entry] on narrow screens, or (on
/// wide screens, where [MaterialLogViewer] shows a master-detail split
/// instead) to select it as the one shown in a [LogEntryDetailPanel]
/// alongside the list — in that case [selected] highlights this tile while
/// its entry is the one currently shown.
class LogEntryTile extends StatelessWidget {
  const LogEntryTile({
    required this.entry,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  /// The raw log entry this tile renders, in the `Map<String, dynamic>`
  /// shape structured_log produces (`event`, `level`, `timestamp`, and any
  /// context keys).
  final Map<String, dynamic> entry;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// Whether this entry is the one currently shown in an adjacent
  /// [LogEntryDetailPanel] (the master-detail split on wide screens) —
  /// tinted to indicate that. Not meaningful (left `false`) in the
  /// narrow/bottom-sheet case, where nothing is showing alongside the list
  /// for a highlight to refer to.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = logLevelOf(entry);
    final dotColor = level != null
        ? logLevelColor(level, theme.brightness)
        : theme.colorScheme.onSurfaceVariant;
    final event = entry['event']?.toString() ?? '';
    final time = formatEntryTime(entry['timestamp']);
    final category = entry['category'];

    return Container(
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      event,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (category is String) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
