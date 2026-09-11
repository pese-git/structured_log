import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

void main() {
  group('logLevelAbbreviation', () {
    test('every level has a distinct, non-empty abbreviation', () {
      final abbreviations = LogLevel.values.map(logLevelAbbreviation).toSet();

      expect(abbreviations, hasLength(LogLevel.values.length));
      expect(abbreviations.every((a) => a.isNotEmpty), isTrue);
    });
  });
}
