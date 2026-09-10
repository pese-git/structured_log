import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_entry_tile.dart';
import 'log_level_colors.dart';

/// Keys that identify an [Map] log entry's own bookkeeping fields rather
/// than caller-supplied context — excluded from [LogEntryDetailSheet]'s
/// context listing since they're already shown in its header.
const _bookkeepingKeys = {'event', 'level', 'timestamp'};

/// The expanded, detailed view of one log entry, shown as a modal bottom
/// sheet by [MaterialLogViewerPage] when its [LogEntryTile] is tapped.
///
/// Shows every context key of [entry] (everything except `event`, `level`,
/// and `timestamp`, which are already rendered in the header above) as a
/// key/value pair, plus a button that copies that context to the clipboard
/// as plain text.
class LogEntryDetailSheet extends StatelessWidget {
  const LogEntryDetailSheet({required this.entry, super.key});

  /// The log entry being displayed in full.
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = logLevelOf(entry);
    final levelColor = level != null
        ? logLevelColor(level, theme.brightness)
        : theme.colorScheme.onSurfaceVariant;
    final event = entry['event']?.toString() ?? '';
    final time = formatEntryTime(entry['timestamp']);
    final contextEntries = entry.entries
        .where((e) => !_bookkeepingKeys.contains(e.key))
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: levelColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  level?.name.toUpperCase() ?? '',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: levelColor,
                    fontWeight: FontWeight.bold,
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
            const SizedBox(height: 6),
            Text(event, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text(
              'CONTEXT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            for (final field in contextEntries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.key,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '${field.value}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _copyContext(context, contextEntries),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy context'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyContext(
    BuildContext context,
    List<MapEntry<String, dynamic>> contextEntries,
  ) {
    final text = contextEntries.map((e) => '${e.key}: ${e.value}').join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }
}
