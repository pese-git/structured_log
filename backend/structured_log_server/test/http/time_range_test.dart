import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/time_range.dart';
import 'package:test/test.dart';

Matcher _refuses(String field) => throwsA(
  isA<ApiError>()
      .having((e) => e.statusCode, 'statusCode', 400)
      .having((e) => e.code, 'code', 'invalid_request')
      .having((e) => e.details?['field'], 'details.field', field),
);

void main() {
  group('parseTimeRange', () {
    test('absent bounds are not an error', () {
      final range = parseTimeRange({});
      expect(range.from, isNull);
      expect(range.to, isNull);
    });

    test('an ISO 8601 bound arrives as it was written', () {
      final range = parseTimeRange({
        'from': '2026-06-01T10:00:00Z',
        'to': '2026-06-02T10:00:00Z',
      });
      expect(range.from, DateTime.utc(2026, 6, 1, 10));
      expect(range.to, DateTime.utc(2026, 6, 2, 10));
    });

    test('a date alone is a bound too', () {
      expect(parseTimeRange({'from': '2026-06-01'}).from, isNotNull);
    });

    test('an offset is honoured rather than refused', () {
      // The endpoint has always accepted these, and the check added for
      // rolled-over calendars must not narrow what is allowed.
      expect(
        parseTimeRange({'from': '2026-06-01T12:00:00+03:00'}).from,
        DateTime.utc(2026, 6, 1, 9),
      );
    });

    test('a leap day exists in a leap year and not otherwise', () {
      expect(parseTimeRange({'from': '2024-02-29'}).from, isNotNull);
      expect(() => parseTimeRange({'from': '2026-02-29'}), _refuses('from'));
    });

    test('what cannot be read at all is refused', () {
      for (final raw in ['yesterday', '', 'nope', '01/06/2026']) {
        expect(
          () => parseTimeRange({'from': raw}),
          _refuses('from'),
          reason: raw,
        );
      }
    });

    test('a component out of range is refused, not rolled over', () {
      // `DateTime.tryParse` answers these rather than refusing them — month
      // 13 as January of the next year, February 30th as March 2nd — so
      // without this the query would run over a range nobody asked for.
      for (final raw in [
        '2026-13-01',
        '2026-00-01',
        '2026-02-30',
        '2026-06-00',
        '2026-06-01T25:00:00',
        '2026-06-01T10:60:00',
      ]) {
        expect(() => parseTimeRange({'to': raw}), _refuses('to'), reason: raw);
      }
    });

    test('each bound is named by the error it causes', () {
      expect(() => parseTimeRange({'from': 'nope'}), _refuses('from'));
      expect(() => parseTimeRange({'to': 'nope'}), _refuses('to'));
    });
  });
}
