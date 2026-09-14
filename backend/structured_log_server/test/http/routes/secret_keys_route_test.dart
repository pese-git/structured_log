import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/secret_keys_route.dart';
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
  late int projectId;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    groupId =
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: groupId, name: 'p', retentionDays: 30),
        );
  });
  tearDown(() => db.close());

  List<EffectiveRole> userOnProject(int projectId) => [
        EffectiveRole(
          role: Role.user,
          scopeType: ScopeType.project,
          scopeId: projectId,
        ),
      ];

  group('createSecretKey', () {
    test('an admin can create a key and receives the plaintext once', () async {
      final response = await createSecretKey(
        db,
        authorizer,
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          params: {'id': '$projectId'},
          jsonBody: {'label': 'prod-instance-1'},
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['label'], 'prod-instance-1');
      expect(body['secret'], isA<String>());
      expect((body['secret'] as String), isNotEmpty);
    });

    test('label is optional', () async {
      final response = await createSecretKey(
        db,
        authorizer,
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          params: {'id': '$projectId'},
          jsonBody: const <String, Object?>{},
        ),
      );
      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['label'], isNull);
    });

    test('a read-only caller cannot create a key', () async {
      await expectLater(
        createSecretKey(
          db,
          authorizer,
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/$projectId/secret-keys',
            roles: userOnProject(projectId),
            params: {'id': '$projectId'},
            jsonBody: const <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project is rejected with 404', () async {
      await expectLater(
        createSecretKey(
          db,
          authorizer,
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/999/secret-keys',
            roles: _admin,
            params: {'id': '999'},
            jsonBody: const <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('listSecretKeys', () {
    test('metadata is listed without ever including the secret', () async {
      await createSecretKey(
        db,
        authorizer,
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          params: {'id': '$projectId'},
          jsonBody: {'label': 'k1'},
        ),
      );

      final response = await listSecretKeys(
        db,
        authorizer,
        authenticatedRequest(
          'GET',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          params: {'id': '$projectId'},
        ),
      );
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map).containsKey('secret'), isFalse);
      expect((items.single as Map)['label'], 'k1');
    });

    test('a caller with read-only access can still list', () async {
      final response = await listSecretKeys(
        db,
        authorizer,
        authenticatedRequest(
          'GET',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: userOnProject(projectId),
          params: {'id': '$projectId'},
        ),
      );
      expect(response.statusCode, 200);
    });

    test('a caller with no access at all is rejected with 403', () async {
      await expectLater(
        listSecretKeys(
          db,
          authorizer,
          authenticatedRequest(
            'GET',
            'http://x/v1/projects/$projectId/secret-keys',
            roles: _noRoles,
            params: {'id': '$projectId'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });

  group('revokeSecretKey', () {
    Future<int> createTestKey() async {
      final response = await createSecretKey(
        db,
        authorizer,
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          params: {'id': '$projectId'},
          jsonBody: const <String, Object?>{},
        ),
      );
      final body = await decodeJson(response);
      return body['id'] as int;
    }

    test('revoking sets revoked_at and returns 204', () async {
      final keyId = await createTestKey();

      final response = await revokeSecretKey(
        db,
        authorizer,
        authenticatedRequest(
          'DELETE',
          'http://x/v1/projects/$projectId/secret-keys/$keyId',
          roles: _admin,
          params: {'id': '$projectId', 'keyId': '$keyId'},
        ),
      );
      expect(response.statusCode, 204);

      final row = await (db.select(
        db.projectSecretKeys,
      )..where((t) => t.id.equals(keyId)))
          .getSingle();
      expect(row.revokedAt, isNotNull);
    });

    test('a read-only caller cannot revoke', () async {
      final keyId = await createTestKey();
      await expectLater(
        revokeSecretKey(
          db,
          authorizer,
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/$keyId',
            roles: userOnProject(projectId),
            params: {'id': '$projectId', 'keyId': '$keyId'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown key id is rejected with 404', () async {
      await expectLater(
        revokeSecretKey(
          db,
          authorizer,
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/999',
            roles: _admin,
            params: {'id': '$projectId', 'keyId': '999'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a key id belonging to a different project is rejected with 404',
        () async {
      final keyId = await createTestKey();
      final otherProjectId = await db.into(db.projects).insert(
            ProjectsCompanion.insert(
                groupId: groupId, name: 'other', retentionDays: 30),
          );

      await expectLater(
        revokeSecretKey(
          db,
          authorizer,
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$otherProjectId/secret-keys/$keyId',
            roles: _admin,
            params: {'id': '$otherProjectId', 'keyId': '$keyId'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
