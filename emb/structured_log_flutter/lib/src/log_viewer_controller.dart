import 'package:flutter/foundation.dart';
import 'package:structured_log/structured_log.dart';

import 'log_buffer.dart';

const _levelKey = 'level';
const _timestampKey = 'timestamp';

/// Returns the [LogLevel] a log [entry] was recorded at, by matching its
/// `level` context key (set by every entry via `structured_log`'s
/// `BoundLogger`) against [LogLevel.values]' names — or `null` if the key
/// is missing, not a string, or doesn't match a known level name.
///
/// Exposed as a standalone function (rather than kept private to
/// [LogViewerController]) so UI packages built on this one can render a
/// level-specific indicator (e.g. a colored dot) without re-implementing
/// this parsing themselves.
LogLevel? logLevelOf(Map<String, dynamic> entry) {
  final name = entry[_levelKey];
  if (name is! String) return null;
  for (final level in LogLevel.values) {
    if (level.name == name) return level;
  }
  return null;
}

/// Headless state for a log viewer UI: search, level and category filters,
/// pause/resume, and clearing, all applied on top of a [LogBuffer].
///
/// [LogViewerController] renders no UI itself — it exists so any
/// design-system-specific widget (Material, Cupertino, Fluent, ...) can be
/// built on the same filtering/pause logic without reimplementing it. A
/// concrete UI listens to this controller (it's a [ChangeNotifier]) and
/// reads [visibleEntries] for what to display.
///
/// ```dart
/// final buffer = LogBuffer();
/// final controller = LogViewerController(buffer);
///
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'viewer', output: buffer.capture),
/// ]);
///
/// controller.addListener(() {
///   print('visible: ${controller.visibleEntries.length}');
/// });
///
/// getLogger().warning('slow_query', context: {'duration_ms': 1500});
/// controller.levelFilter = LogLevel.warning; // only warning+ from now on
/// controller.searchQuery = 'slow'; // further narrowed by text
/// ```
class LogViewerController extends ChangeNotifier {
  /// Creates a controller reading from [buffer]. The controller starts
  /// unfiltered (`levelFilter`/`categoryFilter` unset, empty `searchQuery`)
  /// and not [paused].
  LogViewerController(this.buffer) {
    buffer.entries.addListener(_onBufferChanged);
  }

  /// The [LogBuffer] this controller filters and, via [clear], empties.
  final LogBuffer buffer;

  LogLevel? _levelFilter;
  String? _categoryFilter;
  String _searchQuery = '';
  bool _paused = false;
  List<Map<String, dynamic>> _frozenEntries = const [];

  /// The minimum level a visible entry must have, or `null` for no
  /// restriction. Setting this notifies listeners.
  LogLevel? get levelFilter => _levelFilter;

  set levelFilter(LogLevel? value) {
    if (value == _levelFilter) return;
    _levelFilter = value;
    notifyListeners();
  }

  /// The exact `category` context value a visible entry must have, or
  /// `null` for no restriction. Setting this notifies listeners.
  String? get categoryFilter => _categoryFilter;

  set categoryFilter(String? value) {
    if (value == _categoryFilter) return;
    _categoryFilter = value;
    notifyListeners();
  }

  /// Free-text search, matched case-insensitively as a substring against
  /// `event` and every other context value (`level`/`timestamp` excluded).
  /// An empty string means no restriction. Setting this notifies listeners.
  String get searchQuery => _searchQuery;

  set searchQuery(String value) {
    if (value == _searchQuery) return;
    _searchQuery = value;
    notifyListeners();
  }

  /// Whether the live tail is paused. While `true`, [visibleEntries] stays
  /// fixed at the set of entries visible at the moment it was paused, even
  /// as [buffer] keeps capturing new ones; setting it back to `false`
  /// resumes tracking [buffer] live. Setting this notifies listeners.
  bool get paused => _paused;

  set paused(bool value) {
    if (value == _paused) return;
    if (value) {
      _frozenEntries = buffer.entries.value;
    }
    _paused = value;
    notifyListeners();
  }

  /// The entries currently visible: everything in [buffer] (or, while
  /// [paused], the entries frozen at pause time) that satisfies
  /// [levelFilter], [categoryFilter], and [searchQuery]; oldest first,
  /// matching [buffer]'s own order.
  List<Map<String, dynamic>> get visibleEntries {
    final source = _paused ? _frozenEntries : buffer.entries.value;
    return source.where(_matches).toList(growable: false);
  }

  bool _matches(Map<String, dynamic> entry) {
    if (_levelFilter != null) {
      final level = logLevelOf(entry);
      if (level == null || level.index < _levelFilter!.index) return false;
    }
    if (_categoryFilter != null && entry['category'] != _categoryFilter) {
      return false;
    }
    if (_searchQuery.isNotEmpty && !_matchesSearch(entry)) {
      return false;
    }
    return true;
  }

  bool _matchesSearch(Map<String, dynamic> entry) {
    final query = _searchQuery.toLowerCase();
    for (final e in entry.entries) {
      if (e.key == _levelKey || e.key == _timestampKey) continue;
      final value = e.value;
      if (value != null && value.toString().toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  /// Clears [buffer] and any frozen (paused) snapshot, and notifies
  /// listeners — [visibleEntries] becomes empty regardless of [paused].
  void clear() {
    buffer.clear();
    _frozenEntries = const [];
    notifyListeners();
  }

  void _onBufferChanged() {
    if (!_paused) notifyListeners();
  }

  @override
  void dispose() {
    buffer.entries.removeListener(_onBufferChanged);
    super.dispose();
  }
}
