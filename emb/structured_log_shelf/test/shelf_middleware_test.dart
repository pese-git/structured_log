import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_shelf/structured_log_shelf.dart';
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

/// Entries written by the middleware, not by the handler.
List<Map<String, dynamic>> httpEntries(List<Map<String, dynamic>> entries) => [
      for (final entry in entries)
        if ((entry['event'] as String).startsWith('http_request_')) entry,
    ];

Handler pipeline(Handler handler, [Middleware? middleware]) => const Pipeline()
    .addMiddleware(middleware ?? structuredLogRequests())
    .addHandler(handler);

Request get(String path, {Map<String, String>? headers}) =>
    Request('GET', Uri.parse('http://localhost$path'), headers: headers);

Response ok(Request request) => Response.ok('ok');

void main() {
  late List<Map<String, dynamic>> entries;

  setUp(() => entries = captureEntries());
  tearDown(StructlogConfiguration.reset);

  group('the outcome entry', () {
    test('a successful request is one http_request_handled entry', () async {
      final response = await pipeline(ok)(get('/items'));

      expect(response.statusCode, 200);
      expect(eventsOf(entries), ['http_request_handled']);
      final entry = entries.single;
      expect(entry['level'], 'info');
      expect(entry['category'], 'http');
      expect(entry['logger'], 'shelf');
      expect(entry['method'], 'GET');
      expect(entry['path'], '/items');
      expect(entry['status_code'], 200);
      expect(entry['duration_ms'], isA<double>());
      expect(entry['request_id'], isA<String>());
      expect(entry, isNot(contains('query')));
    });

    test('the path is the requested one, wherever the middleware is mounted',
        () async {
      // What Router.mount('/api/', …) does to the request it passes on: the
      // mounted handler sees `url` as `items`.
      final mounted = pipeline(ok);
      await mounted(get('/api/items').change(path: 'api/'));

      expect(entries.single['path'], '/api/items');
    });

    test('the received entry is off by default and written first when on',
        () async {
      await pipeline(
        ok,
        structuredLogRequests(
          levels: const ShelfLogLevels(received: LogLevel.debug),
        ),
      )(get('/stream'));

      expect(
          eventsOf(entries), ['http_request_received', 'http_request_handled']);
      expect(entries.first['level'], 'debug');
      expect(entries.first['path'], '/stream');
      expect(entries.first, isNot(contains('status_code')));
      expect(entries.first['request_id'], entries.last['request_id']);
    });

    test('a 4xx is a warning and a 5xx an error', () async {
      await pipeline((_) => Response.notFound('no'))(get('/missing'));
      await pipeline((_) => Response.internalServerError())(get('/broken'));

      expect([for (final e in entries) e['level']], ['warning', 'error']);
      expect([for (final e in entries) e['status_code']], [404, 500]);
    });

    test('a null level turns its entry off and leaves the response alone',
        () async {
      final response = await pipeline(
        ok,
        structuredLogRequests(levels: const ShelfLogLevels(success: null)),
      )(get('/items'));

      expect(entries, isEmpty);
      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
    });

    test('a given logger and category are used as they are', () async {
      final logger = getLogger('api').bind({'service': 'billing'});
      await pipeline(
        ok,
        structuredLogRequests(logger: logger, category: 'inbound'),
      )(get('/items'));

      expect(entries.single['logger'], 'api');
      expect(entries.single['service'], 'billing');
      expect(entries.single['category'], 'inbound');
    });
  });

  group('a handler that throws', () {
    test('is http_request_failed with its stack, and the error is rethrown',
        () async {
      final handler = pipeline((_) => throw StateError('boom'));

      await expectLater(handler(get('/items')), throwsStateError);

      expect(eventsOf(entries), ['http_request_failed']);
      final entry = entries.single;
      expect(entry['level'], 'error');
      expect(entry['error_type'], 'StateError');
      expect(entry['error'], contains('boom'));
      expect(entry['stack_trace'], isA<String>());
      expect(entry['duration_ms'], isA<double>());
      expect(entry, isNot(contains('status_code')));
    });

    test('keeps the stack of the original throw', () async {
      StackTrace? thrownAt;
      final handler = pipeline((_) {
        try {
          throw ArgumentError('bad');
        } catch (_, stackTrace) {
          thrownAt = stackTrace;
          rethrow;
        }
      });

      StackTrace? caughtAt;
      try {
        await handler(get('/items'));
      } catch (_, stackTrace) {
        caughtAt = stackTrace;
      }
      expect(caughtAt.toString(), thrownAt.toString());
    });
  });

  group('a hijacked request', () {
    test('is handled, not failed, and the socket stays with the handler',
        () async {
      final server = await shelf_io.serve(
        pipeline((request) {
          request.hijack((channel) {
            channel.sink
              ..add(utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: 8\r\n'
                  'connection: close\r\n\r\nhijacked'))
              ..close();
          });
        }),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));

      final client = HttpClient();
      addTearDown(client.close);
      final response =
          await (await client.get('localhost', server.port, '/ws')).close();
      final body = await response.transform(utf8.decoder).join();

      expect(body, 'hijacked');
      expect(eventsOf(entries), ['http_request_handled']);
      expect(entries.single['hijacked'], isTrue);
      expect(entries.single['level'], 'info');
      expect(entries.single, isNot(contains('status_code')));
    });
  });

  group('correlation', () {
    test("the handler's entries carry the request's id", () async {
      final handler = pipeline((request) {
        request.logger.warning('quota_exceeded');
        return Response(429);
      });

      await handler(get('/ingest'));

      expect(eventsOf(entries), ['quota_exceeded', 'http_request_handled']);
      expect(entries.first['request_id'], isNotNull);
      expect(entries.first['request_id'], entries.last['request_id']);
    });

    test('request.requestId is the id in the entries and the header', () async {
      String? seen;
      final response = await pipeline((request) {
        seen = request.requestId;
        return Response.ok('ok');
      })(get('/items'));

      expect(seen, entries.single['request_id']);
      expect(response.headers['x-request-id'], seen);
    });

    test('two requests get different ids', () async {
      final handler = pipeline(ok);
      await handler(get('/a'));
      await handler(get('/b'));

      expect(entries.first['request_id'], isNot(entries.last['request_id']));
    });

    test('the default id is 12 hex characters', () async {
      await pipeline(ok)(get('/items'));

      expect(entries.single['request_id'], matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('without the middleware, request.logger and requestId throw', () {
      expect(
        () => get('/items').logger,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('structuredLogRequests'),
        )),
      );
      expect(() => get('/items').requestId, throwsStateError);
    });

    test('a given generator makes the id', () async {
      final response = await pipeline(
        ok,
        structuredLogRequests(requestIdGenerator: () => 'fixed-1'),
      )(get('/items'));

      expect(entries.single['request_id'], 'fixed-1');
      expect(response.headers['x-request-id'], 'fixed-1');
    });

    test('a generator that throws falls back to the default id', () async {
      final response = await pipeline(
        ok,
        structuredLogRequests(requestIdGenerator: () => throw StateError('x')),
      )(get('/items'));

      expect(response.statusCode, 200);
      expect(entries.single['request_id'], matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('the response header can be renamed or turned off', () async {
      final renamed = await pipeline(
        ok,
        structuredLogRequests(responseHeader: 'X-Trace'),
      )(get('/items'));
      final none = await pipeline(
        ok,
        structuredLogRequests(responseHeader: null),
      )(get('/items'));

      expect(renamed.headers['x-trace'], entries.first['request_id']);
      expect(renamed.headers, isNot(contains('x-request-id')));
      expect(none.headers, isNot(contains('x-request-id')));
    });
  });

  group('an incoming id', () {
    test('is ignored unless trusted', () async {
      final response = await pipeline(ok)(
        get('/items', headers: {'X-Request-Id': 'abc'}),
      );

      expect(entries.single['request_id'], isNot('abc'));
      expect(response.headers['x-request-id'], isNot('abc'));
      expect(entries.single, isNot(contains('request_id_rejected')));
    });

    test('is used when trusted and well-formed', () async {
      final response = await pipeline(
        ok,
        structuredLogRequests(trustIncomingRequestId: true),
      )(get('/items', headers: {'X-Request-Id': '3f2a-proxy.17'}));

      expect(entries.single['request_id'], '3f2a-proxy.17');
      expect(response.headers['x-request-id'], '3f2a-proxy.17');
    });

    test('is read from the configured header', () async {
      await pipeline(
        ok,
        structuredLogRequests(
          trustIncomingRequestId: true,
          incomingRequestIdHeader: 'X-Amzn-Trace-Id',
        ),
      )(get('/items', headers: {
        'X-Amzn-Trace-Id': 'Root:1-5759e988',
        'X-Request-Id': 'other',
      }));

      expect(entries.single['request_id'], 'Root:1-5759e988');
    });

    for (final (name, value) in [
      ('markup', '"><script>'),
      ('too long', 'a' * 129),
      ('a space', 'a b'),
    ]) {
      test('is replaced when trusted but malformed ($name)', () async {
        final response = await pipeline(
          ok,
          structuredLogRequests(
            trustIncomingRequestId: true,
            levels: const ShelfLogLevels(received: LogLevel.debug),
          ),
        )(get('/items', headers: {'X-Request-Id': value}));

        expect(entries.last['request_id'], matches(RegExp(r'^[0-9a-f]{12}$')));
        expect(response.headers['x-request-id'], entries.last['request_id']);
        expect(
          [for (final e in entries) e['request_id_rejected']],
          [true, true],
        );
        expect(jsonEncode(entries), isNot(contains(value)));
      });
    }
  });

  group('secrets', () {
    test('bodies are never written', () async {
      final handler = pipeline(
        (request) async {
          await request.readAsString();
          return Response.ok('token=s3cret-tok');
        },
        structuredLogRequests(
          logHeaders: true,
          levels: const ShelfLogLevels(received: LogLevel.debug),
        ),
      );

      await handler(Request(
        'POST',
        Uri.parse('http://localhost/token'),
        body: 'password=s3cret-pw&username=body-user',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ));

      final written = jsonEncode(entries);
      expect(written, isNot(contains('s3cret-pw')));
      expect(written, isNot(contains('body-user')));
      expect(written, isNot(contains('s3cret-tok')));
    });

    test('headers are not written by default', () async {
      await pipeline(ok)(
        get('/items', headers: {'Authorization': 'Bearer t0ken'}),
      );

      expect(entries.single, isNot(contains('request_headers')));
      expect(entries.single, isNot(contains('response_headers')));
      expect(jsonEncode(entries), isNot(contains('t0ken')));
    });

    test('logged headers have their secrets redacted', () async {
      await pipeline(
        (_) => Response.ok('ok', headers: {'Set-Cookie': 'sid=s3cret'}),
        structuredLogRequests(logHeaders: true),
      )(get('/items', headers: {
        'Authorization': 'Bearer t0ken',
        'Accept': 'text/plain',
      }));

      final entry = entries.single;
      expect(
          entry['request_headers'], containsPair('authorization', 'REDACTED'));
      expect(entry['request_headers'], containsPair('accept', 'text/plain'));
      expect(entry['response_headers'], containsPair('set-cookie', 'REDACTED'));
      expect(jsonEncode(entries), isNot(contains('t0ken')));
      expect(jsonEncode(entries), isNot(contains('s3cret')));
    });

    test('a token in the query is redacted, the rest kept', () async {
      await pipeline(ok)(get('/callback?access_token=t0ken&page=2'));

      expect(entries.single['path'], '/callback');
      expect(entries.single['query'], contains('access_token=REDACTED'));
      expect(entries.single['query'], contains('page=2'));
      expect(jsonEncode(entries), isNot(contains('t0ken')));
    });

    test('a query without secrets is written as it came', () async {
      await pipeline(ok)(get('/items?page=2&sort=name'));

      expect(entries.single['query'], 'page=2&sort=name');
    });

    test('names are compared case-insensitively', () async {
      await pipeline(
        ok,
        structuredLogRequests(
          logHeaders: true,
          redactedHeaders: {'X-Tenant-Secret'},
          redactedQueryParameters: {'Sig'},
        ),
      )(get('/items?SIG=s1gnature', headers: {'x-tenant-secret': 'h1dden'}));

      final written = jsonEncode(entries);
      expect(written, isNot(contains('s1gnature')));
      expect(written, isNot(contains('h1dden')));
    });

    test("the default sets are structured_log_dio's", () {
      // A literal copy rather than an import: neither adapter depends on the
      // other, so the two copies are kept equal by this test.
      expect(defaultRedactedHeaders, {
        'authorization',
        'proxy-authorization',
        'cookie',
        'set-cookie',
        'x-api-key',
      });
      expect(defaultRedactedQueryParameters, {
        'access_token',
        'refresh_token',
        'id_token',
        'token',
        'api_key',
        'apikey',
        'password',
        'client_secret',
      });
    });
  });

  group('filter', () {
    test('drops the entries, not the correlation', () async {
      String? healthId;
      final handler = pipeline(
        (request) {
          if (request.url.path == 'health') healthId = request.requestId;
          return Response.ok('ok');
        },
        structuredLogRequests(filter: (r) => r.url.path != 'health'),
      );

      final health = await handler(get('/health'));
      await handler(get('/items'));

      expect([for (final e in entries) e['path']], ['/items']);
      expect(healthId, isNotNull);
      expect(health.headers['x-request-id'], healthId);
    });

    test('that throws costs the entries, never the response', () async {
      final response = await pipeline(
        (_) => Response.ok('ok'),
        structuredLogRequests(filter: (_) => throw StateError('filter')),
      )(get('/items'));

      expect(entries, isEmpty);
      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
      expect(response.headers['x-request-id'], isNotNull);
    });
  });

  group('logging never changes how a request ends', () {
    test('a sink that throws on every entry', () async {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'broken',
            output: (_, __) => throw StateError('sink'),
          ),
        ],
      );

      final response = await pipeline(ok)(get('/items'));

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
    });

    test('a handler that throws still throws its own error', () async {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(name: 'broken', output: (_, __) => throw StateError('sink')),
        ],
      );

      await expectLater(
        pipeline((_) => throw const FormatException('own'))(get('/items')),
        throwsFormatException,
      );
    });
  });

  group('the configuration', () {
    test('made after the Pipeline was built applies', () async {
      final handler = pipeline((request) {
        request.logger.info('handled_inside');
        return Response.ok('ok');
      });

      final later = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'later',
            output: (entry, _) => later.add(Map.of(entry)),
          ),
        ],
      );
      await handler(get('/items'));

      expect(eventsOf(entries), isEmpty);
      expect(eventsOf(later), ['handled_inside', 'http_request_handled']);
    });

    test('nothing is built for an entry no sink takes', () async {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'errors',
            output: (entry, _) => entries.add(Map.of(entry)),
            minLevel: LogLevel.error,
          ),
        ],
      );

      await pipeline(ok)(get('/items'));

      expect(httpEntries(entries), isEmpty);
    });
  });
}
