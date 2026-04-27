import 'dart:convert';

import 'configuration.dart';
import 'processors.dart';

/// Log levels
enum LogLevel { debug, info, warning, error, critical }

/// A structured logger that binds context to log entries.
class BoundLogger {
  final Map<String, dynamic> _context;
  final StructlogConfiguration _config;

  BoundLogger(this._config, [Map<String, dynamic>? context])
      : _context = Map<String, dynamic>.from(context ?? {});

  /// Bind new context and return a new BoundLogger instance
  BoundLogger bind(Map<String, dynamic> context) {
    final newContext = Map<String, dynamic>.from(_context)..addAll(context);
    return BoundLogger(_config, newContext);
  }

  /// Unbind (remove) keys from context
  BoundLogger unbind(List<String> keys) {
    final newContext = Map<String, dynamic>.from(_context);
    for (final key in keys) {
      newContext.remove(key);
    }
    return BoundLogger(_config, newContext);
  }

  /// Try to log a message
  void tryLog(
    LogLevel level,
    String? event, {
    Map<String, dynamic>? context,
  }) {
    final mergedContext = Map<String, dynamic>.from(_context);
    if (context != null) {
      mergedContext.addAll(context);
    }
    if (event != null) {
      mergedContext['event'] = event;
    }

    final entry = _processEntry(mergedContext, level);
    if (entry != null) {
      _config.output(entry, level);
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

  void debug(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.debug, event, context: context);

  void info(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.info, event, context: context);

  void warning(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.warning, event, context: context);

  void error(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.error, event, context: context);

  void critical(String? event, {Map<String, dynamic>? context}) =>
      tryLog(LogLevel.critical, event, context: context);
}

/// Get a logger instance
BoundLogger getLogger([String? name]) {
  final config = StructlogConfiguration.current;
  final context = <String, dynamic>{};
  if (name != null) {
    context['logger'] = name;
  }
  return BoundLogger(config, context);
}
