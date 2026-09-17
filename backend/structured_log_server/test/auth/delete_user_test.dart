import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/delete_user.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;

  setUp(() => db = openInMemory());
  tearDown(() => db.close());

  Future<User> insertUser({
    String username = 'bob',
    bool isPrimaryAdmin = false,
  }) async {
    final id = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashPassword('s3cret'),
            isPrimaryAdmin: Value(isPrimaryAdmin),
          ),
        );
    return (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
  }

  group('the primary-administrator guard', () {
    test('refuses to delete the primary administrator, no changes made',
        () async {
      final target = await insertUser(isPrimaryAdmin: true);

      final outcome = await deleteUser(db, target);

      expect(outcome.isSuccess, isFalse);
      expect(outcome.failure, DeleteUserFailure.cannotDeletePrimaryAdmin);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.deletedAt, isNull);
      expect(row.isActive, isTrue);
    });

    test('does not even reach the sole-owner check first', () async {
      // A primary admin who also happens to be a sole group owner still
      // gets the identity-based refusal, not the group one — the check
      // order in `deleteUser` stops at the first failure.
      final target = await insertUser(isPrimaryAdmin: true);
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: target.id,
              role: 'owner',
              scopeType: 'group',
              scopeId: Value(groupId),
            ),
          );

      final outcome = await deleteUser(db, target);

      expect(outcome.failure, DeleteUserFailure.cannotDeletePrimaryAdmin);
      expect(outcome.blockingGroups, isEmpty);
    });
  });

  group('the sole-group-owner guard', () {
    test('refuses when the target is the only owner of a group', () async {
      final target = await insertUser();
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: target.id,
              role: 'owner',
              scopeType: 'group',
              scopeId: Value(groupId),
            ),
          );

      final outcome = await deleteUser(db, target);

      expect(outcome.isSuccess, isFalse);
      expect(outcome.failure, DeleteUserFailure.soleGroupOwner);
      expect(outcome.blockingGroups.single.id, groupId);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.deletedAt, isNull, reason: 'no changes on refusal');
    });

    test('succeeds once another owner exists on the same group', () async {
      final target = await insertUser();
      final other = await insertUser(username: 'other-owner');
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      for (final ownerId in [target.id, other.id]) {
        await db.into(db.roleAssignments).insert(
              RoleAssignmentsCompanion.insert(
                subjectType: 'user',
                subjectId: ownerId,
                role: 'owner',
                scopeType: 'group',
                scopeId: Value(groupId),
              ),
            );
      }

      final outcome = await deleteUser(db, target);

      expect(outcome.isSuccess, isTrue);
    });

    test('does not block on a `user`-role grant on the same group', () async {
      // Only `owner` grants count towards "sole owner" — a plain `user`
      // grant on the group isn't a substitute owner.
      final target = await insertUser();
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: target.id,
              role: 'owner',
              scopeType: 'group',
              scopeId: Value(groupId),
            ),
          );
      final other = await insertUser(username: 'reader');
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: other.id,
              role: 'user',
              scopeType: 'group',
              scopeId: Value(groupId),
            ),
          );

      final outcome = await deleteUser(db, target);

      expect(outcome.failure, DeleteUserFailure.soleGroupOwner);
    });

    test('lists every group the target is the sole owner of', () async {
      final target = await insertUser();
      final groupA =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'a'));
      final groupB =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'b'));
      for (final groupId in [groupA, groupB]) {
        await db.into(db.roleAssignments).insert(
              RoleAssignmentsCompanion.insert(
                subjectType: 'user',
                subjectId: target.id,
                role: 'owner',
                scopeType: 'group',
                scopeId: Value(groupId),
              ),
            );
      }

      final outcome = await deleteUser(db, target);

      expect(
        outcome.blockingGroups.map((g) => g.id),
        containsAll([groupA, groupB]),
      );
    });
  });

  group('on success', () {
    test('sets deleted_at and is_active, and leaves the row otherwise intact',
        () async {
      final target = await insertUser();

      final outcome = await deleteUser(db, target);

      expect(outcome.isSuccess, isTrue);
      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.isActive, isFalse);
      expect(row.username, target.username, reason: 'the row is not erased');
    });

    test('revokes every outstanding refresh token', () async {
      final target = await insertUser();
      await db.into(db.refreshTokens).insert(
            RefreshTokensCompanion.insert(
              userId: target.id,
              tokenHash: hashToken('a-refresh-token'),
              expiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
          );

      await deleteUser(db, target);

      final token = await (db.select(db.refreshTokens)
            ..where((t) => t.userId.equals(target.id)))
          .getSingle();
      expect(token.revokedAt, isNotNull);
    });

    test(
        'increments token_version, invalidating already-issued access '
        'tokens', () async {
      final target = await insertUser();

      await deleteUser(db, target);

      final row = await (db.select(db.users)
            ..where((t) => t.id.equals(target.id)))
          .getSingle();
      expect(row.tokenVersion, target.tokenVersion + 1);
    });

    test('removes the target\'s direct role assignments', () async {
      final target = await insertUser();
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      // A second owner so the sole-owner guard doesn't refuse first.
      final other = await insertUser(username: 'other-owner');
      for (final ownerId in [target.id, other.id]) {
        await db.into(db.roleAssignments).insert(
              RoleAssignmentsCompanion.insert(
                subjectType: 'user',
                subjectId: ownerId,
                role: 'owner',
                scopeType: 'group',
                scopeId: Value(groupId),
              ),
            );
      }

      await deleteUser(db, target);

      final remaining = await (db.select(db.roleAssignments)
            ..where(
              (t) =>
                  t.subjectType.equals('user') & t.subjectId.equals(target.id),
            ))
          .get();
      expect(remaining, isEmpty);
      expect(
        await (db.select(db.roleAssignments)
              ..where(
                (t) =>
                    t.subjectType.equals('user') & t.subjectId.equals(other.id),
              ))
            .get(),
        hasLength(1),
        reason: 'the other owner is untouched',
      );
    });

    test('removes the target from every team', () async {
      final target = await insertUser();
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      final teamId = await db.into(db.teams).insert(
            TeamsCompanion.insert(groupId: groupId, name: 't'),
          );
      await db.into(db.teamMembers).insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: target.id),
          );

      await deleteUser(db, target);

      expect(
        await (db.select(db.teamMembers)
              ..where((t) => t.userId.equals(target.id)))
            .get(),
        isEmpty,
      );
    });
  });
}
