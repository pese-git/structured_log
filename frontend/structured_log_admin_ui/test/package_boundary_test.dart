import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// design.md decision 39: this package may not reach the client's business
/// logic, and the compiler already enforces that — a dependency on
/// `structured_log_admin_client`, or on the state/IO libraries it is built
/// from, would have to be declared here first.
///
/// This test does not add enforcement, it records the intent: a contributor
/// who adds `flutter_bloc` to get a component talking to a Bloc directly gets
/// a failure that names the decision, rather than a build that quietly works.
void main() {
  late String pubspec;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  test('depends on nothing but the Flutter SDK and fluent_ui', () {
    // Comment lines are stripped first: the dependency block explains which
    // packages are deliberately absent and names them, which a plain
    // substring search would read as their presence.
    final dependencies = pubspec
        .split('\n')
        .map((line) => line.split('#').first)
        .join('\n')
        .split('dev_dependencies:')
        .first
        .split('dependencies:')
        .last;

    for (final forbidden in const [
      'structured_log_admin_client',
      'flutter_bloc',
      'bloc',
      'cherrypick',
      'fpdart',
      'freezed',
      'dio',
      'retrofit',
      'flutter_secure_storage',
    ]) {
      expect(
        dependencies.contains(forbidden),
        isFalse,
        reason: '$forbidden belongs to the client, not to its component '
            'library (design.md decision 39)',
      );
    }

    expect(dependencies, contains('fluent_ui'));
  });

  test('no source file imports the client', () {
    final offenders = <String>[];
    for (final directory in ['lib', 'test', 'example/lib']) {
      final dir = Directory(directory);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // This file holds the forbidden string in order to search for it.
        if (entity.path.endsWith('package_boundary_test.dart')) continue;
        // The import, not the name: the library doc says out loud who this
        // package exists for, and that is not a dependency.
        if (entity
            .readAsStringSync()
            .contains('package:structured_log_admin_client')) {
          offenders.add(entity.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
