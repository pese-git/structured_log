import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/claims.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/token_service.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

const _ip = '203.0.113.9';
const _agent = 'structured_log_admin_client/0.1';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late TokenService service;
  late int userId;

  setUp(() async {
    db = openInMemory();
    service = TokenService(
      db,
      ClaimsResolver(db, Authorizer(db)),
      AuditWriter(db),
      signingSecret: 'test-secret',
      issuer: 'test',
    );
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'alice',
            passwordHash: hashPassword('correct'),
          ),
        );
  });
  tearDown(() => db.close());

  Future<List<AuditLogEntry>> rows() => db.select(db.auditLogEntries).get();
  Map<String, Object?> metaOf(AuditLogEntry row) =>
      jsonDecode(row.metadata) as Map<String, Object?>;

  Future<void> login({
    String username = 'alice',
    String password = 'correct',
  }) async {
    await service.passwordGrant(
      username: username,
      password: password,
      clientIp: _ip,
      userAgent: _agent,
    );
  }

  test('a successful login records who, from where and with what', () async {
    await login();

    final row = (await rows()).single;
    expect(row.action, 'auth.login_succeeded');
    expect(row.actorUserId, userId);
    expect(row.targetId, userId);
    expect(metaOf(row), {'client_ip': _ip, 'user_agent': _agent});
  });

  test('a wrong password records the reason', () async {
    await login(password: 'wrong');

    final row = (await rows()).single;
    expect(row.action, 'auth.login_failed');
    expect(row.actorUserId, userId, reason: 'the account is known');
    expect(metaOf(row)['reason'], 'invalid_password');
    expect(metaOf(row)['client_ip'], _ip);
  });

  test('a blocked account is refused for being blocked, not for its password',
      () async {
    await (db.update(db.users)..where((t) => t.id.equals(userId)))
        .write(const UsersCompanion(isActive: Value(false)));

    await login();

    expect(metaOf((await rows()).single)['reason'], 'blocked');
  });

  test('a deleted account is refused, and says so', () async {
    // Unreachable today — nothing sets `deleted_at`, because account deletion
    // belongs to a later stage. The branch exists because the collapsed
    // condition this replaced never consulted the column at all, and the
    // moment deletion lands a row with `deleted_at` set and `is_active` still
    // true would otherwise authenticate.
    await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
      UsersCompanion(deletedAt: Value(DateTime.now())),
    );

    final result = await service.passwordGrant(
      username: 'alice',
      password: 'correct',
      clientIp: _ip,
    );

    expect(result.isLeft(), isTrue,
        reason: 'the credentials are still correct');
    expect(metaOf((await rows()).single)['reason'], 'deleted');
  });

  test('an unknown username is recorded without being recorded', () async {
    // The submitted string is regularly a password typed into the wrong box.
    // The assertion is on every row's serialized metadata, not on one expected
    // key, because "nowhere in any form" is what the requirement says.
    await login(username: 'Pa55word!', password: 'whatever');

    final row = (await rows()).single;
    expect(row.action, 'auth.login_failed');
    expect(row.actorUserId, isNull);
    expect(row.targetId, isNull);
    expect(metaOf(row)['reason'], 'unknown_user');
    expect(metaOf(row)['unknown_user'], isTrue);

    for (final stored in await rows()) {
      expect(stored.metadata, isNot(contains('Pa55word!')));
      expect(stored.metadata, isNot(contains('whatever')));
    }
  });

  test('no password ever reaches the journal', () async {
    await login();
    await login(password: 'wrong');

    for (final row in await rows()) {
      expect(row.metadata, isNot(contains('correct')));
      expect(row.metadata, isNot(contains('wrong')));
    }
  });

  test('renewing a session records nothing at all', () async {
    // Counted, not inspected: the requirement is that these produce no rows,
    // and asserting the absence of code would not notice one added later.
    final pair = (await service.passwordGrant(
      username: 'alice',
      password: 'correct',
      clientIp: _ip,
    ))
        .getOrElse((_) => throw StateError('login failed'));

    final before = (await rows()).length;

    var refresh = pair.refreshToken;
    for (var i = 0; i < 3; i++) {
      final renewed = (await service.refreshTokenGrant(refresh))
          .getOrElse((_) => throw StateError('refresh failed'));
      refresh = renewed.refreshToken;
    }

    expect(
      (await rows()).length,
      before,
      reason:
          'a client renewing its session is the same session continuing; one '
          'record per renewal would bury the logins that are events',
    );
  });

  group('logging out', () {
    test('a live token records the logout', () async {
      final pair = (await service.passwordGrant(
        username: 'alice',
        password: 'correct',
        clientIp: _ip,
      ))
          .getOrElse((_) => throw StateError('login failed'));

      await service.revoke(
        pair.refreshToken,
        clientIp: _ip,
        userAgent: _agent,
      );

      final row = (await rows()).last;
      expect(row.action, 'auth.logged_out');
      expect(row.actorUserId, userId);
      expect(metaOf(row)['client_ip'], _ip);
    });

    test('an unknown token records nothing, though the response is the same',
        () async {
      await service.revoke('never-issued', clientIp: _ip);

      expect(
        await rows(),
        isEmpty,
        reason:
            'nobody logged out; the sameness that protects the caller is in '
            'the response, not in the journal',
      );
    });

    test('a second logout of the same token records nothing', () async {
      final pair = (await service.passwordGrant(
        username: 'alice',
        password: 'correct',
        clientIp: _ip,
      ))
          .getOrElse((_) => throw StateError('login failed'));

      await service.revoke(pair.refreshToken, clientIp: _ip);
      final after = (await rows()).length;
      await service.revoke(pair.refreshToken, clientIp: _ip);

      expect((await rows()).length, after);
    });
  });
}
