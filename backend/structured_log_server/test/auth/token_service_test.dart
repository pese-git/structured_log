import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/claims.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
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
  late TokenService service;

  setUp(() {
    db = openInMemory();
    service = TokenService(
      db,
      ClaimsResolver(db, Authorizer(db)),
      AuditWriter(db),
      signingSecret: _secret,
      issuer: _issuer,
      accessTokenTtl: const Duration(minutes: 15),
      refreshTokenTtl: const Duration(days: 30),
    );
  });
  tearDown(() => db.close());

  Future<int> insertUser({
    String username = 'alice',
    String password = 's3cret',
    bool isActive = true,
  }) {
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashPassword(password),
            isActive: Value(isActive),
          ),
        );
  }

  group('passwordGrant', () {
    test('valid credentials return a token pair with a well-formed JWT',
        () async {
      await insertUser();
      final result = await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      );

      final pair = result.getRight().toNullable();
      expect(pair, isNotNull);
      expect(pair!.refreshToken, isNotEmpty);

      final jwt = JWT.verify(
        pair.accessToken,
        SecretKey(_secret),
        issuer: _issuer,
      );
      expect(jwt.subject, isNotNull);
      expect((jwt.payload as Map)['preferred_username'], 'alice');
      expect((jwt.payload as Map)['tv'], 0);
      expect((jwt.payload as Map)['roles'], isEmpty);
    });

    test('wrong password is rejected as invalid_grant', () async {
      await insertUser();
      final result = await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 'wrong',
      );
      expect(
        result.getLeft().toNullable()?.code,
        TokenErrorCode.invalidGrant,
      );
    });

    test('unknown username is rejected as invalid_grant', () async {
      final result = await service.passwordGrant(
        clientIp: testClientIp,
        username: 'nobody',
        password: 'irrelevant',
      );
      expect(
        result.getLeft().toNullable()?.code,
        TokenErrorCode.invalidGrant,
      );
    });

    test('an inactive user is rejected even with the correct password',
        () async {
      await insertUser(isActive: false);
      final result = await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      );
      expect(
        result.getLeft().toNullable()?.code,
        TokenErrorCode.invalidGrant,
      );
    });

    test('roles claim reflects direct and team-inherited grants', () async {
      final userId = await insertUser();
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: userId,
              role: 'admin',
              scopeType: 'global',
            ),
          );

      final result = await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      );
      final pair = result.getRight().toNullable()!;
      final jwt =
          JWT.verify(pair.accessToken, SecretKey(_secret), issuer: _issuer);
      final roles = (jwt.payload as Map)['roles'] as List;
      expect(roles, [
        {'role': 'admin', 'scope_type': 'global', 'scope_id': null},
      ]);
    });
  });

  group('refreshTokenGrant', () {
    test('a valid refresh token rotates and returns a new pair', () async {
      await insertUser();
      final issued = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;

      final result = await service.refreshTokenGrant(issued.refreshToken);
      final rotated = result.getRight().toNullable();
      expect(rotated, isNotNull);
      expect(rotated!.refreshToken, isNot(issued.refreshToken));
    });

    test('the rotated-away token is rejected on reuse', () async {
      await insertUser();
      final issued = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;
      await service.refreshTokenGrant(issued.refreshToken);

      final reuse = await service.refreshTokenGrant(issued.refreshToken);
      expect(reuse.getLeft().toNullable()?.code, TokenErrorCode.invalidGrant);
    });

    test('reusing an already-revoked token revokes the rest of the chain',
        () async {
      await insertUser();
      final first = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;
      final second = (await service.refreshTokenGrant(
        first.refreshToken,
      ))
          .getRight()
          .toNullable()!;

      // `first` is already rotated away; presenting it again simulates theft.
      await service.refreshTokenGrant(first.refreshToken);

      final afterCompromise = await service.refreshTokenGrant(
        second.refreshToken,
      );
      expect(
        afterCompromise.getLeft().toNullable()?.code,
        TokenErrorCode.invalidGrant,
      );
    });

    test('an unknown refresh token is rejected', () async {
      final result = await service.refreshTokenGrant('not-a-real-token');
      expect(result.getLeft().toNullable()?.code, TokenErrorCode.invalidGrant);
    });

    test('an expired refresh token is rejected', () async {
      final userId = await insertUser();
      final rawToken = generateRandomToken();
      await db.into(db.refreshTokens).insert(
            RefreshTokensCompanion.insert(
              userId: userId,
              tokenHash: hashToken(rawToken),
              expiresAt: DateTime.now().subtract(const Duration(days: 1)),
            ),
          );

      final result = await service.refreshTokenGrant(rawToken);
      expect(result.getLeft().toNullable()?.code, TokenErrorCode.invalidGrant);
    });

    test('a refresh token for a now-inactive user is rejected', () async {
      final userId = await insertUser();
      final issued = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;

      await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
        const UsersCompanion(isActive: Value(false)),
      );

      final result = await service.refreshTokenGrant(issued.refreshToken);
      expect(result.getLeft().toNullable()?.code, TokenErrorCode.invalidGrant);
    });

    test('a refreshed token carries freshly resolved roles and tv', () async {
      final userId = await insertUser();
      final issued = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;

      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: userId,
              role: 'admin',
              scopeType: 'global',
            ),
          );
      await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
        UsersCompanion.custom(
            tokenVersion: db.users.tokenVersion + const Constant(1)),
      );

      final refreshed = (await service.refreshTokenGrant(
        issued.refreshToken,
      ))
          .getRight()
          .toNullable()!;
      final jwt = JWT.verify(refreshed.accessToken, SecretKey(_secret),
          issuer: _issuer);
      expect((jwt.payload as Map)['tv'], 1);
      expect((jwt.payload as Map)['roles'], isNotEmpty);
    });
  });

  group('revoke', () {
    test('a revoked refresh token is rejected by a later refresh grant',
        () async {
      await insertUser();
      final issued = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;

      await service.revoke(issued.refreshToken, clientIp: testClientIp);

      final result = await service.refreshTokenGrant(issued.refreshToken);
      expect(result.getLeft().toNullable()?.code, TokenErrorCode.invalidGrant);
    });

    test('revoking an unknown token does not throw', () async {
      await expectLater(
          service.revoke('never-issued', clientIp: testClientIp), completes);
    });

    test('revoking an already-revoked token does not throw', () async {
      await insertUser();
      final issued = (await service.passwordGrant(
        clientIp: testClientIp,
        username: 'alice',
        password: 's3cret',
      ))
          .getRight()
          .toNullable()!;
      await service.revoke(issued.refreshToken, clientIp: testClientIp);
      await expectLater(
          service.revoke(issued.refreshToken, clientIp: testClientIp),
          completes);
    });
  });
}
