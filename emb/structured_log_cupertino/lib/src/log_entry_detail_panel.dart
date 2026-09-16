import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_entry_tile.dart';

/// Keys that identify a log entry's own bookkeeping fields rather than
/// caller-supplied context — excluded from [LogEntryDetailPanel]'s context
/// listing since they're already shown in its header.
const _bookkeepingKeys = {'event', 'level', 'timestamp'};

/// The expanded, detailed view of one log entry: every context key of
/// [entry] (everything except `event`, `level`, and `timestamp`, already
/// rendered in the header above) as a key/value pair, plus a button that
/// copies that context to the clipboard as plain text.
///
/// A plain, non-modal widget — no navigation bar or dismiss affordance of
/// its own — meant to fill whatever space it's given: pushed as its own
/// screen (inside a `CupertinoPageScaffold`) on narrow screens, or shown
/// alongside the list in [CupertinoLogViewer]'s master-detail split on wide
/// ones.
class LogEntryDetailPanel extends StatelessWidget {
  const LogEntryDetailPanel({required this.entry, super.key});

  /// The log entry being displayed in full.
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final resolvedBrightness = CupertinoTheme.brightnessOf(context);
    final level = logLevelOf(entry);
    final levelColor = level != null
        ? logLevelColor(level, resolvedBrightness)
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    final event = entry['event']?.toString() ?? '';
    final time = formatEntryTime(entry['timestamp']);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(
      context,
    );
    final contextEntries = entry.entries
        .where((e) => !_bookkeepingKeys.contains(e.key))
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                            style: theme.textTheme.tabLabelTextStyle.copyWith(
                              color: levelColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: theme.textTheme.tabLabelTextStyle
                                .copyWith(color: secondaryLabel),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event,
                        style: theme.textTheme.navTitleTextStyle,
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  color: CupertinoColors.systemGrey5.resolveFrom(context),
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => _copyContext(contextEntries),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.doc_on_doc,
                        size: 14,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Copy',
                        style: TextStyle(
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            const SizedBox(height: 16),
            Text(
              'CONTEXT',
              style: theme.textTheme.tabLabelTextStyle.copyWith(
                color: secondaryLabel,
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
                              style: theme.textTheme.textStyle.copyWith(
                                color: secondaryLabel,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${field.value}',
                              style: theme.textTheme.textStyle,
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
      ),
    );
  }

  Future<void> _copyContext(List<MapEntry<String, dynamic>> contextEntries) {
    final text = contextEntries.map((e) => '${e.key}: ${e.value}').join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }
}
