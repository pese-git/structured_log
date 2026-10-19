import 'package:flutter/cupertino.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_category_filter_bar.dart';
import 'log_entry_detail_panel.dart';
import 'log_entry_tile.dart';
import 'log_viewer_empty_state.dart';

/// The Cupertino (iOS-style) log viewer for `structured_log`, as a plain
/// embeddable widget rather than a full screen — drop it into a tab, a
/// side panel (iPad split view), or anywhere else that already provides
/// its own page chrome. [CupertinoLogViewerPage] wraps this in a
/// [CupertinoPageScaffold] (with a title and, when pushed, a back button)
/// for the full-screen case; use [CupertinoLogViewer] directly when that
/// page chrome isn't wanted.
///
/// A toolbar ([CupertinoSearchTextField], pause/resume, clear-all) sits
/// above a category-filter pill row (see [LogCategoryFilterBar], only shown
/// once the buffer has two or more distinct categories) and a level-filter
/// [CupertinoSlidingSegmentedControl], above a live, newest-first list.
///
/// How the selected entry's full context is shown adapts to how much width
/// *this widget* is actually given (its own constraints, not the window's
/// — docking it in a narrow side panel behaves the same as a narrow
/// window): below [_masterDetailBreakpoint] — the mobile-style default —
/// tapping a row pushes [LogEntryDetailPanel] as a new screen via
/// [CupertinoPageRoute], the standard iOS "drill into detail" pattern
/// (Mail, Settings on iPhone); at or above it, the list and a non-modal
/// [LogEntryDetailPanel] for the selected entry show side by side instead,
/// matching how those same apps behave on iPad.
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
///       child: CupertinoLogViewer(controller: controller),
///     ),
///   ],
/// )
/// ```
class CupertinoLogViewer extends StatefulWidget {
  const CupertinoLogViewer({
    required this.controller,
    this.labels = const LogViewerLabels(),
    this.onContextCopied,
    super.key,
  });

  /// The controller this widget reads from and mutates in response to user
  /// input (search, level/category filter, pause, clear, selection).
  final LogViewerController controller;

  /// The labels to show instead of the English defaults, passed on to every
  /// part of the viewer, the pushed detail screen included. A `null` field
  /// falls back to [LogViewerLocalizations] when its delegate is registered,
  /// then to the English default. [LogViewerLabels.pause],
  /// [LogViewerLabels.resume] and [LogViewerLabels.clear] become the
  /// semantics labels of the icon-only pause and clear buttons.
  final LogViewerLabels labels;

  /// Called with the entry once the detail view's copy action has put its
  /// context on the clipboard — the place to confirm the copy. Not called
  /// when the clipboard write fails or the detail view has gone away by
  /// then; the viewer shows no confirmation of its own.
  final void Function(Map<String, dynamic> entry)? onContextCopied;

  @override
  State<CupertinoLogViewer> createState() => _CupertinoLogViewerState();
}

class _CupertinoLogViewerState extends State<CupertinoLogViewer> {
  late final TextEditingController _searchController;
  Map<String, dynamic>? _selected;

  /// Below this width the list and detail panel don't fit side by side
  /// usefully — fall back to the list plus a pushed detail screen.
  static const _masterDetailBreakpoint = 700.0;

  /// The list's width in the master-detail (wide) layout.
  static const _listWidth = 360.0;

  // CupertinoSlidingSegmentedControl's type parameter must be non-nullable
  // (it's bound to Object), so levelFilter's `null` ("All") is represented
  // as an index into this list rather than used directly as the segment
  // value.
  static const _levelOptions = <LogLevel?>[
    null,
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
  ];
  static String _defaultLevelLabel(LogLevel? minLevel) => switch (minLevel) {
        null => 'All',
        LogLevel.debug => 'Debug+',
        LogLevel.info => 'Info+',
        LogLevel.warning => 'Warning+',
        LogLevel.error => 'Error+',
        final level => '${level.name}+',
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
    final labels = LogViewerLocalizations.resolve(context, widget.labels);
    final levelLabel = labels.levelFilterLabel ?? _defaultLevelLabel;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      controller: _searchController,
                      placeholder:
                          labels.searchHint ?? 'Search events, categories…',
                      onChanged: (value) => controller.searchQuery = value,
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 8),
                    minimumSize: Size.zero,
                    onPressed: () => controller.paused = !controller.paused,
                    child: Icon(
                      controller.paused
                          ? CupertinoIcons.play_fill
                          : CupertinoIcons.pause_fill,
                      semanticLabel: controller.paused
                          ? labels.resume ?? 'Resume'
                          : labels.pause ?? 'Pause',
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 4),
                    minimumSize: Size.zero,
                    onPressed: () {
                      setState(() => _selected = null);
                      controller.clear();
                    },
                    child: Icon(
                      CupertinoIcons.delete,
                      semanticLabel: labels.clear ?? 'Clear all',
                    ),
                  ),
                ],
              ),
            ),
            LogCategoryFilterBar(controller: controller, labels: labels),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSlidingSegmentedControl<int>(
                // CupertinoSlidingSegmentedControl asserts groupValue is
                // either null or a known key — indexOf returns -1 if
                // levelFilter was set (e.g. programmatically) to a level
                // outside this bar's five options, which isn't a key here.
                groupValue: _levelOptions.contains(controller.levelFilter)
                    ? _levelOptions.indexOf(controller.levelFilter)
                    : null,
                children: {
                  for (var i = 0; i < _levelOptions.length; i++)
                    i: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        levelLabel(_levelOptions[i]),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                },
                onValueChanged: (index) {
                  if (index != null) {
                    controller.levelFilter = _levelOptions[index];
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _buildBody(constraints.maxWidth, controller),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(double maxWidth, LogViewerController controller) {
    final entries = controller.visibleEntries.reversed.toList();
    if (entries.isEmpty) {
      return LogViewerEmptyState(
        hasLogs: controller.buffer.entries.value.isNotEmpty,
        onClearFilters: _resetFilters,
        labels: widget.labels,
      );
    }

    if (maxWidth >= _masterDetailBreakpoint) {
      final selected = entries.any((e) => identical(e, _selected))
          ? _selected!
          : entries.first;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _listWidth,
            child: _buildList(
              entries,
              wide: true,
              selected: selected,
            ),
          ),
          Container(
            width: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          Expanded(child: _detailPanel(selected)),
        ],
      );
    }

    return _buildList(entries, wide: false);
  }

  Widget _detailPanel(Map<String, dynamic> entry) => LogEntryDetailPanel(
        entry: entry,
        labels: widget.labels,
        onContextCopied: widget.onContextCopied,
      );

  Widget _buildList(
    List<Map<String, dynamic>> entries, {
    required bool wide,
    Map<String, dynamic>? selected,
  }) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, index) => Container(
        height: 0.5,
        margin: const EdgeInsets.only(left: 16),
        color: CupertinoColors.separator.resolveFrom(context),
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return LogEntryTile(
          entry: entry,
          selected: wide && selected != null && identical(entry, selected),
          showsDisclosureIndicator: !wide,
          onTap: () {
            if (wide) {
              setState(() => _selected = entry);
            } else {
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => CupertinoPageScaffold(
                    navigationBar: CupertinoNavigationBar(
                      middle: Text(entry['event']?.toString() ?? ''),
                    ),
                    child: _detailPanel(entry),
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}
