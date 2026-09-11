import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_entry_tile.dart';
import 'log_level_colors.dart';

/// Keys that identify a log entry's own bookkeeping fields rather than
/// caller-supplied context — excluded from [LogEntryDetailPanel]'s context
/// listing since they're already shown in its header.
const _bookkeepingKeys = {'event', 'level', 'timestamp'};

/// The detail side of [MaterialLogViewer]'s master-detail split, shown on
/// wide screens alongside the list rather than as a modal.
///
/// Renders the same information as [LogEntryDetailSheet] (the selected
/// entry's full context as key/value pairs, plus a "Copy context" action)
/// but as a plain, non-modal panel meant to fill the space next to the
/// list — no drag handle or "Close" button, since there's nothing to
/// dismiss back to.
class LogEntryDetailPanel extends StatelessWidget {
  const LogEntryDetailPanel({required this.entry, super.key});

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: levelColor,
                            shape: BoxShape.circle,
                          ),
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(event, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _copyContext(context, contextEntries),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy context'),
              ),
            ],
          ),
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
          Expanded(
            child: ListView(
              children: [
                for (final field in contextEntries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            field.key,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${field.value}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
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
