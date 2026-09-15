import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/live_feed_event.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_stream_client.dart';

/// One connection the client made: what it asked for, and the body it is
/// given back.
class _Connection {
  final RequestOptions options;
  final StreamController<Uint8List> body = StreamController<Uint8List>();

  _Connection(this.options);

  int? get sinceId {
    final raw = options.queryParameters['since_id'];
    return raw is int ? raw : int.tryParse('$raw');
  }

  void write(String frame) => body.add(Uint8List.fromList(utf8.encode(frame)));

  void log(int id, {String event = 'tick'}) => write(
    'id: $id\n'
    'event: log\n'
    'data: ${jsonEncode({'id': id, 'project_id': 1, 'received_at': '2026-09-15T09:00:00Z', 'event': event, 'level': 'info'})}\n'
    '\n',
  );

  void end(String reason) => write(
    'event: end\n'
    'data: ${jsonEncode({'reason': reason})}\n'
    '\n',
  );

  /// The connection drops without saying anything — the ordinary case.
  Future<void> drop() => body.close();
}

/// Answers `GET /v1/logs/stream` with a body the test writes into by hand.
class _StreamingAdapter implements HttpClientAdapter {
  final connections = <_Connection>[];

  /// Status for the next connection; 200 unless a test says otherwise.
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (status >= 400) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'forbidden', 'message': 'no'}),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final connection = _Connection(options);
    connections.add(connection);
    return ResponseBody(
      connection.body.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _StreamingAdapter adapter;
  late LogStreamClient client;

  setUp(() {
    // The client logs its reconnections; a test has no use for them on the
    // console, and `StructlogConfiguration` is global, so it is reset below.
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'silent', output: (_, _) {})],
    );
    adapter = _StreamingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://logs.test'))
      ..httpClientAdapter = adapter;
    client = LogStreamClient(
      dio,
      logger: getLogger('test'),
      initialBackoff: const Duration(milliseconds: 1),
      maxBackoff: const Duration(milliseconds: 4),
    );
  });

  tearDown(StructlogConfiguration.reset);

  Stream<LiveFeedEvent> connect({int? sinceId}) => client.connect(
    scope: const LogScope.project(id: 1, name: 'payments'),
    filter: const LogFilter(minLevel: 'warning'),
    sinceId: sinceId,
  );

  /// Waits until [count] connections have been made.
  Future<void> connections(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (adapter.connections.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('only ${adapter.connections.length} connections were made');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  group('frame parsing', () {
    Future<List<SseFrame>> framesOf(List<String> chunks) {
      final bytes = Stream.fromIterable(
        chunks.map((chunk) => utf8.encode(chunk)),
      );
      return parseSseFrames(bytes).toList();
    }

    test('a frame split across chunks is still one frame', () async {
      final frames = await framesOf([
        'id: 7\nev',
        'ent: log\ndata: {"a"',
        ':1}\n\n',
      ]);

      expect(frames, hasLength(1));
      expect(frames.single.id, 7);
      expect(frames.single.event, 'log');
      expect(frames.single.data, '{"a":1}');
    });

    test('keep-alive comments carry no frame', () async {
      final frames = await framesOf([': heartbeat\n\n: heartbeat\n\n']);

      expect(frames, isEmpty);
    });

    test('a payload with newlines arrives as several data lines', () async {
      final frames = await framesOf(['event: log\ndata: one\ndata: two\n\n']);

      expect(frames.single.data, 'one\ntwo');
    });

    test('a multi-byte character split across chunks survives', () async {
      final encoded = utf8.encode('data: привет\n\n');
      final frames = await parseSseFrames(
        Stream.fromIterable([encoded.sublist(0, 9), encoded.sublist(9)]),
      ).toList();

      expect(frames.single.data, 'привет');
    });
  });

  group('connecting', () {
    test('the subscription carries the scope, filter and since_id', () async {
      final events = <LiveFeedEvent>[];
      final subscription = connect(sinceId: 42).listen(events.add);
      await connections(1);

      final query = adapter.connections.single.options.queryParameters;
      expect(adapter.connections.single.options.path, '/v1/logs/stream');
      expect(query['project_id'], 1);
      expect(query['level'], 'warning');
      expect(query['since_id'], 42);

      await subscription.cancel();
    });

    test('log frames arrive as entries', () async {
      final events = <LiveFeedEvent>[];
      final subscription = connect().listen(events.add);
      await connections(1);

      adapter.connections.single
        ..write(': heartbeat\n\n')
        ..log(11, event: 'first')
        ..log(12, event: 'second');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, hasLength(2));
      expect((events.first as LiveFeedEntry).entry.event, 'first');
      expect((events.last as LiveFeedEntry).entry.id, 12);

      await subscription.cancel();
    });
  });

  group('reconnecting', () {
    test(
      'a dropped connection resumes after the last entry delivered',
      () async {
        final events = <LiveFeedEvent>[];
        final subscription = connect().listen(events.add);
        await connections(1);

        adapter.connections.first.log(11);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await adapter.connections.first.drop();
        await connections(2);

        expect(
          adapter.connections.last.sinceId,
          11,
          reason: 'the server replays the gap rather than starting from now',
        );
        expect(
          events.whereType<LiveFeedEnded>(),
          isEmpty,
          reason: 'an ordinary drop is not something the screen has to hear',
        );

        await subscription.cancel();
      },
    );

    test('a token the server revoked is retried, not surfaced', () async {
      final events = <LiveFeedEvent>[];
      final subscription = connect().listen(events.add);
      await connections(1);

      // 200 was already sent, so the server says so in the body — and the
      // reconnect is what gives the interceptor a 401 to refresh against.
      adapter.connections.first.end('token_revoked');
      await connections(2);

      expect(events, isEmpty);

      await subscription.cancel();
    });

    test('a blocked project ends the subscription for good', () async {
      final events = <LiveFeedEvent>[];
      var done = false;
      final subscription = connect().listen(
        events.add,
        onDone: () => done = true,
      );
      await connections(1);

      adapter.connections.first.end('project_blocked');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.single, const LiveFeedEvent.ended('project_blocked'));
      expect(done, isTrue);
      expect(
        adapter.connections,
        hasLength(1),
        reason: 'reconnecting would only be refused again',
      );

      await subscription.cancel();
    });

    test('a refusal to open is reported and not retried', () async {
      adapter.status = 403;
      final events = <LiveFeedEvent>[];
      final subscription = connect().listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.single, isA<LiveFeedFailed>());
      expect(adapter.connections, isEmpty);

      await subscription.cancel();
    });

    test('cancelling stops the reconnect loop', () async {
      final subscription = connect().listen((_) {});
      await connections(1);

      await adapter.connections.first.drop();
      await subscription.cancel();
      final made = adapter.connections.length;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        adapter.connections,
        hasLength(made),
        reason: 'a feed nobody is listening to must not keep dialling',
      );
    });
  });
}
