import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/role_assignments_route.dart';
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
  late RoleAssignmentRoutes routes;

  setUp(() {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = RoleAssignmentRoutes(db, authorizer, AuditWriter(db));
  });
  tearDown(() => db.close());

  Future<int> insertUser({String username = 'bob'}) {
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashPassword('s3cret'),
          ),
        );
  }

  Future<int> insertGroup({String name = 'g'}) {
    return db.into(db.groups).insert(GroupsCompanion.insert(name: name));
  }

  Future<int> insertProject(int groupId, {String name = 'p'}) {
    return db.into(db.projects).insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: name,
            retentionDays: 30,
          ),
        );
  }

  group('createRoleAssignment', () {
    test('an admin can grant a global-scoped role', () async {
      final subjectId = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: _admin,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'admin',
            'scope_type': 'global',
          },
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['subject_type'], 'user');
      expect(body['subject_id'], subjectId);
      expect(body['role'], 'admin');
      expect(body['scope_type'], 'global');
      expect(body['scope_id'], isNull);
    });

    test('an admin can grant an owner role on a group', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: _admin,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'owner',
            'scope_type': 'group',
            'scope_id': groupId,
          },
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['scope_type'], 'group');
      expect(body['scope_id'], groupId);
    });

    test('an admin can grant a user role on a project', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final projectId = await insertProject(groupId);

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: _admin,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'user',
            'scope_type': 'project',
            'scope_id': projectId,
          },
        ),
      );

      expect(response.statusCode, 201);
    });

    test('a non-admin is rejected with 403', () async {
      final subjectId = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _noRoles,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': subjectId,
              'role': 'user',
              'scope_type': 'global',
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('`subject_type: "team"` is rejected — not in this stage', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _admin,
            jsonBody: {
              'subject_type': 'team',
              'subject_id': 1,
              'role': 'user',
              'scope_type': 'global',
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('an invalid role is rejected with 400', () async {
      final subjectId = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _admin,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': subjectId,
              'role': 'superuser',
              'scope_type': 'global',
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('a group/project scope without scope_id is rejected with 400',
        () async {
      final subjectId = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _admin,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': subjectId,
              'role': 'owner',
              'scope_type': 'group',
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('an unknown subject_id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _admin,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': 999,
              'role': 'user',
              'scope_type': 'global',
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('an unknown group scope_id is rejected with 404', () async {
      final subjectId = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _admin,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': subjectId,
              'role': 'owner',
              'scope_type': 'group',
              'scope_id': 999,
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('grants invalidate the subject\'s already-issued tokens', () async {
      final subjectId = await insertUser();
      final before = await (db.select(db.users)
            ..where((t) => t.id.equals(subjectId)))
          .getSingle();

      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: _admin,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'user',
            'scope_type': 'global',
          },
        ),
      );

      final after = await (db.select(db.users)
            ..where((t) => t.id.equals(subjectId)))
          .getSingle();
      expect(after.tokenVersion, before.tokenVersion + 1);
    });

    test('leaves an audit record naming actor, subject, role, and scope',
        () async {
      final subjectId = await insertUser();

      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: _admin,
          userId: 7,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'user',
            'scope_type': 'global',
          },
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'role_assignment.created');
      expect(row.actorUserId, 7);
      final metadata = auditMetadata(row);
      expect(metadata['subject_id'], subjectId);
      expect(metadata['role'], 'user');
      expect(metadata['scope_type'], 'global');
    });

    test('the owner of the group can grant a user role within it', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: ownerRoles,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'user',
            'scope_type': 'group',
            'scope_id': groupId,
          },
        ),
      );

      expect(response.statusCode, 201);
    });

    test('the owner of the enclosing group can grant a role on its project',
        () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final projectId = await insertProject(groupId);
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/role-assignments',
          roles: ownerRoles,
          jsonBody: {
            'subject_type': 'user',
            'subject_id': subjectId,
            'role': 'owner',
            'scope_type': 'project',
            'scope_id': projectId,
          },
        ),
      );

      expect(response.statusCode, 201);
    });

    test('an owner cannot grant the admin role', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: ownerRoles,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': subjectId,
              'role': 'admin',
              'scope_type': 'group',
              'scope_id': groupId,
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an owner cannot grant a role on a different group\'s project',
        () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final otherGroupId = await insertGroup(name: 'other');
      final otherProjectId = await insertProject(otherGroupId);
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: ownerRoles,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': subjectId,
              'role': 'user',
              'scope_type': 'project',
              'scope_id': otherProjectId,
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('a refused attempt leaves no audit record', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/role-assignments',
            roles: _noRoles,
            jsonBody: {
              'subject_type': 'user',
              'subject_id': 999,
              'role': 'user',
              'scope_type': 'global',
            },
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
    });
  });

  group('listRoleAssignments', () {
    Future<int> grant({
      required int subjectId,
      String role = 'user',
      String scopeType = 'global',
      int? scopeId,
    }) {
      return db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: subjectId,
              role: role,
              scopeType: scopeType,
              scopeId: Value(scopeId),
            ),
          );
    }

    test('filters by subject_id and resolves the subject\'s username',
        () async {
      final alice = await insertUser(username: 'alice');
      final bob = await insertUser(username: 'bob');
      await grant(subjectId: alice);
      await grant(subjectId: bob);

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?subject_id=$alice',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect(items.single['subject_id'], alice);
      expect(items.single['subject_name'], 'alice');
    });

    test('filters by scope_type and scope_id and resolves the group\'s name',
        () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup(name: 'payments');
      final otherGroupId = await insertGroup(name: 'other');
      await grant(
        subjectId: subjectId,
        role: 'owner',
        scopeType: 'group',
        scopeId: groupId,
      );
      await grant(
        subjectId: subjectId,
        role: 'owner',
        scopeType: 'group',
        scopeId: otherGroupId,
      );

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?scope_type=group&scope_id=$groupId',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect(items.single['scope_id'], groupId);
      expect(items.single['scope_name'], 'payments');
    });

    test('resolves a project scope\'s name the same way', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final projectId = await insertProject(groupId, name: 'checkout');
      await grant(
        subjectId: subjectId,
        scopeType: 'project',
        scopeId: projectId,
      );

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?scope_type=project&scope_id=$projectId',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      final items = (body['items'] as List).single;
      expect(items['scope_name'], 'checkout');
    });

    test('a global grant has no scope_name', () async {
      final subjectId = await insertUser();
      await grant(subjectId: subjectId);

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?subject_id=$subjectId',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      expect((body['items'] as List).single['scope_name'], isNull);
    });

    test('no filter and no matches both return an empty list, not an error',
        () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?subject_id=999',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect(body['items'], isEmpty);
    });

    test('a non-admin is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/role-assignments',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('the owner of the group can read its own access list', () async {
      final groupId = await insertGroup();
      final subjectId = await insertUser();
      await grant(
        subjectId: subjectId,
        role: 'owner',
        scopeType: 'group',
        scopeId: groupId,
      );
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?scope_type=group&scope_id=$groupId',
          roles: ownerRoles,
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect((body['items'] as List), hasLength(1));
    });

    test('the owner of a different group is refused with 403', () async {
      final groupId = await insertGroup();
      final otherGroupId = await insertGroup(name: 'other');
      final ownerOfOther = [
        EffectiveRole(
          role: Role.owner,
          scopeType: ScopeType.group,
          scopeId: otherGroupId,
        ),
      ];

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/role-assignments?scope_type=group&scope_id=$groupId',
            roles: ownerOfOther,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test(
        'a plain user role on the scope is still refused — reading is '
        '`owner`/`admin`, not `user`', () async {
      final groupId = await insertGroup();
      final userRoles = [
        EffectiveRole(
            role: Role.user, scopeType: ScopeType.group, scopeId: groupId),
      ];

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/role-assignments?scope_type=group&scope_id=$groupId',
            roles: userRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test(
        'the owner of a project\'s enclosing group can read the project\'s '
        'access list too', () async {
      final groupId = await insertGroup();
      final projectId = await insertProject(groupId);
      final subjectId = await insertUser();
      await grant(
        subjectId: subjectId,
        scopeType: 'project',
        scopeId: projectId,
      );
      final ownerOfGroup = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/role-assignments?scope_type=project&scope_id=$projectId',
          roles: ownerOfGroup,
        ),
      );

      expect(response.statusCode, 200);
    });

    test(
        'an owner is still refused when filtering by subject_id alone — '
        'that shape stays admin-only', () async {
      final groupId = await insertGroup();
      final subjectId = await insertUser();
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/role-assignments?subject_id=$subjectId',
            roles: ownerRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });

  group('deleteRoleAssignment', () {
    Future<int> grant(
      int subjectId, {
      String role = 'user',
      String scopeType = 'global',
      int? scopeId,
    }) async {
      return db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: subjectId,
              role: role,
              scopeType: scopeType,
              scopeId: Value(scopeId),
            ),
          );
    }

    test('an admin can revoke a grant', () async {
      final subjectId = await insertUser();
      final assignmentId = await grant(subjectId);

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/role-assignments/$assignmentId',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 204);
      expect(
        await (db.select(db.roleAssignments)
              ..where((t) => t.id.equals(assignmentId)))
            .getSingleOrNull(),
        isNull,
      );
    });

    test('a non-admin is rejected with 403', () async {
      final subjectId = await insertUser();
      final assignmentId = await grant(subjectId);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/role-assignments/$assignmentId',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('the owner of the group can revoke a grant within it', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final assignmentId = await grant(
        subjectId,
        role: 'owner',
        scopeType: 'group',
        scopeId: groupId,
      );
      final ownerRoles = [
        EffectiveRole(
            role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/role-assignments/$assignmentId',
          roles: ownerRoles,
        ),
      );

      expect(response.statusCode, 204);
    });

    test('an owner of a different group cannot revoke this grant', () async {
      final subjectId = await insertUser();
      final groupId = await insertGroup();
      final otherGroupId = await insertGroup(name: 'other');
      final assignmentId = await grant(
        subjectId,
        role: 'owner',
        scopeType: 'group',
        scopeId: groupId,
      );
      final ownerOfOther = [
        EffectiveRole(
          role: Role.owner,
          scopeType: ScopeType.group,
          scopeId: otherGroupId,
        ),
      ];

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/role-assignments/$assignmentId',
            roles: ownerOfOther,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/role-assignments/999',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('revocation invalidates the subject\'s already-issued tokens',
        () async {
      final subjectId = await insertUser();
      final assignmentId = await grant(subjectId);
      final before = await (db.select(db.users)
            ..where((t) => t.id.equals(subjectId)))
          .getSingle();

      await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/role-assignments/$assignmentId',
          roles: _admin,
        ),
      );

      final after = await (db.select(db.users)
            ..where((t) => t.id.equals(subjectId)))
          .getSingle();
      expect(after.tokenVersion, before.tokenVersion + 1);
    });

    test('leaves an audit record', () async {
      final subjectId = await insertUser();
      final assignmentId = await grant(subjectId);

      await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/role-assignments/$assignmentId',
          roles: _admin,
          userId: 7,
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'role_assignment.revoked');
      expect(row.actorUserId, 7);
      expect(row.targetId, assignmentId);
    });
  });
}
