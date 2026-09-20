import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/change_password_route.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late int userId;
  late ChangePasswordRoutes routes;

  setUp(() async {
    db = openInMemory();
    routes = ChangePasswordRoutes(db, AuditWriter(db));
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'alice',
            passwordHash: hashPassword('old-pass'),
            mustChangePassword: const Value(true),
            tokenVersion: const Value(3),
          ),
        );
  });
  tearDown(() => db.close());

  test('a correct current password updates the hash and clears the flag',
      () async {
    final response = await routes.router.call(
      authenticatedRequest(
        'POST',
        'http://x/v1/auth/change-password',
        roles: const [],
        userId: userId,
        jsonBody: {'current_password': 'old-pass', 'new_password': 'new-pass'},
      ),
    );

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body, {});

    final row = await (db.select(
      db.users,
    )..where((t) => t.id.equals(userId)))
        .getSingle();
    expect(row.mustChangePassword, isFalse);
    expect(verifyPassword('new-pass', row.passwordHash), isTrue);
  });

  test('changing the password increments token_version', () async {
    await routes.router.call(
      authenticatedRequest(
        'POST',
        'http://x/v1/auth/change-password',
        roles: const [],
        userId: userId,
        jsonBody: {'current_password': 'old-pass', 'new_password': 'new-pass'},
      ),
    );
    final row = await (db.select(
      db.users,
    )..where((t) => t.id.equals(userId)))
        .getSingle();
    expect(row.tokenVersion, 4);
  });

  test('an incorrect current password is rejected and nothing changes',
      () async {
    await expectLater(
      routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/auth/change-password',
          roles: const [],
          userId: userId,
          jsonBody: {'current_password': 'wrong', 'new_password': 'new-pass'},
        ),
      ),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401)),
    );

    final row = await (db.select(
      db.users,
    )..where((t) => t.id.equals(userId)))
        .getSingle();
    expect(row.mustChangePassword, isTrue);
    expect(verifyPassword('old-pass', row.passwordHash), isTrue);
  });

  test('works even when must_change_password was already false', () async {
    await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
      const UsersCompanion(mustChangePassword: Value(false)),
    );

    final response = await routes.router.call(
      authenticatedRequest(
        'POST',
        'http://x/v1/auth/change-password',
        roles: const [],
        userId: userId,
        jsonBody: {'current_password': 'old-pass', 'new_password': 'new-pass'},
      ),
    );
    expect(response.statusCode, 200);
  });

  test('missing fields are rejected with 400', () async {
    await expectLater(
      routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/auth/change-password',
          roles: const [],
          userId: userId,
          jsonBody: {'current_password': 'old-pass'},
        ),
      ),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
    );
  });

  group('the audit record', () {
    Future<void> change({
      String current = 'old-pass',
      String next = 'new-pass',
    }) async {
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/auth/change-password',
          roles: const [],
          userId: userId,
          jsonBody: {'current_password': current, 'new_password': next},
        ),
      );
    }

    test('a changed password leaves one, carrying neither password', () async {
      await change();

      final row = (await auditRows(db)).single;
      expect(row.action, 'password.changed');
      expect(row.targetType, 'user');
      expect(row.actorUserId, userId);
      expect(
        row.targetId,
        userId,
        reason: 'actor and target are the same account — this endpoint only '
            'ever changes your own',
      );
      expect(auditMetadata(row), isEmpty);
      expect(row.metadata, isNot(contains('old-pass')));
      expect(row.metadata, isNot(contains('new-pass')));
    });

    test('a wrong current password leaves none', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/auth/change-password',
            roles: const [],
            userId: userId,
            jsonBody: {
              'current_password': 'wrong',
              'new_password': 'new-pass',
            },
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(
        await auditRows(db),
        isEmpty,
        reason: 'a refused attempt is an authentication event, not a password '
            'change — and this endpoint does not record those',
      );
    });
  });

  test('a new password over 72 bytes is rejected with 400, nothing changes',
      () async {
    await expectLater(
      routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/auth/change-password',
          roles: const [],
          userId: userId,
          jsonBody: {
            'current_password': 'old-pass',
            'new_password': 'Ж' * 40,
          },
        ),
      ),
      throwsA(
        isA<ApiError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.details?['field'], 'field', 'new_password')
            .having((e) => e.details?['reason'], 'reason', 'too_long'),
      ),
    );
    final row = await (db.select(db.users)..where((t) => t.id.equals(userId)))
        .getSingle();
    expect(verifyPassword('old-pass', row.passwordHash), isTrue);
    expect(row.mustChangePassword, isTrue);
  });
}
