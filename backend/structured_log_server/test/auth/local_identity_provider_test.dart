import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/claims.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/local_identity_provider.dart';
import 'package:structured_log_server/src/auth/token_service.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

const _secret = 'test-signing-secret';
const _issuer = 'structured_log_server-test';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

/// Any address will do; what matters is that one is recorded.
const testClientIp = '203.0.113.9';

void main() {
  late StructuredLogDatabase db;
  late TokenService tokenService;
  late LocalIdentityProvider provider;

  setUp(() {
    db = openInMemory();
    tokenService = TokenService(
      db,
      ClaimsResolver(db, Authorizer(db)),
      AuditWriter(db),
      signingSecret: _secret,
      issuer: _issuer,
    );
    provider =
        LocalIdentityProvider(db, signingSecret: _secret, issuer: _issuer);
  });
  tearDown(() => db.close());

  Future<int> insertUser({String password = 's3cret'}) {
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'alice',
            passwordHash: hashPassword(password),
          ),
        );
  }

  test(
      'a token issued end-to-end by TokenService verifies with a non-null roles list',
      () async {
    final userId = await insertUser();
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );

    final pair = (await tokenService.passwordGrant(
      clientIp: testClientIp,
      username: 'alice',
      password: 's3cret',
    ))
        .getRight()
        .toNullable()!;

    final identity = await provider.verifyAccessToken(pair.accessToken);
    expect(identity, isNotNull);
    expect(identity!.userId, userId);
    expect(identity.username, 'alice');
    expect(identity.roles, isNotEmpty);
  });

  test('a token with a stale tv is rejected', () async {
    final userId = await insertUser();
    await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
      const UsersCompanion(tokenVersion: Value(5)),
    );

    final jwt = JWT({
      'preferred_username': 'alice',
      'tv': 0, // stale — current token_version is 5
      'roles': <Map<String, Object?>>[],
    }, subject: '$userId', issuer: _issuer, jwtId: 'test-jti');
    final token =
        jwt.sign(SecretKey(_secret), expiresIn: const Duration(minutes: 5));

    expect(await provider.verifyAccessToken(token), isNull);
  });

  test('an expired token is rejected', () async {
    final userId = await insertUser();
    final jwt = JWT({
      'preferred_username': 'alice',
      'tv': 0,
      'roles': <Map<String, Object?>>[],
    }, subject: '$userId', issuer: _issuer, jwtId: 'test-jti');
    final token = jwt.sign(
      SecretKey(_secret),
      expiresIn: const Duration(seconds: -1),
    );

    expect(await provider.verifyAccessToken(token), isNull);
  });

  test('a token signed with the wrong secret is rejected', () async {
    final userId = await insertUser();
    final jwt = JWT({
      'preferred_username': 'alice',
      'tv': 0,
      'roles': <Map<String, Object?>>[],
    }, subject: '$userId', issuer: _issuer, jwtId: 'test-jti');
    final token = jwt.sign(
      SecretKey('wrong-secret'),
      expiresIn: const Duration(minutes: 5),
    );

    expect(await provider.verifyAccessToken(token), isNull);
  });

  test('a garbage string is rejected', () async {
    expect(await provider.verifyAccessToken('not.a.jwt'), isNull);
  });

  test('a token for a nonexistent user is rejected', () async {
    final jwt = JWT({
      'preferred_username': 'ghost',
      'tv': 0,
      'roles': <Map<String, Object?>>[],
    }, subject: '999999', issuer: _issuer, jwtId: 'test-jti');
    final token =
        jwt.sign(SecretKey(_secret), expiresIn: const Duration(minutes: 5));

    expect(await provider.verifyAccessToken(token), isNull);
  });
}
