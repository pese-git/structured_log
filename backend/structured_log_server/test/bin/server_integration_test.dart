@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:structured_log_server/src/storage/database.dart';
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
      final dir = Directory.systemTemp.createTempSync(
        'server_integration_test',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/test.sqlite';

      // Pick a free port by briefly binding to port 0.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=$dbPath',
          '--http-port=$port', // overrides STRUCTURED_LOG_HTTP_PORT below
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_HTTP_PORT':
              '0', // would bind an ephemeral port if honored
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
        },
      );
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
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );
      expect(exitCode, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a live subscription over a real socket delivers new entries and catches '
    'up by since_id',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'server_stream_integration',
      );
      addTearDown(() => dir.deleteSync(recursive: true));

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=${dir.path}/test.sqlite',
          '--http-port=$port',
          // Fast enough that a blocked project is noticed inside the test.
          '--sse-heartbeat-interval-seconds=1',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'true',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_USERNAME': 'root',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'bootstrap-pw',
        },
      );
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
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $bearer',
          );
        }
        if (form != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
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
        json: {
          'current_password': 'bootstrap-pw',
          'new_password': 'real-password-1',
        },
      );
      token = await login('real-password-1');

      final group = await call(
        'POST',
        '/v1/groups',
        bearer: token,
        json: {'name': 'g'},
      );
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
            },
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
        })
      >
      subscribe(String query) async {
        final ownClient = HttpClient();
        final request = await ownClient.get(
          'localhost',
          port,
          '/v1/logs/stream?$query',
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(response.headers.contentType?.mimeType, 'text/event-stream');

        final events = <Map<String, Object?>>[];
        final ends = <String>[];
        unawaited(
          response
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .forEach((line) {
                if (line.startsWith('event: end')) ends.add('end');
                if (!line.startsWith('data: ')) return;
                final payload =
                    jsonDecode(line.substring(6)) as Map<String, Object?>;
                if (payload.containsKey('reason')) {
                  ends.add(payload['reason'] as String);
                } else {
                  events.add(payload);
                }
              })
              .catchError((_) {
                /* the connection was dropped on purpose */
              }),
        );
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
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );
      expect(exitCode, 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'over a real process: RBAC, revocation, quotas and the two error shapes',
    () async {
      final dir = Directory.systemTemp.createTempSync('server_api_integration');
      addTearDown(() => dir.deleteSync(recursive: true));

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=${dir.path}/test.sqlite',
          '--http-port=$port',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'true',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_USERNAME': 'root',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'bootstrap-pw',
        },
      );
      addTearDown(() => process.kill(ProcessSignal.sigterm));
      final stderrLines = <String>[];
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stderrLines.add);

      // Broadcast, and kept subscribed: dropping the subscription closes
      // the pipe, and the server's own "Shutting down..." then dies of a
      // broken pipe — which would show up as a bogus non-zero exit code.
      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      stdoutLines.listen((_) {});
      await stdoutLines
          .firstWhere((line) => line.contains('Listening on'))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('server did not report ready in time'),
          );

      final client = HttpClient();
      addTearDown(client.close);

      /// Unlike the helper in the streaming test, this one reports the
      /// status instead of asserting success: half these cases are about
      /// what the server refuses.
      Future<({int status, Map<String, Object?> body})> call(
        String method,
        String path, {
        Object? json,
        String? bearer,
        String? form,
      }) async {
        final request = await client.open(method, 'localhost', port, path);
        if (bearer != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $bearer',
          );
        }
        if (form != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          request.write(form);
        } else if (json != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(json));
        }
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        return (
          status: response.statusCode,
          body: text.isEmpty
              ? const <String, Object?>{}
              : jsonDecode(text) as Map<String, Object?>,
        );
      }

      Future<({String access, String refresh})> login(
        String username,
        String password,
      ) async {
        final response = await call(
          'POST',
          '/v1/auth/token',
          form: 'grant_type=password&username=$username&password=$password',
        );
        expect(response.status, 200, reason: '${response.body}');
        return (
          access: response.body['access_token'] as String,
          refresh: response.body['refresh_token'] as String,
        );
      }

      // --- the forced-password-change gate, end to end -------------------
      var tokens = await login('root', 'bootstrap-pw');

      final gated = await call('GET', '/v1/groups', bearer: tokens.access);
      expect(gated.status, 403, reason: 'a temporary password gates the API');
      expect(gated.body['error'], 'must_change_password');

      final changed = await call(
        'POST',
        '/v1/auth/change-password',
        bearer: tokens.access,
        json: {
          'current_password': 'bootstrap-pw',
          'new_password': 'real-password-1',
        },
      );
      expect(changed.status, 200);

      // Changing the password bumps token_version, so the token that just
      // made the change is itself no longer valid.
      final afterChange = await call(
        'GET',
        '/v1/groups',
        bearer: tokens.access,
      );
      expect(afterChange.status, 401);

      tokens = await login('root', 'real-password-1');
      final admin = tokens.access;
      expect((await call('GET', '/v1/groups', bearer: admin)).status, 200);

      // --- the two error shapes the API deliberately keeps apart ---------
      final badGrant = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=password&username=root&password=wrong',
      );
      expect(badGrant.status, 400);
      expect(badGrant.body['error'], 'invalid_grant');
      expect(
        badGrant.body,
        contains('error_description'),
        reason: 'RFC 6749 §5.2 shape, not the general envelope',
      );

      final notFound = await call('GET', '/v1/projects/999999', bearer: admin);
      expect(notFound.status, 404);
      expect(notFound.body['error'], 'not_found');
      expect(
        notFound.body,
        contains('message'),
        reason: 'the general envelope, not the RFC 6749 one',
      );

      // --- resources, and a caller who may not touch them ----------------
      final group = await call(
        'POST',
        '/v1/groups',
        bearer: admin,
        json: {'name': 'g'},
      );
      expect(group.status, 201);
      final groupId = group.body['id'] as int;

      final project = await call(
        'POST',
        '/v1/groups/$groupId/projects',
        bearer: admin,
        json: {'name': 'p', 'retention_days': 7, 'max_entries': 2},
      );
      expect(project.status, 201);
      final projectId = project.body['id'] as int;

      final key = await call(
        'POST',
        '/v1/projects/$projectId/secret-keys',
        bearer: admin,
        json: <String, Object?>{},
      );
      expect(key.status, 201);
      final secret = key.body['secret'] as String;
      expect(secret, startsWith('slk_'));

      // The plaintext key is shown exactly once.
      final listed = await call(
        'GET',
        '/v1/projects/$projectId/secret-keys',
        bearer: admin,
      );
      expect(listed.status, 200);
      final items = listed.body['items'] as List;
      expect(items.single, isNot(contains('secret')));

      // --- the two credentials do not substitute for one another ---------
      expect(
        (await call('GET', '/v1/groups', bearer: secret)).status,
        401,
        reason: 'a project key is not an access token',
      );
      expect(
        (await call(
          'POST',
          '/v1/logs',
          bearer: admin,
          json: <Object?>[],
        )).status,
        401,
        reason: 'an access token does not authenticate ingestion',
      );

      // --- quotas, enforced per entry ------------------------------------
      Map<String, Object?> entry(String event) => {
        'event': event,
        'level': 'info',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      final ingest = await call(
        'POST',
        '/v1/logs',
        bearer: secret,
        json: [entry('a'), entry('b'), entry('over-quota')],
      );
      expect(ingest.status, 202, reason: 'the request itself is well-formed');
      expect(ingest.body['accepted'], 2);
      final rejected = ingest.body['rejected'] as List;
      expect(rejected, hasLength(1));
      expect(
        (rejected.single as Map)['error'],
        'quota_exceeded',
        reason: 'max_entries was 2',
      );
      expect(
        (rejected.single as Map)['index'],
        2,
        reason: 'the rejection names which entry of the batch it was',
      );

      // Raising the quota lets the next batch through — the same path the
      // operator would take after seeing the rejection.
      expect(
        (await call(
          'PATCH',
          '/v1/projects/$projectId',
          bearer: admin,
          json: {'max_entries': 100},
        )).status,
        200,
      );
      final afterRaise = await call(
        'POST',
        '/v1/logs',
        bearer: secret,
        json: [entry('now-fits')],
      );
      expect(afterRaise.body['accepted'], 1);
      expect(afterRaise.body['rejected'], isEmpty);

      final queried = await call(
        'GET',
        '/v1/logs?project_id=$projectId',
        bearer: admin,
      );
      expect(queried.status, 200);
      expect(
        (queried.body['items'] as List).map((e) => (e as Map)['event']),
        containsAll(['a', 'b', 'now-fits']),
      );

      // --- a caller with no roles sees nothing ---------------------------
      // A bare user is what `POST /v1/users` will create; until that
      // endpoint exists, logging in as one is not possible, so the closest
      // end-to-end check is that a wrong/forged token is refused.
      expect(
        (await call('GET', '/v1/groups', bearer: 'not-a-token')).status,
        401,
      );

      // --- refresh and revocation ----------------------------------------
      final refreshed = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=refresh_token&refresh_token=${tokens.refresh}',
      );
      expect(refreshed.status, 200);

      final revoke = await call(
        'DELETE',
        '/v1/auth/token',
        form: 'refresh_token=${tokens.refresh}',
      );
      expect(revoke.status, 200);

      final reuse = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=refresh_token&refresh_token=${tokens.refresh}',
      );
      expect(reuse.status, 400, reason: 'a revoked refresh token is dead');
      expect(reuse.body['error'], 'invalid_grant');

      process.kill(ProcessSignal.sigterm);
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );
      expect(exitCode, 0, reason: stderrLines.join('\n'));
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'a console that stops reading does not turn a clean shutdown into a crash',
    () async {
      final dir = Directory.systemTemp.createTempSync('server_pipe_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=${dir.path}/test.sqlite',
          '--http-port=$port',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
        },
      );
      addTearDown(() => process.kill(ProcessSignal.sigterm));

      final stderrLines = <String>[];
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stderrLines.add);

      // `firstWhere` cancels its subscription once it matches, which closes
      // the read end of the pipe — the same thing `| head` does, or a
      // supervisor that exits while the server keeps running. The server
      // then writes "Shutting down..." into a pipe nobody holds.
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.contains('Listening on'))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('server did not report ready in time'),
          );

      process.kill(ProcessSignal.sigterm);
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );

      // Without the guard in bin/server.dart this is 255: the broken pipe
      // arrives as an unhandled error in the root zone, where neither a
      // try/catch nor a guarded zone can intercept it.
      expect(exitCode, 0, reason: stderrLines.join('\n'));
      expect(stderrLines.join('\n'), isNot(contains('Unhandled exception')));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('the rate limiter is actually wired into the running server', () async {
    // buildHandler takes the config as an optional argument, so the whole
    // limiter is inert unless bin/server.dart passes it — which it once
    // silently did not. Every other rate-limit test builds the handler
    // itself and cannot see that.
    final dir = Directory.systemTemp.createTempSync('server_ratelimit_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final process = await Process.start(
      'dart',
      [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=${dir.path}/test.sqlite',
        '--http-port=$port',
        '--rate-limit-bucket-capacity=3',
        // Slow enough that the bucket cannot refill mid-test.
        '--rate-limit-refill-per-minute=1',
      ],
      environment: {
        'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
      },
    );
    addTearDown(() => process.kill(ProcessSignal.sigterm));

    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    stdoutLines.listen((_) {});
    await stdoutLines
        .firstWhere((line) => line.contains('Listening on'))
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw StateError('server did not report ready in time'),
        );

    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> attempt() async {
      final request = await client.postUrl(
        Uri.parse('http://localhost:$port/v1/auth/token'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write('grant_type=password&username=nobody&password=wrong');
      return request.close();
    }

    // Three attempts fit in the bucket and are refused on their merits;
    // the fourth is refused by the limiter.
    for (var i = 0; i < 3; i++) {
      final response = await attempt();
      await response.drain<void>();
      expect(response.statusCode, 400, reason: 'attempt $i');
    }

    final throttled = await attempt();
    final body = await throttled.transform(utf8.decoder).join();
    expect(throttled.statusCode, 429);
    expect(throttled.headers.value('retry-after'), isNotNull);
    expect(jsonDecode(body), containsPair('error', 'too_many_requests'));

    process.kill(ProcessSignal.sigterm);
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'the running server logs its own diagnostics as structured JSON',
    () async {
      // buildHandler takes the logger as an optional argument, exactly like
      // the rate-limit config did — so "the middleware exists and is tested"
      // says nothing about whether the real process installed it.
      final dir = Directory.systemTemp.createTempSync('server_logging_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=${dir.path}/test.sqlite',
          '--http-port=$port',
          '--log-format=json',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
        },
      );
      addTearDown(() => process.kill(ProcessSignal.sigterm));

      final lines = <String>[];
      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      stdoutLines.listen(lines.add);
      await stdoutLines
          .firstWhere((line) => line.contains('Listening on'))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('server did not report ready in time'),
          );

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.get('localhost', port, '/healthz');
      await (await request.close()).drain<void>();

      Map<String, Object?>? entryWhere(
        bool Function(Map<String, Object?>) test,
      ) {
        for (final line in lines) {
          if (!line.startsWith('{')) continue;
          final decoded = jsonDecode(line);
          if (decoded is Map<String, Object?> && test(decoded)) return decoded;
        }
        return null;
      }

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (entryWhere((e) => e['event'] == 'request.completed') == null) {
        if (DateTime.now().isAfter(deadline)) {
          fail('no request.completed logged; stdout was:\n${lines.join('\n')}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final completed = entryWhere((e) => e['event'] == 'request.completed')!;
      expect(completed['method'], 'GET');
      expect(completed['path'], '/healthz');
      expect(completed['status'], 200);
      expect(completed['request_id'], isA<String>());

      final started = entryWhere((e) => e['event'] == 'server.starting');
      expect(started, isNotNull, reason: 'startup is logged too');
      expect(
        started!['jwt_secret'],
        '***',
        reason: 'the effective configuration is logged with secrets masked',
      );
      expect(
        lines.join('\n'),
        isNot(contains('integration-test-secret')),
        reason: 'and the secret itself never appears',
      );

      process.kill(ProcessSignal.sigterm);
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('the retention purge job runs in the running server', () async {
    // Third instance of the same hazard: the job is constructed in
    // bin/server.dart, so unit tests of the scheduler say nothing about
    // whether the process ever starts one. A pass that deletes nothing
    // looks identical to a job that was never scheduled, which is why it
    // reports itself at debug.
    final dir = Directory.systemTemp.createTempSync('server_purge_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final process = await Process.start(
      'dart',
      [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=${dir.path}/test.sqlite',
        '--http-port=$port',
        '--log-format=json',
        '--log-level=debug',
        '--retention-purge-interval-seconds=1',
      ],
      environment: {
        'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
      },
    );
    addTearDown(() => process.kill(ProcessSignal.sigterm));

    final lines = <String>[];
    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    stdoutLines.listen(lines.add);
    await stdoutLines
        .firstWhere((line) => line.contains('Listening on'))
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw StateError('server did not report ready in time'),
        );

    bool sawPurge() => lines.any(
      (line) =>
          line.startsWith('{') && line.contains('retention.purge_completed'),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!sawPurge()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the purge job never ran; stdout was:\n${lines.join('\n')}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    process.kill(ProcessSignal.sigterm);
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'over a real process: create-admin marks the first administrator primary, '
    'refuses a second one, and the serving process accepts that account',
    () async {
      // `createAdmin()` is unit-tested, but nothing there proves the
      // `create-admin` subcommand reaches it with the resolved config, nor
      // that the account it writes is one the serving process will then
      // accept (`tasks.md` 10.9 — the same wiring hazard as the purge job
      // above).
      final dir = Directory.systemTemp.createTempSync(
        'create_admin_integration',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/test.sqlite';

      // The password goes through the environment because it has to: a
      // secret parameter deliberately has no CLI flag at all
      // (`config_resolver.dart`), so it can never land in a process listing.
      Future<ProcessResult> runCreateAdmin(String username, String password) {
        return Process.run(
          'dart',
          [
            'run',
            'bin/server.dart',
            'create-admin',
            '--db-path=$dbPath',
            '--bootstrap-admin-username=$username',
          ],
          environment: {'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': password},
        );
      }

      final first = await runCreateAdmin('root', 'chosen-pw');
      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(first.stdout as String, contains('Created administrator "root"'));
      // A password the operator chose is never echoed back at them — only a
      // generated one is, and then on stderr as a one-time warning.
      expect('${first.stdout}${first.stderr}', isNot(contains('chosen-pw')));

      // No second administrator while the first is active: `create-admin` is
      // a recovery path, not a user-management command (`design.md`
      // decisions 12/27).
      final second = await runCreateAdmin('second', 'other-pw');
      expect(second.exitCode, isNot(0));
      expect(
        second.stderr as String,
        contains('active administrator already exists'),
      );

      // `is_primary_admin` has no HTTP surface in Stage 1 (`GET /v1/users`
      // is section 5.1), so the table is the only place it can be read.
      final db = StructuredLogDatabase.open(dbPath);
      final users = await db.select(db.users).get();
      await db.close();
      expect(users, hasLength(1), reason: 'the refused call wrote nothing');
      expect(users.single.username, 'root');
      expect(users.single.isPrimaryAdmin, isTrue);
      expect(
        users.single.mustChangePassword,
        isFalse,
        reason: 'the operator chose the password themselves',
      );

      // --- and the serving process accepts that account ------------------
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=$dbPath',
          '--http-port=$port',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          // Off, so the account under test is the one create-admin wrote and
          // not one auto-bootstrap produced on the way up.
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
        },
      );
      addTearDown(() => process.kill(ProcessSignal.sigterm));

      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      stdoutLines.listen((_) {});
      await stdoutLines
          .firstWhere((line) => line.contains('Listening on'))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('server did not report ready in time'),
          );

      final client = HttpClient();
      addTearDown(client.close);

      final tokenRequest = await client.open(
        'POST',
        'localhost',
        port,
        '/v1/auth/token',
      );
      tokenRequest.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      tokenRequest.write(
        'grant_type=password&username=root&password=chosen-pw',
      );
      final tokenResponse = await tokenRequest.close();
      final tokenBody =
          jsonDecode(await tokenResponse.transform(utf8.decoder).join())
              as Map<String, Object?>;
      expect(tokenResponse.statusCode, 200, reason: '$tokenBody');

      final groupsRequest = await client.open(
        'GET',
        'localhost',
        port,
        '/v1/groups',
      );
      groupsRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${tokenBody['access_token']}',
      );
      final groupsResponse = await groupsRequest.close();
      await groupsResponse.drain<void>();
      expect(
        groupsResponse.statusCode,
        200,
        reason: 'a password the operator chose does not gate the API',
      );

      process.kill(ProcessSignal.sigterm);
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('over a real process: the audit log records what was done and who tried '
      'to get in', () async {
    final dir = Directory.systemTemp.createTempSync('server_audit_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final process = await Process.start(
      'dart',
      [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=${dir.path}/test.sqlite',
        '--http-port=$port',
        // Small enough to exhaust deliberately, and refilling slowly enough
        // that recovery cannot happen mid-test by accident.
        '--rate-limit-bucket-capacity=5',
        '--rate-limit-refill-per-minute=1',
      ],
      environment: {
        'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'true',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_USERNAME': 'root',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'bootstrap-pw',
      },
    );
    addTearDown(() => process.kill(ProcessSignal.sigterm));

    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    stdoutLines.listen((_) {});
    await stdoutLines
        .firstWhere((line) => line.contains('Listening on'))
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw StateError('server did not report ready in time'),
        );

    final client = HttpClient();
    addTearDown(client.close);

    Future<({int status, Map<String, Object?> body})> call(
      String method,
      String path, {
      Object? json,
      String? bearer,
      String? form,
    }) async {
      final request = await client.open(method, 'localhost', port, path);
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(form);
      } else if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (
        status: response.statusCode,
        body: text.isEmpty
            ? const <String, Object?>{}
            : jsonDecode(text) as Map<String, Object?>,
      );
    }

    // One session first, before anything spends the address bucket: the
    // audit log is not a throttled endpoint, so this token keeps working
    // once the limiter has shut the door on logging in.
    var tokens = await (() async {
      final response = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=password&username=root&password=bootstrap-pw',
      );
      expect(response.status, 200, reason: '${response.body}');
      return response.body['access_token']! as String;
    })();

    await call(
      'POST',
      '/v1/auth/change-password',
      bearer: tokens,
      json: {
        'current_password': 'bootstrap-pw',
        'new_password': 'real-password-1',
      },
    );
    final relogin = await call(
      'POST',
      '/v1/auth/token',
      form: 'grant_type=password&username=root&password=real-password-1',
    );
    expect(relogin.status, 200, reason: '${relogin.body}');
    tokens = relogin.body['access_token']! as String;

    // --- what an administrator did -------------------------------------
    final group = await call(
      'POST',
      '/v1/groups',
      bearer: tokens,
      json: {'name': 'payments'},
    );
    expect(group.status, 201);
    final groupId = group.body['id'];

    final project = await call(
      'POST',
      '/v1/groups/$groupId/projects',
      bearer: tokens,
      json: {'name': 'checkout', 'retention_days': 30},
    );
    expect(project.status, 201);
    final projectId = project.body['id'];

    final key = await call(
      'POST',
      '/v1/projects/$projectId/secret-keys',
      bearer: tokens,
      json: {'label': 'ci'},
    );
    expect(key.status, 201);
    final secret = key.body['secret']! as String;

    expect(
      (await call(
        'DELETE',
        '/v1/projects/$projectId/secret-keys/${key.body['id']}',
        bearer: tokens,
      )).status,
      204,
    );

    Future<List<Map<String, Object?>>> auditLog([String query = '']) async {
      final response = await call('GET', '/v1/audit-log$query', bearer: tokens);
      expect(response.status, 200, reason: '${response.body}');
      return (response.body['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
    }

    final actions = (await auditLog()).map((e) => e['action']).toSet();
    expect(
      actions,
      containsAll(<String>[
        'password.changed',
        'group.created',
        'project.created',
        'secret_key.created',
        'secret_key.revoked',
        'auth.login_succeeded',
      ]),
      reason: 'the five mutations plus the sessions that made them',
    );

    final creations = await auditLog('?action=secret_key.created');
    expect(creations, hasLength(1));
    expect(creations.single['target_id'], key.body['id']);

    // The key was answered once, to one caller. The journal is read by more
    // people and for far longer.
    for (final record in await auditLog('?limit=200')) {
      expect(jsonEncode(record), isNot(contains(secret)));
    }

    expect(
      (await call('GET', '/v1/audit-log')).status,
      401,
      reason: 'no credential at all',
    );
    // A project key authenticates ingestion, not administration.
    expect((await call('GET', '/v1/audit-log', bearer: secret)).status, 401);

    // --- who tried to get in --------------------------------------------
    var throttled = false;
    for (var attempt = 0; attempt < 10 && !throttled; attempt++) {
      final refused = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=password&username=root&password=Pa55word-typo',
      );
      throttled = refused.status == 429;
      if (!throttled) expect(refused.status, 400);
    }
    expect(throttled, isTrue, reason: 'the limiter closed the door');

    final failures = await auditLog('?action=auth.login_failed');
    expect(failures, isNotEmpty);
    expect(
      (failures.first['metadata']! as Map)['reason'],
      'invalid_password',
      reason: 'the account exists; only the password was wrong',
    );

    final episodes = await auditLog('?action=auth.throttled');
    expect(
      episodes,
      hasLength(1),
      reason: 'a burst is one episode, however many requests it took',
    );
    expect((episodes.single['metadata']! as Map)['key_kind'], 'ip');

    // Neither the typed password nor anything resembling it survives.
    for (final record in await auditLog('?limit=200')) {
      expect(jsonEncode(record), isNot(contains('Pa55word-typo')));
      expect(jsonEncode(record), isNot(contains('real-password-1')));
    }

    process.kill(ProcessSignal.sigterm);
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 0);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'over a real process: blocking, self-deletion, admin deletion, and '
    'primary-administrator protection (Этап 3, tasks 10.4/10.5/10.7/10.9a)',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'server_user_lifecycle_test',
      );
      addTearDown(() => dir.deleteSync(recursive: true));

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=${dir.path}/test.sqlite',
          '--http-port=$port',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'true',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_USERNAME': 'root',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'bootstrap-pw',
          // This scenario logs in a couple dozen times from one address to
          // exercise several accounts in turn — `log-server-rate-limit`'s IP
          // bucket is covered by its own test above, not this one.
          'STRUCTURED_LOG_RATE_LIMIT_ENABLED': 'false',
        },
      );
      addTearDown(() => process.kill(ProcessSignal.sigterm));

      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      stdoutLines.listen((_) {});
      await stdoutLines
          .firstWhere((line) => line.contains('Listening on'))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('server did not report ready in time'),
          );

      final client = HttpClient();
      addTearDown(client.close);

      Future<({int status, Map<String, Object?> body})> call(
        String method,
        String path, {
        Object? json,
        String? bearer,
        String? form,
      }) async {
        final request = await client.open(method, 'localhost', port, path);
        if (bearer != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $bearer',
          );
        }
        if (form != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          request.write(form);
        } else if (json != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(json));
        }
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        return (
          status: response.statusCode,
          body: text.isEmpty
              ? const <String, Object?>{}
              : jsonDecode(text) as Map<String, Object?>,
        );
      }

      Future<({String access, String refresh})> login(
        String username,
        String password,
      ) async {
        final response = await call(
          'POST',
          '/v1/auth/token',
          form: 'grant_type=password&username=$username&password=$password',
        );
        expect(response.status, 200, reason: '${response.body}');
        return (
          access: response.body['access_token'] as String,
          refresh: response.body['refresh_token'] as String,
        );
      }

      /// Creates a user through `POST /v1/users` (temporary password), then
      /// walks it through the mandatory first change — `must_change_password`
      /// gates everything else, so a freshly admin-created account cannot do
      /// anything, including block/delete itself, until this runs.
      Future<({int id, String access, String refresh})> createAndActivateUser(
        String adminAccess,
        String username,
        String newPassword,
      ) async {
        final created = await call(
          'POST',
          '/v1/users',
          bearer: adminAccess,
          json: {'username': username, 'password': 'temp-$username'},
        );
        expect(created.status, 201, reason: '${created.body}');
        final id = created.body['id'] as int;

        var tokens = await login(username, 'temp-$username');
        final gated = await call('GET', '/v1/groups', bearer: tokens.access);
        expect(gated.status, 403);
        expect(gated.body['error'], 'must_change_password');

        final changed = await call(
          'POST',
          '/v1/auth/change-password',
          bearer: tokens.access,
          json: {
            'current_password': 'temp-$username',
            'new_password': newPassword,
          },
        );
        expect(changed.status, 200, reason: '${changed.body}');

        tokens = await login(username, newPassword);
        return (id: id, access: tokens.access, refresh: tokens.refresh);
      }

      // Root's own forced-password-change, out of the way first.
      var rootTokens = await login('root', 'bootstrap-pw');
      await call(
        'POST',
        '/v1/auth/change-password',
        bearer: rootTokens.access,
        json: {
          'current_password': 'bootstrap-pw',
          'new_password': 'root-password-1',
        },
      );
      rootTokens = await login('root', 'root-password-1');
      final admin = rootTokens.access;

      // ==================================================================
      // 10.4 — blocking a user and a project
      // ==================================================================

      final victim = await createAndActivateUser(admin, 'victim', 'victim-pw');
      final victimId = victim.id;
      var victimAccess = victim.access;
      final victimRefresh = victim.refresh;

      final blockVictim = await call(
        'POST',
        '/v1/users/$victimId/block',
        bearer: admin,
      );
      expect(blockVictim.status, 200);
      expect(
        (await call('GET', '/v1/groups', bearer: victimAccess)).status,
        401,
        reason: 'token_version bumped by blocking',
      );
      final refreshBlocked = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=refresh_token&refresh_token=$victimRefresh',
      );
      expect(refreshBlocked.status, 400);
      expect(refreshBlocked.body['error'], 'invalid_grant');

      final unblockVictim = await call(
        'POST',
        '/v1/users/$victimId/unblock',
        bearer: admin,
      );
      expect(unblockVictim.status, 200);
      victimAccess = (await login('victim', 'victim-pw')).access;
      expect(
        (await call('GET', '/v1/groups', bearer: victimAccess)).status,
        200,
        reason: 'unblocking restores access',
      );

      // --- project blocking ------------------------------------------------
      final group = await call(
        'POST',
        '/v1/groups',
        bearer: admin,
        json: {'name': 'payments'},
      );
      final groupId = group.body['id'];
      final blockedProject = await call(
        'POST',
        '/v1/groups/$groupId/projects',
        bearer: admin,
        json: {'name': 'checkout', 'retention_days': 30},
      );
      final blockedProjectId = blockedProject.body['id'];
      final untouchedProject = await call(
        'POST',
        '/v1/groups/$groupId/projects',
        bearer: admin,
        json: {'name': 'billing', 'retention_days': 30},
      );
      final untouchedProjectId = untouchedProject.body['id'];
      final key = await call(
        'POST',
        '/v1/projects/$blockedProjectId/secret-keys',
        bearer: admin,
        json: <String, Object?>{},
      );
      final secret = key.body['secret'] as String;

      expect(
        (await call(
          'POST',
          '/v1/projects/$blockedProjectId/block',
          bearer: admin,
        )).status,
        200,
      );

      expect(
        (await call(
          'POST',
          '/v1/logs',
          bearer: secret,
          json: [
            {
              'timestamp': DateTime.now().toIso8601String(),
              'level': 'info',
              'event': 'x',
            },
          ],
        )).status,
        403,
      );
      final byProjectId = await call(
        'GET',
        '/v1/logs?project_id=$blockedProjectId',
        bearer: admin,
      );
      expect(byProjectId.status, 403);
      expect(byProjectId.body['error'], 'project_blocked');

      final byGroupId = await call(
        'GET',
        '/v1/logs?group_id=$groupId',
        bearer: admin,
      );
      expect(
        byGroupId.status,
        200,
        reason: 'a group query silently excludes the blocked project',
      );

      expect(
        (await call(
          'POST',
          '/v1/projects/$blockedProjectId/unblock',
          bearer: admin,
        )).status,
        200,
      );
      expect(
        (await call(
          'POST',
          '/v1/logs',
          bearer: secret,
          json: [
            {
              'timestamp': DateTime.now().toIso8601String(),
              'level': 'info',
              'event': 'x',
            },
          ],
        )).status,
        202,
        reason: 'unblocking restores ingestion, no new key needed',
      );

      // --- an owner of the group is refused, even over their own resources
      // The role grant below bumps token_version, so the tokens this
      // returns are discarded immediately — only activation (the forced
      // password change) is what this call is for.
      final ownerId = (await createAndActivateUser(
        admin,
        'owner-of-payments',
        'owner-pw',
      )).id;
      final grantOwner = await call(
        'POST',
        '/v1/role-assignments',
        bearer: admin,
        json: {
          'subject_type': 'user',
          'subject_id': ownerId,
          'role': 'owner',
          'scope_type': 'group',
          'scope_id': groupId,
        },
      );
      expect(grantOwner.status, 201, reason: '${grantOwner.body}');
      // The grant bumped the owner's token_version — re-login for a token
      // that actually carries the new role.
      final ownerAccess = (await login('owner-of-payments', 'owner-pw')).access;

      expect(
        (await call(
          'POST',
          '/v1/users/$victimId/block',
          bearer: ownerAccess,
        )).status,
        403,
        reason: 'blocking is admin-only, not even for an owner',
      );
      expect(
        (await call(
          'POST',
          '/v1/projects/$untouchedProjectId/block',
          bearer: ownerAccess,
        )).status,
        403,
      );

      // ==================================================================
      // 10.5 — self-deletion
      // ==================================================================

      final leaver = await createAndActivateUser(admin, 'leaver', 'leaver-pw');

      final selfDelete = await call(
        'DELETE',
        '/v1/users/me',
        bearer: leaver.access,
        json: {'password': 'leaver-pw'},
      );
      expect(selfDelete.status, 204, reason: '${selfDelete.body}');

      expect(
        (await call('GET', '/v1/groups', bearer: leaver.access)).status,
        401,
      );
      final leaverRefresh = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=refresh_token&refresh_token=${leaver.refresh}',
      );
      expect(leaverRefresh.status, 400);
      expect(leaverRefresh.body['error'], 'invalid_grant');

      final reLogin = await call(
        'POST',
        '/v1/auth/token',
        form: 'grant_type=password&username=leaver&password=leaver-pw',
      );
      expect(reLogin.status, 400);
      expect(reLogin.body['error'], 'invalid_grant');

      final leaverId = leaver.id;
      final unblockDeleted = await call(
        'POST',
        '/v1/users/$leaverId/unblock',
        bearer: admin,
      );
      expect(unblockDeleted.status, 409);
      expect(unblockDeleted.body['error'], 'deleted_account');

      final usernameStillReserved = await call(
        'POST',
        '/v1/users',
        bearer: admin,
        json: {'username': 'leaver', 'password': 'whatever'},
      );
      expect(usernameStillReserved.status, 409);
      expect(usernameStillReserved.body['error'], 'username_taken');

      // ==================================================================
      // 10.7 — admin deletion and the sole-group-owner guard
      // ==================================================================

      final soleGroup = await call(
        'POST',
        '/v1/groups',
        bearer: admin,
        json: {'name': 'sole-owned'},
      );
      final soleGroupId = soleGroup.body['id'];

      final soleOwnerId = (await createAndActivateUser(
        admin,
        'sole-owner',
        'sole-owner-pw',
      )).id;
      await call(
        'POST',
        '/v1/role-assignments',
        bearer: admin,
        json: {
          'subject_type': 'user',
          'subject_id': soleOwnerId,
          'role': 'owner',
          'scope_type': 'group',
          'scope_id': soleGroupId,
        },
      );

      final blockedDeletion = await call(
        'DELETE',
        '/v1/users/$soleOwnerId',
        bearer: admin,
      );
      expect(blockedDeletion.status, 409);
      expect(blockedDeletion.body['error'], 'sole_group_owner');
      final blockingGroups =
          blockedDeletion.body['details']! as Map<String, Object?>;
      expect(
        (blockingGroups['blocking_groups']! as List).map(
          (g) => (g as Map)['id'],
        ),
        contains(soleGroupId),
      );
      expect(
        (await login('sole-owner', 'sole-owner-pw')).access,
        isNotEmpty,
        reason: 'the refused deletion changed nothing',
      );

      // Hand ownership to someone else, then the deletion goes through.
      final secondOwnerCreated = await call(
        'POST',
        '/v1/users',
        bearer: admin,
        json: {'username': 'second-owner', 'password': 'temp-second'},
      );
      await call(
        'POST',
        '/v1/role-assignments',
        bearer: admin,
        json: {
          'subject_type': 'user',
          'subject_id': secondOwnerCreated.body['id'],
          'role': 'owner',
          'scope_type': 'group',
          'scope_id': soleGroupId,
        },
      );

      final allowedDeletion = await call(
        'DELETE',
        '/v1/users/$soleOwnerId',
        bearer: admin,
      );
      expect(allowedDeletion.status, 204, reason: '${allowedDeletion.body}');

      final auditAfterDeletion = await call(
        'GET',
        '/v1/audit-log?action=user.deleted',
        bearer: admin,
      );
      final deletions = auditAfterDeletion.body['items']! as List;
      final soleOwnerDeletion =
          deletions.singleWhere((e) => (e as Map)['target_id'] == soleOwnerId)
              as Map<String, Object?>;
      expect(soleOwnerDeletion['actor_user_id'], isNotNull);

      // ==================================================================
      // 10.9a — the primary administrator cannot be deleted, by anyone
      // ==================================================================

      final secondAdminId = (await createAndActivateUser(
        admin,
        'second-admin',
        'admin2-pw',
      )).id;
      await call(
        'POST',
        '/v1/role-assignments',
        bearer: admin,
        json: {
          'subject_type': 'user',
          'subject_id': secondAdminId,
          'role': 'admin',
          'scope_type': 'global',
        },
      );
      final secondAdminAccess = (await login(
        'second-admin',
        'admin2-pw',
      )).access;

      // Root is `is_primary_admin` — the account auto-bootstrap created.
      final allUsers =
          (await call(
                'GET',
                '/v1/users?limit=200',
                bearer: admin,
              )).body['items']!
              as List;
      final rootId =
          (allUsers.firstWhere((u) => (u as Map)['username'] == 'root')
              as Map)['id'];

      final byOtherAdmin = await call(
        'DELETE',
        '/v1/users/$rootId',
        bearer: secondAdminAccess,
      );
      expect(byOtherAdmin.status, 403);
      expect(byOtherAdmin.body['error'], 'cannot_delete_primary_admin');
      expect(
        (await login('root', 'root-password-1')).access,
        isNotEmpty,
        reason: 'root can still log in',
      );

      final bySelf = await call(
        'DELETE',
        '/v1/users/me',
        bearer: (await login('root', 'root-password-1')).access,
        json: {'password': 'root-password-1'},
      );
      expect(bySelf.status, 403);
      expect(bySelf.body['error'], 'cannot_delete_primary_admin');

      // The second administrator, who is not primary, deletes normally.
      final secondAdminDeleted = await call(
        'DELETE',
        '/v1/users/$secondAdminId',
        bearer: admin,
      );
      expect(secondAdminDeleted.status, 204);

      final auditForRoot = await call(
        'GET',
        '/v1/audit-log?action=user.deleted&target_id=$rootId',
        bearer: admin,
      );
      expect(
        auditForRoot.body['items'],
        isEmpty,
        reason: 'every attempt against the primary administrator was refused',
      );

      process.kill(ProcessSignal.sigterm);
      expect(await process.exitCode.timeout(const Duration(seconds: 15)), 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'a bootstrap password outside the policy stops startup with a config error',
    () async {
      final dir = Directory.systemTemp.createTempSync('server_weak_password');
      addTearDown(() => dir.deleteSync(recursive: true));

      final process = await Process.start(
        'dart',
        [
          'run',
          'bin/server.dart',
          'serve',
          '--db-path=${dir.path}/test.sqlite',
          '--http-port=0',
        ],
        environment: {
          'STRUCTURED_LOG_JWT_SECRET': 'integration-test-secret',
          'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'hunter2',
        },
      );
      final output = StringBuffer();
      final drained = Future.wait([
        process.stdout.transform(utf8.decoder).forEach(output.write),
        process.stderr.transform(utf8.decoder).forEach(output.write),
      ]);

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 60),
      );
      await drained;

      expect(exitCode, isNot(0));
      expect(output.toString(), contains('BOOTSTRAP_ADMIN_PASSWORD'));
      expect(output.toString(), contains('at least 8 characters'));
      // It is a secret: the message names the variable, never the value.
      expect(output.toString(), isNot(contains('hunter2')));
      // Nothing started: no database was created.
      expect(File('${dir.path}/test.sqlite').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
