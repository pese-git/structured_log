import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_category_combo_box.dart';
import 'log_entry_detail_pane.dart';
import 'log_entry_tile.dart';
import 'log_viewer_empty_state.dart';

/// The Fluent UI (WinUI-style) log viewer for `structured_log`, as a plain
/// embeddable widget rather than a full screen — drop it into a `Flyout`, a
/// side panel, a tab, or anywhere else that already provides its own page
/// chrome. [FluentLogViewerPage] wraps this in a [ScaffoldPage] (with a
/// title and, when pushed, a back button) for the full-screen case; use
/// [FluentLogViewer] directly when that page chrome isn't wanted.
///
/// A toolbar (search box, category filter — see [LogCategoryComboBox], only
/// shown once the buffer has two or more distinct categories — minimum-level
/// filter, pause/resume, clear) sits above a live, newest-first master list
/// on the left with the selected entry's full context in a detail pane on
/// the right — a master-detail split view, matching WinUI conventions (Mail,
/// Settings) rather than `structured_log_material`'s mobile-style bottom
/// sheet. Colors and typography come from the ambient `FluentTheme` (light
/// and dark both supported) except for each entry's level indicator, whose
/// palette is fixed — see `logLevelColor`.
///
/// Wire it up by giving the same [LogViewerController] to both this widget
/// and a [LogSink] that feeds it:
///
/// ```dart
/// final buffer = LogBuffer();
/// final controller = LogViewerController(buffer);
///
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'viewer', output: buffer.capture),
/// ]);
///
/// // e.g. docked in a side panel alongside other app content:
/// Row(
///   children: [
///     Expanded(child: MyAppContent()),
///     SizedBox(
///       width: 420,
///       child: FluentLogViewer(controller: controller),
///     ),
///   ],
/// )
/// ```
class FluentLogViewer extends StatefulWidget {
  const FluentLogViewer({required this.controller, super.key});

  /// The controller this widget reads from and mutates in response to user
  /// input (search, level/category filter, pause, clear, selection).
  final LogViewerController controller;

  @override
  State<FluentLogViewer> createState() => _FluentLogViewerState();
}

class _FluentLogViewerState extends State<FluentLogViewer> {
  late final TextEditingController _searchController;
  Map<String, dynamic>? _selected;

  static const _levelOptions = <String, LogLevel?>{
    'All levels': null,
    'Debug and above': LogLevel.debug,
    'Info and above': LogLevel.info,
    'Warning and above': LogLevel.warning,
    'Error and above': LogLevel.error,
  };

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: widget.controller.searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() => _selected = null);
    widget.controller
      ..searchQuery = ''
      ..levelFilter = null
      ..categoryFilter = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: TextBox(
                      controller: _searchController,
                      placeholder: 'Search',
                      prefix: const Padding(
                        padding: EdgeInsetsDirectional.only(start: 8),
                        child: Icon(FluentIcons.search, size: 14),
                      ),
                      onChanged: (value) => controller.searchQuery = value,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 190,
                    child: LogCategoryComboBox(controller: controller),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 190,
                    child: ComboBox<LogLevel?>(
                      value: controller.levelFilter,
                      isExpanded: true,
                      // ComboBox treats a null value as "nothing selected"
                      // and falls back to this placeholder rather than
                      // matching it against the "All levels" item (whose
                      // value is also null) — set explicitly so "no filter"
                      // isn't blank.
                      placeholder: const Text('All levels'),
                      items: [
                        for (final option in _levelOptions.entries)
                          ComboBoxItem(
                            value: option.value,
                            child: Text(option.key),
                          ),
                      ],
                      onChanged: (value) => controller.levelFilter = value,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: controller.paused ? 'Resume' : 'Pause',
                    child: IconButton(
                      icon: Icon(
                        controller.paused
                            ? FluentIcons.play
                            : FluentIcons.pause,
                      ),
                      onPressed: () => controller.paused = !controller.paused,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Clear all',
                    child: IconButton(
                      icon: const Icon(FluentIcons.delete),
                      onPressed: () {
                        setState(() => _selected = null);
                        controller.clear();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(controller)),
          ],
        );
      },
    );
  }

  Widget _buildBody(LogViewerController controller) {
    final entries = controller.visibleEntries.reversed.toList();
    if (entries.isEmpty) {
      return LogViewerEmptyState(
        hasLogs: controller.buffer.entries.value.isNotEmpty,
        onClearFilters: _resetFilters,
      );
    }

    final selected = entries.any((e) => identical(e, _selected))
        ? _selected!
        : entries.first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return LogEntryTile(
                entry: entry,
                selected: identical(entry, selected),
                onTap: () => setState(() => _selected = entry),
              );
            },
          ),
        ),
        const Divider(direction: Axis.vertical),
        Expanded(child: LogEntryDetailPane(entry: selected)),
      ],
    );
  }
}
