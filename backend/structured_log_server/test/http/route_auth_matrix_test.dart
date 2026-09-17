import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

/// What a route requires of the request's principal (`log-server-auth`).
enum Requires { user, project, public }

/// Every route [buildHandler] registers, with the principal it requires.
///
/// This table is the fail-closed guarantee that used to be visible in
/// `buildHandler` itself, back when each route carried its own auth
/// middleware. Now that authentication is one `Pipeline` stage and each
/// handler states its own requirement, the only thing standing between a new
/// endpoint and an unauthenticated caller is that it calls `requireUser()` /
/// `requireProject()` — so every route is enumerated here and probed with the
/// wrong credential. A route added without a `require*` call fails this test;
/// a route deliberately left public has to be written down as such, which is
/// a visible act in review.
const _routes = <({String method, String path, Requires requires})>[
  (method: 'POST', path: '/v1/auth/token', requires: Requires.public),
  (method: 'DELETE', path: '/v1/auth/token', requires: Requires.public),
  (method: 'GET', path: '/healthz', requires: Requires.public),
  (method: 'GET', path: '/v1/audit-log', requires: Requires.user),
  (method: 'POST', path: '/v1/auth/change-password', requires: Requires.user),
  (method: 'POST', path: '/v1/logs', requires: Requires.project),
  (method: 'GET', path: '/v1/logs', requires: Requires.user),
  (method: 'GET', path: '/v1/logs/stream', requires: Requires.user),
  (method: 'POST', path: '/v1/groups', requires: Requires.user),
  (method: 'GET', path: '/v1/groups', requires: Requires.user),
  (method: 'POST', path: '/v1/groups/1/projects', requires: Requires.user),
  (method: 'GET', path: '/v1/projects', requires: Requires.user),
  (method: 'PATCH', path: '/v1/projects/1', requires: Requires.user),
  (method: 'GET', path: '/v1/projects/1', requires: Requires.user),
  (method: 'POST', path: '/v1/projects/1/secret-keys', requires: Requires.user),
  (method: 'GET', path: '/v1/projects/1/secret-keys', requires: Requires.user),
  (
    method: 'DELETE',
    path: '/v1/projects/1/secret-keys/1',
    requires: Requires.user,
  ),
  (method: 'POST', path: '/v1/users', requires: Requires.user),
  (method: 'GET', path: '/v1/users', requires: Requires.user),
  (method: 'PATCH', path: '/v1/users/1', requires: Requires.user),
  (method: 'POST', path: '/v1/users/1/block', requires: Requires.user),
  (method: 'POST', path: '/v1/users/1/unblock', requires: Requires.user),
  (method: 'DELETE', path: '/v1/users/me', requires: Requires.user),
  (method: 'DELETE', path: '/v1/users/1', requires: Requires.user),
  (method: 'POST', path: '/v1/projects/1/block', requires: Requires.user),
  (method: 'POST', path: '/v1/projects/1/unblock', requires: Requires.user),
  (method: 'POST', path: '/v1/role-assignments', requires: Requires.user),
  (method: 'GET', path: '/v1/role-assignments', requires: Requires.user),
  (
    method: 'DELETE',
    path: '/v1/role-assignments/1',
    requires: Requires.user,
  ),
];

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late Handler handler;
  late String secretKey;

  setUp(() async {
    db = openInMemory();
    handler = buildHandler(db, signingSecret: 'test-secret', issuer: 'test');

    final groupId = await db.into(db.groups).insert(
          GroupsCompanion.insert(name: 'g'),
        );
    final projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: 'p',
            retentionDays: 30,
          ),
        );
    secretKey = generateProjectSecretKey();
    await db.into(db.projectSecretKeys).insert(
          ProjectSecretKeysCompanion.insert(
            projectId: projectId,
            keyHash: hashToken(secretKey),
            label: const Value('ingest'),
          ),
        );
  });
  tearDown(() => db.close());

  Future<Response> send(
    ({String method, String path, Requires requires}) route, {
    String? token,
  }) async {
    return handler(
      Request(
        route.method,
        Uri.parse('http://x${route.path}'),
        body: route.method == 'GET' || route.method == 'DELETE'
            ? null
            : jsonEncode(<String, Object?>{}),
        headers: token == null ? null : {'authorization': 'Bearer $token'},
      ),
    );
  }

  test('the table covers every annotated route', () {
    // `Router` doesn't expose what was registered on it, and since
    // `shelf_router_generator` took over the route table there is nothing to
    // count in `server.dart` either — the routes are the `@Route`
    // annotations. Adding one without a line here fails this, which is the
    // point: whoever adds a route has to say what authenticates it.
    final annotations = Directory('lib/src/http/routes')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_route.dart'))
        .map((f) => f.readAsStringSync())
        .expand((source) => RegExp(r'@Route[.(]').allMatches(source))
        .length;

    expect(
      _routes.length,
      annotations,
      reason: '@Route-annotated handlers missing from _routes',
    );
  });

  for (final route in _routes) {
    final name = '${route.method} ${route.path}';

    if (route.requires == Requires.public) {
      test('$name is public and does not 401 on a missing credential',
          () async {
        final response = await send(route);
        expect(response.statusCode, isNot(401));
      });
      continue;
    }

    test('$name rejects a request with no credential', () async {
      final response = await send(route);
      expect(response.statusCode, 401, reason: 'no Authorization header');
    });

    test('$name rejects a credential of the wrong kind', () async {
      // A project secret key must not open a management endpoint; an access
      // token must not open ingestion. For the user routes an unsigned
      // placeholder would also 401, so the key — a real, valid credential of
      // the other kind — is the meaningful probe.
      final wrong = route.requires == Requires.user
          ? secretKey
          : 'eyJhbGciOiJIUzI1NiJ9.e30.not-a-real-signature';
      final response = await send(route, token: wrong);
      expect(response.statusCode, 401);
    });
  }
}
