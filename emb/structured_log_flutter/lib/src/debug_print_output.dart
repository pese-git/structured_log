import 'package:flutter/foundation.dart';
import 'package:structured_log/structured_log.dart';

/// An [OutputFunction] for a phone's console: one line per entry through
/// [debugPrint], with no ANSI colours — the time, the level, the `event`, and
/// every other field as escaped `key=value` pairs:
///
/// ```text
/// 12:30:15.250 INFO login user="u" attempt=2
/// ```
///
/// `defaultOutput` pretty-prints JSON across many lines, which logcat and
/// the Xcode console interleave with everything else, and
/// `coloredConsoleOutput`'s escape codes show up in the iOS console as
/// noise. Here a value holding a newline or an escape sequence is written
/// escaped, as `formatLogfmt` writes it, so an entry stays on its line.
/// [debugPrint] throttles a burst so Android does not drop lines; it does
/// not shorten one, and logcat cuts a line past about 4 KB.
///
/// The time is the entry's `timestamp` in the device's local time, to the
/// millisecond; an entry without one that parses is written without it.
///
/// ```dart
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'console', output: debugPrintOutput),
/// ]);
/// ```
void debugPrintOutput(Map<String, dynamic> entry, LogLevel level) {
  final rest = Map<String, dynamic>.of(entry)
    ..remove('event')
    ..remove('level')
    ..remove('timestamp');
  final event = entry['event'];
  debugPrint([
    if (_timeOf(entry['timestamp']) case final time?) time,
    level.name.toUpperCase(),
    if (event != null) _eventText(event),
    if (rest.isNotEmpty) formatLogfmt(rest),
  ].join(' '));
}

String? _timeOf(Object? timestamp) {
  if (timestamp is! String) return null;
  final parsed = DateTime.tryParse(timestamp);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.'
      '${local.millisecond.toString().padLeft(3, '0')}';
}

final _bareWord = RegExp(r'^[A-Za-z0-9_.:/-]+$');

/// An event name as it is, when it is a plain word; quoted and escaped, as
/// any logfmt value, when it is not.
String _eventText(Object event) {
  if (event is String && _bareWord.hasMatch(event)) return event;
  // formatLogfmt writes `_=<value>`; the value is what is wanted here.
  return formatLogfmt({'_': event}).substring(2);
}
