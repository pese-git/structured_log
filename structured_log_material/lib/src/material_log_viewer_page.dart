import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'log_entry_detail_sheet.dart';
import 'log_entry_tile.dart';
import 'log_viewer_empty_state.dart';

/// A ready-to-use Material 3 log viewer screen for `structured_log`, built
/// on a [LogViewerController].
///
/// Shows a live, newest-first list of the controller's
/// [LogViewerController.visibleEntries], with a top bar for search, a
/// minimum-level filter, pause/resume, and clearing; tapping a row opens
/// its full context in a [LogEntryDetailSheet]. Colors, typography, and
/// surfaces come from the ambient `Theme` (light and dark both supported)
/// except for each entry's level indicator, whose palette is fixed — see
/// `logLevelColor`.
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
/// // Push it, or embed it as a tab/page in your own navigation:
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => MaterialLogViewerPage(controller: controller),
/// ));
/// ```
class MaterialLogViewerPage extends StatefulWidget {
  const MaterialLogViewerPage({required this.controller, super.key});

  /// The controller this screen reads from and mutates in response to user
  /// input (search, level filter, pause, clear).
  final LogViewerController controller;

  @override
  State<MaterialLogViewerPage> createState() => _MaterialLogViewerPageState();
}

class _MaterialLogViewerPageState extends State<MaterialLogViewerPage> {
  late final TextEditingController _searchController;

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
    widget.controller
      ..searchQuery = ''
      ..levelFilter = null
      ..categoryFilter = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => IconButton(
              tooltip: controller.paused ? 'Resume' : 'Pause',
              icon: Icon(
                controller.paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
              ),
              onPressed: () => controller.paused = !controller.paused,
            ),
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: controller.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => controller.searchQuery = value,
              decoration: InputDecoration(
                hintText: 'Search events, categories…',
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
          _LevelFilterChips(controller: controller),
          const Divider(height: 1),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final entries = controller.visibleEntries.reversed.toList();
                if (entries.isEmpty) {
                  return LogViewerEmptyState(
                    hasLogs: controller.buffer.entries.value.isNotEmpty,
                    onClearFilters: _resetFilters,
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return LogEntryTile(
                      entry: entry,
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => LogEntryDetailSheet(entry: entry),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelFilterChips extends StatelessWidget {
  const _LevelFilterChips({required this.controller});

  final LogViewerController controller;

  static const _options = <String, LogLevel?>{
    'All': null,
    'Debug+': LogLevel.debug,
    'Info+': LogLevel.info,
    'Warning+': LogLevel.warning,
    'Error+': LogLevel.error,
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
            for (final option in _options.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(option.key),
                  selected: controller.levelFilter == option.value,
                  onSelected: (_) => controller.levelFilter = option.value,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
