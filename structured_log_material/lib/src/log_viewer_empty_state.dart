import 'package:flutter/material.dart';

/// The state [MaterialLogViewerPage] shows in place of the list when there
/// is nothing to display, distinguishing two cases:
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
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                hasLogs ? Icons.search_off_rounded : Icons.receipt_long_rounded,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasLogs ? 'No logs match the current filter' : 'No logs yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasLogs
                  ? 'Try a different search term, or clear the active '
                      'filters to see everything.'
                  : 'Logs will appear here as soon as your app emits its '
                      'first event.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (hasLogs) ...[
              const SizedBox(height: 12),
              TextButton(
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
