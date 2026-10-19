import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_category_chips.dart';
import 'log_entry_detail_panel.dart';
import 'log_entry_detail_sheet.dart';
import 'log_entry_tile.dart';
import 'log_viewer_empty_state.dart';

/// The Material 3 log viewer for `structured_log`, as a plain embeddable
/// widget rather than a full screen — drop it into a tab, a side panel, a
/// dialog, or anywhere else that already provides its own page chrome.
/// [MaterialLogViewerPage] wraps this in a [Scaffold]/[AppBar] for the
/// full-screen case; use [MaterialLogViewer] directly when that page chrome
/// isn't wanted.
///
/// A toolbar (search field, pause/resume, clear-all) sits above
/// category-filter chips (see [LogCategoryChips], only shown once the
/// buffer has two or more distinct categories) and level-filter chips,
/// above a live, newest-first list.
///
/// How the selected entry's full context is shown adapts to how much width
/// *this widget* is actually given (its own constraints, not the window's):
/// below [_masterDetailBreakpoint] — the mobile-style default — tapping a
/// row opens a [LogEntryDetailSheet] as a modal bottom sheet, matching
/// Material apps like Gmail's phone layout; at or above it, the list and a
/// non-modal [LogEntryDetailPanel] for the selected entry show side by
/// side, matching Material's own list-detail layout guidance for tablet
/// and desktop.
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
///       child: MaterialLogViewer(controller: controller),
///     ),
///   ],
/// )
/// ```
class MaterialLogViewer extends StatefulWidget {
  const MaterialLogViewer({
    required this.controller,
    this.labels = const LogViewerLabels(),
    this.onContextCopied,
    super.key,
  });

  /// The controller this widget reads from and mutates in response to user
  /// input (search, level/category filter, pause, clear, selection).
  final LogViewerController controller;

  /// The labels to show instead of the English defaults, passed on to every
  /// part of the viewer, the detail sheet included. A `null` field falls back
  /// to [LogViewerLocalizations] when its delegate is registered, then to
  /// the English default.
  final LogViewerLabels labels;

  /// Called with the entry once the detail view's copy action has put its
  /// context on the clipboard — the place to confirm the copy, e.g. with a
  /// [SnackBar]. Not called when the clipboard write fails or the detail
  /// view has gone away by then; the viewer shows no confirmation of its own.
  final void Function(Map<String, dynamic> entry)? onContextCopied;

  @override
  State<MaterialLogViewer> createState() => _MaterialLogViewerState();
}

class _MaterialLogViewerState extends State<MaterialLogViewer> {
  late final TextEditingController _searchController;
  Map<String, dynamic>? _selected;

  /// Below this width the list and detail panel don't fit side by side
  /// usefully — fall back to the list plus a modal bottom sheet per entry.
  static const _masterDetailBreakpoint = 700.0;

  /// The list's width in the master-detail (wide) layout.
  static const _listWidth = 360.0;

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
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => controller.searchQuery = value,
                      decoration: InputDecoration(
                        hintText:
                            labels.searchHint ?? 'Search events, categories…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: controller.paused
                        ? labels.resume ?? 'Resume'
                        : labels.pause ?? 'Pause',
                    icon: Icon(
                      controller.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    onPressed: () => controller.paused = !controller.paused,
                  ),
                  IconButton(
                    tooltip: labels.clear ?? 'Clear all',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () {
                      setState(() => _selected = null);
                      controller.clear();
                    },
                  ),
                ],
              ),
            ),
            LogCategoryChips(controller: controller, labels: labels),
            _LevelFilterChips(controller: controller, labels: labels),
            const Divider(height: 1),
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
              onTap: (entry) => setState(() => _selected = entry),
              selected: selected,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: LogEntryDetailPanel(
              entry: selected,
              labels: widget.labels,
              onContextCopied: widget.onContextCopied,
            ),
          ),
        ],
      );
    }

    return _buildList(
      entries,
      onTap: (entry) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // A long entry fills the screen; the route takes the status bar's
        // inset away from the sheet's own SafeArea, so without this the
        // header ends up under the clock.
        useSafeArea: true,
        builder: (_) => LogEntryDetailSheet(
          entry: entry,
          labels: widget.labels,
          onContextCopied: widget.onContextCopied,
        ),
      ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> entries, {
    required void Function(Map<String, dynamic> entry) onTap,
    Map<String, dynamic>? selected,
  }) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return LogEntryTile(
          entry: entry,
          selected: selected != null && identical(entry, selected),
          onTap: () => onTap(entry),
        );
      },
    );
  }
}

class _LevelFilterChips extends StatelessWidget {
  const _LevelFilterChips({required this.controller, required this.labels});

  final LogViewerController controller;
  final LogViewerLabels labels;

  static const _options = <LogLevel?>[
    null,
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
  ];

  static String _defaultLabel(LogLevel? minLevel) => switch (minLevel) {
        null => 'All',
        LogLevel.debug => 'Debug+',
        LogLevel.info => 'Info+',
        LogLevel.warning => 'Warning+',
        LogLevel.error => 'Error+',
        final level => '${level.name}+',
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final option in _options)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(
                    (labels.levelFilterLabel ?? _defaultLabel)(option),
                  ),
                  selected: controller.levelFilter == option,
                  onSelected: (_) => controller.levelFilter = option,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
