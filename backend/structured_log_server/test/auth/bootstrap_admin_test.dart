import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/bootstrap_admin.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

ServerConfig baseConfig({
  bool bootstrapAdminEnabled = true,
  String bootstrapAdminUsername = 'admin',
  String? bootstrapAdminPassword,
}) {
  return ServerConfig(
    dbPath: ':memory:',
    httpHost: '0.0.0.0',
    httpPort: 8080,
    jwtSecret: 'secret',
    jwtIssuer: 'test',
    maxIngestBodyBytes: 1024,
    retentionPurgeIntervalSeconds: 3600,
    bootstrapAdminEnabled: bootstrapAdminEnabled,
    bootstrapAdminUsername: bootstrapAdminUsername,
    bootstrapAdminPassword: bootstrapAdminPassword,
    logLevel: 'info',
    logFile: null,
    logFormat: 'console',
    logMaxFileBytes: 1024,
    logMaxFiles: 1,
    rateLimitEnabled: true,
    rateLimitBucketCapacity: 10,
    rateLimitRefillPerMinute: 10,
    rateLimitMaxKeys: 100,
    trustedProxyHops: 0,
    sseHeartbeatIntervalSeconds: 25,
    // No ceiling, so these fixtures behave exactly as
    // they did before live subscriptions had one.
    maxLiveSubscriptionsPerUser: 0,
    maxLiveSubscriptions: 0,
  );
}

void main() {
  late StructuredLogDatabase db;
  late List<String> warnings;

  setUp(() {
    db = openInMemory();
    warnings = [];
  });
  tearDown(() => db.close());

  test(
    'an empty database gets an administrator with both flags and no email',
    () async {
      final outcome = await bootstrapAdmin(
        db,
        baseConfig(bootstrapAdminPassword: 's3cret'),
        logWarning: warnings.add,
      );
      expect(outcome.created, isTrue);

      final user = await db.select(db.users).getSingle();
      expect(user.username, 'admin');
      expect(user.isPrimaryAdmin, isTrue);
      expect(user.mustChangePassword, isTrue);
      expect(user.email, isNull);
      expect(verifyPassword('s3cret', user.passwordHash), isTrue);

      final roles = await db.select(db.roleAssignments).get();
      expect(roles, hasLength(1));
      expect(roles.single.role, 'admin');
      expect(roles.single.scopeType, 'global');
    },
  );

  test('a non-empty database is left untouched', () async {
    await db
        .into(db.users)
        .insert(UsersCompanion.insert(username: 'existing', passwordHash: 'h'));

    final outcome = await bootstrapAdmin(
      db,
      baseConfig(bootstrapAdminPassword: 's3cret'),
      logWarning: warnings.add,
    );
    expect(outcome.created, isFalse);

    final users = await db.select(db.users).get();
    expect(users, hasLength(1));
    expect(users.single.username, 'existing');
  });

  test(
    'explicit parameters on a non-empty database produce a warning',
    () async {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(username: 'existing', passwordHash: 'h'),
          );

      await bootstrapAdmin(
        db,
        baseConfig(bootstrapAdminPassword: 's3cret'),
        logWarning: warnings.add,
      );
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('not applied'));
    },
  );

  test('a non-empty database with default parameters logs nothing', () async {
    await db
        .into(db.users)
        .insert(UsersCompanion.insert(username: 'existing', passwordHash: 'h'));

    await bootstrapAdmin(db, baseConfig(), logWarning: warnings.add);
    expect(warnings, isEmpty);
  });

  test(
    'the switch disables creation, with a warning on an empty database',
    () async {
      final outcome = await bootstrapAdmin(
        db,
        baseConfig(bootstrapAdminEnabled: false),
        logWarning: warnings.add,
      );
      expect(outcome.created, isFalse);
      expect(await db.select(db.users).get(), isEmpty);
      expect(warnings.single, contains('create-admin'));
    },
  );

  test('a disabled switch on a non-empty database logs nothing', () async {
    await db
        .into(db.users)
        .insert(UsersCompanion.insert(username: 'existing', passwordHash: 'h'));
    await bootstrapAdmin(
      db,
      baseConfig(bootstrapAdminEnabled: false),
      logWarning: warnings.add,
    );
    expect(warnings, isEmpty);
  });

  test('an unset password is generated and reported exactly once', () async {
    final outcome = await bootstrapAdmin(
      db,
      baseConfig(),
      logWarning: warnings.add,
    );
    expect(outcome.created, isTrue);
    expect(outcome.generatedPassword, isNotNull);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains(outcome.generatedPassword!));
    expect(warnings.single, contains('temporary'));

    final user = await db.select(db.users).getSingle();
    expect(
      verifyPassword(outcome.generatedPassword!, user.passwordHash),
      isTrue,
    );
  });

  test('a password supplied via config is not logged', () async {
    final outcome = await bootstrapAdmin(
      db,
      baseConfig(bootstrapAdminPassword: 'my-explicit-secret'),
      logWarning: warnings.add,
    );
    expect(outcome.generatedPassword, isNull);
    expect(warnings, isEmpty);
  });

  test('a custom username is honored', () async {
    await bootstrapAdmin(
      db,
      baseConfig(bootstrapAdminUsername: 'root', bootstrapAdminPassword: 'x'),
      logWarning: warnings.add,
    );
    final user = await db.select(db.users).getSingle();
    expect(user.username, 'root');
  });
}
