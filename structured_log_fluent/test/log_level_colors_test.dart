import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

void main() {
  group('logLevelColor', () {
    test('every level has a distinct color in light mode', () {
      final colors = {
        for (final level in LogLevel.values)
          level: logLevelColor(level, Brightness.light),
      };

      expect(colors.values.toSet(), hasLength(LogLevel.values.length));
    });

    test('every level has a distinct color in dark mode', () {
      final colors = {
        for (final level in LogLevel.values)
          level: logLevelColor(level, Brightness.dark),
      };

      expect(colors.values.toSet(), hasLength(LogLevel.values.length));
    });

    test('a given level resolves to a different color per brightness', () {
      expect(
        logLevelColor(LogLevel.warning, Brightness.light),
        isNot(logLevelColor(LogLevel.warning, Brightness.dark)),
      );
    });
  });

  group('logLevelAbbreviation', () {
    test('every level has a distinct, non-empty abbreviation', () {
      final abbreviations = LogLevel.values.map(logLevelAbbreviation).toSet();

      expect(abbreviations, hasLength(LogLevel.values.length));
      expect(abbreviations.every((a) => a.isNotEmpty), isTrue);
    });
  });
}
