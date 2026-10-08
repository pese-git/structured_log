import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_drift/structured_log_drift.dart';
import 'package:test/test.dart';

/// Collects every entry the sinks receive, at whatever level.
List<Map<String, dynamic>> captureEntries() {
  final entries = <Map<String, dynamic>>[];
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => entries.add(Map.of(entry)),
        minLevel: LogLevel.trace,
      ),
    ],
  );
  return entries;
}

List<String> eventsOf(List<Map<String, dynamic>> entries) =>
    [for (final entry in entries) entry['event'] as String];

/// Runs [body] in a zone that records uncaught errors, and returns them
/// once [body] has finished.
Future<List<Object>> uncaughtErrorsOf(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    await body();
    done.complete();
  }, (error, _) => errors.add(error));
  await done.future;
  return errors;
}

/// A database without generated tables: the interceptor only ever sees SQL
/// text, so custom statements exercise it as fully as generated code does.
class TestDatabase extends GeneratedDatabase {
  TestDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

/// An executor whose every query fails with [error] — for what a driver
/// other than sqlite3 might put in its message.
class FailingExecutor implements QueryExecutor {
  FailingExecutor(this.error);

  final Object error;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) =>
      Future.error(error);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An executor whose every delete succeeds, removing [count] rows.
class DeletingExecutor implements QueryExecutor {
  DeletingExecutor(this.count);

  final int count;

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      Future.value(count);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<Map<String, dynamic>> entries;
  final databases = <TestDatabase>[];

  /// A fresh in-memory database behind [interceptor], with a table `t`
  /// created before the interceptor's entries are collected.
  Future<TestDatabase> open([
    StructuredLogDriftInterceptor? interceptor,
  ]) async {
    final db = TestDatabase(
      NativeDatabase.memory().interceptWith(
        interceptor ?? StructuredLogDriftInterceptor(),
      ),
    );
    databases.add(db);
    await db.customStatement(
      'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)',
    );
    entries.clear();
    return db;
  }

  setUp(() => entries = captureEntries());

  tearDown(() async {
    for (final db in databases) {
      await db.close();
    }
    databases.clear();
    StructlogConfiguration.reset();
  });

  group('db_query', () {
    test('a select carries its kind, statement, rows and duration', () async {
      final db = await open();
      await db
          .customStatement("INSERT INTO t (name) VALUES ('a'), ('b'), ('c')");
      entries.clear();

      await db.customSelect('SELECT * FROM t').get();

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry, containsPair('event', 'db_query'));
      expect(entry, containsPair('kind', 'select'));
      expect(entry, containsPair('statement', 'SELECT * FROM t'));
      expect(entry, containsPair('rows', 3));
      expect(entry, containsPair('category', 'db'));
      expect(entry, containsPair('logger', 'drift'));
      expect(entry, containsPair('level', 'debug'));
      expect(entry['duration_ms'], isA<double>());
      expect(entry.keys, isNot(contains('slow')));
    });

    test('an update carries the rows it changed', () async {
      final db = await open();
      await db.customStatement("INSERT INTO t (name) VALUES ('a'), ('b')");
      entries.clear();

      await db.customUpdate(
        'UPDATE t SET name = ?',
        variables: [Variable('z')],
        updates: const {},
      );

      expect(entries.single, containsPair('kind', 'update'));
      expect(entries.single, containsPair('affected_rows', 2));
    });

    // drift runs customUpdate through runUpdate whatever its updateKind;
    // only the generated delete(table) reaches runDelete, so it is called
    // directly here.
    test('a delete carries the rows it removed', () async {
      final interceptor = StructuredLogDriftInterceptor();

      final removed = await interceptor.runDelete(
        DeletingExecutor(2),
        'DELETE FROM t WHERE name = ?',
        const ['a'],
      );

      expect(removed, 2);
      expect(entries.single, containsPair('kind', 'delete'));
      expect(entries.single, containsPair('affected_rows', 2));
    });

    test('an insert carries the id of the row it added', () async {
      final db = await open();

      await db.customInsert(
        'INSERT INTO t (id, name) VALUES (7, ?)',
        variables: [Variable('a')],
      );

      expect(entries.single, containsPair('kind', 'insert'));
      expect(entries.single, containsPair('insert_id', 7));
    });

    test('a long statement is cut short', () async {
      final db = await open();
      final statement = 'SELECT 1 ${'-' * 3000}';

      await db.customSelect(statement).get();

      final written = entries.single['statement'] as String;
      expect(written, hasLength(defaultStatementMaxLength + 1));
      expect(written, endsWith('…'));
    });
  });

  group('arguments', () {
    test('are not written by default', () async {
      final db = await open();

      await db.customSelect(
        'SELECT * FROM t WHERE name = ?',
        variables: [Variable('secret-token')],
      ).get();

      expect(entries.single.keys, isNot(contains('arguments')));
      expect(jsonEncode(entries), isNot(contains('secret-token')));
    });

    test('are written when asked for, blobs by their size', () async {
      final db = await open(StructuredLogDriftInterceptor(logArguments: true));

      await db.customSelect(
        'SELECT ?, ?, ?',
        variables: [
          Variable('a'),
          Variable(Uint8List(16)),
          Variable('x' * 1500),
        ],
      ).get();

      final arguments = entries.single['arguments'] as List;
      expect(arguments[0], 'a');
      expect(arguments[1], '<16 bytes>');
      expect(arguments[2], hasLength(defaultArgumentMaxLength + 1));
    });

    test('are scrubbed from the text of a sqlite3 error', () async {
      final db = await open();

      await expectLater(
        db.customSelect(
          'SELECT * FROM missing WHERE name = ?',
          variables: [Variable('secret-token')],
        ).get(),
        throwsA(isA<SqliteException>()),
      );

      final failed = entries.single;
      expect(failed, containsPair('event', 'db_query_failed'));
      expect(failed, containsPair('error_type', 'SqliteException'));
      expect(failed['error'], contains('no such table'));
      expect(jsonEncode(entries), isNot(contains('secret-token')));
    });

    // A real failing statement rather than a constructed SqliteException:
    // its constructor changed between sqlite3 2.x and 3.x, and what this
    // test guards is the message of whichever version is installed.
    test('a parameter list is hidden even when no argument names it', () async {
      final db = await open();
      await db.customStatement('CREATE UNIQUE INDEX t_name ON t (name)');
      await db.customInsert(
        'INSERT INTO t (name) VALUES (?)',
        variables: [Variable('abc')],
      );
      entries.clear();

      Object? caught;
      try {
        await db.customInsert(
          'INSERT INTO t (name) VALUES (?)',
          variables: [Variable('abc')],
        );
      } catch (error) {
        caught = error;
      }

      // The driver itself quotes the argument; a three-character one is
      // below the scrubbing length, so only the parameter list can hide it.
      expect(caught, isA<SqliteException>());
      expect(caught.toString(), contains('parameters: abc'));
      final failed = entries.single;
      expect(failed['error'], contains('UNIQUE constraint failed'));
      expect(failed['error'], endsWith('parameters: <hidden>'));
      expect(failed['error'], isNot(contains('abc')));
    });

    test('are scrubbed from any driver message that quotes them', () async {
      final error = StateError('duplicate key value (email)=(alice@x.io)');
      final interceptor = StructuredLogDriftInterceptor();

      await expectLater(
        interceptor.runSelect(
          FailingExecutor(error),
          'SELECT 1',
          const ['alice@x.io', 'ok'],
        ),
        throwsA(same(error)),
      );

      expect(
        entries.single['error'],
        'Bad state: duplicate key value (email)=(<argument>)',
      );
    });

    test('an error whose toString throws is written by its type', () async {
      final error = _UnprintableError();

      await expectLater(
        StructuredLogDriftInterceptor().runSelect(
          FailingExecutor(error),
          'SELECT 1',
          const [],
        ),
        throwsA(same(error)),
      );

      expect(entries.single['error'], '<_UnprintableError>');
      expect(entries.single, containsPair('error_type', '_UnprintableError'));
    });

    test('go to the core untouched when they are written anyway', () async {
      final error = StateError('value secret-token');
      final interceptor = StructuredLogDriftInterceptor(logArguments: true);

      await expectLater(
        interceptor.runSelect(
          FailingExecutor(error),
          'SELECT ?',
          const ['secret-token'],
        ),
        throwsA(same(error)),
      );

      expect(entries.single['error'], 'Bad state: value secret-token');
      expect(entries.single, containsPair('error_type', 'StateError'));
    });
  });

  group('slow queries', () {
    test('at or above the threshold are a warning marked slow', () async {
      final db = await open(
        StructuredLogDriftInterceptor(slowQueryThreshold: Duration.zero),
      );

      await db.customSelect('SELECT 1').get();

      expect(entries.single, containsPair('level', 'warning'));
      expect(entries.single, containsPair('slow', true));
    });

    test('are never marked with no threshold', () async {
      final db = await open(
        StructuredLogDriftInterceptor(slowQueryThreshold: null),
      );

      await db.customSelect('SELECT 1').get();

      expect(entries.single, containsPair('level', 'debug'));
      expect(entries.single.keys, isNot(contains('slow')));
    });

    test('a slow batch is marked too', () async {
      final db = await open(
        StructuredLogDriftInterceptor(slowQueryThreshold: Duration.zero),
      );

      await db.batch((batch) {
        batch.customStatement('INSERT INTO t (name) VALUES (?)', ['a']);
      });

      final batch = entries.firstWhere((e) => e['event'] == 'db_batch');
      expect(batch, containsPair('level', 'warning'));
      expect(batch, containsPair('slow', true));
    });
  });

  group('db_batch', () {
    test('one entry for the whole batch, none per statement', () async {
      final db = await open();

      await db.batch((batch) {
        batch.customStatement('INSERT INTO t (name) VALUES (?)', ['a']);
        batch.customStatement('INSERT INTO t (name) VALUES (?)', ['b']);
      });

      expect(eventsOf(entries), ['db_batch', 'db_transaction_committed']);
      final batch = entries.first;
      expect(batch, containsPair('statement_count', 1));
      expect(batch, containsPair('execution_count', 2));
      expect(batch['duration_ms'], isA<double>());
      expect(batch.keys, isNot(contains('arguments')));
    });

    test('a failing batch is written and still throws', () async {
      final db = await open();

      await expectLater(
        db.batch((batch) {
          batch.customStatement('INSERT INTO missing VALUES (?)', ['a']);
        }),
        throwsA(isA<SqliteException>()),
      );

      final failed = entries.firstWhere((e) => e['event'] == 'db_query_failed');
      expect(failed, containsPair('kind', 'batch'));
      expect(
          failed, containsPair('statement', 'INSERT INTO missing VALUES (?)'));
    });
  });

  group('failures', () {
    test('are written with the error and reach the caller as is', () async {
      final db = await open();
      Object? caught;

      try {
        await db.customStatement('INSERT INTO missing VALUES (1)');
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<SqliteException>());
      final failed = entries.single;
      expect(failed, containsPair('event', 'db_query_failed'));
      expect(failed, containsPair('kind', 'custom'));
      expect(failed, containsPair('level', 'error'));
      expect(failed, containsPair('error_type', 'SqliteException'));
      expect(failed['stack_trace'], isA<String>());
      expect(failed['error'], contains('no such table: missing'));
    });

    test('keep their stack trace through the interceptor', () async {
      final error = StateError('boom');
      final interceptor = StructuredLogDriftInterceptor();
      StackTrace? trace;

      try {
        await interceptor.runSelect(FailingExecutor(error), 'SELECT 1', []);
      } catch (_, stackTrace) {
        trace = stackTrace;
      }

      expect(trace.toString(), entries.single['stack_trace']);
    });
  });

  group('transactions', () {
    test('a rollback follows the failure that caused it', () async {
      final db = await open();

      await expectLater(
        db.transaction(() async {
          await db.customStatement('INSERT INTO missing VALUES (1)');
        }),
        throwsA(isA<SqliteException>()),
      );

      expect(
        eventsOf(entries),
        ['db_query_failed', 'db_transaction_rolled_back'],
      );
      expect(entries.last, containsPair('level', 'warning'));
      expect(entries.last['duration_ms'], isA<double>());
    });

    test('a nested transaction is timed on its own', () async {
      final db = await open();

      await db.transaction(() async {
        await db.transaction(() async {
          await db.customSelect('SELECT 1').get();
        });
        await db.customSelect('SELECT 2').get();
      });

      final commits = [
        for (final e in entries)
          if (e['event'] == 'db_transaction_committed') e,
      ];
      expect(commits, hasLength(2));
      expect(commits.first, containsPair('level', 'trace'));
      final inner = commits.first['duration_ms'] as double;
      final outer = commits.last['duration_ms'] as double;
      expect(inner, lessThanOrEqualTo(outer));
    });
  });

  group('levels', () {
    test('null turns a kind of entry off', () async {
      final db = await open(
        StructuredLogDriftInterceptor(
            levels: const DriftLogLevels(query: null)),
      );

      await db.customSelect('SELECT 1').get();
      await expectLater(
        db.customStatement('INSERT INTO missing VALUES (1)'),
        throwsA(isA<SqliteException>()),
      );

      expect(eventsOf(entries), ['db_query_failed']);
    });

    test('nothing is built for an entry no sink takes', () async {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'info',
            output: (entry, level) => entries.add(entry),
            minLevel: LogLevel.info,
          ),
        ],
      );
      final db = await open(
        StructuredLogDriftInterceptor(
          filter: (kind, statement) => true,
          logArguments: true,
        ),
      );

      await db.customSelect('SELECT ?', variables: [Variable('a')]).get();

      expect(entries, isEmpty);
    });
  });

  group('filter', () {
    test('leaves out the queries it rejects', () async {
      final db = await open(
        StructuredLogDriftInterceptor(
          filter: (kind, statement) => !statement.startsWith('PRAGMA'),
        ),
      );

      await db.customSelect('PRAGMA user_version').get();
      await db.customSelect('SELECT 1').get();

      expect(entries.single, containsPair('statement', 'SELECT 1'));
    });

    test('is told the kind of query', () async {
      final kinds = <String>[];
      final db = await open(
        StructuredLogDriftInterceptor(
          filter: (kind, statement) {
            kinds.add(kind);
            return true;
          },
        ),
      );

      kinds.clear(); // the CREATE TABLE of open()

      await db.customSelect('SELECT 1').get();
      await db.batch((batch) {
        batch.customStatement('INSERT INTO t (name) VALUES (?)', ['a']);
      });

      expect(kinds, ['select', 'batch']);
    });

    test('a throwing filter costs the entry, not the query', () async {
      late List<QueryRow> rows;
      final errors = await uncaughtErrorsOf(() async {
        final db = await open(
          StructuredLogDriftInterceptor(
            filter: (kind, statement) => throw StateError('filter'),
          ),
        );
        rows = await db.customSelect('SELECT 1 AS one').get();
      });

      expect(errors, isEmpty);
      expect(rows.single.read<int>('one'), 1);
      expect(entries, isEmpty);
    });

    test('a rejected failure is not written but still throws', () async {
      final db = await open(
        StructuredLogDriftInterceptor(filter: (kind, statement) => false),
      );

      await expectLater(
        db.customStatement('INSERT INTO missing VALUES (1)'),
        throwsA(isA<SqliteException>()),
      );

      expect(entries, isEmpty);
    });
  });

  group('never changes the query', () {
    test('a failing sink does not reach the caller', () async {
      final db = await open();
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'broken',
            output: (_, __) => throw StateError('sink'),
            minLevel: LogLevel.trace,
          ),
        ],
      );

      final rows = await db.customSelect('SELECT 1 AS one').get();

      expect(rows.single.read<int>('one'), 1);
    });

    test('a throwing logger does not reach the caller either', () async {
      final db = await open(
        StructuredLogDriftInterceptor(logger: _ThrowingLogger()),
      );

      final rows = await db.customSelect('SELECT 1 AS one').get();
      await db.transaction(() async {});

      expect(rows.single.read<int>('one'), 1);
    });
  });

  group('configuration', () {
    test('a later configure reaches the interceptor', () async {
      final db = await open();
      final later = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'later',
            output: (entry, level) => later.add(entry),
            minLevel: LogLevel.trace,
          ),
        ],
      );

      await db.customSelect('SELECT 1').get();

      expect(entries, isEmpty);
      expect(eventsOf(later), ['db_query']);
    });

    test('a given logger and category replace the defaults', () async {
      final db = await open(
        StructuredLogDriftInterceptor(
          logger: getLogger('store').bind({'db': 'main'}),
          category: 'storage',
        ),
      );

      await db.customSelect('SELECT 1').get();

      expect(entries.single, containsPair('logger', 'store'));
      expect(entries.single, containsPair('db', 'main'));
      expect(entries.single, containsPair('category', 'storage'));
    });

    test('a null category writes none', () async {
      final db = await open(StructuredLogDriftInterceptor(category: null));

      await db.customSelect('SELECT 1').get();

      expect(entries.single.keys, isNot(contains('category')));
    });
  });
}

/// A logger whose every call throws, to show that nothing the interceptor
/// does with it can fail a query.
class _ThrowingLogger implements BoundLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('logger');
}

/// An error whose message cannot be read.
class _UnprintableError implements Exception {
  @override
  String toString() => throw StateError('toString');
}
