import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/groups_route.dart';
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
  late GroupRoutes routes;

  setUp(() {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = GroupRoutes(db, authorizer);
  });
  tearDown(() => db.close());

  group('createGroup', () {
    test('admin can create a group', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups',
          roles: _admin,
          jsonBody: {'name': 'payments-team'},
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['name'], 'payments-team');
      expect(body['id'], isNotNull);
      expect(body['created_at'], isNotNull);
    });

    test('a non-admin is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups',
            roles: _noRoles,
            jsonBody: {'name': 'x'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('a missing name is rejected with 400', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups',
            roles: _admin,
            jsonBody: <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('listGroups', () {
    test('a global admin sees every group', () async {
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'a'));
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'b'));

      final response = await routes.router.call(
        authenticatedRequest('GET', 'http://x/v1/groups', roles: _admin),
      );
      final body = await decodeJson(response);
      expect((body['items'] as List), hasLength(2));
    });

    test('a user only sees groups covered by their roles', () async {
      final groupA = await db.into(db.groups).insert(
            GroupsCompanion.insert(name: 'visible'),
          );
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'hidden'));

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/groups',
          roles: [
            EffectiveRole(
              role: Role.owner,
              scopeType: ScopeType.group,
              scopeId: groupA,
            ),
          ],
        ),
      );
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['name'], 'visible');
    });

    test('a caller with no roles sees no groups', () async {
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'a'));

      final response = await routes.router.call(
        authenticatedRequest('GET', 'http://x/v1/groups', roles: _noRoles),
      );
      final body = await decodeJson(response);
      expect(body['items'], isEmpty);
    });
  });
}
