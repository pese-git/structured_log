import 'dart:convert';

import 'logger.dart';

/// A function that transforms (or drops) a log entry before it reaches any
/// sink.
///
/// Every [BoundLogger] call runs the current
/// `StructlogConfiguration.processors` list on the merged entry, in order,
/// each processor receiving the previous one's output. Returning the [entry]
/// unchanged (or a modified copy) passes it on to the next processor and,
/// eventually, to every accepting [LogSink]. Returning `null` drops the
/// entry — no processor after it runs, and no sink is called.
///
/// Processors should be pure functions of their input and not depend on
/// call order relative to other processors, unless that ordering is
/// documented (as it is for the enrich-then-render pattern below).
///
/// ```dart
/// // A custom processor that redacts a sensitive key.
/// Map<String, dynamic>? redactPassword(Map<String, dynamic> entry) {
///   if (entry.containsKey('password')) entry['password'] = '***';
///   return entry;
/// }
///
/// // A custom processor that drops noisy debug entries entirely.
/// Map<String, dynamic>? dropDebugNoise(Map<String, dynamic> entry) {
///   if (entry['level'] == 'debug' && entry['event'] == 'heartbeat') {
///     return null; // dropped — no later processor or sink sees it
///   }
///   return entry;
/// }
///
/// StructlogConfiguration.configure(
///   processors: [dropNullValues, redactPassword, dropDebugNoise],
/// );
/// ```
typedef Processor = Map<String, dynamic>? Function(Map<String, dynamic> entry);

/// A function that delivers a fully-processed log [entry] (at the given
/// [level]) to a concrete destination — stdout, a file, a test-capture
/// variable, anything.
///
/// This is the type every built-in output in this library
/// ([defaultOutput], [fileOutput], [rotatingFileOutput],
/// [coloredConsoleOutput]) and [LogSink.output] share; write your own to
/// integrate with a destination this package doesn't cover directly:
///
/// ```dart
/// // Send every entry to an in-memory list (handy in tests).
/// final captured = <Map<String, dynamic>>[];
/// OutputFunction captureOutput = (entry, level) => captured.add(entry);
///
/// StructlogConfiguration.configure(output: captureOutput);
/// getLogger().info('event');
/// print(captured.single['event']); // 'event'
/// ```
typedef OutputFunction = void Function(
    Map<String, dynamic> entry, LogLevel level);

/// Adds an ISO-8601 `timestamp` to [entry] if it doesn't already have one.
///
/// Not needed in the default pipeline — [BoundLogger.tryLog] already stamps
/// every entry with `timestamp` before running processors — but useful as
/// a building block for custom processor pipelines that construct entries
/// another way.
///
/// ```dart
/// final entry = <String, dynamic>{'event': 'custom'};
/// addTimestamp(entry);
/// print(entry['timestamp']); // e.g. '2026-09-10T12:00:00.000'
/// ```
Map<String, dynamic>? addTimestamp(Map<String, dynamic> entry) {
  if (!entry.containsKey('timestamp')) {
    entry['timestamp'] = DateTime.now().toIso8601String();
  }
  return entry;
}

/// A no-op processor kept for pipelines that want to document, in the
/// `processors:` list itself, that the entry's `level` key is expected to
/// already be present (as it always is — [BoundLogger.tryLog] sets it
/// before any processor runs) rather than to actually add it.
///
/// ```dart
/// StructlogConfiguration.configure(
///   processors: [dropNullValues, addLogLevel], // addLogLevel is a no-op
/// );
/// ```
Map<String, dynamic>? addLogLevel(Map<String, dynamic> entry) {
  return entry;
}

/// Prints [entry] as a single-line JSON string via [print] and returns it
/// unchanged, so it can be chained with other processors or reach a sink
/// afterwards.
///
/// ```dart
/// jsonRenderer({'event': 'startup', 'pid': 123});
/// // stdout: {"event":"startup","pid":123}
/// ```
Map<String, dynamic>? jsonRenderer(Map<String, dynamic> entry) {
  print(jsonEncode(entry));
  return entry;
}

/// Prints [entry] as space-separated `key=value` pairs (logfmt style) via
/// [print] and returns it unchanged. String values are wrapped in double
/// quotes; other values use their `toString()`.
///
/// ```dart
/// logfmtRenderer({'event': 'startup', 'pid': 123});
/// // stdout: event="startup" pid=123
/// ```
Map<String, dynamic>? logfmtRenderer(Map<String, dynamic> entry) {
  final pairs = entry.entries.map((e) {
    final value = e.value is String ? '"${e.value}"' : e.value.toString();
    return '${e.key}=$value';
  }).join(' ');
  print(pairs);
  return entry;
}

/// Removes every key in [entry] whose value is `null`, in place, and
/// returns the same map. This is the default (and only default) processor
/// in `StructlogConfiguration.processors` — it keeps entries with optional,
/// unset context fields (e.g. `context: {'user_id': maybeNull}`) free of
/// noisy `null` keys in the rendered output.
///
/// ```dart
/// final entry = {'event': 'login', 'user_id': 42, 'session': null};
/// dropNullValues(entry);
/// print(entry); // {event: login, user_id: 42}
/// ```
Map<String, dynamic>? dropNullValues(Map<String, dynamic> entry) {
  entry.removeWhere((key, value) => value == null);
  return entry;
}
