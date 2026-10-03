import 'configuration.dart';
import 'correlation.dart';
import 'encoding.dart';
import 'report.dart';
import 'sink.dart';
import 'timestamp.dart';

/// Log levels, from least to most severe. `trace` sits below `debug` and is
/// filtered out by a sink's default `minLevel` (`LogLevel.debug`) unless a
/// sink explicitly lowers it — useful for high-volume detail (e.g. raw
/// protocol frames) that should stay off unless deliberately enabled.
///
/// Each level has a matching convenience method on [BoundLogger]
/// ([BoundLogger.trace], [BoundLogger.debug], [BoundLogger.info],
/// [BoundLogger.warning], [BoundLogger.error], [BoundLogger.critical]):
///
/// ```dart
/// final log = getLogger();
/// log.trace('raw_frame', context: {'bytes': 128}); // usually filtered out
/// log.debug('cache_miss', context: {'key': 'user:42'});
/// log.info('user_login', context: {'user_id': 42});
/// log.warning('slow_query', context: {'duration_ms': 1500});
/// log.error('payment_failed', context: {'error': 'timeout'});
/// log.critical('out_of_memory');
/// ```
enum LogLevel { trace, debug, info, warning, error, critical }

/// A structured logger that carries bound context and delivers entries to
/// the sinks configured in [StructlogConfiguration].
///
/// Instances are immutable: [bind], [unbind], and [withCorrelation] never
/// mutate the receiver — each returns a new [BoundLogger] with the extra
/// context, so it is always safe to keep a reference to a parent logger and
/// derive child loggers from it without affecting siblings.
///
/// Obtain instances through [getLogger], not this constructor directly:
///
/// ```dart
/// import 'package:structured_log/structured_log.dart';
///
/// void main() {
///   final log = getLogger('payments');
///   log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
///
///   // Derive a child logger with extra, always-present context.
///   final requestLog = log.bind({'request_id': 'abc-123'});
///   requestLog.info('processing_request');
///   requestLog.warning('slow_query', context: {'duration_ms': 1500});
/// }
/// ```
class BoundLogger {
  final Map<String, dynamic> _context;
  final LogCorrelation? _correlation;

  /// The configuration this logger was given, or `null` for one that
  /// follows [StructlogConfiguration.current] — every logger [getLogger]
  /// returns.
  final StructlogConfiguration? _config;

  /// A logger that always uses [config], whatever
  /// [StructlogConfiguration.configure] does afterwards — for handing a
  /// logger its configuration explicitly (dependency injection, a test that
  /// must not share global state). [StructlogConfiguration.initialContext]
  /// is not merged in; [getLogger] is what does that.
  BoundLogger(
    StructlogConfiguration config, [
    Map<String, dynamic>? context,
    LogCorrelation? correlation,
  ]) : this._(config, context, correlation);

  BoundLogger._(
    this._config,
    Map<String, dynamic>? context,
    this._correlation,
  ) : _context = Map<String, dynamic>.from(context ?? {});

  StructlogConfiguration get _configuration =>
      _config ?? StructlogConfiguration.current;

  /// Returns a new [BoundLogger] with [context] merged into this logger's
  /// bound context. Keys in [context] overwrite same-named keys already
  /// bound on this logger; the receiver itself is left unchanged.
  ///
  /// ```dart
  /// final requestLog = getLogger().bind({'request_id': 'abc-123'});
  /// final userLog = requestLog.bind({'user_id': 42});
  ///
  /// userLog.info('user_action', context: {'action': 'purchase'});
  /// // -> {"request_id": "abc-123", "user_id": 42, "event": "user_action",
  /// //     "action": "purchase", ...}
  /// ```
  BoundLogger bind(Map<String, dynamic> context) {
    final newContext = Map<String, dynamic>.from(_context)..addAll(context);
    return BoundLogger._(_config, newContext, _correlation);
  }

  /// Returns a new [BoundLogger] with [keys] removed from the bound
  /// context. Keys that aren't currently bound are ignored. The receiver
  /// itself is left unchanged.
  ///
  /// ```dart
  /// final log = getLogger().bind({'request_id': 'abc-123', 'user_id': 42});
  /// final anonymized = log.unbind(['user_id']);
  ///
  /// anonymized.info('event'); // no user_id in the entry
  /// log.info('event'); // still has user_id — the original is untouched
  /// ```
  BoundLogger unbind(List<String> keys) {
    final newContext = Map<String, dynamic>.from(_context);
    for (final key in keys) {
      newContext.remove(key);
    }
    return BoundLogger._(_config, newContext, _correlation);
  }

  /// Bind typed correlation identifiers (session, request, connection,
  /// tool-call, message, operation) and return a new BoundLogger instance.
  ///
  /// Only the passed (non-null) fields are changed; unset fields are
  /// inherited from this logger's existing correlation, if any. The parent
  /// logger is left untouched. Correlation fields are serialized under
  /// fixed snake_case keys (`session_id`, `request_id`, ...) — see
  /// [LogCorrelation.toContext] — and take priority over same-named keys
  /// coming from [bind] or inline `context`.
  ///
  /// ```dart
  /// final sessionLog = getLogger().withCorrelation(
  ///   sessionId: 's-14',
  ///   requestId: 'r-42',
  /// );
  /// sessionLog.info('processing_request');
  /// // -> {"session_id": "s-14", "request_id": "r-42", ...}
  ///
  /// // Child scope: inherits sessionId/requestId, adds toolCallId.
  /// final toolLog = sessionLog.withCorrelation(toolCallId: 'tc-3');
  /// toolLog.info('tool_invoked');
  /// // -> {"session_id": "s-14", "request_id": "r-42",
  /// //     "tool_call_id": "tc-3", ...}
  /// ```
  BoundLogger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) {
    final addition = LogCorrelation(
      sessionId: sessionId,
      requestId: requestId,
      connectionGeneration: connectionGeneration,
      toolCallId: toolCallId,
      messageId: messageId,
      operationId: operationId,
    );
    final merged = (_correlation ?? const LogCorrelation()).merge(addition);
    return BoundLogger._(_config, _context, merged);
  }

  /// Whether an entry at [level] would reach at least one enabled sink —
  /// for skipping the work of building a costly entry nobody will see:
  ///
  /// ```dart
  /// if (log.isEnabled(LogLevel.trace)) {
  ///   log.trace('frame', context: {'hex': hexDump(bytes)});
  /// }
  /// ```
  ///
  /// With [category], the answer is [LogSink.accepts] for that category.
  /// Without it, the answer is about the level alone: some enabled sink's
  /// `minLevel` is at or below [level]. A sink whose `accepts` throws counts
  /// as accepting — saying "off" would hide entries it might want.
  ///
  /// [tryLog] asks the level-alone question itself, first, and returns
  /// straight away when the answer is no: the entry is never assembled and
  /// no processor runs. The category cannot be checked that early — it is
  /// only known once the context is merged.
  bool isEnabled(LogLevel level, {String? category}) {
    for (final sink in _configuration.sinks) {
      try {
        if (category == null
            ? _takesLevel(sink, level)
            : sink.accepts(level, category)) {
          return true;
        }
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  static bool _takesLevel(LogSink sink, LogLevel level) =>
      sink.enabled && level.index >= sink.minLevel.index;

  /// Logs [event] at [level] with [context] merged into the bound context.
  ///
  /// This is the level-generic entry point that [trace], [debug], [info],
  /// [warning], [error], and [critical] all delegate to; call it directly
  /// when the level is only known at runtime:
  ///
  /// ```dart
  /// LogLevel levelFor(int statusCode) =>
  ///     statusCode >= 500 ? LogLevel.error : LogLevel.info;
  ///
  /// log.tryLog(levelFor(response.statusCode), 'http_response',
  ///     context: {'status': response.statusCode});
  /// ```
  ///
  /// The merge order — from lowest to highest priority — is: this logger's
  /// bound context, then this call's [context], then typed correlation
  /// fields from [withCorrelation]. The resulting entry is passed through
  /// [StructlogConfiguration.processors]; a processor returning `null`
  /// drops the entry and no sink is called. Otherwise the entry is
  /// delivered to every [LogSink] in [StructlogConfiguration.sinks] whose
  /// [LogSink.accepts] matches.
  ///
  /// Nothing thrown inside this call reaches the caller. An exception from
  /// one sink's output is reported (to `stderr`, or through `print` on the
  /// web) and does not stop delivery to the other sinks. An exception from
  /// a processor replaces the entry with a stub — `event`, `level`,
  /// `timestamp`, `logger` and `category`, where they are strings, plus
  /// `processor_failed` naming the exception's type — and the processors
  /// after it do not run. The stub, not the entry, is what the sinks get:
  /// the processor that failed may have been the one meant to redact it.
  void tryLog(
    LogLevel level,
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    try {
      _log(level, event, context, error, stackTrace);
    } catch (error, stackTrace) {
      reportInternalError(
        'structured_log: logging "$event" threw: $error\n$stackTrace',
      );
    }
  }

  void _log(
    LogLevel level,
    String? event,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final config = _configuration;
    if (!config.sinks.any((sink) => _takesLevel(sink, level))) return;

    final mergedContext = <String, dynamic>{
      // Read now, not when the logger was made: a logger kept in a field
      // outlives the configuration it was created under.
      if (_config == null) ...config.initialContext,
      ..._context,
    };
    if (context != null) {
      mergedContext.addAll(context);
    }
    if (error != null) {
      mergedContext['error'] = describeValue(error);
      mergedContext['error_type'] = error.runtimeType.toString();
    }
    if (stackTrace != null) {
      mergedContext['stack_trace'] = stackTrace.toString();
    }
    if (_correlation != null) {
      // Typed correlation fields take priority over same-named keys coming
      // from the arbitrary Map-based context.
      mergedContext.addAll(_correlation!.toContext());
    }
    if (event != null) {
      mergedContext['event'] = event;
    }

    final entry = _processEntry(config, mergedContext, level);
    if (entry == null) return;

    final category = switch (entry['category']) {
      final String category => category,
      _ => null,
    };
    for (final sink in config.sinks) {
      try {
        if (!sink.accepts(level, category)) continue;
        sink.output(entry, level);
      } catch (error, stackTrace) {
        reportInternalError(
          'structured_log: sink "${sink.name}" threw: $error\n$stackTrace',
        );
      }
    }
  }

  Map<String, dynamic>? _processEntry(
    StructlogConfiguration config,
    Map<String, dynamic> entry,
    LogLevel level,
  ) {
    entry['level'] = level.name;
    entry['timestamp'] = formatTimestamp(DateTime.now(), config.timestampMode);

    for (final processor in config.processors) {
      final Map<String, dynamic>? result;
      try {
        result = processor(entry);
      } catch (error, stackTrace) {
        // The type only, here and in the stub: a processor's message may
        // quote the very value it was meant to hide.
        reportInternalError(
          'structured_log: a processor threw ${error.runtimeType} '
          'on "${entry['event']}"; delivering a stub instead\n$stackTrace',
        );
        return {
          ...identifyingFields(entry),
          'processor_failed': error.runtimeType.toString(),
        };
      }
      if (result == null) {
        return null;
      }
      entry = result;
    }

    return entry;
  }

  /// Logs [event] at [LogLevel.trace] — see [tryLog].
  ///
  /// Filtered out by every sink's default `minLevel` (`debug`); a sink must
  /// opt in with `minLevel: LogLevel.trace` to receive it. Use it for
  /// high-volume detail you normally want disabled, e.g.:
  ///
  /// ```dart
  /// log.trace('raw_frame', context: {'bytes': 128});
  /// ```
  void trace(
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      tryLog(
        LogLevel.trace,
        event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );

  /// Logs [event] at [LogLevel.debug] — see [tryLog].
  ///
  /// ```dart
  /// log.debug('cache_miss', context: {'key': 'user:42'});
  /// ```
  void debug(
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      tryLog(
        LogLevel.debug,
        event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );

  /// Logs [event] at [LogLevel.info] — see [tryLog].
  ///
  /// ```dart
  /// log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
  /// ```
  void info(
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      tryLog(
        LogLevel.info,
        event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );

  /// Logs [event] at [LogLevel.warning] — see [tryLog].
  ///
  /// ```dart
  /// log.warning('slow_query', context: {'duration_ms': 1500});
  /// ```
  void warning(
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      tryLog(
        LogLevel.warning,
        event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );

  /// Logs [event] at [LogLevel.error] — see [tryLog].
  ///
  /// ```dart
  /// log.error('payment_failed', context: {'error': 'timeout'});
  /// ```
  void error(
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      tryLog(
        LogLevel.error,
        event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );

  /// Logs [event] at [LogLevel.critical] — see [tryLog].
  ///
  /// ```dart
  /// log.critical('out_of_memory');
  /// ```
  void critical(
    String? event, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      tryLog(
        LogLevel.critical,
        event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );
}

/// Returns a new [BoundLogger] that follows the current global configuration
/// ([StructlogConfiguration.current]).
///
/// If [name] is given, it is bound under the `logger` context key on every
/// entry the returned logger produces — handy for telling which part of an
/// app an entry came from. [StructlogConfiguration.initialContext] is
/// merged in first, so [name] (and any later [BoundLogger.bind] or inline
/// `context`) can override an `initialContext` key of the same name.
///
/// The logger reads [StructlogConfiguration.current] — sinks, processors,
/// `initialContext` — when it makes each entry, not when it is created, so
/// one kept in a `static final` field picks up a later
/// [StructlogConfiguration.configure] or [StructlogConfiguration.reset]. So
/// does every logger derived from it with [BoundLogger.bind],
/// [BoundLogger.unbind] or [BoundLogger.withCorrelation]. To pin a logger
/// to one configuration instead, construct [BoundLogger] with it.
///
/// ```dart
/// final log = getLogger('payments'); // context: {"logger": "payments"}
/// log.info('charge_created', context: {'amount_cents': 1999});
///
/// final anonymous = getLogger(); // no "logger" key
/// anonymous.info('startup');
/// ```
BoundLogger getLogger([String? name]) =>
    BoundLogger._(null, {if (name != null) 'logger': name}, null);
