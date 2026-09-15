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

  test(
    'over a real process: RBAC, revocation, quotas and the two error shapes',
    () async {
      final dir = Directory.systemTemp.createTempSync('server_api_integration');
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
      ], environment: {
        'STRUCTURED_LOG_JWT_SIGNING_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'true',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_USERNAME': 'root',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD': 'bootstrap-pw',
      });
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
        json: {'current_password': 'bootstrap-pw', 'new_password': 'real-pw'},
      );
      expect(changed.status, 200);

      // Changing the password bumps token_version, so the token that just
      // made the change is itself no longer valid.
      final afterChange =
          await call('GET', '/v1/groups', bearer: tokens.access);
      expect(afterChange.status, 401);

      tokens = await login('root', 'real-pw');
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
      expect(badGrant.body, contains('error_description'),
          reason: 'RFC 6749 §5.2 shape, not the general envelope');

      final notFound = await call(
        'GET',
        '/v1/projects/999999',
        bearer: admin,
      );
      expect(notFound.status, 404);
      expect(notFound.body['error'], 'not_found');
      expect(notFound.body, contains('message'),
          reason: 'the general envelope, not the RFC 6749 one');

      // --- resources, and a caller who may not touch them ----------------
      final group =
          await call('POST', '/v1/groups', bearer: admin, json: {'name': 'g'});
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
        (await call('POST', '/v1/logs', bearer: admin, json: <Object?>[]))
            .status,
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
      expect((rejected.single as Map)['index'], 2,
          reason: 'the rejection names which entry of the batch it was');

      // Raising the quota lets the next batch through — the same path the
      // operator would take after seeing the rejection.
      expect(
        (await call('PATCH', '/v1/projects/$projectId',
                bearer: admin, json: {'max_entries': 100}))
            .status,
        200,
      );
      final afterRaise = await call('POST', '/v1/logs',
          bearer: secret, json: [entry('now-fits')]);
      expect(afterRaise.body['accepted'], 1);
      expect(afterRaise.body['rejected'], isEmpty);

      final queried =
          await call('GET', '/v1/logs?project_id=$projectId', bearer: admin);
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
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 10));
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

      final process = await Process.start('dart', [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=${dir.path}/test.sqlite',
        '--http-port=$port',
      ], environment: {
        'STRUCTURED_LOG_JWT_SIGNING_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
      });
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
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 10));

      // Without the guard in bin/server.dart this is 255: the broken pipe
      // arrives as an unhandled error in the root zone, where neither a
      // try/catch nor a guarded zone can intercept it.
      expect(exitCode, 0, reason: stderrLines.join('\n'));
      expect(
        stderrLines.join('\n'),
        isNot(contains('Unhandled exception')),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
