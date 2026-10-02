import 'encoding.dart';
import 'logger.dart';
import 'processors.dart';

/// Prints [entry] to stdout as indented (pretty-printed) JSON. This is the
/// library's default output — used by `StructlogConfiguration()` /
/// `StructlogConfiguration.reset()` when no `output`/`sinks` is given.
///
/// ```dart
/// defaultOutput({'event': 'startup', 'pid': 123}, LogLevel.info);
/// // stdout:
/// // {
/// //   "event": "startup",
/// //   "pid": 123
/// // }
/// ```
void defaultOutput(Map<String, dynamic> entry, LogLevel level) {
  print(encodeLogEntry(entry, indent: '  '));
}

/// Prints [entry] to stdout as one human-readable, ANSI-colored line: a
/// color keyed to [level] (grey for trace, cyan debug, green info, yellow
/// warning, red error, magenta critical), the timestamp, the level name,
/// the `event`, and any remaining context as a trailing JSON object.
/// Intended for local development consoles rather than machine parsing —
/// use [jsonLineOutput], or `fileOutput` from `package:structured_log/io.dart`,
/// for that.
///
/// ```dart
/// StructlogConfiguration.configure(output: coloredConsoleOutput);
///
/// getLogger().warning('slow_query', context: {'duration_ms': 1500});
/// // stdout (yellow): [2026-09-10T12:00:00.000] WARNING: slow_query {"duration_ms":1500}
/// ```
void coloredConsoleOutput(Map<String, dynamic> entry, LogLevel level) {
  final event = entry['event'] ?? '';
  final context = Map<String, dynamic>.from(entry)
    ..remove('event')
    ..remove('level')
    ..remove('timestamp');

  String colorCode;
  switch (level) {
    case LogLevel.trace:
      colorCode = '\x1B[90m'; // grey
      break;
    case LogLevel.debug:
      colorCode = '\x1B[36m'; // cyan
      break;
    case LogLevel.info:
      colorCode = '\x1B[32m'; // green
      break;
    case LogLevel.warning:
      colorCode = '\x1B[33m'; // yellow
      break;
    case LogLevel.error:
      colorCode = '\x1B[31m'; // red
      break;
    case LogLevel.critical:
      colorCode = '\x1B[35m'; // magenta
      break;
  }

  const reset = '\x1B[0m';
  final timestamp = entry['timestamp'] ?? '';
  final contextStr = context.isNotEmpty ? ' ${encodeLogEntry(context)}' : '';

  print(
      '$colorCode[$timestamp] ${level.name.toUpperCase()}: $event$reset$contextStr');
}

/// Prints [entry] to stdout as one line of JSON — the output form of what
/// the deprecated [jsonRenderer] processor did from inside the processor
/// chain.
///
/// As a sink's output it runs after every processor, so a redactor can no
/// longer be placed after it by mistake, and it does not print an entry
/// that a later processor drops. Values `jsonEncode` refuses are converted
/// as [encodeLogEntry] describes.
///
/// ```dart
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'stdout', output: jsonLineOutput),
/// ]);
/// getLogger().info('startup', context: {'pid': 123});
/// // {"pid":123,"event":"startup","level":"info","timestamp":"..."}
/// ```
void jsonLineOutput(Map<String, dynamic> entry, LogLevel level) =>
    print(encodeLogEntry(entry));

/// Prints [entry] to stdout as one logfmt line — see [formatLogfmt]. The
/// output form of the deprecated [logfmtRenderer] processor.
///
/// ```dart
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'stdout', output: logfmtOutput),
/// ]);
/// getLogger().info('startup', context: {'pid': 123});
/// // pid=123 event="startup" level="info" timestamp="..."
/// ```
void logfmtOutput(Map<String, dynamic> entry, LogLevel level) =>
    print(formatLogfmt(entry));

/// [entry] as one logfmt line: space-separated `key=value` pairs, in the
/// entry's order.
///
/// Whatever the entry holds, the result is a single line whose fields are
/// exactly the entry's keys — a value written by a user cannot add a field
/// or start a new line:
///
/// - numbers, booleans and `null` are written bare;
/// - everything else is written as a double-quoted string, with `\`, `"`,
///   newline, carriage return and tab escaped as `\\`, `\"`, `\n`, `\r`,
///   `\t`, and every other control character (and U+2028/U+2029, which some
///   viewers break lines on) as `\uXXXX`. Maps and lists are written as
///   their JSON; other values as [encodeLogEntry] converts them, so a
///   `DateTime` is ISO-8601 in UTC and a `Duration` its microseconds;
/// - a key keeps its letters, digits, `_`, `.` and `-`; anything else
///   becomes `_`, and an empty key is written `_`.
///
/// ```dart
/// formatLogfmt({'event': 'login', 'user': 'a" admin=true'});
/// // event="login" user="a\" admin=true"
/// ```
String formatLogfmt(Map<String, dynamic> entry) => [
      for (final MapEntry(:key, :value) in entry.entries)
        '${_logfmtKey(key)}=${_logfmtValue(value)}',
    ].join(' ');

final _unsafeKeyCharacter = RegExp(r'[^A-Za-z0-9_.\-]');

String _logfmtKey(String key) =>
    key.isEmpty ? '_' : key.replaceAll(_unsafeKeyCharacter, '_');

String _logfmtValue(Object? value) {
  final converted = switch (value) {
    null || num() || bool() || String() => value,
    Map() || List() => encodeValue(value),
    _ => toEncodableValue(value),
  };
  return converted is String ? _quote(converted) : '$converted';
}

String _quote(String text) {
  final out = StringBuffer('"');
  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x5C:
        out.write(r'\\');
      case 0x22:
        out.write(r'\"');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case < 0x20 || 0x7F || 0x2028 || 0x2029:
        out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      default:
        out.writeCharCode(unit);
    }
  }
  out.write('"');
  return out.toString();
}
