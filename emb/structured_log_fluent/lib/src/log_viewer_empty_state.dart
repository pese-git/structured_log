import 'package:fluent_ui/fluent_ui.dart';

/// The state [FluentLogViewerPage] shows in place of the list when there is
/// nothing to display, distinguishing two cases:
///
/// - [hasLogs] is `false`: the underlying log buffer has never captured
///   anything — shown as "no logs yet", with no filter-reset action (there
///   is no filter to blame).
/// - [hasLogs] is `true`: the buffer has entries, but none of them satisfy
///   the current search/level/category filter — shown as "no matches",
///   with a "Clear filters" action wired to [onClearFilters].
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
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.resources.controlFillColorDefault,
                border: Border.all(
                    color: theme.resources.controlStrokeColorDefault),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                hasLogs ? FluentIcons.search_issue : FluentIcons.news,
                size: 26,
                color: theme.resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasLogs ? 'No results found' : 'No logs yet',
              style: theme.typography.subtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasLogs
                  ? 'No log entries match the current filter.'
                  : 'Logs will appear here as soon as your app emits its '
                      'first event.',
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasLogs) ...[
              const SizedBox(height: 14),
              Button(
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
