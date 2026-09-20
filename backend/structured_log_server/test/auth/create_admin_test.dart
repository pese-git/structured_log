import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/create_admin.dart';
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

  test('creates an administrator on an empty database', () async {
    final outcome =
        await createAdmin(db, username: 'root', password: 's3cret-pass');
    expect(outcome.success, isTrue);

    final user = await db.select(db.users).getSingle();
    expect(user.username, 'root');
    expect(user.isPrimaryAdmin, isTrue);
    expect(verifyPassword('s3cret-pass', user.passwordHash), isTrue);

    final roles = await db.select(db.roleAssignments).get();
    expect(roles.single.role, 'admin');
  });

  test('an operator-supplied password does not require change', () async {
    final outcome =
        await createAdmin(db, username: 'root', password: 's3cret-pass');
    expect(outcome.success, isTrue);
    expect(outcome.generatedPassword, isNull);

    final user = await db.select(db.users).getSingle();
    expect(user.mustChangePassword, isFalse);
  });

  test('an unset password is generated and requires a change', () async {
    final outcome = await createAdmin(db, username: 'root');
    expect(outcome.success, isTrue);
    expect(outcome.generatedPassword, isNotNull);

    final user = await db.select(db.users).getSingle();
    expect(user.mustChangePassword, isTrue);
    expect(
        verifyPassword(outcome.generatedPassword!, user.passwordHash), isTrue);
  });

  test('fails when an active admin already exists', () async {
    await createAdmin(db, username: 'first', password: 'password-a');
    final outcome =
        await createAdmin(db, username: 'second', password: 'password-b');
    expect(outcome.success, isFalse);
    expect(outcome.error, isNotNull);

    final users = await db.select(db.users).get();
    expect(users, hasLength(1));
  });

  test('succeeds again once the sole admin is deactivated', () async {
    final first =
        await createAdmin(db, username: 'first', password: 'password-a');
    expect(first.success, isTrue);

    final firstUser = await db.select(db.users).getSingle();
    await (db.update(db.users)..where((t) => t.id.equals(firstUser.id))).write(
      const UsersCompanion(isActive: Value(false)),
    );

    final second =
        await createAdmin(db, username: 'second', password: 'password-b');
    expect(second.success, isTrue);
  });

  test('a second created admin does not become is_primary_admin', () async {
    final firstOutcome =
        await createAdmin(db, username: 'first', password: 'password-a');
    expect(firstOutcome.success, isTrue);
    final firstUser = await db.select(db.users).getSingle();
    await (db.update(db.users)..where((t) => t.id.equals(firstUser.id))).write(
      const UsersCompanion(isActive: Value(false)),
    );

    await createAdmin(db, username: 'second', password: 'password-b');

    final second = await (db.select(
      db.users,
    )..where((t) => t.username.equals('second')))
        .getSingle();
    expect(second.isPrimaryAdmin, isFalse);
  });

  test('a password outside the policy is refused and nothing is written',
      () async {
    for (final (password, expected) in [
      ('short', 'at least 8 characters'),
      ('x' * 73, 'at most 72 bytes'),
    ]) {
      final outcome =
          await createAdmin(db, username: 'root', password: password);
      expect(outcome.success, isFalse);
      expect(outcome.error, contains(expected));
      // The message says what is wrong, never what was typed.
      expect(outcome.error, isNot(contains(password)));
    }
    expect(await db.select(db.users).get(), isEmpty);
  });
}
