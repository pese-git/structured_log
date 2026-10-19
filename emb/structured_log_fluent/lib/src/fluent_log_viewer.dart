import 'dart:math' as math;

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
  const FluentLogViewer({
    required this.controller,
    this.labels = const LogViewerLabels(),
    this.onContextCopied,
    super.key,
  });

  /// The controller this widget reads from and mutates in response to user
  /// input (search, level/category filter, pause, clear, selection).
  final LogViewerController controller;

  /// The labels to show instead of the English defaults, passed on to every
  /// part of the viewer, the detail pane included. A `null` field falls back
  /// to [LogViewerLocalizations] when its delegate is registered, then to
  /// the English default.
  final LogViewerLabels labels;

  /// Called with the entry once the detail pane's copy action has put its
  /// context on the clipboard — the place to confirm the copy, e.g. with an
  /// `InfoBar`. Not called when the clipboard write fails or the pane has
  /// gone away by then; the viewer shows no confirmation of its own.
  final void Function(Map<String, dynamic> entry)? onContextCopied;

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

  /// Width of the category filter in both toolbar layouts (the narrow one
  /// shrinks it to fit — see [_buildNarrowToolbar]) and the gap between the
  /// filters.
  static const _categoryBoxWidth = 190.0;
  static const _toolbarGap = 10.0;

  static const _levelOptions = <LogLevel?>[
    null,
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
  ];

  static String _defaultLevelLabel(LogLevel? minLevel) => switch (minLevel) {
        null => 'All levels',
        LogLevel.debug => 'Debug and above',
        LogLevel.info => 'Info and above',
        LogLevel.warning => 'Warning and above',
        LogLevel.error => 'Error and above',
        final level => '${level.name} and above',
      };

  /// [FluentLogViewer.labels] resolved against [LogViewerLocalizations] for
  /// the current build.
  LogViewerLabels _labels = const LogViewerLabels();

  String _levelLabel(LogLevel? minLevel) =>
      (_labels.levelFilterLabel ?? _defaultLevelLabel)(minLevel);

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
    _labels = LogViewerLocalizations.resolve(context, widget.labels);
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
      placeholder: _labels.searchHint ?? 'Search',
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
      placeholder: Text(_levelLabel(null)),
      items: [
        for (final option in _levelOptions)
          ComboBoxItem(value: option, child: Text(_levelLabel(option))),
      ],
      onChanged: (value) => controller.levelFilter = value,
    );
  }

  Widget _pauseButton(LogViewerController controller) {
    return Tooltip(
      message: controller.paused
          ? _labels.resume ?? 'Resume'
          : _labels.pause ?? 'Pause',
      child: IconButton(
        icon: Icon(controller.paused ? FluentIcons.play : FluentIcons.pause),
        onPressed: () => controller.paused = !controller.paused,
      ),
    );
  }

  Widget _clearButton(LogViewerController controller) {
    return Tooltip(
      message: _labels.clear ?? 'Clear all',
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
        const SizedBox(width: _toolbarGap),
        SizedBox(
          width: _categoryBoxWidth,
          child: LogCategoryComboBox(
            controller: controller,
            labels: _labels,
          ),
        ),
        const SizedBox(width: _toolbarGap),
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
        LayoutBuilder(
          builder: (context, constraints) {
            // Reserved whether or not the category box renders anything (it
            // hides itself with fewer than two categories) — matching the
            // wide toolbar, which reserves the same space for it. Capped at
            // the wide toolbar's width, but never more than half the row: a
            // fixed 190 left the level box under its minimum width (it
            // overflowed) once the row got narrower than ~244 px.
            final categoryWidth = math.min(
              _categoryBoxWidth,
              (constraints.maxWidth - _toolbarGap) / 2,
            );
            return Row(
              children: [
                SizedBox(
                  width: categoryWidth,
                  child: LogCategoryComboBox(
                    controller: controller,
                    labels: _labels,
                  ),
                ),
                const SizedBox(width: _toolbarGap),
                Expanded(child: _levelComboBox(controller)),
              ],
            );
          },
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
        labels: _labels,
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
          Expanded(child: _detailPane(selected)),
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
              message: _labels.backToList ?? 'Back to list',
              child: IconButton(
                icon: const Icon(FluentIcons.back),
                onPressed: () => setState(() => _detailOpenNarrow = false),
              ),
            ),
          ),
          const Divider(),
          Expanded(child: _detailPane(selected)),
        ],
      );
    }

    return _buildList(entries, selected, narrow: true);
  }

  Widget _detailPane(Map<String, dynamic> entry) => LogEntryDetailPane(
        entry: entry,
        labels: _labels,
        onContextCopied: widget.onContextCopied,
      );

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
