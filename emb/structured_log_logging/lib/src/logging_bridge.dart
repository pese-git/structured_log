import 'dart:async';

import 'package:logging/logging.dart';
import 'package:structured_log/structured_log.dart';

/// Maps a `package:logging` [Level] to the [LogLevel] its records are
/// written at; `null` leaves records of that level out.
typedef LogLevelOf = LogLevel? Function(Level level);

/// The default [LogLevelOf]: by [Level.value], so a custom level such as
/// `Level('NOTICE', 850)` lands somewhere sensible too.
///
/// | `Level.value` | [LogLevel] | Standard levels |
/// |---|---|---|
/// | below 500 | [LogLevel.trace] | `FINEST`, `FINER` |
/// | 500–699 | [LogLevel.debug] | `FINE` |
/// | 700–899 | [LogLevel.info] | `CONFIG`, `INFO` |
/// | 900–999 | [LogLevel.warning] | `WARNING` |
/// | 1000–1199 | [LogLevel.error] | `SEVERE` |
/// | 1200 and up | [LogLevel.critical] | `SHOUT` |
///
/// `CONFIG` goes to `info` rather than `debug`: libraries write one-off
/// startup configuration with it, which is expected to show at `info`.
LogLevel defaultLogLevelOf(Level level) => switch (level.value) {
      < 500 => LogLevel.trace,
      < 700 => LogLevel.debug,
      < 900 => LogLevel.info,
      < 1000 => LogLevel.warning,
      < 1200 => LogLevel.error,
      _ => LogLevel.critical,
    };

/// Writes every record published by a `package:logging` [Logger] as a
/// `structured_log` entry.
///
/// ```dart
/// Logger.root.level = Level.ALL; // package:logging's own gate, see below
/// StructuredLogLoggingBridge().attach();
/// ```
///
/// Each [LogRecord] becomes one entry: its message is the `event`, its
/// logger's name the `logger` (`root` for the root logger), and its error
/// and stack trace become `error`, `error_type` and `stack_trace` exactly as
/// with `BoundLogger.error`. Every entry carries [category] (`logging` by
/// default), so a sink can take — or leave — everything that came from
/// other libraries.
///
/// The bridge never changes `package:logging`'s levels. `Logger.root`
/// passes `INFO` and above by default, and a record below that is never
/// created, so it never reaches the bridge either; set `Logger.root.level`
/// yourself if you want `FINE` and below.
///
/// The record's `object` is not written — its `toString()` is already the
/// message — and neither are its `time`, `sequenceNumber` or `zone`: pass
/// [context] to add fields from a record, such as a request id kept in its
/// zone.
class StructuredLogLoggingBridge {
  /// Creates the bridge; nothing is written until [attach].
  ///
  /// [source] is the logger whose records are bridged, `Logger.root` by
  /// default. Another logger only makes a difference with
  /// `hierarchicalLoggingEnabled`: without it, every logger's records are
  /// published on the root's stream.
  StructuredLogLoggingBridge({
    Logger? source,
    this.levelOf = defaultLogLevelOf,
    this.filter,
    this.category = 'logging',
    this.context,
  }) : source = source ?? Logger.root;

  /// The logger whose records are bridged.
  final Logger source;

  /// The level each record is written at; see [defaultLogLevelOf].
  final LogLevelOf levelOf;

  /// When given, only records for which it returns `true` are written.
  final bool Function(LogRecord record)? filter;

  /// The `category` of every entry; `null` writes none.
  final String? category;

  /// When given, the fields it returns are added to the record's entry.
  final Map<String, Object?>? Function(LogRecord record)? context;

  StreamSubscription<LogRecord>? _subscription;

  /// Whether records are being bridged.
  bool get isAttached => _subscription != null;

  /// Starts bridging [source]'s records. Calling it again while attached
  /// does nothing, so records are never written twice.
  void attach() {
    _subscription ??= source.onRecord.listen(_onRecord);
  }

  /// Stops bridging; [attach] starts again.
  void detach() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Runs inside the caller's `Logger.log`, since `package:logging`
  /// publishes synchronously — so it must never throw: an exception would
  /// not reach that call but the zone the bridge was attached in, as an
  /// uncaught error.
  ///
  /// It cannot recurse either. While it runs, `package:logging`'s stream is
  /// still firing this record, and the stream refuses another: a sink that
  /// logs through `package:logging` gets a `StateError` from that call
  /// instead of re-entering here.
  void _onRecord(LogRecord record) {
    try {
      _deliver(record);
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
    }
  }

  void _deliver(LogRecord record) {
    // The callbacks do not redact anything — that is what processors are
    // for — so one that throws costs the entry its type in `bridge_failed`,
    // not the entry. Only the type: an exception's message may quote a
    // value.
    String? failed;

    if (filter != null) {
      try {
        if (!filter!(record)) return;
      } catch (error) {
        failed = error.runtimeType.toString();
      }
    }

    LogLevel? mapped;
    var mappingFailed = false;
    try {
      mapped = levelOf(record.level);
    } catch (error) {
      failed ??= error.runtimeType.toString();
      mappingFailed = true;
    }
    if (mapped == null && !mappingFailed) return;
    final level = mapped ?? defaultLogLevelOf(record.level);

    Map<String, Object?>? extra;
    if (context != null) {
      try {
        extra = context!(record);
      } catch (error) {
        failed ??= error.runtimeType.toString();
      }
    }

    final name = record.loggerName;
    getLogger(name.isEmpty ? 'root' : name).tryLog(
      level,
      record.message,
      context: {
        ...?extra,
        if (category != null) 'category': category,
        if (failed != null) 'bridge_failed': failed,
      },
      error: _isAutogenerated(record) ? null : record.error,
      stackTrace: record.stackTrace,
    );
  }

  /// Whether [record]'s error is the placeholder `package:logging` puts in
  /// when it adds a stack trace of its own (`recordStackTraceAtLevel`).
  ///
  /// Compared in full rather than by its prefix, so a real error that
  /// happens to start the same way is still written.
  static bool _isAutogenerated(LogRecord record) =>
      record.error is String &&
      record.error ==
          'autogenerated stack trace for ${record.level} ${record.message}';
}
