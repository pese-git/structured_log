import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/request_helpers.dart';
import 'package:test/test.dart';

Request withBody(String body) =>
    Request('POST', Uri.parse('http://x/y'), body: body);

Matcher throwsApiError(int statusCode, String code) => throwsA(
  isA<ApiError>()
      .having((e) => e.statusCode, 'statusCode', statusCode)
      .having((e) => e.code, 'code', code),
);

void main() {
  group('parsePathId', () {
    test('parses a decimal id', () {
      expect(parsePathId('42', 'id'), 42);
    });

    test('rejects a non-numeric value as 404, not 400', () {
      // An id that can't be parsed can't address an existing row either
      // way, and answering 400 would let a caller tell "malformed" apart
      // from "absent" — which is a difference they have no business
      // learning from an unauthorized probe.
      expect(() => parsePathId('abc', 'id'), throwsApiError(404, 'not_found'));
    });

    test('rejects an empty value', () {
      expect(() => parsePathId('', 'id'), throwsApiError(404, 'not_found'));
    });

    test('rejects a float and a numeric-looking suffix', () {
      expect(() => parsePathId('1.5', 'id'), throwsApiError(404, 'not_found'));
      expect(() => parsePathId('42x', 'id'), throwsApiError(404, 'not_found'));
    });

    test('names the parameter in the message', () {
      expect(
        () => parsePathId('x', 'keyId'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            contains('keyId'),
          ),
        ),
      );
    });
  });

  group('readJsonBody', () {
    test('decodes a JSON object', () async {
      expect(await readJsonBody(withBody('{"a": 1}')), {'a': 1});
    });

    test('treats an empty body as an empty object', () async {
      // Endpoints whose fields are all optional are called with no body at
      // all; that is not a malformed request.
      expect(await readJsonBody(withBody('')), isEmpty);
    });

    test('rejects malformed JSON with 400', () async {
      expect(
        () => readJsonBody(withBody('{not json')),
        throwsApiError(400, 'invalid_request'),
      );
    });

    test('rejects a non-object top level with 400', () async {
      for (final body in ['[1,2]', '"text"', '7', 'null']) {
        expect(
          () => readJsonBody(withBody(body)),
          throwsApiError(400, 'invalid_request'),
          reason: body,
        );
      }
    });

    test('preserves nested structure', () async {
      final decoded = await readJsonBody(
        withBody(
          jsonEncode({
            'nested': {'a': 1},
            'list': [1, 2],
          }),
        ),
      );
      expect(decoded['nested'], {'a': 1});
      expect(decoded['list'], [1, 2]);
    });
  });

  group('readBodyCapped', () {
    test('a body within the cap is returned whole', () async {
      expect(await readBodyCapped(withBody('hello'), 5), 'hello');
    });

    test('a declared Content-Length over the cap is refused unread', () async {
      var read = false;
      final request = Request(
        'POST',
        Uri.parse('http://x/y'),
        headers: {'content-length': '100'},
        body:
            Stream<List<int>>.fromIterable([
              [1],
            ]).map((c) {
              read = true;
              return c;
            }),
      );
      await expectLater(
        readBodyCapped(request, 10),
        throwsA(isA<BodyTooLargeException>()),
      );
      expect(read, isFalse);
    });

    test('a chunked body is cut off once it crosses the cap', () async {
      var chunksRead = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          chunksRead++;
          yield List.filled(1024, 65);
        }
      }

      // No Content-Length: nothing declares the size, so only counting while
      // reading can stop it.
      final request = Request('POST', Uri.parse('http://x/y'), body: endless());
      await expectLater(
        readBodyCapped(request, 4096),
        throwsA(isA<BodyTooLargeException>()),
      );
      expect(chunksRead, lessThan(10));
    });

    test('readJsonBody answers 413 for an oversized management body', () async {
      final huge = Request(
        'POST',
        Uri.parse('http://x/y'),
        body: '{"a":"${'x' * (maxSmallBodyBytes + 1)}"}',
      );
      await expectLater(
        readJsonBody(huge),
        throwsApiError(413, 'payload_too_large'),
      );
    });
  });
}
