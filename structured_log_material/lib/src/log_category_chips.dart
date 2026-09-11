import 'package:flutter/material.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

/// A `category`-filter selector for [MaterialLogViewer], mirroring its
/// level filter's horizontal choice-chip row. Options are derived
/// dynamically from the distinct `category` values currently present in
/// [controller]'s [LogViewerController.buffer] — the package has no way to
/// know domain category names (they're entirely consumer-defined), so raw
/// category strings are used as chip labels, plus [allLabel] for "no
/// filter" (`categoryFilter == null`).
///
/// Renders nothing ([SizedBox.shrink]) while fewer than two distinct
/// categories are present — a single option wouldn't filter anything.
class LogCategoryChips extends StatelessWidget {
  const LogCategoryChips({
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
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(allLabel),
                  selected: controller.categoryFilter == null,
                  onSelected: (_) => controller.categoryFilter = null,
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: controller.categoryFilter == category,
                    onSelected: (_) => controller.categoryFilter = category,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
