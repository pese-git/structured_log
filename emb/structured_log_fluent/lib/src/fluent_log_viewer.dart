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
/// Both the toolbar and the master-detail split adapt to how much width
/// this widget is actually given (its own constraints, not the window's —
/// docking it in a narrow side panel behaves the same as a narrow window):
/// below [_toolbarBreakpoint] the toolbar wraps onto a second row instead of
/// overflowing, and below [_masterDetailBreakpoint] the split collapses to a
/// single pane — the list, with a tapped entry's detail replacing it (and a
/// back button to return), rather than the two dropping below a usable
/// width side by side.
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

  /// Whether a tapped entry's detail is showing in place of the list —
  /// only meaningful below [_masterDetailBreakpoint], where the two don't
  /// fit side by side.
  bool _detailOpenNarrow = false;

  /// Below this width the toolbar wraps search/category/level onto a
  /// second row instead of overflowing — comfortably above the toolbar's
  /// worst case (search box + both dropdowns + pause/clear, with padding).
  static const _toolbarBreakpoint = 820.0;

  /// Below this width the master-detail split collapses to a single pane.
  static const _masterDetailBreakpoint = 640.0;

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
    setState(() {
      _selected = null;
      _detailOpenNarrow = false;
    });
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
        return LayoutBuilder(
          builder: (context, constraints) {
            final narrowToolbar = constraints.maxWidth < _toolbarBreakpoint;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: narrowToolbar
                      ? _buildNarrowToolbar(controller)
                      : _buildWideToolbar(controller),
                ),
                Expanded(
                  child: _buildBody(constraints.maxWidth, controller),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _searchBox(LogViewerController controller) {
    return TextBox(
      controller: _searchController,
      placeholder: 'Search',
      prefix: const Padding(
        padding: EdgeInsetsDirectional.only(start: 8),
        child: Icon(FluentIcons.search, size: 14),
      ),
      onChanged: (value) => controller.searchQuery = value,
    );
  }

  Widget _levelComboBox(LogViewerController controller) {
    return ComboBox<LogLevel?>(
      value: controller.levelFilter,
      isExpanded: true,
      // ComboBox treats a null value as "nothing selected" and falls back
      // to this placeholder rather than matching it against the "All
      // levels" item (whose value is also null) — set explicitly so "no
      // filter" isn't blank.
      placeholder: const Text('All levels'),
      items: [
        for (final option in _levelOptions.entries)
          ComboBoxItem(value: option.value, child: Text(option.key)),
      ],
      onChanged: (value) => controller.levelFilter = value,
    );
  }

  Widget _pauseButton(LogViewerController controller) {
    return Tooltip(
      message: controller.paused ? 'Resume' : 'Pause',
      child: IconButton(
        icon: Icon(controller.paused ? FluentIcons.play : FluentIcons.pause),
        onPressed: () => controller.paused = !controller.paused,
      ),
    );
  }

  Widget _clearButton(LogViewerController controller) {
    return Tooltip(
      message: 'Clear all',
      child: IconButton(
        icon: const Icon(FluentIcons.delete),
        onPressed: () {
          setState(() {
            _selected = null;
            _detailOpenNarrow = false;
          });
          controller.clear();
        },
      ),
    );
  }

  Widget _buildWideToolbar(LogViewerController controller) {
    return Row(
      children: [
        SizedBox(width: 240, child: _searchBox(controller)),
        const SizedBox(width: 10),
        SizedBox(
          width: 190,
          child: LogCategoryComboBox(controller: controller),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 190, child: _levelComboBox(controller)),
        const Spacer(),
        _pauseButton(controller),
        const SizedBox(width: 4),
        _clearButton(controller),
      ],
    );
  }

  Widget _buildNarrowToolbar(LogViewerController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _searchBox(controller)),
            const SizedBox(width: 8),
            _pauseButton(controller),
            const SizedBox(width: 4),
            _clearButton(controller),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Reserved at a fixed width whether or not it renders anything
            // (it hides itself with fewer than two categories) — matching
            // the wide toolbar, which reserves the same space for it.
            SizedBox(
              width: 190,
              child: LogCategoryComboBox(controller: controller),
            ),
            const SizedBox(width: 10),
            Expanded(child: _levelComboBox(controller)),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(double maxWidth, LogViewerController controller) {
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

    if (maxWidth >= _masterDetailBreakpoint) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 340,
            child: _buildList(entries, selected, narrow: false),
          ),
          const Divider(direction: Axis.vertical),
          Expanded(child: LogEntryDetailPane(entry: selected)),
        ],
      );
    }

    if (_detailOpenNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Tooltip(
              message: 'Back to list',
              child: IconButton(
                icon: const Icon(FluentIcons.back),
                onPressed: () => setState(() => _detailOpenNarrow = false),
              ),
            ),
          ),
          const Divider(),
          Expanded(child: LogEntryDetailPane(entry: selected)),
        ],
      );
    }

    return _buildList(entries, selected, narrow: true);
  }

  Widget _buildList(
    List<Map<String, dynamic>> entries,
    Map<String, dynamic> selected, {
    required bool narrow,
  }) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return LogEntryTile(
          entry: entry,
          // In the single-pane (narrow) case nothing is showing alongside
          // the list for a highlight to refer to.
          selected: !narrow && identical(entry, selected),
          onTap: () => setState(() {
            _selected = entry;
            if (narrow) _detailOpenNarrow = true;
          }),
        );
      },
    );
  }
}
