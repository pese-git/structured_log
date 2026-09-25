import 'package:test/test.dart';

import '../tool/coverage_floor.dart';

/// Two files, one of them generated, written the way `format_coverage`
/// writes them.
const _lcov = '''
SF:/repo/pkg/lib/src/a.dart
DA:1,3
DA:2,0
DA:3,1
end_of_record
SF:/repo/pkg/lib/src/a.g.dart
DA:1,0
DA:2,0
end_of_record
''';

void main() {
  group('isGenerated', () {
    test('knows the three shapes this repo generates', () {
      expect(isGenerated('lib/src/database.g.dart'), isTrue);
      expect(isGenerated('lib/features/x/state.freezed.dart'), isTrue);
      // gen-l10n output is committed, so it does not end in `.g.dart` and
      // would otherwise be counted as code somebody wrote.
      expect(isGenerated('lib/l10n/app_localizations_en.dart'), isTrue);
      expect(isGenerated('lib/l10n/app_localizations.dart'), isTrue);
      expect(isGenerated('lib/src/logger.dart'), isFalse);
      expect(isGenerated('lib/l10n/formatting.dart'), isFalse);
    });
  });

  group('parseLcov', () {
    test('counts a line as covered when it was hit at all', () {
      final report = parseLcov(_lcov.split('\n'));
      expect(report.total, 3);
      expect(report.hit, 2);
      expect(report.percent, closeTo(66.7, 0.1));
    });

    test('generated files are left out of both halves', () {
      final report = parseLcov(_lcov.split('\n'));
      expect(
        report.byFile.keys.where(isGenerated),
        isEmpty,
        reason: 'a generated file must not even appear in the breakdown',
      );
    });

    test('a file measured twice is merged, not counted twice', () {
      // The server collects three runs — default, integration, postgres —
      // into one directory, so the same file arrives more than once and a
      // line covered by any run is covered.
      const twice = '''
SF:/repo/pkg/lib/src/a.dart
DA:1,0
DA:2,1
end_of_record
SF:/repo/pkg/lib/src/a.dart
DA:1,4
DA:2,0
end_of_record
''';
      final report = parseLcov(twice.split('\n'));
      expect(report.total, 2, reason: 'two lines exist, not four');
      expect(report.hit, 2, reason: 'each was covered by one run or the other');
    });

    test('an empty report is not a passing report', () {
      final report = parseLcov(const []);
      expect(report.total, 0);
      expect(report.meets(0), isFalse);
      expect(
        report.meets(100),
        isFalse,
        reason: 'no data means the step that produced it broke, not that '
            'everything is covered',
      );
    });
  });

  group('meets', () {
    CoverageReport reportOf(int hit, int total) => parseLcov([
          'SF:/repo/pkg/lib/a.dart',
          for (var i = 0; i < hit; i++) 'DA:${i + 1},1',
          for (var i = hit; i < total; i++) 'DA:${i + 1},0',
          'end_of_record',
        ]);

    test('exactly at the floor passes', () {
      expect(reportOf(90, 100).meets(90), isTrue);
    });

    test('a tenth below the floor fails', () {
      expect(reportOf(899, 1000).meets(90), isFalse);
    });

    test('above the floor passes', () {
      expect(reportOf(95, 100).meets(90), isTrue);
    });
  });
}
