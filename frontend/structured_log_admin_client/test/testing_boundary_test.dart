import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/testing/` is scaffolding that happens to live under `lib/`.
///
/// It is there because an `integration_test/` target compiled for the web
/// cannot reach into `test/` — `package:` reaches only into `lib/` — and both
/// the widget tests and the driven-app flow need the same mock server. The
/// cost of that is a directory the application could import by accident, and
/// an application that answered its own HTTP from a mock would be a defect no
/// test in this package could see: every one of them installs a mock on
/// purpose.
///
/// So the direction is checked rather than agreed: nothing under `lib/`, other
/// than `lib/testing/` itself, may import it.
void main() {
  test('nothing in the application imports its own test scaffolding', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.startsWith('lib/testing/')) continue;
      if (entity.readAsStringSync().contains('testing/mock_server.dart')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'lib/testing/ exists for tests to import, not for the app: an '
          'application wired to a mock server would ship as one',
    );
  });
}
