@Tags(['postgres'])
library;

import 'dart:io';

import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/session.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

/// `session.dart` against the dialect the SQLite-backed suite cannot reach.
///
/// `revokeRefreshTokensExcept` is one `UPDATE`, which looks like the last
/// place a dialect could matter — and it was where one did. Sparing a token
/// was written with drift's `isNotValue`, the null-safe `IS NOT <value>`:
/// valid in SQLite, and refused outright by PostgreSQL, where `IS NOT` takes
/// only NULL/TRUE/FALSE. Every existing test passed, because they all run on
/// `NativeDatabase.memory()`. What failed was `POST /v1/auth/change-password`
/// on a deployed server — with `42601` and a 500, on the one command a
/// bootstrap administrator must complete before anything else works.
///
/// So the rule this file stands for is narrower than "test both backends":
/// a query built with anything beyond `equals`/`isNull`/`isIn` needs a case
/// here, because that is where the dialects stop agreeing
/// (`add-postgres-backend` design.md).

String _env(String suffix, String fallback) =>
    Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_$suffix'] ?? fallback;

final _host = _env('HOST', 'localhost');
final _port = int.parse(_env('PORT', '5432'));
final _database = _env('DATABASE', 'postgres');
final _username = _env('USERNAME', 'postgres');
final _password = Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_PASSWORD'];

void main() {
  late StructuredLogDatabase db;
  late int userId;

  setUpAll(() {
    if (_password == null) {
      throw StateError(
        'STRUCTURED_LOG_TEST_POSTGRES_PASSWORD must be set to run tests '
        'tagged postgres (see dart_test.yaml).',
      );
    }
  });

  setUp(() async {
    db = StructuredLogDatabase.openPostgres(
      host: _host,
      port: _port,
      database: _database,
      username: _username,
      password: _password!,
      sslMode: 'disable',
    );
    // Shared physical database, no per-file isolation: `--concurrency=1` and
    // a truncate of its own, like every other file in this tag.
    await db.customStatement(
      'TRUNCATE refresh_tokens, users RESTART IDENTITY CASCADE',
    );
    userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'alice',
            passwordHash: hashPassword('old-pass'),
          ),
        );
  });
  tearDown(() => db.close());

  Future<String> issueToken() async {
    final plain = generateRandomToken();
    await db
        .into(db.refreshTokens)
        .insert(
          RefreshTokensCompanion.insert(
            userId: userId,
            tokenHash: hashToken(plain),
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          ),
        );
    return plain;
  }

  Future<DateTime?> revokedAtOf(String plain) async {
    final row = await (db.select(
      db.refreshTokens,
    )..where((t) => t.tokenHash.equals(hashToken(plain)))).getSingle();
    return row.revokedAt;
  }

  test('sparing the named token revokes the rest', () async {
    final kept = await issueToken();
    final phone = await issueToken();
    final laptop = await issueToken();

    final revoked = await revokeRefreshTokensExcept(
      db,
      userId,
      exceptTokenHash: hashToken(kept),
    );

    expect(revoked, 2);
    expect(await revokedAtOf(kept), null);
    expect(await revokedAtOf(phone), isNot(null));
    expect(await revokedAtOf(laptop), isNot(null));
  });

  test('sparing nobody revokes everything', () async {
    final phone = await issueToken();
    final laptop = await issueToken();

    expect(await revokeRefreshTokensExcept(db, userId), 2);
    expect(await revokedAtOf(phone), isNot(null));
    expect(await revokedAtOf(laptop), isNot(null));
  });

  test('a hash nobody holds spares nothing', () async {
    final phone = await issueToken();

    final revoked = await revokeRefreshTokensExcept(
      db,
      userId,
      exceptTokenHash: hashToken('never-issued'),
    );

    expect(revoked, 1);
    expect(await revokedAtOf(phone), isNot(null));
  });
}
