import 'dart:io';

import 'configuration.dart';
import 'correlation.dart';

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
  final StructlogConfiguration _config;

  BoundLogger(
    this._config, [
    Map<String, dynamic>? context,
    LogCorrelation? correlation,
  ])  : _context = Map<String, dynamic>.from(context ?? {}),
        _correlation = correlation;

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
    return BoundLogger(_config, newContext, _correlation);
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
    return BoundLogger(_config, newContext, _correlation);
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
    return BoundLogger(_config, _context, merged);
  }

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
  /// [LogSink.accepts] matches. An exception thrown by one sink's output
  /// function is caught and reported to `stderr` — it does not stop
  /// delivery to the other sinks and never propagates to the caller, so a
  /// broken sink can never crash the logging call site.
  void tryLog(
    LogLevel level,
    String? event, {
    Map<String, dynamic>? context,
  }) {
    final mergedContext = Map<String, dynamic>.from(_context);
    if (context != null) {
      mergedContext.addAll(context);
    }
    if (_correlation != null) {
      // Typed correlation fields take priority over same-named keys coming
      // from the arbitrary Map-based context.
      mergedContext.addAll(_correlation!.toContext());
    }
    if (event != null) {
      mergedContext['event'] = event;
    }

    final entry = _processEntry(mergedContext, level);
    if (entry != null) {
      final category = entry['category'] as String?;
      for (final sink in _config.sinks) {
        if (!sink.accepts(level, category)) continue;
        try {
          sink.output(entry, level);
        } catch (error, stackTrace) {
          stderr.writeln(
            'structured_log: sink "${sink.name}" threw: $error\n$stackTrace',
          );
        }
      }
    }
  }

  Map<String, dynamic>? _processEntry(
    Map<String, dynamic> entry,
    LogLevel level,
  ) {
    entry['level'] = level.name;
    entry['timestamp'] = DateTime.now().toIso8601String();

    for (final processor in _config.processors) {
      final result = processor(entry);
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
  void trace(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.trace, event, context: context);

  /// Logs [event] at [LogLevel.debug] — see [tryLog].
  ///
  /// ```dart
  /// log.debug('cache_miss', context: {'key': 'user:42'});
  /// ```
  void debug(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.debug, event, context: context);

  /// Logs [event] at [LogLevel.info] — see [tryLog].
  ///
  /// ```dart
  /// log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
  /// ```
  void info(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.info, event, context: context);

  /// Logs [event] at [LogLevel.warning] — see [tryLog].
  ///
  /// ```dart
  /// log.warning('slow_query', context: {'duration_ms': 1500});
  /// ```
  void warning(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.warning, event, context: context);

  /// Logs [event] at [LogLevel.error] — see [tryLog].
  ///
  /// ```dart
  /// log.error('payment_failed', context: {'error': 'timeout'});
  /// ```
  void error(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.error, event, context: context);

  /// Logs [event] at [LogLevel.critical] — see [tryLog].
  ///
  /// ```dart
  /// log.critical('out_of_memory');
  /// ```
  void critical(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.critical, event, context: context);
}

/// Returns a new [BoundLogger] bound to the current global configuration
/// ([StructlogConfiguration.current]).
///
/// If [name] is given, it is bound under the `logger` context key on every
/// entry the returned logger produces — handy for telling which part of an
/// app an entry came from. [StructlogConfiguration.initialContext] is
/// merged in first, so [name] (and any later [BoundLogger.bind] or inline
/// `context`) can override an `initialContext` key of the same name.
///
/// Because [BoundLogger] reads the configuration once, at construction
/// time, call [getLogger] again after
/// [StructlogConfiguration.configure]/[StructlogConfiguration.reset] to
/// pick up the new settings — reusing an old instance keeps talking to the
/// configuration it was created with.
///
/// ```dart
/// final log = getLogger('payments'); // context: {"logger": "payments"}
/// log.info('charge_created', context: {'amount_cents': 1999});
///
/// final anonymous = getLogger(); // no "logger" key
/// anonymous.info('startup');
/// ```
BoundLogger getLogger([String? name]) {
  final config = StructlogConfiguration.current;
  final context = Map<String, dynamic>.from(config.initialContext);
  if (name != null) {
    context['logger'] = name;
  }
  return BoundLogger(config, context);
}
