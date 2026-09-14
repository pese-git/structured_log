import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/projects_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
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

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;
  late int groupId;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    groupId =
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
  });
  tearDown(() => db.close());

  List<EffectiveRole> ownerOf(int groupId) => [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

  group('createProject', () {
    test('an owner of the group can create a project with a quota', () async {
      final response = await createProject(
        db,
        authorizer,
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/projects',
          roles: ownerOf(groupId),
          params: {'groupId': '$groupId'},
          jsonBody: {
            'name': 'checkout-service',
            'retention_days': 30,
            'max_entries': 1000000,
          },
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['name'], 'checkout-service');
      expect(body['group_id'], groupId);
      expect(body['retention_days'], 30);
      expect(body['max_entries'], 1000000);
      expect(body['max_bytes'], isNull);
      expect(body['is_blocked'], isFalse);
      expect(body.containsKey('entry_count'), isFalse);
    });

    test('a project-usage row is created alongside the project', () async {
      final response = await createProject(
        db,
        authorizer,
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/projects',
          roles: _admin,
          params: {'groupId': '$groupId'},
          jsonBody: {'name': 'p', 'retention_days': 7},
        ),
      );
      final body = await decodeJson(response);
      final usage = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(body['id'] as int)))
          .getSingle();
      expect(usage.entryCount, 0);
      expect(usage.totalBytes, 0);
    });

    test('a caller without write access to the group is rejected with 403',
        () async {
      await expectLater(
        createProject(
          db,
          authorizer,
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/projects',
            roles: _noRoles,
            params: {'groupId': '$groupId'},
            jsonBody: {'name': 'p', 'retention_days': 7},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown group is rejected with 404', () async {
      await expectLater(
        createProject(
          db,
          authorizer,
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/999/projects',
            roles: _admin,
            params: {'groupId': '999'},
            jsonBody: {'name': 'p', 'retention_days': 7},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a missing retention_days is rejected with 400', () async {
      await expectLater(
        createProject(
          db,
          authorizer,
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/projects',
            roles: _admin,
            params: {'groupId': '$groupId'},
            jsonBody: {'name': 'p'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('updateProjectQuota', () {
    Future<int> createTestProject() async {
      final id = await db.into(db.projects).insert(
            ProjectsCompanion.insert(
                groupId: groupId, name: 'p', retentionDays: 30),
          );
      await db.into(db.projectUsage).insert(
            ProjectUsageCompanion.insert(projectId: Value(id)),
          );
      return id;
    }

    test('an owner can partially update the quota', () async {
      final projectId = await createTestProject();

      final response = await updateProjectQuota(
        db,
        authorizer,
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          params: {'id': '$projectId'},
          jsonBody: {'max_entries': 500},
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect(body['max_entries'], 500);
      expect(body['retention_days'], 30); // untouched field preserved
    });

    test('max_entries can be cleared back to unlimited with an explicit null',
        () async {
      final projectId = await createTestProject();
      await updateProjectQuota(
        db,
        authorizer,
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          params: {'id': '$projectId'},
          jsonBody: {'max_entries': 500},
        ),
      );

      final response = await updateProjectQuota(
        db,
        authorizer,
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          params: {'id': '$projectId'},
          jsonBody: {'max_entries': null},
        ),
      );
      final body = await decodeJson(response);
      expect(body['max_entries'], isNull);
    });

    test('a caller with only read access is rejected with 403', () async {
      final projectId = await createTestProject();
      await expectLater(
        updateProjectQuota(
          db,
          authorizer,
          authenticatedRequest(
            'PATCH',
            'http://x/v1/projects/$projectId',
            roles: [
              EffectiveRole(
                role: Role.user,
                scopeType: ScopeType.project,
                scopeId: projectId,
              ),
            ],
            params: {'id': '$projectId'},
            jsonBody: {'max_entries': 1},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('write access via the enclosing group is honored', () async {
      final projectId = await createTestProject();
      final response = await updateProjectQuota(
        db,
        authorizer,
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          params: {'id': '$projectId'},
          jsonBody: {'max_bytes': 42},
        ),
      );
      expect(response.statusCode, 200);
    });
  });

  group('getProject', () {
    Future<int> createTestProject() async {
      final id = await db.into(db.projects).insert(
            ProjectsCompanion.insert(
                groupId: groupId, name: 'p', retentionDays: 30),
          );
      await db.into(db.projectUsage).insert(
            ProjectUsageCompanion.insert(
              projectId: Value(id),
              entryCount: const Value(12),
              totalBytes: const Value(3400),
            ),
          );
      return id;
    }

    test('a user with project-level access can read usage', () async {
      final projectId = await createTestProject();
      final response = await getProject(
        db,
        authorizer,
        authenticatedRequest(
          'GET',
          'http://x/v1/projects/$projectId',
          roles: [
            EffectiveRole(
              role: Role.user,
              scopeType: ScopeType.project,
              scopeId: projectId,
            ),
          ],
          params: {'id': '$projectId'},
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect(body['entry_count'], 12);
      expect(body['total_bytes'], 3400);
    });

    test('a caller with no access is rejected with 403', () async {
      final projectId = await createTestProject();
      await expectLater(
        getProject(
          db,
          authorizer,
          authenticatedRequest(
            'GET',
            'http://x/v1/projects/$projectId',
            roles: _noRoles,
            params: {'id': '$projectId'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project is rejected with 404', () async {
      await expectLater(
        getProject(
          db,
          authorizer,
          authenticatedRequest(
            'GET',
            'http://x/v1/projects/999',
            roles: _admin,
            params: {'id': '999'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
