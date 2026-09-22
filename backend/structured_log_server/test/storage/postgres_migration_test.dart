@Tags(['postgres'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

/// `add-postgres-backend` design.md decisions 4/7 — mirrors the
/// dialect-sensitive groups of `test/storage/database_test.dart` (schema
/// creation, the version-1-to-2 index upgrade, the newer-schema refusal)
/// against a real Postgres instance. Everything else in that file (unique
/// constraints, cascading, round-tripping) is plain SQL behavior already
/// exercised the same way regardless of backend — not duplicated here.
///
/// Connection settings: `STRUCTURED_LOG_TEST_POSTGRES_*`, same convention as
/// the other Postgres-tagged storage tests.
String _env(String suffix, String fallback) =>
    Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_$suffix'] ?? fallback;

final _host = _env('HOST', 'localhost');
final _port = int.parse(_env('PORT', '5432'));
final _database = _env('DATABASE', 'postgres');
final _username = _env('USERNAME', 'postgres');
final _password = Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_PASSWORD'];

const _wantedIndexes = [
  'idx_project_secret_keys_key_hash',
  'idx_refresh_tokens_token_hash',
  'idx_refresh_tokens_expires_at',
];

StructuredLogDatabase _open() => StructuredLogDatabase.openPostgres(
  host: _host,
  port: _port,
  database: _database,
  username: _username,
  password: _password!,
  sslMode: 'disable',
);

/// Drops and recreates the `public` schema on a plain `package:postgres`
/// connection, bypassing drift entirely — going through
/// `StructuredLogDatabase.openPostgres` for this would trigger its own
/// migration (`onCreate`/`beforeOpen`) before the drop even ran, which is
/// exactly the state these tests need to control themselves.
Future<void> _resetSchema() async {
  final endpoint = pg.Endpoint(
    host: _host,
    port: _port,
    database: _database,
    username: _username,
    password: _password!,
  );
  final conn = await pg.Connection.open(
    endpoint,
    settings: const pg.ConnectionSettings(sslMode: pg.SslMode.disable),
  );
  await conn.execute('DROP SCHEMA IF EXISTS public CASCADE');
  await conn.execute('CREATE SCHEMA public');
  await conn.close();
}

Future<Set<String>> _indexNames(StructuredLogDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'",
      )
      .get();
  return rows.map((r) => r.read<String>('indexname')).toSet();
}

void main() {
  setUpAll(() {
    if (_password == null) {
      throw StateError(
        'STRUCTURED_LOG_TEST_POSTGRES_PASSWORD must be set to run tests '
        'tagged postgres (see dart_test.yaml).',
      );
    }
  });

  setUp(_resetSchema);

  test('a new database has the credential hash indexes', () async {
    final db = _open();
    addTearDown(db.close);
    // Any statement is enough to force drift to open the connection and run
    // its migration (`onCreate`) against the just-emptied schema.
    await db.customStatement('SELECT 1');
    expect(await _indexNames(db), containsAll(_wantedIndexes));
  });

  test(
    'a version 1 database gains them on open (the onUpgrade path)',
    () async {
      final fresh = _open();
      await fresh.customStatement('SELECT 1'); // creates at the current version
      for (final name in _wantedIndexes) {
        await fresh.customStatement('DROP INDEX $name');
      }
      await fresh.customStatement('UPDATE __schema SET version = 1');
      await fresh.close();

      final upgraded = _open();
      addTearDown(upgraded.close);
      await upgraded.customStatement('SELECT 1'); // triggers onUpgrade(1, 2)
      expect(await _indexNames(upgraded), containsAll(_wantedIndexes));
    },
  );

  test('refuses a database written by a newer schema', () async {
    final current = _open();
    final newer = current.schemaVersion + 1;
    await current.customStatement('SELECT 1'); // creates at the current version
    await current.customStatement('UPDATE __schema SET version = $newer');
    await current.close();

    final old = _open();
    addTearDown(old.close);
    await expectLater(
      old.select(old.users).get(),
      throwsA(
        predicate(
          (e) =>
              '$e'.contains('schema version $newer') && '$e'.contains('newer'),
          'names the database version and says it is newer',
        ),
      ),
    );
  });

  test('opens a database at the current version', () async {
    await _open().close(); // creates it
    final again = _open();
    addTearDown(again.close);
    expect(await again.select(again.users).get(), isEmpty);
  });
}
