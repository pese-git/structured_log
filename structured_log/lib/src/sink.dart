import 'logger.dart';
import 'processors.dart';

/// A single log output destination with its own level/category filtering.
///
/// A [BoundLogger] delivers each entry to every enabled sink whose filters
/// accept it — the caller doesn't need to know how many sinks exist.
/// Configure the active sinks via `StructlogConfiguration.configure(sinks:
/// [...])`.
///
/// ```dart
/// StructlogConfiguration.configure(sinks: [
///   // Everything goes to the console.
///   LogSink(name: 'console', output: coloredConsoleOutput),
///   // Only entries tagged category: 'protocol' also go to this file.
///   LogSink(
///     name: 'protocol',
///     output: fileOutput('logs/protocol.log'),
///     categories: {'protocol'},
///   ),
///   // Only warning and above go to this file, regardless of category.
///   LogSink(
///     name: 'alerts',
///     output: fileOutput('logs/alerts.log'),
///     minLevel: LogLevel.warning,
///   ),
/// ]);
///
/// final log = getLogger();
/// log.info('app_event'); // console only
/// log.debug('raw_frame', context: {'category': 'protocol'}); // console + protocol.log
/// log.error('payment_failed'); // console + alerts.log
///
/// // Toggle a sink off at runtime without rebuilding the configuration.
/// StructlogConfiguration.setSinkEnabled('protocol', enabled: false);
/// ```
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
  /// delivered to this sink: `false` if the sink is [enabled] `== false`,
  /// if [level] is below [minLevel], or if [categories] is non-null and
  /// doesn't contain [category] (including when [category] is `null`).
  /// Called by [BoundLogger.tryLog] once per sink for every log call — you
  /// normally don't need to call this yourself.
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
