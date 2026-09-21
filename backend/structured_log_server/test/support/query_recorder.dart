import 'package:drift/drift.dart';

/// Records what reaches the database: every statement, and every transaction
/// opened — `nested` when it is opened inside another, which drift turns into a
/// `SAVEPOINT`.
class Recorder extends QueryInterceptor {
  final statements = <String>[];
  final transactions = <String>[];

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions.add(parent is TransactionExecutor ? 'nested' : 'top-level');
    return super.beginTransaction(parent);
  }

  @override
  Future<void> runCustom(
    QueryExecutor e,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runCustom(e, statement, args);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String statement, List<Object?> args) {
    statements.add(statement);
    return super.runInsert(e, statement, args);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String statement, List<Object?> args) {
    statements.add(statement);
    return super.runUpdate(e, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(e, statement, args);
  }

  @override
  Future<void> runBatched(QueryExecutor e, BatchedStatements statements_) {
    statements.add(
      'BATCH(${statements_.statements.length} statement(s), '
      '${statements_.arguments.length} row(s))',
    );
    return super.runBatched(e, statements_);
  }

  void clear() {
    statements.clear();
    transactions.clear();
  }
}
