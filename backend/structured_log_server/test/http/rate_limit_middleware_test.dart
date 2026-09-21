import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

/// A [ServerConfig] with only the fields this suite cares about set to
/// anything meaningful.
ServerConfig configWith({
  bool enabled = true,
  int capacity = 3,
  int refillPerMinute = 60,
  int maxKeys = 1000,
  int trustedProxyHops = 0,
}) {
  return ServerConfig(
    dbPath: ':memory:',
    httpHost: 'localhost',
    httpPort: 0,
    jwtSecret: 'test-secret',
    jwtIssuer: 'test',
    maxIngestBodyBytes: 1024 * 1024,
    retentionPurgeIntervalSeconds: 3600,
    bootstrapAdminEnabled: false,
    bootstrapAdminUsername: 'root',
    bootstrapAdminPassword: null,
    logLevel: 'info',
    logFile: null,
    logFormat: 'json',
    logMaxFileBytes: 1024,
    logMaxFiles: 1,
    rateLimitEnabled: enabled,
    rateLimitBucketCapacity: capacity,
    rateLimitRefillPerMinute: refillPerMinute,
    rateLimitMaxKeys: maxKeys,
    trustedProxyHops: trustedProxyHops,
    sseHeartbeatIntervalSeconds: 30,
  );
}

void main() {
  late StructuredLogDatabase db;
  late DateTime now;
  late int userId;

  DateTime clock() => now;

  Handler handlerWith(ServerConfig config) => buildHandler(
    db,
    signingSecret: 'test-secret',
    issuer: 'test',
    config: config,
    clock: clock,
  );

  setUp(() async {
    now = DateTime.utc(2026, 1, 1);
    db = openInMemory();
    userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'alice',
            passwordHash: hashPassword('correct'),
          ),
        );
    await db
        .into(db.roleAssignments)
        .insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );
  });
  tearDown(() => db.close());

  Future<Response> login(
    Handler handler, {
    String username = 'alice',
    String password = 'correct',
    Map<String, String>? headers,
  }) async {
    return handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/auth/token'),
        body: 'grant_type=password&username=$username&password=$password',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          ...?headers,
        },
      ),
    );
  }

  Future<Map<String, Object?>> body(Response response) async {
    final text = await response.readAsString();
    return text.isEmpty ? const {} : jsonDecode(text) as Map<String, Object?>;
  }

  group('scope', () {
    test('log ingestion is never throttled', () async {
      final handler = handlerWith(configWith(capacity: 1));
      final groupId = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'g'));
      final projectId = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'p',
              retentionDays: 7,
            ),
          );
      await db
          .into(db.projectUsage)
          .insert(ProjectUsageCompanion.insert(projectId: Value(projectId)));
      final key = generateProjectSecretKey();
      await db
          .into(db.projectSecretKeys)
          .insert(
            ProjectSecretKeysCompanion.insert(
              projectId: projectId,
              keyHash: hashToken(key),
            ),
          );

      // Far past any auth limit: volume here is governed by project quotas,
      // not by request frequency.
      for (var i = 0; i < 20; i++) {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://x/v1/logs'),
            body: jsonEncode([
              {
                'event': 'e$i',
                'level': 'info',
                'timestamp': '2026-01-01T00:00:00Z',
              },
            ]),
            headers: {'authorization': 'Bearer $key'},
          ),
        );
        expect(response.statusCode, isNot(429), reason: 'batch $i');
      }
    });

    test('management requests are never throttled', () async {
      final handler = handlerWith(configWith(capacity: 1));
      final token = (await body(await login(handler)))['access_token'];

      for (var i = 0; i < 20; i++) {
        final response = await handler(
          Request(
            'GET',
            Uri.parse('http://x/v1/groups'),
            headers: {'authorization': 'Bearer $token'},
          ),
        );
        expect(response.statusCode, 200, reason: 'request $i');
      }
    });
  });

  group('the IP bucket', () {
    test('spends on every throttled request, success or not', () async {
      final handler = handlerWith(configWith(capacity: 3));

      // Successes still cost the address a token — that is what caps a
      // single host's total rate regardless of outcome.
      for (var i = 0; i < 3; i++) {
        expect((await login(handler)).statusCode, 200, reason: 'login $i');
      }

      final throttled = await login(handler);
      expect(throttled.statusCode, 429);
    });

    test('spraying across usernames still runs into the IP bucket', () async {
      final handler = handlerWith(configWith(capacity: 3));

      for (var i = 0; i < 3; i++) {
        final response = await login(
          handler,
          username: 'user$i',
          password: 'x',
        );
        expect(response.statusCode, 400, reason: 'no subject bucket exhausted');
      }

      expect((await login(handler, username: 'user99')).statusCode, 429);
    });

    test('recovers on its own once enough time has passed', () async {
      final handler = handlerWith(configWith(capacity: 1, refillPerMinute: 60));
      expect((await login(handler)).statusCode, 200);
      expect((await login(handler)).statusCode, 429);

      now = now.add(const Duration(seconds: 1));

      expect(
        (await login(handler)).statusCode,
        200,
        reason: 'no administrator involved',
      );
    });
  });

  group('the subject bucket', () {
    test(
      'guessing one account from many addresses hits the subject bucket',
      () async {
        // This is the case the subject bucket exists for. From a single
        // address the IP bucket always binds first — it spends on every
        // request while the subject spends only on failures, and both are
        // configured with the same capacity — so the interesting attacker is
        // the distributed one, whose every request comes from a fresh address
        // and therefore a fresh IP bucket.
        final handler = handlerWith(
          configWith(capacity: 2, trustedProxyHops: 1),
        );

        Future<Response> from(String ip) =>
            login(handler, password: 'wrong', headers: {'x-forwarded-for': ip});

        expect((await from('203.0.113.1')).statusCode, 400);
        expect((await from('203.0.113.2')).statusCode, 400);

        final third = await from('203.0.113.3');
        expect(
          third.statusCode,
          429,
          reason: "a third address, but alice's own bucket is empty",
        );
      },
    );

    test('other accounts stay reachable while one is being guessed', () async {
      final handler = handlerWith(configWith(capacity: 2, trustedProxyHops: 1));
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'bob',
              passwordHash: hashPassword('bobs-password'),
            ),
          );

      for (final ip in ['203.0.113.1', '203.0.113.2']) {
        await login(
          handler,
          password: 'wrong',
          headers: {'x-forwarded-for': ip},
        );
      }

      final bob = await login(
        handler,
        username: 'bob',
        password: 'bobs-password',
        headers: {'x-forwarded-for': '203.0.113.9'},
      );
      expect(bob.statusCode, 200, reason: 'the subject bucket is per subject');
    });

    test(
      'a success refills the subject, so honest users are not throttled',
      () async {
        final handler = handlerWith(configWith(capacity: 10));

        // Two typos, then a correct password: the subject bucket is back to
        // full, and only the IP bucket has been spent.
        expect((await login(handler, password: 'wrong')).statusCode, 400);
        expect((await login(handler, password: 'wrong')).statusCode, 400);
        expect((await login(handler)).statusCode, 200);

        for (var i = 0; i < 5; i++) {
          expect(
            (await login(handler, password: 'wrong')).statusCode,
            400,
            reason: 'attempt $i — the subject bucket was refilled',
          );
        }
      },
    );

    test('guessing a victim does not lock the victim out', () async {
      final handler = handlerWith(configWith(capacity: 2, refillPerMinute: 60));

      // The attacker exhausts alice's subject bucket...
      await login(handler, password: 'wrong');
      await login(handler, password: 'wrong');
      expect((await login(handler)).statusCode, 429);

      // ...and alice is back in as soon as the buckets refill, with no
      // administrator and no cleared flag.
      now = now.add(const Duration(seconds: 5));
      expect((await login(handler)).statusCode, 200);

      final user = await (db.select(
        db.users,
      )..where((t) => t.id.equals(userId))).getSingle();
      expect(user.isActive, isTrue, reason: 'throttling is not lockout');
    });

    test('a throttled attempt never checks the password', () async {
      final handler = handlerWith(configWith(capacity: 2));
      await login(handler, password: 'wrong');
      await login(handler, password: 'wrong');

      // The correct password now, and it must still be refused: the whole
      // point is that the credential is not evaluated.
      final response = await login(handler);
      expect(response.statusCode, 429);
      expect((await body(response))['error'], 'too_many_requests');
    });

    test('an unknown username is throttled like a known one', () async {
      // Anti-enumeration: the limiter keys on the submitted string, so the
      // responses cannot be used to tell which accounts exist.
      final handler = handlerWith(configWith(capacity: 2));

      final known = <int>[];
      final unknown = <int>[];
      for (var i = 0; i < 3; i++) {
        known.add((await login(handler, password: 'wrong')).statusCode);
      }
      now = now.add(const Duration(minutes: 5));
      for (var i = 0; i < 3; i++) {
        unknown.add(
          (await login(
            handler,
            username: 'ghost',
            password: 'wrong',
          )).statusCode,
        );
      }

      expect(known, unknown);
    });

    test('a malformed request does not count against the subject', () async {
      final handler = handlerWith(configWith(capacity: 3));

      // No password field at all: an invalid_request, not a failed
      // credential, so the subject bucket must be untouched.
      for (var i = 0; i < 5; i++) {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://x/v1/auth/token'),
            body: 'grant_type=password&username=alice',
            headers: {'content-type': 'application/x-www-form-urlencoded'},
          ),
        );
        expect(response.statusCode, anyOf(400, 429));
      }

      // The IP bucket is spent by now; give it time and confirm alice's own
      // bucket was never drained.
      now = now.add(const Duration(minutes: 5));
      expect((await login(handler, password: 'wrong')).statusCode, 400);
      expect((await login(handler, password: 'wrong')).statusCode, 400);
    });
  });

  group('the 429 response', () {
    test('carries Retry-After and the general envelope, even on the token '
        'endpoint', () async {
      final handler = handlerWith(configWith(capacity: 1, refillPerMinute: 6));
      await login(handler);

      final response = await login(handler);
      expect(response.statusCode, 429);
      expect(response.headers['retry-after'], '10');

      final decoded = await body(response);
      expect(decoded['error'], 'too_many_requests');
      expect(decoded, contains('message'));
      expect(
        decoded,
        isNot(contains('error_description')),
        reason: 'the one place this endpoint leaves the RFC 6749 shape',
      );
    });

    test('Retry-After is never zero', () async {
      final handler = handlerWith(
        configWith(capacity: 1, refillPerMinute: 600),
      );
      await login(handler);

      final response = await login(handler);
      expect(int.parse(response.headers['retry-after']!), greaterThan(0));
    });

    test('no tokens are issued by a throttled request', () async {
      final handler = handlerWith(configWith(capacity: 1));
      await login(handler);

      final before = await db.select(db.refreshTokens).get();
      final response = await login(handler);
      final after = await db.select(db.refreshTokens).get();

      expect(response.statusCode, 429);
      expect(after.length, before.length);
    });
  });

  group('change-password is throttled by the authenticated user', () {
    test('wrong current passwords run the subject bucket down', () async {
      final handler = handlerWith(configWith(capacity: 10));
      final token = (await body(await login(handler)))['access_token'];

      Future<Response> change(String current) async => handler(
        Request(
          'POST',
          Uri.parse('http://x/v1/auth/change-password'),
          body: jsonEncode({
            'current_password': current,
            'new_password': 'brand-new',
          }),
          headers: {'authorization': 'Bearer $token'},
        ),
      );

      for (var i = 0; i < 10; i++) {
        final response = await change('wrong');
        if (response.statusCode == 429) return;
      }
      fail('the subject bucket never ran out');
    });
  });

  group('client address', () {
    test('a forged X-Forwarded-For is ignored by default', () async {
      final handler = handlerWith(configWith(capacity: 2));

      // Different made-up addresses every time: without trusted hops they
      // all share one bucket, so the limiter still bites.
      for (var i = 0; i < 2; i++) {
        await login(handler, headers: {'x-forwarded-for': '10.0.0.$i'});
      }

      final response = await login(
        handler,
        headers: {'x-forwarded-for': '10.0.0.99'},
      );
      expect(response.statusCode, 429);
    });

    test('with one trusted hop the client address is counted', () async {
      final handler = handlerWith(configWith(capacity: 1, trustedProxyHops: 1));

      expect(
        (await login(
          handler,
          headers: {'x-forwarded-for': '203.0.113.1'},
        )).statusCode,
        200,
      );
      expect(
        (await login(
          handler,
          headers: {'x-forwarded-for': '203.0.113.1'},
        )).statusCode,
        429,
        reason: 'the same client is throttled',
      );
      expect(
        (await login(
          handler,
          headers: {'x-forwarded-for': '203.0.113.2'},
        )).statusCode,
        200,
        reason: 'a different client behind the same proxy is not',
      );
    });

    test('with one trusted hop the rightmost entry wins', () async {
      // Everything left of the entries appended by trusted infrastructure is
      // client-supplied, so a client prepending addresses must not get a
      // fresh bucket out of it.
      final handler = handlerWith(configWith(capacity: 1, trustedProxyHops: 1));

      await login(handler, headers: {'x-forwarded-for': 'fake, 203.0.113.7'});
      final response = await login(
        handler,
        headers: {'x-forwarded-for': 'another-fake, 203.0.113.7'},
      );

      expect(response.statusCode, 429);
    });
  });

  group('the off switch', () {
    test('a disabled limiter never answers 429', () async {
      final handler = handlerWith(configWith(enabled: false, capacity: 1));

      for (var i = 0; i < 20; i++) {
        final response = await login(handler, password: 'wrong');
        expect(response.statusCode, 400, reason: 'attempt $i');
      }
      expect((await login(handler)).statusCode, 200);
    });
  });

  group('the audit record of an episode', () {
    Future<List<AuditLogEntry>> throttleRecords() async {
      final rows = await db.select(db.auditLogEntries).get();
      return rows.where((r) => r.action == 'auth.throttled').toList();
    }

    Map<String, Object?> metaOf(AuditLogEntry row) =>
        jsonDecode(row.metadata) as Map<String, Object?>;

    test(
      'a burst against one address records once, not once per request',
      () async {
        // An attack is a burst by definition. One record per refused request
        // would bury the journal under the very traffic it is reporting.
        final handler = handlerWith(configWith(capacity: 2));

        for (var i = 0; i < 8; i++) {
          await login(handler, password: 'wrong');
        }

        final records = await throttleRecords();
        expect(records, hasLength(1));
        expect(metaOf(records.single), {
          'key_kind': 'ip',
          'path': '/v1/auth/token',
          'client_ip': isA<String>(),
        });
        expect(records.single.actorUserId, isNull);
        expect(records.single.targetType, 'auth');
      },
    );

    test(
      'the record is written on the first refusal, not on the last token',
      () async {
        // The request that empties the bucket is one the limiter *allowed*. A
        // record for it would say an attempt was throttled when it was served.
        final handler = handlerWith(configWith(capacity: 2));

        await login(handler, password: 'wrong');
        await login(handler, password: 'wrong');
        expect(
          await throttleRecords(),
          isEmpty,
          reason: 'two requests, two tokens, both served',
        );

        final refused = await login(handler, password: 'wrong');
        expect(refused.statusCode, 429);
        expect(await throttleRecords(), hasLength(1));
      },
    );

    test('a later burst after recovery is a second episode', () async {
      final handler = handlerWith(configWith(capacity: 2, refillPerMinute: 60));

      for (var i = 0; i < 4; i++) {
        await login(handler, password: 'wrong');
      }
      expect(await throttleRecords(), hasLength(1));

      // Long enough for the bucket to refill completely.
      now = now.add(const Duration(minutes: 5));
      for (var i = 0; i < 4; i++) {
        await login(handler, password: 'wrong');
      }

      expect(
        await throttleRecords(),
        hasLength(2),
        reason: 'a fresh stretch of being empty is a fresh thing to report',
      );
    });

    test('the two key kinds are counted apart', () async {
      // Spraying one account from many addresses never exhausts an address
      // bucket, which is exactly what the subject half exists for — and it
      // gets its own episode. A test asserting "exactly one record" without
      // saying per what would be wrong for this case.
      final handler = handlerWith(configWith(capacity: 2, trustedProxyHops: 1));

      for (var i = 0; i < 6; i++) {
        await login(
          handler,
          password: 'wrong',
          headers: {'x-forwarded-for': '198.51.100.$i'},
        );
      }

      final records = await throttleRecords();
      expect(records, hasLength(1));
      expect(metaOf(records.single)['key_kind'], 'subject');
      expect(
        metaOf(records.single)['client_ip'],
        isNot('198.51.100.0'),
        reason: 'the address of the refused request, not of the first attempt',
      );
    });

    test(
      'the throttled subject is not stored for the token endpoint',
      () async {
        // It is a submitted string — regularly a password typed into the
        // username box.
        final handler = handlerWith(
          configWith(capacity: 1, trustedProxyHops: 1),
        );

        for (var i = 0; i < 3; i++) {
          await login(
            handler,
            username: 'Pa55word!',
            password: 'x',
            headers: {'x-forwarded-for': '198.51.100.$i'},
          );
        }

        for (final row in await db.select(db.auditLogEntries).get()) {
          expect(row.metadata, isNot(contains('Pa55word!')));
        }
      },
    );
  });
}
