import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_dio/structured_log_dio.dart';
import 'package:test/test.dart';

/// Answers with a scripted body and records nothing — what is logged is
/// what these tests look at.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.body = '{"ok":true}', this.contentType = 'application/json'});

  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(body, 200, headers: {
        'content-type': [contentType],
      });

  @override
  void close({bool force = false}) {}
}

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

  Dio dioWith(
    StructuredLogDioInterceptor interceptor, {
    _Adapter? adapter,
    ResponseType responseType = ResponseType.json,
  }) =>
      Dio(BaseOptions(
        baseUrl: 'https://api.example.com',
        responseType: responseType,
      ))
        ..httpClientAdapter = adapter ?? _Adapter()
        ..interceptors.add(interceptor);

  String everything() => jsonEncode(entries);

  Object? requestBody() => entries.first['request_body'];
  Object? responseBody() => entries.last['response_body'];

  group('A structured body', () {
    test('has its secrets redacted before it is written', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>('/oauth/token', data: {
        'username': 'u',
        'password': 'p-secret',
        'client_secret': 's-secret',
      });

      expect(
        requestBody(),
        '{"username":"u","password":"REDACTED","client_secret":"REDACTED"}',
      );
      expect(everything(), isNot(contains('p-secret')));
      expect(everything(), isNot(contains('s-secret')));
    });

    test('nested and in lists too, whatever the case of the key', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>('/batch', data: [
        {
          'auth': {'Access_Token': 'a-secret'},
          'n': 1,
        },
      ]);

      expect(
        requestBody(),
        '[{"auth":{"Access_Token":"REDACTED"},"n":1}]',
      );
    });

    test('a decoded JSON response is redacted the same way', () async {
      final dio = dioWith(
        StructuredLogDioInterceptor(logResponseBody: true),
        adapter: _Adapter(body: '{"access_token":"t-secret","expires_in":60}'),
      );

      await dio.post<dynamic>('/oauth/token');

      expect(responseBody(), '{"access_token":"REDACTED","expires_in":60}');
      expect(everything(), isNot(contains('t-secret')));
    });

    test('the set of field names can be replaced', () async {
      final dio = dioWith(StructuredLogDioInterceptor(
        logRequestBody: true,
        redactedBodyFields: {'pin'},
      ));

      await dio.post<dynamic>('/card', data: {'PIN': '1234', 'password': 'p'});

      expect(requestBody(), '{"PIN":"REDACTED","password":"p"}');
    });

    test('the default set is the core one', () {
      expect(defaultRedactedBodyFields, same(defaultSensitiveKeys));
    });
  });

  group('A string body', () {
    test('of a form is parsed, redacted and written back', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>(
        '/oauth/token',
        data: 'grant_type=password&username=u&password=p%26secret',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      expect(
        requestBody(),
        'grant_type=password&username=u&password=REDACTED',
      );
      expect(everything(), isNot(contains('secret')));
    });

    test('of JSON is parsed, redacted and written back', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>(
        '/token',
        data: '{"refresh_token":"r-secret","scope":"a"}',
        options: Options(contentType: 'application/vnd.api+json'),
      );

      expect(requestBody(), '{"refresh_token":"REDACTED","scope":"a"}');
    });

    test('of a JSON response read as plain text too', () async {
      final dio = dioWith(
        StructuredLogDioInterceptor(logResponseBody: true),
        adapter: _Adapter(
          body: '{"id_token":"i-secret"}',
          contentType: 'application/json; charset=utf-8',
        ),
        responseType: ResponseType.plain,
      );

      await dio.get<dynamic>('/me');

      expect(responseBody(), '{"id_token":"REDACTED"}');
    });

    test('that does not parse as its type says is not written', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>(
        '/token',
        data: '{"password": "p-secret"',
        options: Options(contentType: Headers.jsonContentType),
      );

      expect(requestBody(), '<unparseable body>');
      expect(everything(), isNot(contains('p-secret')));
    });

    test('of a form keeps a name without a value as it was', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>(
        '/flags',
        data: 'verbose&password=p',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      expect(requestBody(), 'verbose&password=REDACTED');
    });

    test('of a form that does not decode is not written', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>(
        '/token',
        data: 'note=100%zz&password=p-secret',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      expect(requestBody(), '<unparseable body>');
      expect(everything(), isNot(contains('p-secret')));
    });

    test('of any other type is written only by its length', () async {
      final dio = dioWith(StructuredLogDioInterceptor(logRequestBody: true));

      await dio.post<dynamic>(
        '/note',
        data: 'secret=p',
        options: Options(contentType: 'text/plain'),
      );

      expect(requestBody(), '<8 chars>');
    });

    test('of any other type is written when that is asked for', () async {
      final dio = dioWith(StructuredLogDioInterceptor(
        logRequestBody: true,
        logUnrecognizedBodies: true,
      ));

      await dio.post<dynamic>(
        '/note',
        data: 'hello',
        options: Options(contentType: 'text/plain'),
      );

      expect(requestBody(), 'hello');
    });
  });

  group('A describeBody of the caller', () {
    test('gets the body already redacted', () async {
      Object? seen;
      final dio = dioWith(StructuredLogDioInterceptor(
        logRequestBody: true,
        describeBody: (body) => seen = body,
      ));

      await dio.post<dynamic>('/login', data: {'password': 'p-secret'});

      expect(seen, {'password': 'REDACTED'});
      expect(everything(), isNot(contains('p-secret')));
    });
  });
}
