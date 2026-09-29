import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/session.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase _openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

void main() {
  late StructuredLogDatabase db;
  late int userId;

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

  Future<bool> isLive(String plain) async {
    final row = await (db.select(
      db.refreshTokens,
    )..where((t) => t.tokenHash.equals(hashToken(plain)))).getSingle();
    return row.revokedAt == null;
  }

  setUp(() async {
    db = _openInMemory();
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

  group('revokeRefreshTokensExcept', () {
    test('revokes every live token but the named one', () async {
      final kept = await issueToken();
      final phone = await issueToken();
      final laptop = await issueToken();

      await revokeRefreshTokensExcept(
        db,
        userId,
        reason: RevocationReason.passwordChanged,
        exceptTokenHash: hashToken(kept),
      );

      expect(await isLive(kept), isTrue);
      expect(await isLive(phone), isFalse);
      expect(await isLive(laptop), isFalse);
    });

    test('returns how many it revoked', () async {
      final kept = await issueToken();
      await issueToken();
      await issueToken();

      final revoked = await revokeRefreshTokensExcept(
        db,
        userId,
        reason: RevocationReason.passwordChanged,
        exceptTokenHash: hashToken(kept),
      );

      expect(revoked, 2);
    });

    test('a hash nobody holds spares nothing', () async {
      final phone = await issueToken();
      final laptop = await issueToken();

      final revoked = await revokeRefreshTokensExcept(
        db,
        userId,
        reason: RevocationReason.passwordChanged,
        exceptTokenHash: hashToken('never-issued'),
      );

      expect(revoked, 2);
      expect(await isLive(phone), isFalse);
      expect(await isLive(laptop), isFalse);
    });

    test(
      'an already-revoked token is neither re-stamped nor counted',
      () async {
        final spent = await issueToken();
        final revokedAt = DateTime.now().subtract(const Duration(days: 1));
        await (db.update(db.refreshTokens)
              ..where((t) => t.tokenHash.equals(hashToken(spent))))
            .write(RefreshTokensCompanion(revokedAt: Value(revokedAt)));
        await issueToken();

        final revoked = await revokeRefreshTokensExcept(
          db,
          userId,
          reason: RevocationReason.passwordChanged,
        );

        expect(revoked, 1, reason: 'only the one that was still live');
        final row = await (db.select(
          db.refreshTokens,
        )..where((t) => t.tokenHash.equals(hashToken(spent)))).getSingle();
        expect(
          row.revokedAt?.millisecondsSinceEpoch,
          revokedAt.millisecondsSinceEpoch,
          reason:
              'the moment a token died is a fact about it; a later sweep must '
              'not rewrite it',
        );
      },
    );

    test('records why on each row it revokes', () async {
      final kept = await issueToken();
      final phone = await issueToken();

      await revokeRefreshTokensExcept(
        db,
        userId,
        reason: RevocationReason.passwordChanged,
        exceptTokenHash: hashToken(kept),
      );

      Future<String?> reasonOf(String plain) async =>
          (await (db.select(db.refreshTokens)
                    ..where((t) => t.tokenHash.equals(hashToken(plain))))
                  .getSingle())
              .revokedReason;
      expect(await reasonOf(phone), RevocationReason.passwordChanged.wire);
      expect(await reasonOf(kept), isNull, reason: 'the spared one is live');
    });

    test('does not rewrite why an already-revoked token died', () async {
      final spent = await issueToken();
      await (db.update(
        db.refreshTokens,
      )..where((t) => t.tokenHash.equals(hashToken(spent)))).write(
        RefreshTokensCompanion(
          revokedAt: Value(DateTime.now()),
          revokedReason: Value(RevocationReason.rotated.wire),
        ),
      );

      await revokeRefreshTokensExcept(
        db,
        userId,
        reason: RevocationReason.passwordChanged,
      );

      final row = await (db.select(
        db.refreshTokens,
      )..where((t) => t.tokenHash.equals(hashToken(spent)))).getSingle();
      expect(
        row.revokedReason,
        RevocationReason.rotated.wire,
        reason:
            'a sweep relabelling a rotated token would hide the reuse its '
            'return is evidence of',
      );
    });

    test('leaves another account alone', () async {
      final mine = await issueToken();
      final otherUserId = await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'bob',
              passwordHash: hashPassword('bob-pass'),
            ),
          );
      final theirs = generateRandomToken();
      await db
          .into(db.refreshTokens)
          .insert(
            RefreshTokensCompanion.insert(
              userId: otherUserId,
              tokenHash: hashToken(theirs),
              expiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
          );

      await revokeRefreshTokensExcept(
        db,
        userId,
        reason: RevocationReason.passwordChanged,
      );

      expect(await isLive(mine), isFalse);
      expect(await isLive(theirs), isTrue);
    });
  });

  test(
    'revokeAllRefreshTokens still revokes everything the account holds',
    () async {
      final phone = await issueToken();
      final laptop = await issueToken();

      await revokeAllRefreshTokens(
        db,
        userId,
        reason: RevocationReason.blocked,
      );

      expect(await isLive(phone), isFalse);
      expect(await isLive(laptop), isFalse);
    },
  );

  group('RevocationReason.signalsReuse', () {
    test('only a rotated token is a theft signal', () {
      for (final reason in RevocationReason.values) {
        expect(
          RevocationReason.signalsReuse(reason.wire),
          reason == RevocationReason.rotated,
          reason: reason.wire,
        );
      }
    });

    test('an unrecorded or unknown reason fails towards detection', () {
      expect(RevocationReason.signalsReuse(null), isTrue);
      expect(RevocationReason.signalsReuse('something-new'), isTrue);
    });
  });
}
