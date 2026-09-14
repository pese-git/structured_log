import 'package:flutter/cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

/// A `category`-filter selector for [CupertinoLogViewer]: a horizontally
/// scrollable row of pill-shaped filter buttons — the iOS pattern for a
/// dynamic, open-ended set of filter tags (App Store genres, Podcasts
/// categories, ...), as opposed to [CupertinoSlidingSegmentedControl]'s
/// fixed-width closed set (used for the level filter instead, since that
/// one has a small, constant number of options).
///
/// Options are derived dynamically from the distinct `category` values
/// currently present in [controller]'s [LogViewerController.buffer] — the
/// package has no way to know domain category names (they're entirely
/// consumer-defined), so raw category strings are used as pill labels, plus
/// [allLabel] for "no filter" (`categoryFilter == null`).
///
/// Renders nothing ([SizedBox.shrink]) while fewer than two distinct
/// categories are present — a single option wouldn't filter anything.
class LogCategoryFilterBar extends StatelessWidget {
  const LogCategoryFilterBar({
    required this.controller,
    this.allLabel = 'All',
    super.key,
  });

  /// The controller this selector reads [LogViewerController.buffer] from
  /// and writes [LogViewerController.categoryFilter] to.
  final LogViewerController controller;

  /// The label shown for "no filter" (`categoryFilter == null`).
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final categories = <String>{
          for (final entry in controller.buffer.entries.value)
            if (entry['category'] case final String category) category,
        }.toList()
          ..sort();

        if (categories.length < 2) return const SizedBox.shrink();

        return SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _Pill(
                label: allLabel,
                selected: controller.categoryFilter == null,
                onTap: () => controller.categoryFilter = null,
              ),
              for (final category in categories)
                _Pill(
                  label: category,
                  selected: controller.categoryFilter == category,
                  onTap: () => controller.categoryFilter = category,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size.zero,
        borderRadius: BorderRadius.circular(16),
        color: selected
            ? primary
            : CupertinoColors.systemGrey6.resolveFrom(context),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? CupertinoColors.white
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}
