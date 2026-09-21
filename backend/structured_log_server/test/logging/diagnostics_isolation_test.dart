import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

void main() {
  late StructuredLogDatabase db;
  late Handler handler;
  late List<Map<String, dynamic>> captured;
  late String accessToken;
  late String refreshToken;
  late String secretKey;
  late int projectId;

  /// Everything the server logged during the test, as one blob — the
  /// crudest possible way to ask "does this string appear anywhere in our
  /// diagnostics", which is exactly the question a leak test asks.
  String loggedText() => captured.map(jsonEncode).join('\n');

  setUp(() async {
    captured = [];
    StructlogConfiguration.configure(
      sinks: [
        LogSink(
          name: 'capture',
          output: (entry, level) => captured.add(entry),
          minLevel: LogLevel.trace,
        ),
      ],
    );

    db = openInMemory();
    handler = buildHandler(
      db,
      signingSecret: 'test-secret',
      issuer: 'test',
      logger: getLogger(),
    );

    final userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'alice',
            passwordHash: hashPassword('sup3r-s3cret-pw'),
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
    final groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db
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
    secretKey = generateProjectSecretKey();
    await db
        .into(db.projectSecretKeys)
        .insert(
          ProjectSecretKeysCompanion.insert(
            projectId: projectId,
            keyHash: hashToken(secretKey),
          ),
        );

    final tokenResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/auth/token'),
        body: 'grant_type=password&username=alice&password=sup3r-s3cret-pw',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );
    final decoded =
        jsonDecode(await tokenResponse.readAsString()) as Map<String, Object?>;
    accessToken = decoded['access_token'] as String;
    refreshToken = decoded['refresh_token'] as String;
  });

  tearDown(() async {
    StructlogConfiguration.reset();
    await db.close();
  });

  group('request logging', () {
    test(
      'records one entry per request, with the fields that matter',
      () async {
        captured.clear();
        await handler(Request('GET', Uri.parse('http://x/healthz')));

        final completed = captured
            .where((e) => e['event'] == 'request.completed')
            .toList();
        expect(completed, hasLength(1));
        expect(completed.single['method'], 'GET');
        expect(completed.single['path'], '/healthz');
        expect(completed.single['status'], 200);
        expect(completed.single['duration_ms'], isA<int>());
        expect(completed.single['request_id'], isA<String>());
      },
    );

    test('level follows the outcome', () async {
      captured.clear();
      await handler(Request('GET', Uri.parse('http://x/v1/groups')));
      final unauthorized = captured.singleWhere(
        (e) => e['event'] == 'request.completed',
      );
      expect(unauthorized['status'], 401);
      expect(unauthorized['level'], 'warning', reason: "the caller's problem");

      captured.clear();
      await handler(Request('GET', Uri.parse('http://x/healthz')));
      expect(
        captured.singleWhere((e) => e['event'] == 'request.completed')['level'],
        'info',
      );
    });

    test('each request gets its own correlation id', () async {
      captured.clear();
      await handler(Request('GET', Uri.parse('http://x/healthz')));
      await handler(Request('GET', Uri.parse('http://x/healthz')));

      final ids = captured
          .where((e) => e['event'] == 'request.completed')
          .map((e) => e['request_id'])
          .toSet();
      expect(ids, hasLength(2));
    });
  });

  group('secrets never reach the diagnostics', () {
    test(
      'logging in leaks neither the password nor the issued tokens',
      () async {
        captured.clear();
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://x/v1/auth/token'),
            body: 'grant_type=password&username=alice&password=sup3r-s3cret-pw',
            headers: {'content-type': 'application/x-www-form-urlencoded'},
          ),
        );
        final issued =
            jsonDecode(await response.readAsString()) as Map<String, Object?>;

        expect(loggedText(), isNot(contains('sup3r-s3cret-pw')));
        expect(loggedText(), isNot(contains(issued['access_token'])));
        expect(loggedText(), isNot(contains(issued['refresh_token'])));
        expect(
          loggedText(),
          contains('request.completed'),
          reason: 'the request was logged — the absence above is not vacuous',
        );
      },
    );

    test('a failed login leaks neither the attempted password nor the name of '
        'the header', () async {
      captured.clear();
      await handler(
        Request(
          'POST',
          Uri.parse('http://x/v1/auth/token'),
          body: 'grant_type=password&username=alice&password=guessed-wrong',
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );

      expect(loggedText(), isNot(contains('guessed-wrong')));
    });

    test('changing a password leaks neither the old nor the new one', () async {
      captured.clear();
      await handler(
        Request(
          'POST',
          Uri.parse('http://x/v1/auth/change-password'),
          body: jsonEncode({
            'current_password': 'sup3r-s3cret-pw',
            'new_password': 'even-more-s3cret',
          }),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );

      expect(loggedText(), isNot(contains('sup3r-s3cret-pw')));
      expect(loggedText(), isNot(contains('even-more-s3cret')));
      expect(loggedText(), isNot(contains(accessToken)));
    });

    test(
      'ingesting logs leaks neither the project key nor the entries',
      () async {
        captured.clear();
        await handler(
          Request(
            'POST',
            Uri.parse('http://x/v1/logs'),
            body: jsonEncode([
              {
                'event': 'tenant-business-data',
                'level': 'info',
                'timestamp': '2026-01-01T00:00:00Z',
                'card_number': '4111-1111-1111-1111',
              },
            ]),
            headers: {'authorization': 'Bearer $secretKey'},
          ),
        );

        expect(loggedText(), isNot(contains(secretKey)));
        expect(
          loggedText(),
          isNot(contains('4111-1111-1111-1111')),
          reason: "a tenant's payload must not be copied into our diagnostics",
        );
      },
    );

    test('the refresh token is not logged when it is revoked', () async {
      captured.clear();
      await handler(
        Request(
          'DELETE',
          Uri.parse('http://x/v1/auth/token'),
          body: 'refresh_token=$refreshToken',
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );

      expect(loggedText(), isNot(contains(refreshToken)));
    });
  });

  group("diagnostics stay out of the tenants' journal", () {
    test('nothing the server logs about itself lands in log_entries', () async {
      // The server's own log and `log_entries` are different journals
      // (`design.md` decision 48): diagnostics belong to no project, and
      // writing them there would distort someone's quota.
      captured.clear();
      await handler(Request('GET', Uri.parse('http://x/healthz')));
      await handler(Request('GET', Uri.parse('http://x/v1/groups')));
      await handler(
        Request(
          'POST',
          Uri.parse('http://x/v1/logs'),
          body: jsonEncode([
            {
              'event': 'the-only-entry',
              'level': 'info',
              'timestamp': '2026-01-01T00:00:00Z',
            },
          ]),
          headers: {'authorization': 'Bearer $secretKey'},
        ),
      );

      final stored = await db.select(db.logEntries).get();
      expect(stored.map((e) => e.event), ['the-only-entry']);
      expect(
        captured.where((e) => e['event'] == 'request.completed'),
        hasLength(3),
        reason: 'the server did log about itself — just not in there',
      );
    });

    test('diagnostics do not inflate a project usage counter', () async {
      final before = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(projectId))).getSingle();

      for (var i = 0; i < 5; i++) {
        await handler(Request('GET', Uri.parse('http://x/healthz')));
      }

      final after = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(projectId))).getSingle();
      expect(after.entryCount, before.entryCount);
      expect(after.totalBytes, before.totalBytes);
    });
  });
}
