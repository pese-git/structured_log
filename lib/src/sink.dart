import 'logger.dart';
import 'processors.dart';

/// A single log output destination with its own level/category filtering.
///
/// A [BoundLogger] delivers each entry to every enabled sink whose filters
/// accept it — the caller doesn't need to know how many sinks exist.
class LogSink {
  /// Identifies this sink for runtime toggling via
  /// `StructlogConfiguration.setSinkEnabled`.
  final String name;

  final OutputFunction output;

  /// Minimum level this sink accepts (inclusive).
  final LogLevel minLevel;

  /// Categories this sink accepts, matched against the entry's `category`
  /// context key. `null` means no restriction — all categories pass.
  final Set<String>? categories;

  /// Whether this sink is currently active. Mutable so it can be toggled at
  /// runtime without rebuilding the configuration.
  bool enabled;

  LogSink({
    required this.name,
    required this.output,
    this.minLevel = LogLevel.debug,
    this.categories,
    this.enabled = true,
  });

  /// Whether an entry at [level] with the given [category] should be
  /// delivered to this sink.
  bool accepts(LogLevel level, String? category) {
    if (!enabled) return false;
    if (level.index < minLevel.index) return false;
    if (categories != null &&
        (category == null || !categories!.contains(category))) {
      return false;
    }
    return true;
  }
}
