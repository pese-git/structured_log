import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http_client/structured_log_http_client.dart';
import 'package:test/test.dart';

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

/// Answers every request with [status] and [body].
MockClient answering(
  int status, {
  String body = '{"ok":true}',
  Map<String, String> headers = const {'content-type': 'application/json'},
}) =>
    MockClient(
        (request) async => http.Response(body, status, headers: headers));

final api = Uri.parse('https://api.example.com');

void main() {
  late List<Map<String, dynamic>> entries;

  setUp(() => entries = captureEntries());
  tearDown(StructlogConfiguration.reset);

  group('a successful call', () {
    test('logs the request and the response, paired by id', () async {
      final client = StructuredLogHttpClient(answering(200));
      final response = await client.get(api.resolve('/v1/items?page=2'));

      expect(response.body, '{"ok":true}');
      expect(eventsOf(entries), ['http_request', 'http_response']);
      final [request, outcome] = entries;
      expect(request, containsPair('method', 'GET'));
      expect(request,
          containsPair('url', 'https://api.example.com/v1/items?page=2'));
      expect(request, containsPair('category', 'http'));
      expect(request, containsPair('logger', 'http'));
      expect(request, containsPair('level', 'debug'));
      expect(outcome, containsPair('status_code', 200));
      expect(outcome['duration_ms'], isA<int>());
      expect(outcome['http_request_id'], request['http_request_id']);
    });

    test('numbers calls one after another', () async {
      final client = StructuredLogHttpClient(answering(200));
      await client.get(api);
      await client.get(api);

      expect([for (final e in entries) e['http_request_id']], [1, 1, 2, 2]);
    });

    test('leaves headers and bodies out by default', () async {
      final client = StructuredLogHttpClient(answering(200));
      await client.post(
        api.resolve('/login'),
        headers: {'authorization': 'Bearer t'},
        body: '{"password":"hunter2"}',
      );

      for (final entry in entries) {
        expect(entry.keys, isNot(contains('request_headers')));
        expect(entry.keys, isNot(contains('request_body')));
        expect(entry.keys, isNot(contains('response_body')));
      }
      expect(jsonEncode(entries), isNot(contains('hunter2')));
    });

    test('close() closes the inner client', () async {
      var closed = false;
      final inner = _ClosingClient(() => closed = true);
      StructuredLogHttpClient(inner).close();

      expect(closed, isTrue);
    });
  });

  group('outcomes', () {
    test('every status is a response, levelled by its code', () async {
      final statuses = [301, 404, 503];
      for (final status in statuses) {
        await StructuredLogHttpClient(answering(status)).get(api);
      }

      final outcomes = entries.where((e) => e['event'] == 'http_response');
      expect([for (final o in outcomes) o['level']],
          ['debug', 'warning', 'error']);
      expect([for (final o in outcomes) o['status_code']], statuses);
    });

    test(
        'a client that throws is a failure, and the error still reaches '
        'the caller', () async {
      final client = StructuredLogHttpClient(
        MockClient((_) => throw http.ClientException('refused', api)),
      );
      await expectLater(client.get(api), throwsA(isA<http.ClientException>()));

      final error = entries.last;
      expect(error, containsPair('event', 'http_error'));
      expect(error, containsPair('level', 'error'));
      expect(error, containsPair('error_type', 'ClientException'));
      expect(error, containsPair('error', 'refused'));
      expect(error.keys, isNot(contains('status_code')));
      expect(error['duration_ms'], isA<int>());
    });

    test('a non-ClientException is logged through toString()', () async {
      final client = StructuredLogHttpClient(
        MockClient((_) => throw TimeoutException('too slow')),
      );
      await expectLater(client.get(api), throwsA(isA<TimeoutException>()));

      expect(entries.last, containsPair('error_type', 'TimeoutException'));
      expect(entries.last['error'], contains('too slow'));
    });

    test('an aborted request is logged at the cancel level', () async {
      final abort = Completer<void>();
      final inner = MockClient.streaming((request, body) async {
        await (request as http.Abortable).abortTrigger;
        throw http.RequestAbortedException(request.url);
      });
      final client = StructuredLogHttpClient(inner);
      final call = client.send(
        http.AbortableRequest('GET', api, abortTrigger: abort.future),
      );
      abort.complete();
      await expectLater(call, throwsA(isA<http.RequestAbortedException>()));

      expect(entries.last, containsPair('event', 'http_error'));
      expect(
          entries.last, containsPair('error_type', 'RequestAbortedException'));
      expect(entries.last, containsPair('level', 'debug'));
    });
  });

  group('redaction', () {
    test('sensitive headers are replaced when headers are logged', () async {
      final client = StructuredLogHttpClient(
        answering(200, headers: {'set-cookie': 'sid=abc', 'x-trace': 't-1'}),
        logHeaders: true,
      );
      await client.get(api, headers: {
        'Authorization': 'Bearer secret-token',
        'Accept-Language': 'ru',
      });

      final [request, response] = entries;
      expect(request['request_headers'],
          containsPair('Authorization', 'REDACTED'));
      expect(request['request_headers'], containsPair('Accept-Language', 'ru'));
      expect(
          response['response_headers'], containsPair('set-cookie', 'REDACTED'));
      expect(response['response_headers'], containsPair('x-trace', 't-1'));
      expect(jsonEncode(entries), isNot(contains('secret-token')));
      expect(jsonEncode(entries), isNot(contains('sid=abc')));
    });

    test('sensitive query parameters and user info are always redacted',
        () async {
      final client = StructuredLogHttpClient(answering(200));
      await client.get(Uri.parse(
        'https://user:pw@api.example.com/cb'
        '?Access_Token=t1&state=s&token=a&token=b',
      ));

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
      final client = StructuredLogHttpClient(
        answering(200),
        logHeaders: true,
        redactedHeaders: {'x-tenant'},
        redactedQueryParameters: {'state'},
      );
      await client.get(api.resolve('/?state=s'), headers: {'X-Tenant': 'acme'});

      expect(entries.first['url'], 'https://api.example.com/?state=REDACTED');
      expect(entries.first['request_headers'],
          containsPair('X-Tenant', 'REDACTED'));
    });
  });

  group('request bodies', () {
    test('a textual body is logged as text', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logRequestBody: true,
      );
      await client.post(api, body: {'name': 'x'});

      expect(entries.first, containsPair('request_body', 'name=x'));
    });

    test('a binary body is summarised', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logRequestBody: true,
      );
      await client.post(
        api,
        headers: {'content-type': 'image/png'},
        body: Uint8List(42),
      );

      expect(entries.first, containsPair('request_body', '<42 bytes>'));
    });

    test('a long body is cut short', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logRequestBody: true,
        // Plain text is written only by its size unless asked for.
        logUnrecognizedBodies: true,
      );
      await client.post(api, body: 'x' * 5000);

      final body = entries.first['request_body'] as String;
      expect(body, hasLength(defaultHttpBodyMaxLength + 1));
      expect(body, endsWith('…'));
    });

    test('multipart and streamed bodies are summarised', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logRequestBody: true,
      );
      await client.send(http.MultipartRequest('POST', api)
        ..fields['a'] = '1'
        ..files.add(http.MultipartFile.fromString('f', 'content')));
      final streamed = http.StreamedRequest('POST', api);
      final sent = client.send(streamed);
      streamed.sink.close();
      await sent;

      final requests = entries.where((e) => e['event'] == 'http_request');
      expect([
        for (final r in requests) r['request_body']
      ], [
        '<multipart: 1 fields, 1 files>',
        '<stream>',
      ]);
    });
  });

  group('response bodies', () {
    test('are logged once read, and reach the reader unchanged', () async {
      final client = StructuredLogHttpClient(
        answering(200, body: '{"items":[1,2]}'),
        logResponseBody: true,
      );
      final response = await client.get(api);

      expect(response.body, '{"items":[1,2]}');
      expect(entries.last, containsPair('response_body', '{"items":[1,2]}'));
      expect(entries.last, containsPair('status_code', 200));
    });

    test('wait for the body: nothing is logged until it is read', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logResponseBody: true,
      );
      final response = await client.send(http.Request('GET', api));
      expect(eventsOf(entries), ['http_request']);

      await response.stream.drain<void>();
      expect(eventsOf(entries), ['http_request', 'http_response']);
    });

    test('a reader that stops early still gets the entry', () async {
      final chunks = StreamController<List<int>>();
      final client = StructuredLogHttpClient(
        MockClient.streaming(
          (request, body) async => http.StreamedResponse(chunks.stream, 200,
              headers: {'content-type': 'text/event-stream'}),
        ),
        logResponseBody: true,
        logUnrecognizedBodies: true,
      );
      final response = await client.send(http.Request('GET', api));
      final first = Completer<void>();
      final subscription = response.stream.listen((_) => first.complete());
      chunks.add(utf8.encode('data: one\n\n'));
      await first.future;
      await subscription.cancel();

      expect(entries.last, containsPair('event', 'http_response'));
      expect(entries.last, containsPair('response_body', 'data: one\n\n'));
    });

    test('keep only the start of a long body, and say so', () async {
      final client = StructuredLogHttpClient(
        answering(200,
            body: 'y' * 10000, headers: {'content-type': 'text/plain'}),
        logResponseBody: true,
        logUnrecognizedBodies: true,
      );
      final response = await client.get(api);

      expect(response.body, hasLength(10000));
      final logged = entries.last['response_body'] as String;
      expect(logged, hasLength(defaultHttpBodyMaxLength + 1));
      expect(logged, endsWith('…'));
    });

    test('a binary body is summarised by its size', () async {
      final client = StructuredLogHttpClient(
        MockClient((_) async => http.Response.bytes(Uint8List(7), 200,
            headers: {'content-type': 'application/octet-stream'})),
        logResponseBody: true,
      );
      await client.get(api);

      expect(entries.last, containsPair('response_body', '<7 bytes>'));
    });

    test('a body that fails half-way is an error with its status', () async {
      final client = StructuredLogHttpClient(
        MockClient.streaming(
          (request, body) async => http.StreamedResponse(
            Stream<List<int>>.error(http.ClientException('reset')),
            200,
          ),
        ),
        logResponseBody: true,
      );
      final response = await client.send(http.Request('GET', api));
      await expectLater(
        response.stream.toBytes(),
        throwsA(isA<http.ClientException>()),
      );

      expect(entries.last, containsPair('event', 'http_error'));
      expect(entries.last, containsPair('status_code', 200));
      expect(entries.last, containsPair('error', 'reset'));
    });

    test('keep the url after redirects, when the response had one', () async {
      final redirected = api.resolve('/final');
      final client = StructuredLogHttpClient(
        // Not MockClient: it rebuilds the response and drops the url.
        _AnsweringClient(() => _ResponseWithUrl(redirected)),
        logResponseBody: true,
      );
      final response = await client.send(http.Request('GET', api));

      expect(response, isA<http.BaseResponseWithUrl>());
      expect((response as http.BaseResponseWithUrl).url, redirected);
      await response.stream.drain<void>();

      final plain = await StructuredLogHttpClient(
        answering(200),
        logResponseBody: true,
      ).send(http.Request('GET', api));
      expect(plain, isNot(isA<http.BaseResponseWithUrl>()));
      await plain.stream.drain<void>();
    });

    test('pause and resume reach the source', () async {
      final chunks = StreamController<List<int>>();
      final client = StructuredLogHttpClient(
        MockClient.streaming(
          (request, body) async => http.StreamedResponse(chunks.stream, 200),
        ),
        logResponseBody: true,
      );
      final response = await client.send(http.Request('GET', api));
      final subscription = response.stream.listen(null);
      subscription.pause();
      expect(chunks.isPaused, isTrue);
      subscription.resume();
      expect(chunks.isPaused, isFalse);
      await subscription.cancel();
    });
  });

  group('configuration', () {
    test('a null level turns that outcome off', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        levels: const HttpLogLevels(request: null),
      );
      await client.get(api);

      expect(eventsOf(entries), ['http_response']);
    });

    test('filter drops both entries of a call it rejects', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        filter: (request) => request.url.path != '/health',
      );
      await client.get(api.resolve('/health'));
      await client.get(api.resolve('/items'));

      expect(entries.map((e) => e['url']).toSet(),
          {'https://api.example.com/items'});
    });

    test('a given logger and category replace the defaults', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logger: getLogger('api').bind({'service': 'billing'}),
        category: 'network',
      );
      await client.get(api);

      expect(entries.first, containsPair('logger', 'api'));
      expect(entries.first, containsPair('service', 'billing'));
      expect(entries.first, containsPair('category', 'network'));
    });

    test('a null category keeps the one the logger carries', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logger: getLogger().bind({'category': 'mine'}),
        category: null,
      );
      await client.get(api);

      expect(entries.first, containsPair('category', 'mine'));
    });

    test('a later configure() reaches a client built without a logger',
        () async {
      final client = StructuredLogHttpClient(answering(200));
      final later = captureEntries();
      await client.get(api);

      expect(entries, isEmpty);
      expect(eventsOf(later), ['http_request', 'http_response']);
    });
  });

  group('never breaks a call', () {
    test('a throwing describer costs the body, not the response', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        logResponseBody: true,
        describeBody: (_) => throw StateError('describer broke'),
      );
      final response = await client.get(api);

      expect(response.statusCode, 200);
      expect(entries.last, containsPair('describe_failed', 'StateError'));
    });

    test('a throwing filter costs the entries, not the request', () async {
      final client = StructuredLogHttpClient(
        answering(200),
        filter: (_) => throw StateError('no'),
      );
      final response = await client.get(api);

      expect(response.statusCode, 200);
      expect(entries, isEmpty);
    });

    test('every entry survives jsonEncode', () async {
      final client = StructuredLogHttpClient(
        answering(500),
        logHeaders: true,
        logRequestBody: true,
        logResponseBody: true,
      );
      await client.post(api, body: '{"a":1}');

      expect(() => jsonEncode(entries), returnsNormally);
    });
  });
}

/// What `IOClient`/`BrowserClient` return: a response that knows its final
/// URL. `package:http`'s own class for it is not exported.
class _ResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  @override
  final Uri url;

  _ResponseWithUrl(this.url) : super(Stream.value(utf8.encode('ok')), 200);
}

class _AnsweringClient extends http.BaseClient {
  final http.StreamedResponse Function() answer;

  _AnsweringClient(this.answer);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      answer();
}

class _ClosingClient extends http.BaseClient {
  final void Function() onClose;

  _ClosingClient(this.onClose);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}
