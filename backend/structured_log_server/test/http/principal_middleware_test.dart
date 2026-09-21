import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/auth/principal.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/principal_middleware.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

class _FakeIdentityProvider implements IdentityProvider {
  final VerifiedIdentity? Function(String) _verify;
  var calls = 0;

  _FakeIdentityProvider(this._verify);

  @override
  Future<VerifiedIdentity?> verifyAccessToken(String bearerToken) async {
    calls++;
    return _verify(bearerToken);
  }
}

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

const _identity = VerifiedIdentity(userId: 42, username: 'alice', roles: []);

void main() {
  late StructuredLogDatabase db;
  late int projectId;
  late String activeKey;
  late String revokedKey;
  late _FakeIdentityProvider provider;

  /// Runs [request] through the middleware and reports the principal the
  /// inner handler saw — the middleware's only job.
  Future<Principal> resolve(Request request) async {
    late Principal seen;
    final handler = const Pipeline()
        .addMiddleware(principalMiddleware(provider, db))
        .addHandler((req) async {
          seen = req.principal;
          return Response.ok('ok');
        });
    final response = await handler(request);
    expect(
      response.statusCode,
      200,
      reason: 'the middleware must never answer on its own',
    );
    return seen;
  }

  Request bearer(String? token) {
    return Request(
      'GET',
      Uri.parse('http://x/v1/logs'),
      headers: token == null ? null : {'authorization': 'Bearer $token'},
    );
  }

  setUp(() async {
    db = openInMemory();
    provider = _FakeIdentityProvider(
      (token) => token == 'good-token' ? _identity : null,
    );
    final groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: 'p',
            retentionDays: 30,
          ),
        );
    activeKey = generateProjectSecretKey();
    await db
        .into(db.projectSecretKeys)
        .insert(
          ProjectSecretKeysCompanion.insert(
            projectId: projectId,
            keyHash: hashToken(activeKey),
            label: const Value('active'),
          ),
        );
    revokedKey = generateProjectSecretKey();
    await db
        .into(db.projectSecretKeys)
        .insert(
          ProjectSecretKeysCompanion.insert(
            projectId: projectId,
            keyHash: hashToken(revokedKey),
            label: const Value('revoked'),
            revokedAt: Value(DateTime.now()),
          ),
        );
  });
  tearDown(() => db.close());

  group('resolution', () {
    test('a valid access token resolves to the user', () async {
      final principal = await resolve(bearer('good-token'));
      expect(principal, isA<UserPrincipal>());
      expect((principal as UserPrincipal).identity.userId, 42);
    });

    test('a valid project secret key resolves to its project', () async {
      final principal = await resolve(bearer(activeKey));
      expect(principal, isA<ProjectPrincipal>());
      expect((principal as ProjectPrincipal).projectId, projectId);
    });

    test('a revoked project secret key resolves to anonymous', () async {
      expect(await resolve(bearer(revokedKey)), isA<AnonymousPrincipal>());
    });

    test(
      'an unknown key with the scheme prefix resolves to anonymous',
      () async {
        final principal = await resolve(bearer(generateProjectSecretKey()));
        expect(principal, isA<AnonymousPrincipal>());
      },
    );

    test('a token the provider rejects resolves to anonymous', () async {
      expect(await resolve(bearer('bad-token')), isA<AnonymousPrincipal>());
    });

    test('no Authorization header resolves to anonymous', () async {
      expect(await resolve(bearer(null)), isA<AnonymousPrincipal>());
    });

    test('a non-Bearer Authorization header resolves to anonymous', () async {
      final request = Request(
        'GET',
        Uri.parse('http://x/v1/logs'),
        headers: {'authorization': 'Basic abc'},
      );
      expect(await resolve(request), isA<AnonymousPrincipal>());
    });
  });

  group('discrimination', () {
    test('a prefixed value never reaches the identity provider', () async {
      await resolve(bearer(activeKey));
      await resolve(bearer(generateProjectSecretKey()));
      expect(provider.calls, 0);
    });

    test('an access token is never looked up as a secret key', () async {
      // The only observable proof that the key lookup was skipped is that a
      // token whose text happens to hash to a stored key still resolves as a
      // token: strip the prefix off a real key and it stops authenticating.
      final stripped = activeKey.substring(projectSecretKeyPrefix.length);
      expect(await resolve(bearer(stripped)), isA<AnonymousPrincipal>());
      expect(provider.calls, 1);
    });
  });

  group('requireUser', () {
    test('returns the identity for a user principal', () async {
      final request = bearer('good-token').change(
        context: {'structured_log_server.principal': UserPrincipal(_identity)},
      );
      expect(request.requireUser().userId, 42);
    });

    test('throws 401 for an anonymous principal', () {
      expect(
        () => bearer(null).requireUser(),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws 401 for a project principal', () {
      final request = bearer(null).change(
        context: {'structured_log_server.principal': ProjectPrincipal(1)},
      );
      expect(
        () => request.requireUser(),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws 403 must_change_password for a temporary password', () {
      const temporary = VerifiedIdentity(
        userId: 7,
        username: 'bob',
        roles: [],
        mustChangePassword: true,
      );
      final request = bearer(null).change(
        context: {'structured_log_server.principal': UserPrincipal(temporary)},
      );
      expect(
        () => request.requireUser(),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'must_change_password'),
        ),
      );
    });

    test('allowTemporaryPassword opts a handler out of the gate', () {
      const temporary = VerifiedIdentity(
        userId: 7,
        username: 'bob',
        roles: [],
        mustChangePassword: true,
      );
      final request = bearer(null).change(
        context: {'structured_log_server.principal': UserPrincipal(temporary)},
      );
      expect(request.requireUser(allowTemporaryPassword: true).userId, 7);
    });
  });

  group('requireProject', () {
    test('returns the project id for a project principal', () {
      final request = bearer(null).change(
        context: {'structured_log_server.principal': ProjectPrincipal(5)},
      );
      expect(request.requireProject(), 5);
    });

    test('throws 401 for an anonymous principal', () {
      expect(
        () => bearer(null).requireProject(),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws 401 for a user principal', () {
      final request = bearer(null).change(
        context: {'structured_log_server.principal': UserPrincipal(_identity)},
      );
      expect(
        () => request.requireProject(),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  test('a request that never passed the middleware reads as anonymous', () {
    expect(bearer('good-token').principal, isA<AnonymousPrincipal>());
  });
}
