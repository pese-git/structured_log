import 'package:flutter/cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

/// A single row in [CupertinoLogViewerPage]'s list: a colored dot for the
/// entry's level, its `event` text, a formatted timestamp, and — if the
/// entry has a `category` context key — a category tag underneath.
///
/// Tapping the tile calls [onTap]; [CupertinoLogViewer] uses that to either
/// push a [LogEntryDetailPanel] as a new screen (narrow screens, showing
/// [showsDisclosureIndicator]'s trailing chevron — the standard iOS
/// "drills into a detail screen" affordance) or select it as the one shown
/// in a non-modal [LogEntryDetailPanel] alongside the list (wide screens,
/// where [selected] highlights this tile instead).
class LogEntryTile extends StatelessWidget {
  const LogEntryTile({
    required this.entry,
    required this.onTap,
    this.selected = false,
    this.showsDisclosureIndicator = true,
    super.key,
  });

  /// The raw log entry this tile renders, in the `Map<String, dynamic>`
  /// shape structured_log produces (`event`, `level`, `timestamp`, and any
  /// context keys).
  final Map<String, dynamic> entry;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// Whether this entry is the one currently shown in an adjacent
  /// (non-modal) detail panel — the master-detail split on wide screens.
  /// Tinted to indicate that; meaningless (left `false`) when
  /// [showsDisclosureIndicator] is `true`, since tapping there navigates
  /// away rather than updating something shown alongside the list.
  final bool selected;

  /// Whether to show a trailing chevron, iOS's standard affordance for "tap
  /// to drill into a detail screen" — set by [CupertinoLogViewer] to match
  /// whether tapping actually does that (narrow screens) or just updates
  /// the adjacent panel in place (wide screens, where it's turned off).
  final bool showsDisclosureIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final resolvedBrightness = CupertinoTheme.brightnessOf(context);
    final level = logLevelOf(entry);
    final dotColor = level != null
        ? logLevelColor(level, resolvedBrightness)
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    final event = entry['event']?.toString() ?? '';
    final time = formatEntryTime(entry['timestamp']);
    final category = entry['category'];

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        color:
            selected ? CupertinoColors.systemGrey5.resolveFrom(context) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
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
                          style: theme.textTheme.textStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: theme.textTheme.tabLabelTextStyle.copyWith(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
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
                          color: CupertinoColors.systemGrey6.resolveFrom(
                            context,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category,
                          style: theme.textTheme.tabLabelTextStyle.copyWith(
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showsDisclosureIndicator) ...[
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ],
          ],
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
