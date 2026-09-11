import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_category_combo_box.dart';
import 'log_entry_detail_pane.dart';
import 'log_entry_tile.dart';
import 'log_viewer_empty_state.dart';

/// A ready-to-use Fluent UI (WinUI-style) log viewer screen for
/// `structured_log`, built on a [LogViewerController].
///
/// Shows a live, newest-first list of the controller's
/// [LogViewerController.visibleEntries] on the left, with a header bar
/// (title, search, category filter — see [LogCategoryComboBox], only shown
/// once the buffer has two or more distinct categories — minimum-level
/// filter, pause/resume, clear) above it, and the selected entry's full
/// context in a detail pane on the right —
/// a master-detail split view, matching WinUI conventions (Mail, Settings)
/// rather than `structured_log_material`'s mobile-style bottom sheet.
/// Colors and typography come from the ambient `FluentTheme` (light and
/// dark both supported) except for each entry's level indicator, whose
/// palette is fixed — see `logLevelColor`. When pushed via `Navigator`
/// (e.g. with `FluentPageRoute`, as below) the header shows a back button
/// automatically; it's omitted when this widget is the navigator root.
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
/// runApp(FluentApp(
///   home: FluentLogViewerPage(controller: controller),
/// ));
/// ```
class FluentLogViewerPage extends StatefulWidget {
  const FluentLogViewerPage({required this.controller, super.key});

  /// The controller this screen reads from and mutates in response to user
  /// input (search, level filter, pause, clear, selection).
  final LogViewerController controller;

  @override
  State<FluentLogViewerPage> createState() => _FluentLogViewerPageState();
}

class _FluentLogViewerPageState extends State<FluentLogViewerPage> {
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
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Row(
            children: [
              if (Navigator.canPop(context)) ...[
                IconButton(
                  icon: const Icon(FluentIcons.back),
                  onPressed: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 8),
              ],
              Text('Logs', style: theme.typography.title),
              const SizedBox(width: 24),
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
                  // ComboBox treats a null value as "nothing selected" and
                  // falls back to this placeholder rather than matching it
                  // against the "All levels" item (whose value is also
                  // null) — set explicitly so "no filter" isn't blank.
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
                    controller.paused ? FluentIcons.play : FluentIcons.pause,
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
      ),
      content: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
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
        },
      ),
    );
  }
}
