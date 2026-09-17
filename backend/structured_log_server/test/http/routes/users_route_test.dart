import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/users_route.dart';
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
  late UserRoutes routes;

  setUp(() {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = UserRoutes(db, authorizer, AuditWriter(db));
  });
  tearDown(() => db.close());

  Future<User> insertUser({
    String username = 'bob',
    String password = 's3cret',
    bool isPrimaryAdmin = false,
  }) async {
    final id = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashPassword(password),
            isPrimaryAdmin: Value(isPrimaryAdmin),
          ),
        );
    return (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> makeSoleOwner(int userId, {String groupName = 'g'}) async {
    final groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: groupName));
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'owner',
            scopeType: 'group',
            scopeId: Value(groupId),
          ),
        );
  }

  group('createUser', () {
    test('an admin can create a user with a temporary password', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/users',
          roles: _admin,
          jsonBody: {'username': 'newbie', 'password': 'temp-123'},
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['username'], 'newbie');
      expect(body['must_change_password'], isTrue);
      expect(body['is_active'], isTrue);
      expect(body['email'], isNull);
      expect(body['email_verified_at'], isNull);
    });

    test('a non-admin is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users',
            roles: _noRoles,
            jsonBody: {'username': 'newbie', 'password': 'temp-123'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('a missing username is rejected with 400', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users',
            roles: _admin,
            jsonBody: {'password': 'temp-123'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('a missing password is rejected with 400', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users',
            roles: _admin,
            jsonBody: {'username': 'newbie'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('a taken username is rejected with 409', () async {
      await insertUser(username: 'taken');

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users',
            roles: _admin,
            jsonBody: {'username': 'taken', 'password': 'temp-123'},
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.code, 'code', 'username_taken'),
        ),
      );
    });

    test('an `email` field is silently ignored', () async {
      // Not in this stage's scope (`design.md` "Delivery Phases", Этап 3) —
      // a submitted `email` neither errors nor is stored.
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/users',
          roles: _admin,
          jsonBody: {
            'username': 'newbie',
            'password': 'temp-123',
            'email': 'newbie@example.com',
          },
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['email'], isNull);
    });

    test('leaves an audit record naming the actor and the username', () async {
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/users',
          roles: _admin,
          userId: 7,
          jsonBody: {'username': 'newbie', 'password': 'temp-123'},
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'user.created');
      expect(row.actorUserId, 7);
      expect(auditMetadata(row)['username'], 'newbie');
    });

    test('a refused attempt leaves no audit record', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users',
            roles: _noRoles,
            jsonBody: {'username': 'newbie', 'password': 'temp-123'},
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
    });
  });

  group('listUsers', () {
    test('an admin sees every user', () async {
      await insertUser(username: 'a');
      await insertUser(username: 'b');

      final response = await routes.router.call(
        authenticatedRequest('GET', 'http://x/v1/users', roles: _admin),
      );

      final body = await decodeJson(response);
      expect((body['items'] as List), hasLength(2));
    });

    test('a non-admin is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest('GET', 'http://x/v1/users', roles: _noRoles),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('paginates by cursor without skipping or repeating rows', () async {
      for (var i = 0; i < 5; i++) {
        await insertUser(username: 'user$i');
      }

      final firstPage = await decodeJson(
        await routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/users?limit=2',
            roles: _admin,
          ),
        ),
      );
      expect(firstPage['items'], hasLength(2));
      expect(firstPage['next_cursor'], isNotNull);

      final secondPage = await decodeJson(
        await routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/users?limit=2&cursor=${firstPage['next_cursor']}',
            roles: _admin,
          ),
        ),
      );
      final firstIds =
          (firstPage['items'] as List).map((u) => (u as Map)['id']).toSet();
      final secondIds =
          (secondPage['items'] as List).map((u) => (u as Map)['id']).toSet();
      expect(firstIds.intersection(secondIds), isEmpty);
    });

    test('?username= narrows to users whose username contains it', () async {
      await insertUser(username: 'alice');
      await insertUser(username: 'bob');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/users?username=ali',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect(items.single['username'], 'alice');
    });

    test('?username= is case-insensitive', () async {
      await insertUser(username: 'Alice');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/users?username=ALICE',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      expect((body['items'] as List), hasLength(1));
    });

    test('?username= matching nothing returns an empty list, not an error',
        () async {
      await insertUser(username: 'alice');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/users?username=zzz',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect(body['items'], isEmpty);
    });
  });

  group('updateUser', () {
    test('an admin can change display_name without touching the password',
        () async {
      final target = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/users/${target.id}',
          roles: _admin,
          jsonBody: {'display_name': 'Bob Diaz'},
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      expect(body['display_name'], 'Bob Diaz');
      expect(body['must_change_password'], isFalse);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.tokenVersion, target.tokenVersion);
    });

    test('setting a new password marks it temporary and revokes sessions',
        () async {
      final target = await insertUser();
      await db.into(db.refreshTokens).insert(
            RefreshTokensCompanion.insert(
              userId: target.id,
              tokenHash: hashToken('a-refresh-token'),
              expiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
          );

      final response = await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/users/${target.id}',
          roles: _admin,
          jsonBody: {'password': 'new-temp-password'},
        ),
      );

      final body = await decodeJson(response);
      expect(body['must_change_password'], isTrue);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.tokenVersion, target.tokenVersion + 1);
      final token = await (db.select(db.refreshTokens)
            ..where((t) => t.userId.equals(target.id)))
          .getSingle();
      expect(token.revokedAt, isNotNull);
    });

    test('an `email` field is silently ignored', () async {
      final target = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/users/${target.id}',
          roles: _admin,
          jsonBody: {'email': 'bob@example.com'},
        ),
      );

      final body = await decodeJson(response);
      expect(body['email'], isNull);
    });

    test('a non-admin is rejected with 403', () async {
      final target = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'PATCH',
            'http://x/v1/users/${target.id}',
            roles: _noRoles,
            jsonBody: {'display_name': 'x'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'PATCH',
            'http://x/v1/users/999',
            roles: _admin,
            jsonBody: {'display_name': 'x'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('the audit record names changed fields, never a password value',
        () async {
      final target = await insertUser();

      await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/users/${target.id}',
          roles: _admin,
          userId: 7,
          jsonBody: {'display_name': 'Bob Diaz', 'password': 'new-secret'},
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'user.updated');
      expect(row.actorUserId, 7);
      final metadata = auditMetadata(row);
      expect(
        metadata['changed_fields'],
        containsAll(['display_name', 'password']),
      );
      expect(row.metadata, isNot(contains('new-secret')));
    });

    test('an empty patch writes no audit record', () async {
      final target = await insertUser();

      await routes.router.call(
        authenticatedRequest(
          'PATCH',
          'http://x/v1/users/${target.id}',
          roles: _admin,
          jsonBody: const <String, Object?>{},
        ),
      );

      expect(await auditRows(db), isEmpty);
    });
  });

  group('blockUser / unblockUser', () {
    test('blocking deactivates, revokes sessions, and is reversible', () async {
      final target = await insertUser();
      await db.into(db.refreshTokens).insert(
            RefreshTokensCompanion.insert(
              userId: target.id,
              tokenHash: hashToken('a-refresh-token'),
              expiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
          );

      final blocked = await decodeJson(
        await routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users/${target.id}/block',
            roles: _admin,
          ),
        ),
      );
      expect(blocked['is_active'], isFalse);
      final blockedRow = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(blockedRow.tokenVersion, target.tokenVersion + 1);
      final token = await (db.select(db.refreshTokens)
            ..where((t) => t.userId.equals(target.id)))
          .getSingle();
      expect(token.revokedAt, isNotNull);

      final unblocked = await decodeJson(
        await routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users/${target.id}/unblock',
            roles: _admin,
          ),
        ),
      );
      expect(unblocked['is_active'], isTrue);
    });

    test('a non-admin is rejected with 403 on both', () async {
      final target = await insertUser();

      for (final action in ['block', 'unblock']) {
        await expectLater(
          routes.router.call(
            authenticatedRequest(
              'POST',
              'http://x/v1/users/${target.id}/$action',
              roles: _noRoles,
            ),
          ),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403),
          ),
        );
      }
    });

    test('unblocking a deleted account is rejected with 409', () async {
      final target = await insertUser();
      await (db.update(db.users)..where((t) => t.id.equals(target.id))).write(
        UsersCompanion(deletedAt: Value(DateTime.now())),
      );

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/users/${target.id}/unblock',
            roles: _admin,
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.code, 'code', 'deleted_account'),
        ),
      );
    });

    test('blocking leaves user.blocked, unblocking leaves user.unblocked',
        () async {
      final target = await insertUser();

      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/users/${target.id}/block',
          roles: _admin,
        ),
      );
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/users/${target.id}/unblock',
          roles: _admin,
        ),
      );

      final actions = (await auditRows(db)).map((r) => r.action).toList();
      expect(actions, ['user.blocked', 'user.unblocked']);
    });
  });

  group('deleteMe', () {
    test('the correct password deletes the caller\'s own account', () async {
      final target = await insertUser(password: 'correct-horse');

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/users/me',
          roles: _noRoles,
          userId: target.id,
          jsonBody: {'password': 'correct-horse'},
        ),
      );

      expect(response.statusCode, 204);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      final auditRow = (await auditRows(db)).single;
      expect(auditRow.action, 'user.deleted');
      expect(auditRow.actorUserId, target.id);
      expect(auditRow.targetId, target.id);
    });

    test('the wrong password is rejected with 401 and changes nothing',
        () async {
      final target = await insertUser(password: 'correct-horse');

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/me',
            roles: _noRoles,
            userId: target.id,
            jsonBody: {'password': 'wrong'},
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'invalid_grant'),
        ),
      );

      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.deletedAt, isNull);
      expect(await auditRows(db), isEmpty);
    });

    test('the primary administrator cannot delete themselves', () async {
      final target = await insertUser(isPrimaryAdmin: true);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/me',
            roles: _admin,
            userId: target.id,
            jsonBody: {'password': 's3cret'},
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'cannot_delete_primary_admin'),
        ),
      );
      expect(await auditRows(db), isEmpty);
    });

    test('a sole group owner cannot delete themselves', () async {
      final target = await insertUser();
      await makeSoleOwner(target.id);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/me',
            roles: _noRoles,
            userId: target.id,
            jsonBody: {'password': 's3cret'},
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.code, 'code', 'sole_group_owner'),
        ),
      );
    });

    test('works even while must_change_password is set', () async {
      // `DELETE /v1/users/me` is on the forced-password-change allowlist
      // (`principal_middleware.dart`).
      final target = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/users/me',
          roles: _noRoles,
          userId: target.id,
          mustChangePassword: true,
          jsonBody: {'password': 's3cret'},
        ),
      );

      expect(response.statusCode, 204);
    });
  });

  group('deleteUserById', () {
    test('an admin can delete another user', () async {
      final target = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/users/${target.id}',
          roles: _admin,
          userId: 999,
        ),
      );

      expect(response.statusCode, 204);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      final auditRow = (await auditRows(db)).single;
      expect(auditRow.actorUserId, 999);
      expect(auditRow.targetId, target.id);
    });

    test('targeting the caller\'s own id is rejected with 400', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/1',
            roles: _admin,
            userId: 1,
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'self_deletion_requires_me'),
        ),
      );
    });

    test('a non-admin is rejected with 403', () async {
      final target = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/${target.id}',
            roles: _noRoles,
            userId: 999,
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
            'http://x/v1/users/999',
            roles: _admin,
            userId: 1,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('cannot delete the primary administrator, no password required',
        () async {
      final target = await insertUser(isPrimaryAdmin: true);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/${target.id}',
            roles: _admin,
            userId: 999,
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'cannot_delete_primary_admin'),
        ),
      );
    });

    test('cannot delete a sole group owner', () async {
      final target = await insertUser();
      await makeSoleOwner(target.id);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/users/${target.id}',
            roles: _admin,
            userId: 999,
          ),
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.code, 'code', 'sole_group_owner'),
        ),
      );
    });
  });
}
