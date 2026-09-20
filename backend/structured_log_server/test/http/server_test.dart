import 'dart:convert';

import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

Future<Map<String, Object?>> body(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, Object?>;

void main() {
  late StructuredLogDatabase db;
  late Handler handler;

  setUp(() {
    db = openInMemory();
    handler = buildHandler(db, signingSecret: 'test-secret', issuer: 'test');
  });
  tearDown(() => db.close());

  test('GET /healthz needs no authentication', () async {
    final response = await handler(
      Request('GET', Uri.parse('http://x/healthz')),
    );
    expect(response.statusCode, 200);
  });

  test('a management route without a token is rejected with 401', () async {
    final response = await handler(
      Request('GET', Uri.parse('http://x/v1/groups')),
    );
    expect(response.statusCode, 401);
  });

  test('POST /v1/logs without a project key is rejected with 401', () async {
    final response = await handler(
      Request('POST', Uri.parse('http://x/v1/logs'), body: '[]'),
    );
    expect(response.statusCode, 401);
  });

  test('a revoked project key stops authenticating ingestion', () async {
    // The one leg the key lifecycle tests don't reach on their own: revoking
    // is a management action, but its whole point is what happens on the
    // ingestion path afterwards.
    final userId = await db.into(db.users).insert(
          UsersCompanion.insert(
              username: 'root', passwordHash: hashPassword('s3cret')),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );

    final tokenResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/auth/token'),
        body: 'grant_type=password&username=root&password=s3cret',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );
    final accessToken = (await body(tokenResponse))['access_token'] as String;
    Map<String, String> bearer() => {'authorization': 'Bearer $accessToken'};

    final group = await handler(
      Request('POST', Uri.parse('http://x/v1/groups'),
          body: jsonEncode({'name': 'g'}), headers: bearer()),
    );
    final groupId = (await body(group))['id'] as int;
    final project = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/groups/$groupId/projects'),
        body: jsonEncode({'name': 'p', 'retention_days': 7}),
        headers: bearer(),
      ),
    );
    final projectId = (await body(project))['id'] as int;
    final key = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/projects/$projectId/secret-keys'),
        body: jsonEncode(<String, Object?>{}),
        headers: bearer(),
      ),
    );
    final keyBody = await body(key);
    final secret = keyBody['secret'] as String;
    final keyId = keyBody['id'] as int;

    Future<Response> ingest() async => handler(
          Request(
            'POST',
            Uri.parse('http://x/v1/logs'),
            body: jsonEncode([
              {
                'event': 'e',
                'level': 'info',
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              }
            ]),
            headers: {'authorization': 'Bearer $secret'},
          ),
        );

    expect((await ingest()).statusCode, 202);

    final revoked = await handler(
      Request(
        'DELETE',
        Uri.parse('http://x/v1/projects/$projectId/secret-keys/$keyId'),
        headers: bearer(),
      ),
    );
    expect(revoked.statusCode, 204);

    expect((await ingest()).statusCode, 401,
        reason: 'the revoked key must stop authenticating immediately');
  });

  test('a full admin flow: login, create group/project/key, ingest, query',
      () async {
    // Seed a user with global admin, the way section 34's bootstrap will.
    final userId = await db.into(db.users).insert(
          UsersCompanion.insert(
              username: 'root', passwordHash: hashPassword('s3cret')),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );

    final tokenResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/auth/token'),
        body: 'grant_type=password&username=root&password=s3cret',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );
    expect(tokenResponse.statusCode, 200);
    final tokenBody = await body(tokenResponse);
    final accessToken = tokenBody['access_token'] as String;

    Map<String, String> bearer() => {'authorization': 'Bearer $accessToken'};

    final groupResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/groups'),
        body: jsonEncode({'name': 'g'}),
        headers: bearer(),
      ),
    );
    expect(groupResponse.statusCode, 201);
    final groupId = (await body(groupResponse))['id'] as int;

    final projectResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/groups/$groupId/projects'),
        body: jsonEncode({'name': 'p', 'retention_days': 30}),
        headers: bearer(),
      ),
    );
    expect(projectResponse.statusCode, 201);
    final projectId = (await body(projectResponse))['id'] as int;

    final keyResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/projects/$projectId/secret-keys'),
        body: jsonEncode(<String, Object?>{}),
        headers: bearer(),
      ),
    );
    expect(keyResponse.statusCode, 201);
    final secretKey = (await body(keyResponse))['secret'] as String;

    final ingestResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/logs'),
        body: jsonEncode([
          {
            'event': 'startup',
            'level': 'info',
            'timestamp': DateTime.now().toIso8601String(),
          },
        ]),
        headers: {'authorization': 'Bearer $secretKey'},
      ),
    );
    expect(ingestResponse.statusCode, 202);
    expect((await body(ingestResponse))['accepted'], 1);

    final queryResponse = await handler(
      Request(
        'GET',
        Uri.parse('http://x/v1/logs?project_id=$projectId'),
        headers: bearer(),
      ),
    );
    expect(queryResponse.statusCode, 200);
    final items = (await body(queryResponse))['items'] as List;
    expect(items, hasLength(1));
    expect((items.single as Map)['event'], 'startup');
  });

  test('max-ingest-body-bytes from the config reaches the ingest route',
      () async {
    // The value is parsed and validated in `ServerConfig`, and used two
    // layers down in `LogRoutes`; nothing but this leg notices the two not
    // being joined. Pinned through `buildHandler`, because a `LogRoutes`
    // built by hand takes its cap from a constructor argument and would pass
    // either way.
    final groupId =
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
    final projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: groupId, name: 'p', retentionDays: 30),
        );
    final key = generateProjectSecretKey();
    await db.into(db.projectSecretKeys).insert(
          ProjectSecretKeysCompanion.insert(
              projectId: projectId, keyHash: hashToken(key)),
        );
    final capped = buildHandler(
      db,
      signingSecret: 'test-secret',
      issuer: 'test',
      config: ServerConfig(
        dbPath: ':memory:',
        httpHost: 'localhost',
        httpPort: 0,
        jwtSecret: 'test-secret',
        jwtIssuer: 'test',
        maxIngestBodyBytes: 64,
        retentionPurgeIntervalSeconds: 3600,
        bootstrapAdminEnabled: false,
        bootstrapAdminUsername: 'root',
        bootstrapAdminPassword: null,
        logLevel: 'info',
        logFile: null,
        logFormat: 'json',
        logMaxFileBytes: 1024,
        logMaxFiles: 1,
        rateLimitEnabled: false,
        rateLimitBucketCapacity: 10,
        rateLimitRefillPerMinute: 60,
        rateLimitMaxKeys: 1000,
        trustedProxyHops: 0,
        sseHeartbeatIntervalSeconds: 30,
        corsAllowedOrigins: const {},
      ),
    );

    final response = await capped(
      Request(
        'POST',
        Uri.parse('http://x/v1/logs'),
        headers: {'authorization': 'Bearer $key'},
        body: jsonEncode([
          {'event': 'e', 'level': 'info', 'timestamp': '2026-01-01T00:00:00Z'},
        ]),
      ),
    );

    expect(response.statusCode, 413);
  });
}
