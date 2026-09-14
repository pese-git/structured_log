import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/logs_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];
const _noRoles = <EffectiveRole>[];

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

Request ingestRequest(int projectId, Object body) {
  return Request(
    'POST',
    Uri.parse('http://x/v1/logs'),
    body: jsonEncode(body),
    context: {'structured_log_server.authenticatedProjectId': projectId},
  );
}

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;
  late LogStore logStore;
  late int groupId;
  late int projectId;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    logStore = DriftLogStore(db);
    groupId =
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: groupId, name: 'p', retentionDays: 30),
        );
    await db.into(db.projectUsage).insert(
          ProjectUsageCompanion.insert(projectId: Value(projectId)),
        );
  });
  tearDown(() => db.close());

  group('ingestLogs', () {
    test('a well-formed batch is accepted and persisted, project_usage updated',
        () async {
      final response = await ingestLogs(
        db,
        logStore,
        ingestRequest(projectId, [
          {'event': 'e1', 'level': 'info', 'timestamp': '2026-01-01T00:00:00Z'},
          {
            'event': 'e2',
            'level': 'error',
            'timestamp': '2026-01-01T00:00:01Z'
          },
        ]),
      );

      expect(response.statusCode, 202);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['accepted'], 2);
      expect(body['rejected'], isEmpty);

      final rows = await db.select(db.logEntries).get();
      expect(rows, hasLength(2));

      final usage = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(projectId)))
          .getSingle();
      expect(usage.entryCount, 2);
    });

    test('a partially invalid batch reports rejections and still returns 202',
        () async {
      final response = await ingestLogs(
        db,
        logStore,
        ingestRequest(projectId, [
          {'event': 'ok', 'level': 'info', 'timestamp': '2026-01-01T00:00:00Z'},
          {'event': 'bad'}, // missing level
        ]),
      );

      expect(response.statusCode, 202);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['accepted'], 1);
      expect((body['rejected'] as List), hasLength(1));
      expect((body['rejected'] as List).single, {
        'index': 1,
        'error': 'validation_error',
        'message':
            'level: must be one of trace, debug, info, warning, error, critical',
      });
    });

    test('ingestion into a blocked project is rejected wholesale with 403',
        () async {
      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(
        const ProjectsCompanion(isBlocked: Value(true)),
      );

      await expectLater(
        ingestLogs(
          db,
          logStore,
          ingestRequest(projectId, [
            {
              'event': 'e',
              'level': 'info',
              'timestamp': '2026-01-01T00:00:00Z'
            },
          ]),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'project_blocked'),
        ),
      );

      expect(await db.select(db.logEntries).get(), isEmpty);
    });

    test('a body over the size limit is rejected with 413, nothing stored',
        () async {
      await expectLater(
        ingestLogs(
          db,
          logStore,
          ingestRequest(projectId, [
            {
              'event': 'e',
              'level': 'info',
              'timestamp': '2026-01-01T00:00:00Z'
            },
          ]),
          maxBodyBytes: 5,
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 413)),
      );
      expect(await db.select(db.logEntries).get(), isEmpty);
    });

    test('a non-array body is rejected with 400', () async {
      await expectLater(
        ingestLogs(db, logStore, ingestRequest(projectId, {'not': 'an array'})),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('queryLogs', () {
    Future<void> seedLogs() async {
      await logStore.insertBatch(projectId, [
        LogEntriesCompanion.insert(
          projectId: 0,
          receivedAt: DateTime.now(),
          timestamp: DateTime.now(),
          level: 'info',
          event: 'e1',
          sizeBytes: 1,
          contextJson: '{"event":"e1","level":"info"}',
        ),
      ]);
    }

    test('requires exactly one of project_id/group_id', () async {
      await expectLater(
        queryLogs(
          db,
          authorizer,
          logStore,
          authenticatedRequest('GET', 'http://x/v1/logs', roles: _admin),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('rejects both project_id and group_id given together', () async {
      await expectLater(
        queryLogs(
          db,
          authorizer,
          logStore,
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=$projectId&group_id=$groupId',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('an authorized project_id query returns matching entries', () async {
      await seedLogs();
      final response = await queryLogs(
        db,
        authorizer,
        logStore,
        authenticatedRequest(
          'GET',
          'http://x/v1/logs?project_id=$projectId',
          roles: _admin,
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['event'], 'e1');
      expect((items.single as Map)['project_id'], projectId);
    });

    test('no access to the project scope is rejected with 403', () async {
      await expectLater(
        queryLogs(
          db,
          authorizer,
          logStore,
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=$projectId',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project_id is rejected with 404', () async {
      await expectLater(
        queryLogs(
          db,
          authorizer,
          logStore,
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=999999',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a directly-queried blocked project is rejected with project_blocked',
        () async {
      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(
        const ProjectsCompanion(isBlocked: Value(true)),
      );
      await expectLater(
        queryLogs(
          db,
          authorizer,
          logStore,
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=$projectId',
            roles: _admin,
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'project_blocked'),
        ),
      );
    });

    test(
        'a group_id query silently excludes a blocked project instead of failing',
        () async {
      await seedLogs();
      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(
        const ProjectsCompanion(isBlocked: Value(true)),
      );

      final response = await queryLogs(
        db,
        authorizer,
        logStore,
        authenticatedRequest(
          'GET',
          'http://x/v1/logs?group_id=$groupId',
          roles: _admin,
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['items'], isEmpty);
    });

    test(
        'a group with no visible non-blocked projects returns an empty page, not an error',
        () async {
      final emptyGroup = await db.into(db.groups).insert(
            GroupsCompanion.insert(name: 'empty'),
          );
      final response = await queryLogs(
        db,
        authorizer,
        logStore,
        authenticatedRequest(
          'GET',
          'http://x/v1/logs?group_id=$emptyGroup',
          roles: _admin,
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['items'], isEmpty);
      expect(body['next_cursor'], isNull);
    });

    test('a context.<key> query parameter filters on the custom field',
        () async {
      await logStore.insertBatch(projectId, [
        LogEntriesCompanion.insert(
          projectId: 0,
          receivedAt: DateTime.now(),
          timestamp: DateTime.now(),
          level: 'info',
          event: 'has-order',
          sizeBytes: 1,
          contextJson: '{"event":"has-order","order_id":"ord_1"}',
        ),
        LogEntriesCompanion.insert(
          projectId: 0,
          receivedAt: DateTime.now(),
          timestamp: DateTime.now(),
          level: 'info',
          event: 'no-order',
          sizeBytes: 1,
          contextJson: '{"event":"no-order"}',
        ),
      ]);

      final response = await queryLogs(
        db,
        authorizer,
        logStore,
        authenticatedRequest(
          'GET',
          'http://x/v1/logs?project_id=$projectId&context.order_id=ord_1',
          roles: _admin,
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['event'], 'has-order');
    });
  });

  group('healthCheck', () {
    test('returns 200 with a status field', () async {
      final response =
          await healthCheck(Request('GET', Uri.parse('http://x/healthz')));
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'ok');
    });
  });
}
