import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_dio/structured_log_dio.dart';
import 'package:test/test.dart';

/// Answers every request with what the test scripted, without a socket.
class FakeAdapter implements HttpClientAdapter {
  int status;
  String body;
  Map<String, List<String>> headers;

  /// Builds what to throw from the request's own options, the way a real
  /// adapter does — an exception naming other options would not be
  /// recognised as this call's.
  Object Function(RequestOptions options)? throwing;
  Completer<void>? hold;
  final reached = Completer<void>();

  FakeAdapter({
    this.status = 200,
    this.body = '{"ok":true}',
    this.headers = const {
      'content-type': ['application/json'],
    },
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwing != null) throw throwing!(options);
    if (!reached.isCompleted) reached.complete();
    if (hold != null) {
      await Future.any([hold!.future, if (cancelFuture != null) cancelFuture]);
    }
    return ResponseBody.fromString(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

List<Map<String, dynamic>> captureEntries() {
  final entries = <Map<String, dynamic>>[];
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => entries.add(Map.of(entry)),
        minLevel: LogLevel.trace,
      ),
    ],
  );
  return entries;
}

List<String> eventsOf(List<Map<String, dynamic>> entries) =>
    [for (final entry in entries) entry['event'] as String];

Dio dioWith(FakeAdapter adapter, StructuredLogDioInterceptor interceptor) =>
    Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(interceptor);

void main() {
  late List<Map<String, dynamic>> entries;
  late FakeAdapter adapter;

  setUp(() {
    entries = captureEntries();
    adapter = FakeAdapter();
  });

  tearDown(StructlogConfiguration.reset);

  group('a successful call', () {
    test('logs the request and the response, paired by id', () async {
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await dio.get<dynamic>('/v1/items', queryParameters: {'page': 2});

      expect(eventsOf(entries), ['http_request', 'http_response']);
      final [request, response] = entries;
      expect(request, containsPair('method', 'GET'));
      expect(request,
          containsPair('url', 'https://api.example.com/v1/items?page=2'));
      expect(request, containsPair('category', 'http'));
      expect(request, containsPair('logger', 'dio'));
      expect(request, containsPair('level', 'debug'));
      expect(response, containsPair('status_code', 200));
      expect(response['duration_ms'], isA<int>());
      expect(response['http_request_id'], request['http_request_id']);
    });

    test('numbers calls one after another', () async {
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await dio.get<dynamic>('/a');
      await dio.get<dynamic>('/b');

      final ids = [for (final e in entries) e['http_request_id']];
      expect(ids, [1, 1, 2, 2]);
    });

    test('leaves headers and bodies out by default', () async {
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await dio.post<dynamic>('/login', data: {'password': 'hunter2'});

      for (final entry in entries) {
        expect(entry.keys, isNot(contains('request_headers')));
        expect(entry.keys, isNot(contains('request_body')));
        expect(entry.keys, isNot(contains('response_body')));
      }
      expect(jsonEncode(entries), isNot(contains('hunter2')));
    });
  });

  group('outcomes', () {
    test('a 4xx is a warning whether or not validateStatus accepts it',
        () async {
      adapter.status = 404;
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await expectLater(
        dio.get<dynamic>('/missing'),
        throwsA(isA<DioException>()),
      );
      await dio.get<dynamic>(
        '/missing',
        options: Options(validateStatus: (_) => true),
      );

      final outcomes = entries.where((e) => e['event'] != 'http_request');
      expect(eventsOf(outcomes.toList()), ['http_error', 'http_response']);
      for (final outcome in outcomes) {
        expect(outcome, containsPair('level', 'warning'));
        expect(outcome, containsPair('status_code', 404));
      }
      expect(outcomes.first, containsPair('error_type', 'badResponse'));
      // dio's message for a bad response only restates the status code.
      expect(outcomes.first.keys, isNot(contains('error')));
    });

    test('a 5xx is an error', () async {
      adapter.status = 503;
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await expectLater(dio.get<dynamic>('/'), throwsA(isA<DioException>()));

      expect(entries.last, containsPair('level', 'error'));
      expect(entries.last, containsPair('status_code', 503));
    });

    test('a failure without a response carries no status', () async {
      adapter.throwing = (options) => DioException.connectionError(
            requestOptions: options,
            reason: 'refused',
          );
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await expectLater(dio.get<dynamic>('/'), throwsA(isA<DioException>()));

      final error = entries.last;
      expect(error, containsPair('event', 'http_error'));
      expect(error, containsPair('level', 'error'));
      expect(error, containsPair('error_type', 'connectionError'));
      expect(error['error'], contains('refused'));
      expect(error.keys, isNot(contains('status_code')));
      expect(error['duration_ms'], isA<int>());
    });

    test('an adapter that throws something else still gets logged', () async {
      adapter.throwing = (_) => StateError('adapter broke');
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      await expectLater(dio.get<dynamic>('/'), throwsA(isA<DioException>()));

      expect(entries.last, containsPair('error_type', 'unknown'));
      expect(entries.last['error'], contains('adapter broke'));
    });

    test('a cancelled call is logged at the cancel level', () async {
      adapter.hold = Completer<void>();
      final token = CancelToken();
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      final call = dio.get<dynamic>('/slow', cancelToken: token);
      // Cancelled before it is sent, a call never reaches the interceptor.
      await adapter.reached.future;
      token.cancel('user left');
      await expectLater(call, throwsA(isA<DioException>()));

      expect(entries.last, containsPair('error_type', 'cancel'));
      expect(entries.last, containsPair('level', 'debug'));
    });
  });

  group('redaction', () {
    test('sensitive headers are replaced when headers are logged', () async {
      adapter.headers = {
        'set-cookie': ['sid=abc'],
        'x-trace': ['t-1', 't-2'],
      };
      final dio =
          dioWith(adapter, StructuredLogDioInterceptor(logHeaders: true));
      await dio.get<dynamic>(
        '/',
        options: Options(headers: {
          'Authorization': 'Bearer secret-token',
          'Accept-Language': 'ru',
        }),
      );

      final [request, response] = entries;
      expect(request['request_headers'],
          containsPair('Authorization', 'REDACTED'));
      expect(request['request_headers'], containsPair('Accept-Language', 'ru'));
      expect(
          response['response_headers'], containsPair('set-cookie', 'REDACTED'));
      expect(response['response_headers'], containsPair('x-trace', 't-1, t-2'));
      expect(jsonEncode(entries), isNot(contains('secret-token')));
      expect(jsonEncode(entries), isNot(contains('sid=abc')));
    });

    test('sensitive query parameters and user info are always redacted',
        () async {
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(StructuredLogDioInterceptor());
      await dio.get<dynamic>(
        'https://user:pw@api.example.com/cb'
        '?Access_Token=t1&state=s&token=a&token=b',
      );

      final url = entries.first['url'] as String;
      expect(url, isNot(contains('pw')));
      expect(url, isNot(contains('t1')));
      expect(Uri.parse(url).queryParametersAll, {
        'Access_Token': ['REDACTED'],
        'state': ['s'],
        'token': ['REDACTED', 'REDACTED'],
      });
      expect(Uri.parse(url).userInfo, isEmpty);
    });

    test('the redaction sets can be replaced', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          logHeaders: true,
          redactedHeaders: {'x-tenant'},
          redactedQueryParameters: {'state'},
        ),
      );
      await dio.get<dynamic>(
        '/?state=s',
        options: Options(headers: {'X-Tenant': 'acme'}),
      );

      expect(entries.first['url'], 'https://api.example.com/?state=REDACTED');
      expect(entries.first['request_headers'],
          containsPair('X-Tenant', 'REDACTED'));
    });
  });

  group('bodies', () {
    test('are logged when asked, through the describer', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
            logRequestBody: true, logResponseBody: true),
      );
      await dio.post<dynamic>('/items', data: {'name': 'x'});

      expect(entries.first, containsPair('request_body', '{"name":"x"}'));
      expect(entries.last, containsPair('response_body', '{"ok":true}'));
    });

    test('an error response keeps its body', () async {
      adapter
        ..status = 422
        ..body = '{"error":"invalid"}';
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(logResponseBody: true),
      );
      await expectLater(dio.get<dynamic>('/'), throwsA(isA<DioException>()));

      expect(
          entries.last, containsPair('response_body', '{"error":"invalid"}'));
    });

    test('the default describer summarises what it should not dump', () {
      expect(describeHttpBody(null), isNull);
      expect(describeHttpBody('plain'), 'plain');
      expect(describeHttpBody(Uint8List(42)), '<42 bytes>');
      expect(describeHttpBody(const Stream<int>.empty()), '<stream>');
      expect(
        describeHttpBody(FormData.fromMap({'a': '1', 'b': '2'})),
        '<FormData: 2 fields, 0 files>',
      );
      expect(describeHttpBody([1, 'two']), '[1,"two"]');
      expect(describeHttpBody(42), '42');

      final long = describeHttpBody('x' * (defaultHttpBodyMaxLength + 5));
      expect(long, hasLength(defaultHttpBodyMaxLength + 1));
      expect(long, endsWith('…'));

      expect(
        describeHttpBody({'when': DateTime(2026)}),
        startsWith('<_Map<String, DateTime> could not be described'),
      );
    });
  });

  group('configuration', () {
    test('a null level turns that outcome off', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          levels: const HttpLogLevels(request: null),
        ),
      );
      await dio.get<dynamic>('/');

      expect(eventsOf(entries), ['http_response']);
    });

    test('filter drops both entries of a call it rejects', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          filter: (options) => !options.path.contains('health'),
        ),
      );
      await dio.get<dynamic>('/health');
      await dio.get<dynamic>('/items');

      expect(entries.map((e) => e['url']).toSet(), {
        'https://api.example.com/items',
      });
    });

    test('a given logger and category replace the defaults', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          logger: getLogger('api').bind({'service': 'billing'}),
          category: 'network',
        ),
      );
      await dio.get<dynamic>('/');

      expect(entries.first, containsPair('logger', 'api'));
      expect(entries.first, containsPair('service', 'billing'));
      expect(entries.first, containsPair('category', 'network'));
    });

    test('a null category keeps the one the logger carries', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          logger: getLogger().bind({'category': 'mine'}),
          category: null,
        ),
      );
      await dio.get<dynamic>('/');

      expect(entries.first, containsPair('category', 'mine'));
    });

    test('a later configure() reaches an interceptor built without a logger',
        () async {
      final dio = dioWith(adapter, StructuredLogDioInterceptor());
      final later = captureEntries();
      await dio.get<dynamic>('/');

      expect(entries, isEmpty);
      expect(eventsOf(later), ['http_request', 'http_response']);
    });
  });

  group('never breaks a call', () {
    test('a throwing describer costs the body, not the response', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          logResponseBody: true,
          describeBody: (_) => throw StateError('describer broke'),
        ),
      );
      final response = await dio.get<dynamic>('/');

      expect(response.statusCode, 200);
      expect(entries.last, containsPair('describe_failed', 'StateError'));
    });

    test('a throwing filter costs the entries, not the request', () async {
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(filter: (_) => throw StateError('no')),
      );
      final response = await dio.get<dynamic>('/');

      expect(response.statusCode, 200);
      expect(entries, isEmpty);
    });

    test('every entry survives jsonEncode', () async {
      adapter.status = 500;
      final dio = dioWith(
        adapter,
        StructuredLogDioInterceptor(
          logHeaders: true,
          logRequestBody: true,
          logResponseBody: true,
        ),
      );
      await expectLater(
        dio.post<dynamic>('/', data: {'a': 1}),
        throwsA(isA<DioException>()),
      );

      expect(() => jsonEncode(entries), returnsNormally);
    });
  });
}
