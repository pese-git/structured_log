import 'dart:io';

import 'package:test/test.dart';

/// Diagnostics that bypass `structured_log` are the thing this guards
/// against (`design.md` decision 48): a `print` cannot be filtered by level,
/// cannot be pointed at a file, and does not carry structured fields — so
/// once one exists, the server's diagnostics live in two mechanisms and only
/// one of them is configurable.
///
/// A convention would not hold. This does.
void main() {
  final forbidden = <({RegExp pattern, String what})>[
    (pattern: RegExp(r'(^|[^\w.])print\s*\('), what: 'print('),
    (pattern: RegExp(r'(^|[^\w.])debugPrint\s*\('), what: 'debugPrint('),
    (
      pattern: RegExp(r"import\s+'dart:developer'"),
      what: "import 'dart:developer'",
    ),
  ];

  /// `example/` is exempt: sample code is read, not run in production, and
  /// a `print` there is often the clearest way to show what a call returns.
  final roots = ['lib', 'bin', 'test'];

  test('no print/debugPrint/dart:developer anywhere in the package', () {
    final offences = <String>[];

    for (final root in roots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;

      for (final file in directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // Generated code is not ours to police, and is not committed.
        if (file.path.endsWith('.g.dart')) continue;
        if (file.path.endsWith('.freezed.dart')) continue;
        // This file names the forbidden calls in order to look for them.
        if (file.path.endsWith('no_print_test.dart')) continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // A mention in a comment is documentation, not a call.
          final code = line.split('//').first;
          for (final rule in forbidden) {
            if (rule.pattern.hasMatch(code)) {
              offences.add('${file.path}:${i + 1}: ${rule.what} — $line');
            }
          }
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason: 'use the server logger (lib/src/logging/setup.dart) instead:\n'
          '${offences.join('\n')}',
    );
  });

  test('the guard actually matches what it claims to', () {
    // Without this, a regex that matches nothing would pass the test above
    // for the wrong reason forever.
    const samples = [
      'print("x");',
      '  print(entry);',
      'debugPrint("x");',
      "import 'dart:developer';",
    ];
    for (final sample in samples) {
      expect(
        forbidden.any((rule) => rule.pattern.hasMatch(sample)),
        isTrue,
        reason: 'should have been caught: $sample',
      );
    }

    // And does not fire on things that merely look similar.
    const allowed = [
      'stdout.writeln(line);',
      'buffer.write(text);',
      'final printed = format(entry);',
      'logger.info("sprint.completed");',
    ];
    for (final sample in allowed) {
      expect(
        forbidden.any((rule) => rule.pattern.hasMatch(sample)),
        isFalse,
        reason: 'false positive on: $sample',
      );
    }
  });
}
