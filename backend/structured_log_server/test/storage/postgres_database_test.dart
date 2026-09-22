@Tags(['postgres'])
library;

import 'dart:io';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

/// Connection settings for a real PostgreSQL instance to test against —
/// `STRUCTURED_LOG_TEST_POSTGRES_*`, defaulting to a plain local server
/// (`docker run -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres`).
/// Password has no default — there's no safe one to guess.
String _env(String suffix, String fallback) =>
    Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_$suffix'] ?? fallback;

final _host = _env('HOST', 'localhost');
final _port = int.parse(_env('PORT', '5432'));
final _database = _env('DATABASE', 'postgres');
final _username = _env('USERNAME', 'postgres');
final _password = Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_PASSWORD'];

void main() {
  // Fails loudly with what's missing rather than a bare connection-refused,
  // for whoever runs `dart test --tags postgres` without having read
  // dart_test.yaml's description of the tag first.
  setUpAll(() {
    if (_password == null) {
      throw StateError(
        'STRUCTURED_LOG_TEST_POSTGRES_PASSWORD must be set to run tests '
        'tagged postgres (see dart_test.yaml).',
      );
    }
  });

  StructuredLogDatabase open() => StructuredLogDatabase.openPostgres(
    host: _host,
    port: _port,
    database: _database,
    username: _username,
    password: _password!,
    sslMode: 'disable',
  );

  test('opens, runs a statement, and closes cleanly', () async {
    final db = open();
    addTearDown(() async {
      try {
        await db.close();
      } catch (_) {
        // Already closed by the test itself below — fine.
      }
    });

    await db.customStatement('SELECT 1');
    await db.close();
  });

  test(
    'close() closes the underlying pool, not just drift\'s own wrapper — '
    'regression for a real hang found running the server end to end',
    () async {
      // The bug this pins: `PgDatabase.opened(pool)` does not close `pool`
      // when drift's `close()` runs — only `StructuredLogDatabase.close()`'s
      // override (`database.dart`) closing `_ownedPool` explicitly does.
      // Without it, `close()` returns, but the pool's connections stay open
      // and the process never exits (found running the real server against
      // a real Postgres and sending it SIGTERM — not caught by any test
      // that only checks `close()` completes, since drift's own wrapper
      // always reports closed regardless of the pool underneath it).
      //
      // Built with the public constructor directly, keeping a reference to
      // the raw `pool` alongside it — the same one the `openPostgres`
      // factory would build and hand to `PgDatabase.opened`, but visible
      // here so the test can check *it*, not drift's opinion of it.
      final endpoint = pg.Endpoint(
        host: _host,
        port: _port,
        database: _database,
        username: _username,
        password: _password!,
      );
      final pool = pg.Pool.withEndpoints([
        endpoint,
      ], settings: const pg.PoolSettings(sslMode: pg.SslMode.disable));
      final db = StructuredLogDatabase(
        PgDatabase.opened(pool),
        ownedPool: pool,
      );

      await db.customStatement('SELECT 1');
      await db.close();

      // The raw pool, not drift's wrapper — proves the pool itself, not
      // just drift's opinion of it, is actually closed.
      await expectLater(pool.execute('SELECT 1'), throwsA(anything));
    },
  );
}
