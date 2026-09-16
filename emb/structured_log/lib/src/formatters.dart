import 'dart:convert';
import 'dart:io';

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
  final encoder = JsonEncoder.withIndent('  ');
  print(encoder.convert(entry));
}

/// Returns an [OutputFunction] that appends each entry as a single-line
/// JSON object to the file at [filePath], synchronously. The file (and any
/// missing parent directories) is created on first write if it doesn't
/// exist; existing content is preserved and new lines are appended.
///
/// Writing is blocking (`File.writeAsStringSync`) — for high-throughput
/// logging where that matters, prefer [AsyncFileOutput].
///
/// ```dart
/// StructlogConfiguration.configure(output: fileOutput('logs/app.log'));
///
/// final log = getLogger();
/// log.info('user_login', context: {'user_id': 42});
/// // appends one line to logs/app.log:
/// // {"event":"user_login","user_id":42,"level":"info","timestamp":"..."}
/// ```
OutputFunction fileOutput(String filePath) {
  final file = File(filePath);
  final dir = file.parent;
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return (Map<String, dynamic> entry, LogLevel level) {
    file.writeAsStringSync(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  };
}

/// Returns an [OutputFunction] like [fileOutput], but rotates the file once
/// it reaches [maxSizeBytes]: before a write that would exceed the limit,
/// the current file is renamed to `<filePath>.0`, any existing `.0`
/// becomes `.1`, and so on up to `.{maxBackups - 1}` — the oldest backup
/// beyond that is deleted. A fresh file at [filePath] is then created for
/// the new entry. Writing (and rotation) is synchronous; for a non-blocking
/// version see [AsyncRotatingFileOutput].
///
/// ```dart
/// StructlogConfiguration.configure(
///   output: rotatingFileOutput(
///     'logs/app.log',
///     maxSizeBytes: 1024 * 1024, // 1 MB per file
///     maxBackups: 5, // keep app.log.0 .. app.log.4
///   ),
/// );
///
/// final log = getLogger();
/// for (var i = 0; i < 100000; i++) {
///   log.info('iteration', context: {'i': i});
/// }
/// // logs/app.log holds the newest entries; logs/app.log.0, .1, ...
/// // hold progressively older ones, oldest discarded past maxBackups.
/// ```
OutputFunction rotatingFileOutput(
  String filePath, {
  int maxSizeBytes = 10 * 1024 * 1024, // 10MB default
  int maxBackups = 5,
}) {
  final file = File(filePath);
  final dir = file.parent;
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  void rotate() {
    // Delete oldest backup
    final oldest = File('$filePath.${maxBackups - 1}');
    if (oldest.existsSync()) {
      oldest.deleteSync();
    }
    // Shift backups
    for (var i = maxBackups - 2; i >= 0; i--) {
      final src = File('$filePath.$i');
      final dst = File('$filePath.${i + 1}');
      if (src.existsSync()) {
        src.renameSync(dst.path);
      }
    }
    // Move current to .0
    if (file.existsSync()) {
      file.renameSync('$filePath.0');
    }
  }

  return (Map<String, dynamic> entry, LogLevel level) {
    if (file.existsSync() && file.lengthSync() >= maxSizeBytes) {
      rotate();
    }
    file.writeAsStringSync(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  };
}

/// Prints [entry] to stdout as one human-readable, ANSI-colored line: a
/// color keyed to [level] (grey for trace, cyan debug, green info, yellow
/// warning, red error, magenta critical), the timestamp, the level name,
/// the `event`, and any remaining context as a trailing JSON object.
/// Intended for local development consoles rather than machine parsing —
/// pipe entries to [jsonRenderer] or [fileOutput] for that.
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
  final contextStr = context.isNotEmpty ? ' ${jsonEncode(context)}' : '';

  print(
      '$colorCode[$timestamp] ${level.name.toUpperCase()}: $event$reset$contextStr');
}
