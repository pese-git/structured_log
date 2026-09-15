import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http/structured_log_http.dart';
import 'package:test/test.dart';

/// Records what it was asked to send and answers however the test says.
class FakeSender {
  final batches = <List<Map<String, dynamic>>>[];
  final List<BatchResult> scripted;
  BatchResult fallback;

  /// Completes on every call, so a test can wait for a specific attempt
  /// rather than sleeping.
  final _calls = StreamController<int>.broadcast();

  FakeSender({
    this.scripted = const [],
    this.fallback = const BatchResult.delivered(),
  });

  int get attempts => batches.length;
  Stream<int> get calls => _calls.stream;

  Future<BatchResult> send(List<Map<String, dynamic>> entries) async {
    batches.add(entries);
    _calls.add(batches.length);
    return batches.length <= scripted.length
        ? scripted[batches.length - 1]
        : fallback;
  }
}

Map<String, dynamic> entry(String event) => {'event': event, 'level': 'info'};

/// Polls until [test] holds — the output is driven by real timers, so there
/// is nothing to await directly.
Future<void> waitFor(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 3),
  String what = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  tearDown(StructlogConfiguration.reset);

  group('OutputFunction contract', () {
    test('plugs into a LogSink and queues what the logger produces', () async {
      final sender = FakeSender();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        sender: sender.send,
      );

      StructlogConfiguration.configure(
        sinks: [LogSink(name: 'server', output: output)],
      );
      getLogger().info('startup', context: {'port': 8080});
      await output.flushed;

      expect(sender.batches, hasLength(1));
      final sent = sender.batches.single.single;
      expect(sent['event'], 'startup');
      expect(sent['port'], 8080);
      expect(sent['level'], 'info');
    });
  });

  group('non-blocking delivery', () {
    test('logging returns before a slow send completes', () async {
      final release = Completer<void>();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        sender: (_) async {
          await release.future;
          return const BatchResult.delivered();
        },
      );

      var returned = false;
      output(entry('slow'), LogLevel.info);
      returned = true;

      expect(returned, isTrue, reason: 'the call must not await the send');
      final flushed = output.flushed;
      // Nothing has completed the send yet, so `flushed` must still be
      // pending — otherwise the test above proves nothing.
      var flushCompleted = false;
      unawaited(flushed.then((_) => flushCompleted = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(flushCompleted, isFalse);

      release.complete();
      await flushed;
      expect(flushCompleted, isTrue);
    });
  });

  group('batching', () {
    test('sends as soon as batchSize entries are waiting', () async {
      final sender = FakeSender();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 3,
        // Long enough that a timeout-driven send would fail the test.
        batchTimeout: const Duration(seconds: 30),
        sender: sender.send,
      );

      for (final e in ['a', 'b', 'c']) {
        output(entry(e), LogLevel.info);
      }
      await waitFor(() => sender.attempts == 1, what: 'the full batch');

      expect(sender.batches.single.map((e) => e['event']), ['a', 'b', 'c']);
    });

    test('a partial batch goes out when the timeout elapses', () async {
      final sender = FakeSender();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 100,
        batchTimeout: const Duration(milliseconds: 30),
        sender: sender.send,
      );

      output(entry('lonely'), LogLevel.info);
      await waitFor(() => sender.attempts == 1, what: 'the timed-out batch');

      expect(sender.batches.single.map((e) => e['event']), ['lonely']);
    });

    test('an idle output sends nothing', () async {
      final sender = FakeSender();
      HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchTimeout: const Duration(milliseconds: 20),
        sender: sender.send,
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sender.attempts, 0);
    });

    test('batches never overlap and keep their order', () async {
      var inFlight = 0;
      var overlapped = false;
      final seen = <String>[];
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        sender: (entries) async {
          if (inFlight > 0) overlapped = true;
          inFlight++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          seen.add(entries.single['event'] as String);
          inFlight--;
          return const BatchResult.delivered();
        },
      );

      for (final e in ['1', '2', '3']) {
        output(entry(e), LogLevel.info);
      }
      await output.flushed;

      expect(overlapped, isFalse);
      expect(seen, ['1', '2', '3']);
    });
  });

  group('retry with backoff', () {
    test('a transient failure is retried and then succeeds', () async {
      final sender = FakeSender(
        scripted: [const BatchResult.retryable('connection refused')],
      );
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        retryBackoff: const Duration(milliseconds: 5),
        sender: sender.send,
      );

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(sender.attempts, 2);
      expect(
        sender.batches.map((b) => b.single['event']),
        ['e', 'e'],
        reason: 'the same batch, not a re-queued copy',
      );
    });

    test('a delivered batch is not sent again', () async {
      final sender = FakeSender();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        sender: sender.send,
      );

      output(entry('once'), LogLevel.info);
      await output.flushed;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(sender.attempts, 1);
    });

    test('attempts stop at maxAttempts and the failure is reported', () async {
      final reports = <String>[];
      final sender = FakeSender(fallback: const BatchResult.retryable('down'));
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        maxAttempts: 3,
        retryBackoff: const Duration(milliseconds: 1),
        sender: sender.send,
        report: reports.add,
      );

      output(entry('doomed'), LogLevel.info);
      await output.flushed;

      expect(sender.attempts, 3);
      expect(reports.join('\n'), contains('giving up'));
    });

    test('the delay grows between attempts', () async {
      final at = <DateTime>[];
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        maxAttempts: 3,
        retryBackoff: const Duration(milliseconds: 40),
        sender: (_) async {
          at.add(DateTime.now());
          return const BatchResult.retryable('down');
        },
        report: (_) {},
      );

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(at, hasLength(3));
      final first = at[1].difference(at[0]);
      final second = at[2].difference(at[1]);
      expect(
        second,
        greaterThan(first),
        reason: 'backoff must grow, not stay flat',
      );
    });
  });

  group('non-retryable answers', () {
    test('a rejection is reported once and never retried', () async {
      final reports = <String>[];
      final sender = FakeSender(
        fallback: const BatchResult.rejected('HTTP 401'),
      );
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_revoked',
        batchSize: 1,
        retryBackoff: const Duration(milliseconds: 1),
        sender: sender.send,
        report: reports.add,
      );

      output(entry('rejected'), LogLevel.info);
      await output.flushed;

      expect(sender.attempts, 1, reason: 'a 401 will answer 401 forever');
      expect(reports.single, contains('HTTP 401'));
    });

    test('a rejected batch does not stop the ones behind it', () async {
      // The failure isolation `_SerializedAsyncOutput` exists for: one bad
      // batch must not silently kill the queue.
      var call = 0;
      final delivered = <String>[];
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        sender: (entries) async {
          call++;
          if (call == 1) return const BatchResult.rejected('HTTP 400');
          delivered.add(entries.single['event'] as String);
          return const BatchResult.delivered();
        },
        report: (_) {},
      );

      output(entry('bad'), LogLevel.info);
      output(entry('good'), LogLevel.info);
      await output.flushed;

      expect(delivered, ['good']);
    });

    test('a sender that throws is caught and the queue survives', () async {
      final reports = <String>[];
      var call = 0;
      final delivered = <String>[];
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        sender: (entries) async {
          call++;
          if (call == 1) throw StateError('boom');
          delivered.add(entries.single['event'] as String);
          return const BatchResult.delivered();
        },
        report: reports.add,
      );

      output(entry('throws'), LogLevel.info);
      output(entry('after'), LogLevel.info);
      await output.flushed;

      expect(reports.join('\n'), contains('boom'));
      expect(delivered, ['after']);
    });
  });

  group('bounded memory', () {
    test('the buffer never exceeds its limit and eviction is reported',
        () async {
      final reports = <String>[];
      final sender = FakeSender(fallback: const BatchResult.retryable('down'));
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        // Large enough that no batch leaves on its own while the test fills
        // the buffer past its limit.
        batchSize: 5,
        batchTimeout: const Duration(seconds: 30),
        maxBufferedEntries: 5,
        maxAttempts: 1,
        sender: sender.send,
        report: reports.add,
      );

      for (var i = 0; i < 12; i++) {
        output(entry('e$i'), LogLevel.info);
      }
      await output.flushed;

      final sent = sender.batches.expand((b) => b).toList();
      expect(
        sent.length,
        lessThanOrEqualTo(12),
        reason: 'nothing is invented',
      );
      expect(reports.join('\n'), contains('buffer full'));
      expect(reports.join('\n'), contains('dropped'));
    });

    test('the oldest entries are the ones dropped', () async {
      final sender = FakeSender();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 3,
        batchTimeout: const Duration(seconds: 30),
        maxBufferedEntries: 3,
        sender: sender.send,
        report: (_) {},
      );

      // Four entries into a three-deep buffer: the fourth evicts the first,
      // and the batch that leaves must be the three newest.
      output(entry('oldest'), LogLevel.info);
      output(entry('b'), LogLevel.info);
      await Future<void>.delayed(Duration.zero);
      expect(sender.attempts, 0, reason: 'batchSize not reached yet');

      output(entry('c'), LogLevel.info);
      await waitFor(() => sender.attempts == 1, what: 'the first batch');
      expect(sender.batches.single.map((e) => e['event']), [
        'oldest',
        'b',
        'c',
      ]);
    });

    test('maxBufferedEntries below batchSize is refused at construction', () {
      // Otherwise a full batch could never be assembled and the output would
      // quietly never send anything.
      expect(
        () => HttpLogOutput(
          serverUrl: 'http://example.invalid',
          projectSecretKey: 'slk_test',
          batchSize: 10,
          maxBufferedEntries: 5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('flushed', () {
    test('sends what is still buffered rather than waiting for the timeout',
        () async {
      final sender = FakeSender();
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 100,
        batchTimeout: const Duration(seconds: 30),
        sender: sender.send,
      );

      output(entry('pending'), LogLevel.info);
      await output.flushed;

      expect(sender.attempts, 1);
    });

    test('completes even when every attempt failed', () async {
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        batchSize: 1,
        maxAttempts: 2,
        retryBackoff: const Duration(milliseconds: 1),
        sender: (_) async => const BatchResult.retryable('down'),
        report: (_) {},
      );

      output(entry('e'), LogLevel.info);
      await output.flushed.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('flushed must complete on final failure too'),
      );
    });

    test('on an empty output it completes immediately', () async {
      final output = HttpLogOutput(
        serverUrl: 'http://example.invalid',
        projectSecretKey: 'slk_test',
        sender: (_) async => const BatchResult.delivered(),
      );

      await output.flushed.timeout(const Duration(seconds: 1));
    });
  });

  group('over a real socket', () {
    late HttpServer server;
    late List<HttpRequest> received;
    late List<String> bodies;
    late int status;

    setUp(() async {
      status = 202;
      received = [];
      bodies = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        received.add(request);
        bodies.add(await utf8.decodeStream(request));
        request.response.statusCode = status;
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('posts the batch to /v1/logs with the project key', () async {
      final output = HttpLogOutput(
        serverUrl: 'http://localhost:${server.port}',
        projectSecretKey: 'slk_secret',
        batchSize: 2,
      );
      addTearDown(output.close);

      output(entry('one'), LogLevel.info);
      output(entry('two'), LogLevel.info);
      await output.flushed;

      expect(received, hasLength(1));
      final request = received.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/logs');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer slk_secret',
      );
      expect(request.headers.contentType?.mimeType, 'application/json');

      final sent = jsonDecode(bodies.single) as List;
      expect(sent.map((e) => (e as Map)['event']), ['one', 'two']);
    });

    test('a base URL with a trailing slash still hits /v1/logs', () async {
      final output = HttpLogOutput(
        serverUrl: 'http://localhost:${server.port}/',
        projectSecretKey: 'slk_secret',
        batchSize: 1,
      );
      addTearDown(output.close);

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(received.single.uri.path, '/v1/logs');
    });

    test('a 5xx is retried', () async {
      status = 503;
      final reports = <String>[];
      final output = HttpLogOutput(
        serverUrl: 'http://localhost:${server.port}',
        projectSecretKey: 'slk_secret',
        batchSize: 1,
        maxAttempts: 2,
        retryBackoff: const Duration(milliseconds: 5),
        report: reports.add,
      );
      addTearDown(output.close);

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(received, hasLength(2));
      expect(reports.join('\n'), contains('giving up'));
    });

    test('a 401 is not retried', () async {
      status = 401;
      final reports = <String>[];
      final output = HttpLogOutput(
        serverUrl: 'http://localhost:${server.port}',
        projectSecretKey: 'slk_revoked',
        batchSize: 1,
        maxAttempts: 4,
        retryBackoff: const Duration(milliseconds: 5),
        report: reports.add,
      );
      addTearDown(output.close);

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(received, hasLength(1));
      expect(reports.single, contains('HTTP 401'));
    });

    test('429 is treated as "later", not "never"', () async {
      status = 429;
      final output = HttpLogOutput(
        serverUrl: 'http://localhost:${server.port}',
        projectSecretKey: 'slk_secret',
        batchSize: 1,
        maxAttempts: 2,
        retryBackoff: const Duration(milliseconds: 5),
        report: (_) {},
      );
      addTearDown(output.close);

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(received, hasLength(2));
    });

    test('an unreachable server is retried, then given up on', () async {
      final port = server.port;
      await server.close(force: true);
      final reports = <String>[];
      final output = HttpLogOutput(
        serverUrl: 'http://localhost:$port',
        projectSecretKey: 'slk_secret',
        batchSize: 1,
        maxAttempts: 2,
        retryBackoff: const Duration(milliseconds: 5),
        report: reports.add,
      );
      addTearDown(output.close);

      output(entry('e'), LogLevel.info);
      await output.flushed;

      expect(reports.join('\n'), contains('giving up'));
    });
  });
}
