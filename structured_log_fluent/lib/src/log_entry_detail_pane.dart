import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_entry_tile.dart';
import 'log_level_colors.dart';

/// Keys that identify a log entry's own bookkeeping fields rather than
/// caller-supplied context — excluded from [LogEntryDetailPane]'s context
/// listing since they're already shown in its header.
const _bookkeepingKeys = {'event', 'level', 'timestamp'};

/// The detail side of [FluentLogViewerPage]'s master-detail split view:
/// shows the selected entry's full context (everything except `event`,
/// `level`, and `timestamp`, already in the header) as key/value pairs,
/// plus a "Copy" action that copies that context to the clipboard as plain
/// text.
///
/// Unlike `structured_log_material`'s modal bottom sheet, this renders
/// alongside the list rather than covering it — the master-detail pattern
/// WinUI apps use (Mail, Settings) instead of a mobile-style sheet.
class LogEntryDetailPane extends StatelessWidget {
  const LogEntryDetailPane({required this.entry, super.key});

  /// The log entry being displayed in full.
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final level = logLevelOf(entry);
    final levelColor = level != null
        ? logLevelColor(level, theme.brightness)
        : theme.resources.textFillColorSecondary;
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
                        Text(
                          level != null ? logLevelAbbreviation(level) : '',
                          style: theme.typography.caption?.copyWith(
                            color: levelColor,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
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
                    const SizedBox(height: 8),
                    Text(event, style: theme.typography.subtitle),
                  ],
                ),
              ),
              Button(
                onPressed: () => _copyContext(contextEntries),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.copy, size: 14),
                    const SizedBox(width: 6),
                    const Text('Copy'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          Text(
            'CONTEXT',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final field in contextEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            field.key,
                            style: theme.typography.body?.copyWith(
                              color: theme.resources.textFillColorSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${field.value}',
                            style: theme.typography.body,
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

  Future<void> _copyContext(List<MapEntry<String, dynamic>> contextEntries) {
    final text = contextEntries.map((e) => '${e.key}: ${e.value}').join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }
}
