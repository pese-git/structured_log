import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

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
    this.labels = const LogViewerLabels(),
    super.key,
  });

  /// Whether the underlying buffer holds at least one entry (even though
  /// none of them are currently visible).
  final bool hasLogs;

  /// Called when the "Clear filters" action is activated. Only shown when
  /// [hasLogs] is `true`.
  final VoidCallback onClearFilters;

  /// The labels to show instead of the English defaults; see
  /// [LogViewerLabels.emptyTitle], [LogViewerLabels.emptyMessage],
  /// [LogViewerLabels.noMatchesTitle], [LogViewerLabels.noMatchesMessage] and
  /// [LogViewerLabels.clearFilters].
  final LogViewerLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final labels = LogViewerLocalizations.resolve(context, this.labels);
    // Centred when there is room, scrollable instead of overflowing when the
    // host is shorter than the content (e.g. a docked panel).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: _content(theme, labels),
        ),
      ),
    );
  }

  Widget _content(FluentThemeData theme, LogViewerLabels labels) {
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
              hasLogs
                  ? labels.noMatchesTitle ?? 'No results found'
                  : labels.emptyTitle ?? 'No logs yet',
              style: theme.typography.subtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasLogs
                  ? labels.noMatchesMessage ??
                      'No log entries match the current filter.'
                  : labels.emptyMessage ??
                      'Logs will appear here as soon as your app emits its '
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
                child: Text(labels.clearFilters ?? 'Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
