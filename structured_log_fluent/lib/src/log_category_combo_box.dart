import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

/// A `category`-filter selector for [FluentLogViewerPage], mirroring its
/// existing level filter. Options are derived dynamically from the distinct
/// `category` values currently present in [controller]'s
/// [LogViewerController.buffer] — the package has no way to know domain
/// category names (e.g. `application`/`protocol` are consumer-specific), so
/// raw category strings are used as display labels, plus [allLabel] for
/// "no filter" (`categoryFilter == null`).
///
/// Renders nothing ([SizedBox.shrink]) while fewer than two distinct
/// categories are present — a single option wouldn't filter anything.
///
/// ```dart
/// Row(
///   children: [
///     // ... search box, level ComboBox ...
///     LogCategoryComboBox(controller: controller),
///   ],
/// )
/// ```
class LogCategoryComboBox extends StatelessWidget {
  const LogCategoryComboBox({
    required this.controller,
    this.allLabel = 'All types',
    super.key,
  });

  /// The controller this selector reads [LogViewerController.buffer] from
  /// and writes [LogViewerController.categoryFilter] to.
  final LogViewerController controller;

  /// The label shown for "no filter" (`categoryFilter == null`), and used
  /// as the ComboBox's placeholder.
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

        return ComboBox<String?>(
          value: controller.categoryFilter,
          isExpanded: true,
          // ComboBox treats a null value as "nothing selected" and falls
          // back to this placeholder rather than matching it against the
          // allLabel item (whose value is also null) — set explicitly so
          // "no filter" isn't blank.
          placeholder: Text(allLabel),
          items: [
            ComboBoxItem(value: null, child: Text(allLabel)),
            for (final category in categories)
              ComboBoxItem(value: category, child: Text(category)),
          ],
          onChanged: (value) => controller.categoryFilter = value,
        );
      },
    );
  }
}
