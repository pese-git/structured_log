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

  group('deleteRoleAssignment', () {
    Future<int> grant(int subjectId) async {
      return db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: subjectId,
              role: 'user',
              scopeType: 'global',
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
