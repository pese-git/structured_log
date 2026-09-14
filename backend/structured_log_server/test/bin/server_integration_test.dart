@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Runs `bin/server.dart` as a real OS process — `log-server-config`'s
/// "config from environment, overridden by an argument" priority only
/// really proves itself once a genuinely separate process resolves
/// `Platform.environment` on its own, not through a value handed to it in
/// the same isolate.
void main() {
  test(
    'the server process starts from env config, an argument overrides the port, '
    'and it answers GET /healthz',
    () async {
      final dir =
          Directory.systemTemp.createTempSync('server_integration_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/test.sqlite';

      // Pick a free port by briefly binding to port 0.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start('dart', [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=$dbPath',
        '--http-port=$port', // overrides STRUCTURED_LOG_HTTP_PORT below
      ], environment: {
        'STRUCTURED_LOG_JWT_SIGNING_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_HTTP_PORT':
            '0', // would bind an ephemeral port if honored
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
      });
      addTearDown(() {
        process.kill(ProcessSignal.sigterm);
      });

      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      final ready = stdoutLines.firstWhere(
        (line) => line.contains('Listening on'),
      );
      await ready.timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw StateError('server did not report ready in time'),
      );

      final client = HttpClient();
      final httpRequest = await client.get('localhost', port, '/healthz');
      final httpResponse = await httpRequest.close();
      final body = await httpResponse.transform(utf8.decoder).join();
      client.close();
      expect(httpResponse.statusCode, 200);
      expect(jsonDecode(body), {'status': 'ok'});

      process.kill(ProcessSignal.sigterm);
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 10));
      expect(exitCode, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a live subscription over a real socket delivers new entries and catches '
    'up by since_id',
    () async {
      final dir =
          Directory.systemTemp.createTempSync('server_stream_integration');
      addTearDown(() => dir.deleteSync(recursive: true));

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start('dart', [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=${dir.path}/test.sqlite',
        '--http-port=$port',
        // Fast enough that a blocked project is noticed inside the test.
        '--sse-heartbeat-interval-seconds=1',
      ], environment: {
        'STRUCTURED_LOG_JWT_SIGNING_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'true',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_USERNAME': 'root',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'bootstrap-pw',
      });
      addTearDown(() => process.kill(ProcessSignal.sigterm));

      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      await stdoutLines
          .firstWhere((line) => line.contains('Listening on'))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('server did not report ready in time'),
          );

      final client = HttpClient();
      addTearDown(client.close);

      Future<Map<String, Object?>> call(
        String method,
        String path, {
        Object? json,
        String? bearer,
        String? form,
      }) async {
        final request = await client.open(method, 'localhost', port, path);
        if (bearer != null) {
          request.headers
              .set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
        }
        if (form != null) {
          request.headers.contentType =
              ContentType('application', 'x-www-form-urlencoded');
          request.write(form);
        } else if (json != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(json));
        }
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        expect(
          response.statusCode,
          lessThan(300),
          reason: '$method $path -> ${response.statusCode} $text',
        );
        if (text.isEmpty) return const {};
        return jsonDecode(text) as Map<String, Object?>;
      }

      Future<String> login(String password) async {
        final tokens = await call(
          'POST',
          '/v1/auth/token',
          form: 'grant_type=password&username=root&password=$password',
        );
        return tokens['access_token'] as String;
      }

      // The bootstrap admin starts with a temporary password, so everything
      // else is closed to it until it changes one.
      var token = await login('bootstrap-pw');
      await call(
        'POST',
        '/v1/auth/change-password',
        bearer: token,
        json: {'current_password': 'bootstrap-pw', 'new_password': 'real-pw'},
      );
      token = await login('real-pw');

      final group = await call('POST', '/v1/groups', bearer: token, json: {
        'name': 'g',
      });
      final groupId = group['id'] as int;
      final project = await call(
        'POST',
        '/v1/groups/$groupId/projects',
        bearer: token,
        json: {'name': 'p', 'retention_days': 7},
      );
      final projectId = project['id'] as int;
      final key = await call(
        'POST',
        '/v1/projects/$projectId/secret-keys',
        bearer: token,
        json: <String, Object?>{},
      );
      final secret = key['secret'] as String;
      expect(secret, startsWith('slk_'));

      Future<void> ingest(String event) async {
        await call(
          'POST',
          '/v1/logs',
          bearer: secret,
          json: [
            {
              'event': event,
              'level': 'info',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            }
          ],
        );
      }

      /// Opens a subscription and decodes frames as they arrive. Nothing
      /// here may collect the whole body: the endpoint never ends on its own.
      ///
      /// Each subscription gets its own [HttpClient] purely so that `drop`
      /// can tear the connection down the way a vanishing client does —
      /// which also matters for shutdown, since a graceful `server.close()`
      /// waits on connections that are still open.
      Future<
          ({
            List<Map<String, Object?>> events,
            List<String> ends,
            void Function() drop,
          })> subscribe(String query) async {
        final ownClient = HttpClient();
        final request =
            await ownClient.get('localhost', port, '/v1/logs/stream?$query');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(
          response.headers.contentType?.mimeType,
          'text/event-stream',
        );

        final events = <Map<String, Object?>>[];
        final ends = <String>[];
        unawaited(response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
          if (line.startsWith('event: end')) ends.add('end');
          if (!line.startsWith('data: ')) return;
          final payload = jsonDecode(line.substring(6)) as Map<String, Object?>;
          if (payload.containsKey('reason')) {
            ends.add(payload['reason'] as String);
          } else {
            events.add(payload);
          }
        }).catchError((_) {/* the connection was dropped on purpose */}));
        return (
          events: events,
          ends: ends,
          drop: () => ownClient.close(force: true),
        );
      }

      Future<void> waitFor(bool Function() test, String what) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!test()) {
          if (DateTime.now().isAfter(deadline))
            fail('timed out waiting: $what');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      // 1. Live delivery, with no polling in between.
      final first = await subscribe('project_id=$projectId');
      await ingest('live-1');
      await waitFor(() => first.events.isNotEmpty, 'the first live event');
      expect(first.events.single['event'], 'live-1');
      final lastId = first.events.single['id'] as int;

      // 2. Drop the subscription, miss some entries, reconnect with since_id.
      first.drop();
      await ingest('missed-1');
      await ingest('missed-2');

      final second = await subscribe('project_id=$projectId&since_id=$lastId');
      await waitFor(() => second.events.length >= 2, 'the missed entries');
      expect(
        second.events.map((e) => e['event']),
        containsAllInOrder(['missed-1', 'missed-2']),
      );
      expect(
        second.events.map((e) => e['id']).toSet().length,
        second.events.length,
        reason: 'no entry delivered twice',
      );

      // The remaining leg of tasks.md 21.8 — blocking the project ends the
      // open subscription — needs `POST /v1/projects/:id/block`, which is
      // section 5 and not implemented yet. It is covered at the handler
      // level in test/http/routes/log_stream_route_test.dart, which blocks
      // the project through the database directly.

      second.drop();
      process.kill(ProcessSignal.sigterm);
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 10));
      expect(exitCode, 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
