import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http_client/structured_log_http_client.dart';
import 'package:test/test.dart';

final api = Uri.parse('https://api.example.com');

MockClient answering(String body, {String contentType = 'application/json'}) =>
    MockClient((request) async =>
        http.Response(body, 200, headers: {'content-type': contentType}));

void main() {
  late List<Map<String, dynamic>> entries;

  setUp(() {
    entries = [];
    StructlogConfiguration.configure(sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => entries.add(entry),
        minLevel: LogLevel.trace,
      ),
    ]);
  });
  tearDown(StructlogConfiguration.reset);

  String everything() => jsonEncode(entries);
  Object? requestBody() => entries.first['request_body'];
  Object? responseBody() => entries.last['response_body'];

  group('A request body', () {
    test('of JSON has its secrets redacted', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(
        api,
        headers: {'content-type': 'application/json'},
        body: '{"refresh_token":"r-secret","scope":"a"}',
      );

      expect(requestBody(), '{"refresh_token":"REDACTED","scope":"a"}');
      expect(everything(), isNot(contains('r-secret')));
    });

    test('of a form has its secrets redacted', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(api, body: {
        'grant_type': 'password',
        'username': 'u',
        'password': 'p secret',
      });

      expect(
        requestBody(),
        'grant_type=password&username=u&password=REDACTED',
      );
      expect(everything(), isNot(contains('secret')));
    });

    test('nested secrets, whatever the case of the key', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(
        api,
        headers: {'content-type': 'application/vnd.api+json'},
        body: '[{"auth":{"ClientSecret":"c-secret"},"n":1}]',
      );

      expect(requestBody(), '[{"auth":{"ClientSecret":"REDACTED"},"n":1}]');
    });

    test('that does not parse as its type says is not written', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(
        api,
        headers: {'content-type': 'application/json'},
        body: '{"password": "p-secret"',
      );

      expect(requestBody(), '<unparseable body>');
      expect(everything(), isNot(contains('p-secret')));
    });

    test('of a form keeps a name without a value as it was', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(
        api,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'verbose&password=p',
      );

      expect(requestBody(), 'verbose&password=REDACTED');
    });

    test('of a form that does not decode is not written', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(
        api,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'note=100%zz&password=p-secret',
      );

      expect(requestBody(), '<unparseable body>');
      expect(everything(), isNot(contains('p-secret')));
    });

    test('of any other type is written only by its length', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
      );

      await client.post(api, body: 'secret=p');

      expect(requestBody(), '<8 bytes>');
    });

    test('of any other type is written when that is asked for', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
        logUnrecognizedBodies: true,
      );

      await client.post(api, body: 'hello');

      expect(requestBody(), 'hello');
    });

    test('the set of field names can be replaced', () async {
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
        redactedBodyFields: {'pin'},
      );

      await client.post(api, body: {'PIN': '1234', 'password': 'p'});

      expect(requestBody(), 'PIN=REDACTED&password=p');
    });
  });

  group('A response body', () {
    test('reaches the reader as it was, and the log redacted', () async {
      const body = '{"access_token":"t-secret","expires_in":60}';
      final client = StructuredLogHttpClient(
        answering(body),
        logResponseBody: true,
      );

      final response = await client.get(api);

      expect(response.body, body);
      expect(responseBody(), '{"access_token":"REDACTED","expires_in":60}');
      expect(everything(), isNot(contains('t-secret')));
    });

    test('longer than the old capture is still read whole to redact it',
        () async {
      final long = jsonEncode({'id_token': 'i-secret', 'pad': 'z' * 6000});
      final client = StructuredLogHttpClient(
        answering(long),
        logResponseBody: true,
      );

      final response = await client.get(api);

      expect(response.body, long);
      final logged = responseBody() as String;
      expect(logged, startsWith('{"id_token":"REDACTED","pad":"zzz'));
      expect(logged, hasLength(defaultHttpBodyMaxLength + 1));
      expect(everything(), isNot(contains('i-secret')));
    });

    test('of a type whose shape is unknown is written by its length', () async {
      final client = StructuredLogHttpClient(
        answering('token: t-secret', contentType: 'text/plain'),
        logResponseBody: true,
      );

      await client.get(api);

      expect(responseBody(), '<15 bytes>');
    });
  });

  group('A describeBody of the caller', () {
    test('gets the body already redacted', () async {
      Object? seen;
      final client = StructuredLogHttpClient(
        answering('{}'),
        logRequestBody: true,
        describeBody: (body) => seen = body,
      );

      await client.post(api, body: {'password': 'p-secret'});

      expect(seen, 'password=REDACTED');
    });

    test('the default set is the core one', () {
      expect(defaultRedactedBodyFields, same(defaultSensitiveKeys));
    });
  });
}
