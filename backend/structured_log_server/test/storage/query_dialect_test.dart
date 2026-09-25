import 'package:drift/drift.dart';
import 'package:structured_log_server/src/storage/audit_query.dart';
import 'package:structured_log_server/src/storage/query.dart';
import 'package:test/test.dart';

/// `add-postgres-backend` design.md decision 3a: `buildLogQuerySql`/
/// `buildAuditQuerySql` assemble raw SQL with `?` placeholders — the only
/// way to express `LIKE`/`json_extract` conditions drift's typed
/// query-builder can't (`design.md` decision 3 in `add-structured-log-server`)
/// — and `?` is not translated for PostgreSQL by drift itself (only
/// generated code goes through that translation). `placeholdersForDialect`
/// is the one place that rewrites it, so these tests exercise it directly
/// rather than through a live Postgres connection (verified separately,
/// against a real instance, during implementation — see `design.md`).
void main() {
  group('placeholdersForDialect', () {
    test('leaves SQLite text unchanged, byte for byte', () {
      const sql =
          'SELECT * FROM log_entries WHERE project_id IN (?, ?) '
          'AND level = ? LIMIT ?';
      expect(
        placeholdersForDialect(sql, SqlDialect.sqlite, boundVariables: 4),
        sql,
      );
    });

    test('numbers every ? sequentially for Postgres', () {
      const sql =
          'SELECT * FROM log_entries WHERE project_id IN (?, ?) '
          'AND level = ? LIMIT ?';
      expect(
        placeholdersForDialect(sql, SqlDialect.postgres, boundVariables: 4),
        'SELECT * FROM log_entries WHERE project_id IN (\$1, \$2) '
        'AND level = \$3 LIMIT \$4',
      );
    });

    test('a ? the caller did not bind is refused, on every dialect', () {
      // The whole pass rests on one unwritten rule: every `?` in these
      // fragments is a bind parameter. A `?` inside a string literal would
      // be renumbered into `$1` on PostgreSQL and change what the query
      // asks, while SQLite went on working — which is the shape of failure
      // that shipped twice already (#59, #64). Counting is what turns it
      // into a visible error, and it runs for SQLite too *because* that is
      // where the tests run: a mistake must not wait for a Postgres-tagged
      // case that nobody wrote.
      for (final dialect in SqlDialect.values) {
        expect(
          () => placeholdersForDialect(
            "SELECT * FROM log_entries WHERE event LIKE '%?%'",
            dialect,
            boundVariables: 0,
          ),
          throwsA(isA<StateError>()),
          reason: '$dialect',
        );
      }
    });

    test('a bound variable with no ? to sit in is refused too', () {
      for (final dialect in SqlDialect.values) {
        expect(
          () => placeholdersForDialect(
            'SELECT * FROM log_entries WHERE level = ?',
            dialect,
            boundVariables: 2,
          ),
          throwsA(isA<StateError>()),
          reason: '$dialect',
        );
      }
    });

    test('the refusal says what it counted', () {
      expect(
        () => placeholdersForDialect(
          "SELECT '?' , ?",
          SqlDialect.postgres,
          boundVariables: 1,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('2'), contains('1')),
          ),
        ),
      );
    });

    test('a fragment with no placeholder at all is unaffected', () {
      const sql = 'SELECT * FROM log_entries WHERE 1 = 1';
      expect(
        placeholdersForDialect(sql, SqlDialect.postgres, boundVariables: 0),
        sql,
      );
    });
  });

  group('buildLogQuerySql dialect handling', () {
    test('SQLite keeps ? placeholders, same variables as always', () {
      final built = buildLogQuerySql(
        LogQuery(
          projectIds: [1, 2],
          filter: LogFilter(minLevel: 'warning'),
          limit: 10,
        ),
        dialect: SqlDialect.sqlite,
      );
      expect(built.sql, contains('project_id IN (?, ?)'));
      expect(built.sql, isNot(contains(r'$')));
    });

    test('Postgres numbers placeholders across every condition, in order', () {
      final built = buildLogQuerySql(
        LogQuery(
          projectIds: [1, 2],
          filter: LogFilter(minLevel: 'warning'),
          limit: 10,
        ),
        dialect: SqlDialect.postgres,
      );
      // Two projectIds ($1, $2), three levels at-or-above 'warning'
      // (warning, error, critical — $3, $4, $5), then LIMIT ($6).
      expect(
        built.sql,
        'SELECT * FROM log_entries '
        r'WHERE project_id IN ($1, $2) AND level IN ($3, $4, $5) '
        'ORDER BY id DESC '
        r'LIMIT $6',
      );
      expect(built.variables, hasLength(6));
      // Same variables as the SQLite build, in the same order — only the
      // placeholder text in `sql` differs by dialect.
      final sqliteBuilt = buildLogQuerySql(
        LogQuery(
          projectIds: [1, 2],
          filter: LogFilter(minLevel: 'warning'),
          limit: 10,
        ),
        dialect: SqlDialect.sqlite,
      );
      expect(
        built.variables.map((v) => v.value),
        sqliteBuilt.variables.map((v) => v.value),
      );
    });
  });

  group('buildAuditQuerySql dialect handling', () {
    test('Postgres numbers placeholders, same variables as SQLite', () {
      const query = AuditQuery(actorUserId: 7, limit: 20);
      final pg = buildAuditQuerySql(query, dialect: SqlDialect.postgres);
      final sqlite = buildAuditQuerySql(query, dialect: SqlDialect.sqlite);

      expect(
        pg.sql,
        'SELECT * FROM audit_log_entries '
        r'WHERE 1 = 1 AND actor_user_id = $1 '
        'ORDER BY id DESC '
        r'LIMIT $2',
      );
      expect(sqlite.sql, isNot(contains(r'$')));
      expect(
        pg.variables.map((v) => v.value),
        sqlite.variables.map((v) => v.value),
      );
    });
  });
}
