import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
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

  setUp(() async {
    db = openInMemory();
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
    final response = await changePassword(
      db,
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
    await changePassword(
      db,
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
      changePassword(
        db,
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

    final response = await changePassword(
      db,
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
      changePassword(
        db,
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
}
