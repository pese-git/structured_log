import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_drift/structured_log_drift.dart';

/// A database without generated tables, to keep the example to one file;
/// an app passes the intercepted executor to its own generated database
/// the same way.
class ExampleDatabase extends GeneratedDatabase {
  ExampleDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
          name: 'console', output: jsonLineOutput, minLevel: LogLevel.trace),
    ],
  );

  final db = ExampleDatabase(
    NativeDatabase.memory().interceptWith(StructuredLogDriftInterceptor()),
  );

  await db.customStatement(
    'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, token TEXT)',
  );
  // The token is an argument, so it stays out of the log.
  await db.customInsert(
    'INSERT INTO users (name, token) VALUES (?, ?)',
    variables: [Variable('alice'), Variable('secret-token')],
  );
  await db.batch((batch) {
    for (final name in ['bob', 'carol']) {
      batch.customStatement('INSERT INTO users (name) VALUES (?)', [name]);
    }
  });
  await db.customSelect('SELECT * FROM users').get();

  try {
    await db.transaction(() async {
      await db.customStatement('INSERT INTO missing VALUES (1)');
    });
  } on Exception {
    // Logged as db_query_failed, then db_transaction_rolled_back.
  }

  await db.close();
}
