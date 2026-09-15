import 'package:flutter/cupertino.dart';

/// The state [CupertinoLogViewer] shows in place of the list when there is
/// nothing to display, distinguishing two cases:
///
/// - [hasLogs] is `false`: the underlying log buffer has never captured
///   anything — shown as "no logs yet", with no filter-reset action (there
///   is no filter to blame).
/// - [hasLogs] is `true`: the buffer has entries, but none of them satisfy
///   the current search/level/category filter — shown as "no matches",
///   with a button (wired to [onClearFilters]) to reset every filter.
class LogViewerEmptyState extends StatelessWidget {
  const LogViewerEmptyState({
    required this.hasLogs,
    required this.onClearFilters,
    super.key,
  });

  /// Whether the underlying buffer holds at least one entry (even though
  /// none of them are currently visible).
  final bool hasLogs;

  /// Called when the "Clear filters" action is activated. Only shown when
  /// [hasLogs] is `true`.
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(
      context,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6.resolveFrom(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasLogs ? CupertinoIcons.search : CupertinoIcons.doc_plaintext,
                size: 30,
                color: secondaryLabel,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasLogs ? 'No logs match the current filter' : 'No logs yet',
              style: CupertinoTheme.of(
                context,
              ).textTheme.navTitleTextStyle.copyWith(fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasLogs
                  ? 'Try a different search term, or clear the active '
                      'filters to see everything.'
                  : 'Logs will appear here as soon as your app emits its '
                      'first event.',
              style: TextStyle(color: secondaryLabel, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (hasLogs) ...[
              const SizedBox(height: 12),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onClearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
