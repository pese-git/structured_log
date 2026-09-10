import 'dart:convert';
import 'dart:io';

import 'logger.dart';

/// Serializes writes through a chained [Future] so overlapping async calls
/// never race on the same destination, and isolates each write's failure so
/// one bad write never stops the ones queued after it.
///
/// Catching the error on every step (not once on the whole chain) matters:
/// `Future.then` without a matching `onError` skips its callback and
/// forwards the error, so an uncaught failure on one write would silently
/// stop every write queued afterwards.
abstract class _SerializedAsyncOutput {
  Future<void> _queue = Future.value();

  String get _diagnosticLabel;

  Future<void> _write(Map<String, dynamic> entry, LogLevel level);

  /// Completes once every write enqueued so far has finished — either
  /// successfully or after being caught and reported. Await this in tests,
  /// or before process exit, to know all writes have landed.
  Future<void> get flushed => _queue;

  void call(Map<String, dynamic> entry, LogLevel level) {
    _queue = _queue.then((_) => _write(entry, level)).catchError(
      (Object error, StackTrace stackTrace) {
        stderr.writeln(
          'structured_log: $_diagnosticLabel threw: $error\n$stackTrace',
        );
      },
    );
  }
}

/// Non-blocking file output: appends JSON lines to a file without blocking
/// the calling isolate. Writes are serialized and delivered in order; a
/// failing write is caught and reported to stderr without affecting later
/// writes. Directories are created eagerly (synchronously) at construction.
///
/// Prefer this over [fileOutput] for high-throughput logging, where
/// blocking on disk I/O for every call would be wasteful. Keep a reference
/// to the instance (rather than only passing it as `output:`) so you can
/// `await` [flushed] — e.g. in tests, or right before your process exits,
/// to make sure every queued write has actually landed on disk.
///
/// ```dart
/// final asyncOutput = AsyncFileOutput('logs/async.log');
/// StructlogConfiguration.configure(output: asyncOutput);
///
/// final log = getLogger();
/// log.info('async_event_1');
/// log.info('async_event_2');
///
/// // Without this, the process could exit before the writes land.
/// await asyncOutput.flushed;
/// ```
class AsyncFileOutput extends _SerializedAsyncOutput {
  final String filePath;
  final File _file;

  AsyncFileOutput(this.filePath) : _file = File(filePath) {
    final dir = _file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  @override
  String get _diagnosticLabel => 'async file output "$filePath"';

  @override
  Future<void> _write(Map<String, dynamic> entry, LogLevel level) {
    return _file.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  }
}

/// Non-blocking file output with rotation: like [AsyncFileOutput], but
/// rotates to `.0`, `.1`, ... `.{maxBackups - 1}` once the file exceeds
/// [maxSizeBytes]. The size check, rotation, and write are all serialized
/// through the same write queue, so they never race with themselves.
///
/// The non-blocking counterpart of [rotatingFileOutput]; see
/// [AsyncFileOutput] for why and how to use [flushed].
///
/// ```dart
/// final asyncRotating = AsyncRotatingFileOutput(
///   'logs/app.log',
///   maxSizeBytes: 1024 * 1024, // 1 MB per file
///   maxBackups: 5,
/// );
/// StructlogConfiguration.configure(output: asyncRotating);
///
/// final log = getLogger();
/// for (var i = 0; i < 100000; i++) {
///   log.info('iteration', context: {'i': i});
/// }
/// await asyncRotating.flushed;
/// ```
class AsyncRotatingFileOutput extends _SerializedAsyncOutput {
  final String filePath;
  final int maxSizeBytes;
  final int maxBackups;
  final File _file;

  AsyncRotatingFileOutput(
    this.filePath, {
    this.maxSizeBytes = 10 * 1024 * 1024, // 10MB default
    this.maxBackups = 5,
  }) : _file = File(filePath) {
    final dir = _file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  @override
  String get _diagnosticLabel => 'async rotating file output "$filePath"';

  Future<void> _rotate() async {
    final oldest = File('$filePath.${maxBackups - 1}');
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (var i = maxBackups - 2; i >= 0; i--) {
      final src = File('$filePath.$i');
      if (await src.exists()) {
        await src.rename('$filePath.${i + 1}');
      }
    }
    if (await _file.exists()) {
      await _file.rename('$filePath.0');
    }
  }

  @override
  Future<void> _write(Map<String, dynamic> entry, LogLevel level) async {
    if (await _file.exists() && await _file.length() >= maxSizeBytes) {
      await _rotate();
    }
    await _file.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  }
}
