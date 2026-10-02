@TestOn('vm')
library;

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
}

/// `import`/`export` directives, with the default URI of a conditional one.
final _directive = RegExp(r'''^(?:import|export)\s+'([^']+)'.*?;''',
    multiLine: true, dotAll: true);
