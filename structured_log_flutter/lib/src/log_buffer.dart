import 'package:flutter/foundation.dart';
import 'package:structured_log/structured_log.dart';

/// A fixed-size, in-memory ring buffer of log entries, meant to be plugged
/// directly into `structured_log` as an [OutputFunction] (or a [LogSink]'s
/// `output`) so a UI can display a live-updating tail of recent log entries.
///
/// [LogBuffer] captures entries in the order they arrive (oldest first) and
/// keeps at most [capacity] of them — once that many have been captured,
/// adding a new entry evicts the oldest one. It is not a persistent store:
/// entries older than [capacity] captures are gone for good, and nothing is
/// written to disk. For that reason, [LogBuffer] is meant for interactive,
/// in-app inspection (e.g. a debug log viewer), not as a substitute for
/// [fileOutput]/[rotatingFileOutput] or another durable [OutputFunction].
///
/// [entries] is a [ValueListenable] that updates every time a new entry is
/// captured or the buffer is [clear]ed, so a widget can rebuild live via
/// `ValueListenableBuilder`/`AnimatedBuilder` without polling.
///
/// ```dart
/// final buffer = LogBuffer(capacity: 1000);
///
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'console', output: coloredConsoleOutput),
///   LogSink(name: 'viewer', output: buffer.capture),
/// ]);
///
/// getLogger().info('user_login', context: {'user_id': 42});
/// print(buffer.entries.value.length); // 1
/// ```
class LogBuffer {
  /// Creates an empty buffer holding at most [capacity] entries. Defaults to
  /// 500, which comfortably covers a debug session's worth of recent
  /// activity without unbounded memory growth.
  LogBuffer({this.capacity = 500}) : assert(capacity > 0);

  /// The maximum number of entries this buffer holds at once. Capturing
  /// beyond this count evicts the oldest entry first.
  final int capacity;

  final ValueNotifier<List<Map<String, dynamic>>> _entries =
      ValueNotifier(const []);

  /// The entries currently held, oldest first, as a [ValueListenable].
  ///
  /// The list itself is never mutated in place — each capture or [clear]
  /// publishes a new list — so it's safe to read [ValueListenable.value]
  /// and hold onto the reference (e.g. to diff against a later read).
  ValueListenable<List<Map<String, dynamic>>> get entries => _entries;

  /// Captures [entry] into the buffer, evicting the oldest entry first if
  /// [capacity] is exceeded. [level] is accepted (and ignored) only to
  /// match the [OutputFunction] signature required to plug this in as a
  /// sink's `output` directly — see the class-level example.
  void capture(Map<String, dynamic> entry, LogLevel level) {
    final next = List<Map<String, dynamic>>.of(_entries.value)..add(entry);
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    _entries.value = next;
  }

  /// Removes every captured entry. [entries] updates to an empty list and
  /// notifies its listeners.
  void clear() {
    _entries.value = const [];
  }
}
