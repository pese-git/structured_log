import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/page_request.dart';
import 'package:test/test.dart';

Matcher badRequestOn(String field) => throwsA(
  isA<ApiError>()
      .having((e) => e.statusCode, 'statusCode', 400)
      .having((e) => e.details?['field'], 'field', field),
);

void main() {
  group('parsePageRequest', () {
    test('defaults to a page of 50 and no cursor', () {
      expect(parsePageRequest({}), (limit: 50, cursor: null));
    });

    test('takes limit and cursor as given', () {
      expect(parsePageRequest({'limit': '10', 'cursor': '42'}), (
        limit: 10,
        cursor: 42,
      ));
    });

    test('brings a limit above the ceiling down to it instead of refusing', () {
      expect(parsePageRequest({'limit': '200'}).limit, 200);
      expect(parsePageRequest({'limit': '201'}).limit, 200);
      expect(parsePageRequest({'limit': '1000000'}).limit, maxPageSize);
    });

    test('refuses a limit that is not a positive integer', () {
      for (final bad in ['abc', '', '0', '-5', '1.5', '10x']) {
        expect(
          () => parsePageRequest({'limit': bad}),
          badRequestOn('limit'),
          reason: 'limit=$bad',
        );
      }
    });

    test('refuses a cursor the server could not have issued', () {
      for (final bad in ['not-a-cursor', '', '0', '-1', '1.5']) {
        expect(
          () => parsePageRequest({'cursor': bad}),
          badRequestOn('cursor'),
          reason: 'cursor=$bad',
        );
      }
    });
  });
}
