@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:structured_log/io.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  group('The main library', () {
    test('reaches no dart:io import', () {
      // Conditional imports are followed down their default branch: that is
      // the one a compiler without dart:io — the web — takes.
      final offenders = <String>[];
      final seen = <String>{};

      void walk(String path) {
        if (!seen.add(path)) return;
        final source = File(path).readAsStringSync();
        for (final match in _directive.allMatches(source)) {
          final uri = match.group(1)!;
          if (uri == 'dart:io') offenders.add(path);
          if (uri.startsWith('dart:') || uri.startsWith('package:')) continue;
          walk(File(path).parent.uri.resolve(uri).toFilePath());
        }
      }

      walk('lib/structured_log.dart');

      expect(seen, contains(endsWith('formatters.dart')),
          reason: 'the walk has to reach the library it is guarding');
      expect(offenders, isEmpty);
    });
  });

  test('io.dart provides all four file outputs', () async {
    final dir = Directory.systemTemp.createTempSync('structured_log_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final entry = {'event': 'e'};

    fileOutput('${dir.path}/a.log')(entry, LogLevel.info);
    rotatingFileOutput('${dir.path}/b.log')(entry, LogLevel.info);
    final c = AsyncFileOutput('${dir.path}/c.log')..call(entry, LogLevel.info);
    final d = AsyncRotatingFileOutput('${dir.path}/d.log')
      ..call(entry, LogLevel.info);
    await Future.wait([c.flushed, d.flushed]);

    for (final name in ['a', 'b', 'c', 'd']) {
      expect(File('${dir.path}/$name.log').readAsStringSync(),
          contains('"event":"e"'),
          reason: name);
    }
  });

  group('Rotation keeps the size in memory', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('structured_log_'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// An entry whose line is exactly [bytes] long, newline included.
    Map<String, dynamic> entryOf(int bytes) {
      // {"p":"…"} is 8 characters plus the payload, plus the newline.
      return {'p': 'x' * (bytes - 9)};
    }

    test('sync: rotates once the counted size reaches the limit', () {
      final path = '${dir.path}/app.log';
      final output = rotatingFileOutput(path, maxSizeBytes: 100);

      output(entryOf(60), LogLevel.info);
      output(entryOf(40), LogLevel.info); // 100 now: the next write rotates
      expect(File('$path.0').existsSync(), isFalse);

      output(entryOf(10), LogLevel.info);
      output(entryOf(10), LogLevel.info); // the count started again at 0

      expect(File('$path.0').lengthSync(), 100);
      expect(File('$path.1').existsSync(), isFalse);
      expect(File(path).lengthSync(), 20);
    });

    test('sync: counts what the file already held', () {
      final path = '${dir.path}/app.log';
      File(path).writeAsStringSync('y' * 95);
      final output = rotatingFileOutput(path, maxSizeBytes: 100);

      output(entryOf(10), LogLevel.info); // 95 < 100: appended
      output(entryOf(10), LogLevel.info); // 105: rotates first

      expect(File('$path.0').lengthSync(), 105);
      expect(File(path).lengthSync(), 10);
    });

    test('sync: counts bytes, not characters', () {
      final path = '${dir.path}/app.log';
      final output = rotatingFileOutput(path, maxSizeBytes: 20);

      // 'é' is two bytes in UTF-8: this line is 9 + 2 * 6 = 21 bytes.
      output({'p': 'é' * 6}, LogLevel.info);
      output(entryOf(10), LogLevel.info);

      expect(File('$path.0').lengthSync(), 21);
    });

    test('async: rotates once the counted size reaches the limit', () async {
      final path = '${dir.path}/app.log';
      final output = AsyncRotatingFileOutput(path, maxSizeBytes: 100)
        ..call(entryOf(60), LogLevel.info)
        ..call(entryOf(40), LogLevel.info)
        ..call(entryOf(10), LogLevel.info)
        ..call(entryOf(10), LogLevel.info);
      await output.flushed;

      expect(File('$path.0').lengthSync(), 100);
      expect(File('$path.1').existsSync(), isFalse);
      expect(File(path).lengthSync(), 20);
    });

    test('async: counts what the file already held', () async {
      final path = '${dir.path}/app.log';
      File(path).writeAsStringSync('y' * 95);
      final output = AsyncRotatingFileOutput(path, maxSizeBytes: 100)
        ..call(entryOf(10), LogLevel.info)
        ..call(entryOf(10), LogLevel.info);
      await output.flushed;

      expect(File('$path.0').lengthSync(), 105);
      expect(File(path).lengthSync(), 10);
    });

    test('a write that fails is not counted', () async {
      final path = '${dir.path}/app.log';
      final output = AsyncRotatingFileOutput(path, maxSizeBytes: 100);
      // Writes to a directory standing where the file should be fail.
      Directory(path).createSync();
      await IOOverrides.runZoned(
        () {
          output.call(entryOf(60), LogLevel.info);
          return output.flushed;
        },
        stderr: () => _SilentStdout(),
      );
      Directory(path).deleteSync();

      output
        ..call(entryOf(60), LogLevel.info)
        ..call(entryOf(10), LogLevel.info);
      await output.flushed;

      expect(File('$path.0').existsSync(), isFalse,
          reason: 'only 70 bytes ever landed');
    });

    group('without asking the file system on every write', () {
      late _Counter counter;

      R counting<R>(R Function() body) {
        counter = _Counter();
        return IOOverrides.runZoned(
          body,
          createFile: (path) => _CountingFile(path, counter),
        );
      }

      test('sync', () {
        final path = '${dir.path}/app.log';
        counting(() {
          final output = rotatingFileOutput(path);
          counter.reset();
          for (var i = 0; i < 10; i++) {
            output(entryOf(20), LogLevel.info);
          }
        });

        expect(counter.calls, isEmpty);
        expect(File(path).readAsLinesSync(), hasLength(10));
      });

      test('async', () async {
        final path = '${dir.path}/app.log';
        await counting(() async {
          final output = AsyncRotatingFileOutput(path);
          counter.reset();
          for (var i = 0; i < 10; i++) {
            output(entryOf(20), LogLevel.info);
          }
          await output.flushed;
        });

        expect(counter.calls, isEmpty);
        expect(File(path).readAsLinesSync(), hasLength(10));
      });
    });
  });
}

/// `import`/`export` directives, with the default URI of a conditional one.
final _directive = RegExp(r'''^(?:import|export)\s+'([^']+)'.*?;''',
    multiLine: true, dotAll: true);

class _Counter {
  final calls = <String>[];

  void reset() => calls.clear();
}

/// A [File] that records every existence or length query made on it, and
/// passes everything else through to the real file.
class _CountingFile implements File {
  _CountingFile(String path, this._counter)
      // The root zone has no overrides: a plain File, not another of these.
      : _inner = Zone.root.run(() => File(path));

  final File _inner;
  final _Counter _counter;

  @override
  String get path => _inner.path;

  @override
  Directory get parent => _inner.parent;

  @override
  bool existsSync() {
    _counter.calls.add('existsSync');
    return _inner.existsSync();
  }

  @override
  Future<bool> exists() {
    _counter.calls.add('exists');
    return _inner.exists();
  }

  @override
  int lengthSync() {
    _counter.calls.add('lengthSync');
    return _inner.lengthSync();
  }

  @override
  Future<int> length() {
    _counter.calls.add('length');
    return _inner.length();
  }

  @override
  void writeAsBytesSync(List<int> bytes,
          {FileMode mode = FileMode.write, bool flush = false}) =>
      _inner.writeAsBytesSync(bytes, mode: mode, flush: flush);

  @override
  Future<File> writeAsBytes(List<int> bytes,
          {FileMode mode = FileMode.write, bool flush = false}) =>
      _inner.writeAsBytes(bytes, mode: mode, flush: flush);

  @override
  void writeAsStringSync(String contents,
          {FileMode mode = FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) =>
      _inner.writeAsStringSync(contents,
          mode: mode, encoding: encoding, flush: flush);

  @override
  Future<File> writeAsString(String contents,
          {FileMode mode = FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) =>
      _inner.writeAsString(contents,
          mode: mode, encoding: encoding, flush: flush);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_CountingFile.${invocation.memberName}');
}

class _SilentStdout implements Stdout {
  @override
  void writeln([Object? object = '']) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
