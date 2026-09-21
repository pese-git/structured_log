import 'package:cherrypick/cherrypick.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/process_resources.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/logging/setup.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

// Its own file, because closing what a process owns closes the hash worker pool
// — a global of the isolate — and no test after this one may need it.

ServerConfig _config() => ServerConfig(
  dbPath: ':memory:',
  httpHost: 'localhost',
  httpPort: 0,
  jwtSecret: 'test-secret',
  jwtIssuer: 'test',
  maxIngestBodyBytes: 1024,
  retentionPurgeIntervalSeconds: 3600,
  bootstrapAdminEnabled: false,
  bootstrapAdminUsername: 'root',
  bootstrapAdminPassword: null,
  logLevel: 'info',
  logFile: null,
  logFormat: 'json',
  logMaxFileBytes: 1024,
  logMaxFiles: 1,
  rateLimitEnabled: false,
  rateLimitBucketCapacity: 10,
  rateLimitRefillPerMinute: 60,
  rateLimitMaxKeys: 1000,
  trustedProxyHops: 0,
  sseHeartbeatIntervalSeconds: 30,
);

/// Drift reopens a closed database on the next query, so "closed" is not
/// something a query can show; the executor is told, and remembers it.
class _CloseSpy extends QueryInterceptor {
  var closed = false;

  @override
  Future<void> close(QueryExecutor inner) {
    closed = true;
    return super.close(inner);
  }
}

void main() {
  tearDown(CherryPick.closeRootScope);

  test(
    'a scope built with process resources closes what the process owns',
    () async {
      final spy = _CloseSpy();
      final db = StructuredLogDatabase(
        NativeDatabase.memory().interceptWith(spy),
      );
      final root = CherryPick.openScope(scopeName: serverScopeName);
      openServerScope(
        db,
        signingSecret: 'secret',
        issuer: 'test',
        into: root,
        process: ProcessResources(logging: configureServerLogging(_config())),
      );
      expect(await db.customSelect('SELECT 1 AS one').get(), hasLength(1));
      expect(await hashPasswordAsync('a password'), isNotEmpty);

      await CherryPick.closeScope(scopeName: serverScopeName);

      expect(spy.closed, isTrue, reason: 'the database went down with it');
      await expectLater(
        hashPasswordAsync('another password'),
        throwsA(isA<StateError>()),
        reason: 'the hash workers went down with the scope',
      );
    },
  );

  test(
    'without them the scope leaves the database and the workers alone',
    () async {
      final spy = _CloseSpy();
      final db = StructuredLogDatabase(
        NativeDatabase.memory().interceptWith(spy),
      );
      addTearDown(db.close);
      final root = CherryPick.openScope(scopeName: serverScopeName);
      openServerScope(db, signingSecret: 'secret', issuer: 'test', into: root);

      await CherryPick.closeScope(scopeName: serverScopeName);

      expect(spy.closed, isFalse);
      expect(await db.customSelect('SELECT 1 AS one').get(), hasLength(1));
    },
  );
}
