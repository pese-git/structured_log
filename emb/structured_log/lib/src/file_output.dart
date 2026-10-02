import 'dart:convert';
import 'dart:io';

import 'encoding.dart';
import 'logger.dart';
import 'processors.dart';

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
      '${encodeLogEntry(entry)}\n',
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
/// The size is read from the file once, when the output is created, and
/// counted in memory from then on (in bytes, as written): the file system
/// is not asked on every write. A file shortened or removed by someone else
/// in the meantime is not noticed until the next rotation — which then
/// comes early or late by that much, and loses nothing.
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

  var size = file.existsSync() ? file.lengthSync() : 0;

  return (Map<String, dynamic> entry, LogLevel level) {
    if (size >= maxSizeBytes) {
      rotate();
      size = 0;
    }
    final bytes = utf8.encode('${encodeLogEntry(entry)}\n');
    file.writeAsBytesSync(bytes, mode: FileMode.append);
    size += bytes.length;
  };
}
