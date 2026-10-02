import 'dart:async';
import 'dart:collection';

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
/// the file outputs of `package:structured_log/io.dart` or another durable
/// [OutputFunction].
///
/// [entries] is a [ValueListenable], so a widget can rebuild live via
/// `ValueListenableBuilder`/`AnimatedBuilder` without polling. Its value is
/// always current, but its listeners are told at most once per turn of the
/// event loop: a burst of entries logged in one go — a request's worth, a
/// tight loop — is one notification and one rebuild, not one per entry.
/// [clear] notifies at once.
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

  final _BufferedEntries _entries = _BufferedEntries();

  /// The entries currently held, oldest first, as a [ValueListenable].
  ///
  /// The list is unmodifiable and never changes once read — a capture or
  /// [clear] makes the next read a new list — so it's safe to hold onto a
  /// reference (e.g. to diff against a later read). Reading it twice with no
  /// capture in between gives the same list: it is copied once per change
  /// that is read, not once per entry.
  ValueListenable<List<Map<String, dynamic>>> get entries => _entries;

  /// Captures [entry] into the buffer, evicting the oldest entry first if
  /// [capacity] is exceeded. [level] is accepted (and ignored) only to
  /// match the [OutputFunction] signature required to plug this in as a
  /// sink's `output` directly — see the class-level example.
  void capture(Map<String, dynamic> entry, LogLevel level) =>
      _entries.add(entry, capacity);

  /// Removes every captured entry. [entries] updates to an empty list and
  /// notifies its listeners.
  void clear() => _entries.clear();
}

/// The entries behind [LogBuffer.entries]: a queue that evicts from the
/// front, an unmodifiable snapshot made when it is read, and one
/// notification per burst.
class _BufferedEntries extends ChangeNotifier
    implements ValueListenable<List<Map<String, dynamic>>> {
  final ListQueue<Map<String, dynamic>> _queue = ListQueue();

  /// `null` once the queue has changed since the last read.
  List<Map<String, dynamic>>? _snapshot = const [];

  bool _notificationPending = false;

  @override
  List<Map<String, dynamic>> get value =>
      _snapshot ??= List.unmodifiable(_queue);

  void add(Map<String, dynamic> entry, int capacity) {
    _queue.addLast(entry);
    while (_queue.length > capacity) {
      _queue.removeFirst();
    }
    _snapshot = null;
    if (_notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      // Cleared in the meantime, and told then.
      if (!_notificationPending) return;
      _notificationPending = false;
      notifyListeners();
    });
  }

  void clear() {
    _queue.clear();
    _snapshot = const [];
    _notificationPending = false;
    notifyListeners();
  }
}
