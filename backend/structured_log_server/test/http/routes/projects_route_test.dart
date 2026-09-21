import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
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
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;
  late int groupId;
  late ProjectRoutes routes;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = ProjectRoutes(db, authorizer, AuditWriter(db));
    groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
  });
  tearDown(() => db.close());

  List<EffectiveRole> ownerOf(int groupId) => [
    EffectiveRole(
      role: Role.owner,
      scopeType: ScopeType.group,
      scopeId: groupId,
    ),
  ];

  group('createProject', () {
    test('an owner of the group can create a project with a quota', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/projects',
          roles: ownerOf(groupId),
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
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/projects',
          roles: _admin,
          jsonBody: {'name': 'p', 'retention_days': 7},
        ),
      );
      final body = await decodeJson(response);
      final usage = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(body['id'] as int))).getSingle();
      expect(usage.entryCount, 0);
      expect(usage.totalBytes, 0);
    });

    test(
      'a caller without write access to the group is rejected with 403',
      () async {
        await expectLater(
          routes.router.call(
            authenticatedRequest(
              'POST',
              'http://x/v1/groups/$groupId/projects',
              roles: _noRoles,
              jsonBody: {'name': 'p', 'retention_days': 7},
            ),
          ),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403),
          ),
        );
      },
    );

    test('an unknown group is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/999/projects',
            roles: _admin,
            jsonBody: {'name': 'p', 'retention_days': 7},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a missing retention_days is rejected with 400', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/projects',
            roles: _admin,
            jsonBody: {'name': 'p'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('updateProjectQuota', () {
    Future<int> createTestProject() async {
      final id = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'p',
              retentionDays: 30,
            ),
          );
      await db
          .into(db.projectUsage)
          .insert(ProjectUsageCompanion.insert(projectId: Value(id)));
      return id;
    }

    test('an owner can partially update the quota', () async {
      final projectId = await createTestProject();

      final response = await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          jsonBody: {'max_entries': 500},
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect(body['max_entries'], 500);
      expect(body['retention_days'], 30); // untouched field preserved
    });

    test(
      'max_entries can be cleared back to unlimited with an explicit null',
      () async {
        final projectId = await createTestProject();
        await routes.router.call(
          authenticatedRequest(
            'PATCH',
            'http://x/v1/projects/$projectId',
            roles: ownerOf(groupId),
            jsonBody: {'max_entries': 500},
          ),
        );

        final response = await routes.router.call(
          authenticatedRequest(
            'PATCH',
            'http://x/v1/projects/$projectId',
            roles: ownerOf(groupId),
            jsonBody: {'max_entries': null},
          ),
        );
        final body = await decodeJson(response);
        expect(body['max_entries'], isNull);
      },
    );

    test('a caller with only read access is rejected with 403', () async {
      final projectId = await createTestProject();
      await expectLater(
        routes.router.call(
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
            jsonBody: {'max_entries': 1},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('write access via the enclosing group is honored', () async {
      final projectId = await createTestProject();
      final response = await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          jsonBody: {'max_bytes': 42},
        ),
      );
      expect(response.statusCode, 200);
    });
  });

  group('listProjects', () {
    Future<int> addProject(int inGroup, String name, {bool blocked = false}) {
      return db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: inGroup,
              name: name,
              retentionDays: 30,
              isBlocked: Value(blocked),
            ),
          );
    }

    test('an admin sees every project', () async {
      final other = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'other'));
      await addProject(groupId, 'a');
      await addProject(other, 'b');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects',
          roles: [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)],
        ),
      );

      expect(response.statusCode, 200);
      final items = (await decodeJson(response))['items'] as List<Object?>;
      expect(items, hasLength(2));
    });

    test('a project-scoped role sees that project and nothing else', () async {
      final mine = await addProject(groupId, 'mine');
      await addProject(groupId, 'theirs');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects',
          roles: [
            EffectiveRole(
              role: Role.user,
              scopeType: ScopeType.project,
              scopeId: mine,
            ),
          ],
        ),
      );

      final items = (await decodeJson(response))['items'] as List<Object?>;
      // The point of the endpoint being flat: this user holds no role on the
      // enclosing group, so GET /v1/groups shows them nothing, and a
      // projects-under-a-group route would leave them no way in at all.
      expect(items, hasLength(1));
      expect((items.single! as Map<String, Object?>)['name'], 'mine');
    });

    test('a group role covers the projects inside it', () async {
      final other = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'other'));
      await addProject(groupId, 'ours');
      await addProject(other, 'not ours');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects',
          roles: ownerOf(groupId),
        ),
      );

      final items = (await decodeJson(response))['items'] as List<Object?>;
      expect(items, hasLength(1));
      expect((items.single! as Map<String, Object?>)['name'], 'ours');
    });

    test('group_id narrows the same list', () async {
      final other = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'other'));
      await addProject(groupId, 'here');
      await addProject(other, 'elsewhere');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects?group_id=$other',
          roles: [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)],
        ),
      );

      final items = (await decodeJson(response))['items'] as List<Object?>;
      expect(items, hasLength(1));
      expect((items.single! as Map<String, Object?>)['name'], 'elsewhere');
    });

    test('name narrows to projects whose name contains it', () async {
      await addProject(groupId, 'checkout-api');
      await addProject(groupId, 'payments-worker');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects?name=check',
          roles: [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)],
        ),
      );

      final items = (await decodeJson(response))['items'] as List<Object?>;
      expect(items, hasLength(1));
      expect((items.single! as Map<String, Object?>)['name'], 'checkout-api');
    });

    test('name and group_id combine', () async {
      final other = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'other'));
      await addProject(groupId, 'checkout-api');
      await addProject(other, 'checkout-worker');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects?name=checkout&group_id=$other',
          roles: [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)],
        ),
      );

      final items = (await decodeJson(response))['items'] as List<Object?>;
      expect(items, hasLength(1));
      expect(
        (items.single! as Map<String, Object?>)['name'],
        'checkout-worker',
      );
    });

    test('a blocked project is listed, carrying its state', () async {
      await addProject(groupId, 'blocked', blocked: true);

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects',
          roles: ownerOf(groupId),
        ),
      );

      final items = (await decodeJson(response))['items'] as List<Object?>;
      // Hiding it would read as deletion; whoever shows the list decides what
      // to do with the flag.
      expect((items.single! as Map<String, Object?>)['is_blocked'], isTrue);
    });

    test('usage counters are not computed for a list', () async {
      await addProject(groupId, 'p');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects',
          roles: ownerOf(groupId),
        ),
      );

      final project = (await decodeJson(response))['items'] as List<Object?>;
      final json = project.single! as Map<String, Object?>;
      expect(json.containsKey('entry_count'), isFalse);
      expect(json.containsKey('total_bytes'), isFalse);
    });

    test('a non-numeric group_id is a 400, not an empty list', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/projects?group_id=abc',
            roles: ownerOf(groupId),
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('getProject', () {
    Future<int> createTestProject() async {
      final id = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'p',
              retentionDays: 30,
            ),
          );
      await db
          .into(db.projectUsage)
          .insert(
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
      final response = await routes.router.call(
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
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/projects/$projectId',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/projects/999',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('the audit record', () {
    Future<int> createTestProject() async {
      final id = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'p',
              retentionDays: 30,
            ),
          );
      await db
          .into(db.projectUsage)
          .insert(ProjectUsageCompanion.insert(projectId: Value(id)));
      return id;
    }

    test('a created project leaves one, inside its own transaction', () async {
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/projects',
          roles: ownerOf(groupId),
          userId: 4,
          jsonBody: {'name': 'checkout', 'retention_days': 14},
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'project.created');
      expect(row.targetType, 'project');
      expect(row.actorUserId, 4);
      expect(auditMetadata(row), {
        'name': 'checkout',
        'group_id': groupId,
        'retention_days': 14,
      });
    });

    test('a changed quota records both halves of the change', () async {
      // The pair is the whole value of the record: "max_entries is now 500"
      // says nothing without what it was. `before` therefore has to be read
      // ahead of the write, not after it.
      final projectId = await createTestProject();

      await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/projects/$projectId',
          roles: ownerOf(groupId),
          jsonBody: {'max_entries': 500},
        ),
      );

      final metadata = auditMetadata((await auditRows(db)).single);
      expect(metadata['before'], {
        'retention_days': 30,
        'max_entries': null,
        'max_bytes': null,
      });
      expect(metadata['after'], {
        'retention_days': 30,
        'max_entries': 500,
        'max_bytes': null,
      });
    });

    test('a refused quota change leaves none', () async {
      final projectId = await createTestProject();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'PATCH',
            'http://x/v1/projects/$projectId',
            roles: const <EffectiveRole>[],
            jsonBody: {'max_entries': 500},
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
    });

    test('a refused project creation leaves none', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/projects',
            roles: const <EffectiveRole>[],
            jsonBody: {'name': 'x', 'retention_days': 1},
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
      expect(await db.select(db.projects).get(), isEmpty);
    });
  });

  group('blockProject / unblockProject', () {
    Future<int> createTestProject() {
      return db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'p',
              retentionDays: 30,
            ),
          );
    }

    test('an admin can block and unblock a project', () async {
      final projectId = await createTestProject();

      final blocked = await decodeJson(
        await routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/$projectId/block',
            roles: _admin,
          ),
        ),
      );
      expect(blocked['is_blocked'], isTrue);

      final unblocked = await decodeJson(
        await routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/$projectId/unblock',
            roles: _admin,
          ),
        ),
      );
      expect(unblocked['is_blocked'], isFalse);
    });

    test('the owner of the enclosing group is rejected with 403 — admin '
        'only, even for their own project', () async {
      final projectId = await createTestProject();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/$projectId/block',
            roles: ownerOf(groupId),
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/999/block',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('blocking leaves project.blocked, unblocking leaves '
        'project.unblocked', () async {
      final projectId = await createTestProject();

      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/block',
          roles: _admin,
        ),
      );
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/unblock',
          roles: _admin,
        ),
      );

      final actions = (await auditRows(db)).map((r) => r.action).toList();
      expect(actions, ['project.blocked', 'project.unblocked']);
    });
  });
}
