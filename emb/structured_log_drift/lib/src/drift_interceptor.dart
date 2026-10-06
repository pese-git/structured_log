import 'package:drift/drift.dart';
import 'package:structured_log/structured_log.dart';

/// The longest SQL statement [StructuredLogDriftInterceptor] writes before
/// cutting it short.
const int defaultStatementMaxLength = 2000;

/// The longest string argument [StructuredLogDriftInterceptor] writes, when
/// [StructuredLogDriftInterceptor.logArguments] is on, before cutting it
/// short.
const int defaultArgumentMaxLength = 1000;

/// The level of each kind of entry [StructuredLogDriftInterceptor] writes;
/// `null` turns that kind off.
class DriftLogLevels {
  /// A `db_query` that took less than the slow-query threshold.
  final LogLevel? query;

  /// A `db_batch` that took less than the slow-query threshold.
  final LogLevel? batch;

  /// A `db_query` or `db_batch` that took at least the slow-query threshold.
  final LogLevel? slow;

  /// A `db_query_failed`.
  final LogLevel? failed;

  /// A `db_transaction_committed`. `trace` by default: every batch runs in
  /// a transaction of its own, so at `debug` each batch would be logged
  /// twice.
  final LogLevel? committed;

  /// A `db_transaction_rolled_back`, which almost always means an error.
  final LogLevel? rolledBack;

  const DriftLogLevels({
    this.query = LogLevel.debug,
    this.batch = LogLevel.debug,
    this.slow = LogLevel.warning,
    this.failed = LogLevel.error,
    this.committed = LogLevel.trace,
    this.rolledBack = LogLevel.warning,
  });
}

/// A drift [QueryInterceptor] that writes every query, batch, failure and
/// transaction end as a `structured_log` entry.
///
/// ```dart
/// final db = AppDatabase(
///   NativeDatabase(file).interceptWith(StructuredLogDriftInterceptor()),
/// );
/// ```
///
/// Each query becomes a `db_query` with its `kind`, `statement` and
/// `duration_ms`, plus `rows`, `affected_rows` or `insert_id`; a batch a
/// single `db_batch`; a query or batch that throws a `db_query_failed`
/// with `error`, `error_type` and `stack_trace`, and the exception still
/// reaches the caller unchanged. A query at least [slowQueryThreshold] long
/// is written at [DriftLogLevels.slow] with `slow: true`.
///
/// Argument values are not written unless [logArguments] is on: they are
/// where password hashes, tokens and personal data are, and the statements
/// drift builds carry only placeholders.
///
/// Migrations do not pass through an interceptor: drift runs them on the
/// executor underneath, so they are not logged.
class StructuredLogDriftInterceptor extends QueryInterceptor {
  /// Creates the interceptor; pass it to `interceptWith`.
  StructuredLogDriftInterceptor({
    BoundLogger? logger,
    this.loggerName = 'drift',
    this.category = 'db',
    this.levels = const DriftLogLevels(),
    this.slowQueryThreshold = const Duration(milliseconds: 500),
    this.logArguments = false,
    this.filter,
  }) : _logger = logger;

  final BoundLogger? _logger;

  /// The logger entries are written through when no `logger` was given,
  /// looked up on every entry so that a later
  /// `StructlogConfiguration.configure` reaches it.
  final String loggerName;

  /// The `category` of every entry; `null` writes none.
  final String? category;

  /// The level of each kind of entry; see [DriftLogLevels].
  final DriftLogLevels levels;

  /// How long a query or batch may take before it is written as slow;
  /// `null` never marks one slow.
  final Duration? slowQueryThreshold;

  /// Whether a `db_query` carries its `arguments`. Off by default; see the
  /// class documentation.
  final bool logArguments;

  /// When given, only queries for which it returns `true` are written; one
  /// for which it throws is not written either. [kind] is `select`,
  /// `insert`, `update`, `delete`, `custom` or `batch`.
  final bool Function(String kind, String statement)? filter;

  /// When each open transaction began, kept by the executor drift hands
  /// back to [commitTransaction] or [rollbackTransaction], so that nested
  /// transactions do not mix and nothing outlives its transaction.
  final Expando<Stopwatch> _transactionStarts = Expando();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _run(
      'select',
      statement,
      args,
      () => super.runSelect(executor, statement, args),
      (rows) => {'rows': rows.length},
    );
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _run(
      'insert',
      statement,
      args,
      () => super.runInsert(executor, statement, args),
      (id) => {'insert_id': id},
    );
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _run(
      'update',
      statement,
      args,
      () => super.runUpdate(executor, statement, args),
      (count) => {'affected_rows': count},
    );
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _run(
      'delete',
      statement,
      args,
      () => super.runDelete(executor, statement, args),
      (count) => {'affected_rows': count},
    );
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _run(
      'custom',
      statement,
      args,
      () => super.runCustom(executor, statement, args),
      (_) => const {},
    );
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) async {
    final first = statements.statements.isEmpty ? '' : statements.statements[0];
    final stopwatch = Stopwatch()..start();
    try {
      await super.runBatched(executor, statements);
    } catch (error, stackTrace) {
      _failed(
          'batch',
          first,
          [
            for (final set in statements.arguments) ...set.arguments,
          ],
          stopwatch,
          error,
          stackTrace);
      rethrow;
    }
    _guard(() {
      if (!_passes('batch', first)) return;
      final slow = _isSlow(stopwatch);
      _log(
          slow ? levels.slow : levels.batch,
          'db_batch',
          () => {
                'statement_count': statements.statements.length,
                'execution_count': statements.arguments.length,
                'duration_ms': _durationMs(stopwatch),
                if (slow) 'slow': true,
              });
    });
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final transaction = super.beginTransaction(parent);
    _guard(() => _transactionStarts[transaction] = Stopwatch()..start());
    return transaction;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await super.commitTransaction(inner);
    _transactionEnded(inner, levels.committed, 'db_transaction_committed');
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await super.rollbackTransaction(inner);
    _transactionEnded(inner, levels.rolledBack, 'db_transaction_rolled_back');
  }

  /// Runs [query] and writes its entry. The query itself runs outside any
  /// guard, so its result and its exception reach the caller exactly as
  /// drift produced them; only the logging is guarded.
  Future<T> _run<T>(
    String kind,
    String statement,
    List<Object?> args,
    Future<T> Function() query,
    Map<String, Object?> Function(T result) resultFields,
  ) async {
    final stopwatch = Stopwatch()..start();
    final T result;
    try {
      result = await query();
    } catch (error, stackTrace) {
      _failed(kind, statement, args, stopwatch, error, stackTrace);
      rethrow;
    }
    _guard(() {
      if (!_passes(kind, statement)) return;
      final slow = _isSlow(stopwatch);
      _log(
          slow ? levels.slow : levels.query,
          'db_query',
          () => {
                'kind': kind,
                'statement': _cut(statement, defaultStatementMaxLength),
                'duration_ms': _durationMs(stopwatch),
                ...resultFields(result),
                if (slow) 'slow': true,
                if (logArguments) 'arguments': [for (final a in args) _arg(a)],
              });
    });
    return result;
  }

  /// Writes a `db_query_failed`. With [logArguments] off, the error's text
  /// is scrubbed of [args] first: a driver's message may quote them —
  /// `sqlite3` appends every parameter of the failing statement, and a
  /// PostgreSQL unique violation names the duplicate value.
  void _failed(
    String kind,
    String statement,
    List<Object?> args,
    Stopwatch stopwatch,
    Object error,
    StackTrace stackTrace,
  ) {
    _guard(() {
      if (!_passes(kind, statement)) return;
      _log(
        levels.failed,
        'db_query_failed',
        () => {
          'kind': kind,
          'statement': _cut(statement, defaultStatementMaxLength),
          'duration_ms': _durationMs(stopwatch),
          if (!logArguments) ...{
            'error': _scrub(_describe(error), args),
            'error_type': error.runtimeType.toString(),
            'stack_trace': stackTrace.toString(),
          },
        },
        error: logArguments ? error : null,
        stackTrace: logArguments ? stackTrace : null,
      );
    });
  }

  void _transactionEnded(
    TransactionExecutor transaction,
    LogLevel? level,
    String event,
  ) {
    _guard(() {
      final started = _transactionStarts[transaction];
      _transactionStarts[transaction] = null;
      _log(
          level,
          event,
          () => {
                if (started != null) 'duration_ms': _durationMs(started),
              });
    });
  }

  /// Whether [filter] lets the query through; one that throws does not.
  bool _passes(String kind, String statement) {
    final filter = this.filter;
    if (filter == null) return true;
    try {
      return filter(kind, statement);
    } catch (_) {
      return false;
    }
  }

  bool _isSlow(Stopwatch stopwatch) {
    final threshold = slowQueryThreshold;
    return threshold != null && stopwatch.elapsed >= threshold;
  }

  /// Writes an entry, building its fields only once a sink would take it.
  void _log(
    LogLevel? level,
    String event,
    Map<String, Object?> Function() fields, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level == null) return;
    final logger = _logger ?? getLogger(loggerName);
    if (!logger.isEnabled(level, category: category)) return;
    logger.tryLog(
      level,
      event,
      context: {
        if (category != null) 'category': category,
        ...fields(),
      },
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Runs [body], dropping whatever it throws: logging sits in the path of
  /// every query and must never change one.
  static void _guard(void Function() body) {
    try {
      body();
    } catch (_) {
      // Deliberately dropped: an entry is not worth a query.
    }
  }

  /// Milliseconds with microsecond precision: a query against a local
  /// database usually takes less than one, and a whole number would be 0.
  static double _durationMs(Stopwatch stopwatch) =>
      stopwatch.elapsedMicroseconds / 1000;

  /// [text] with the argument values it quotes hidden: the parameter list
  /// `sqlite3` appends after `Causing statement`, and every string argument
  /// of [minScrubbedLength] characters or more wherever it appears. Shorter
  /// strings are left alone — hiding every `1` or `ok` would garble the
  /// message, and a secret is rarely that short.
  static String _scrub(String text, List<Object?> args) {
    var scrubbed = text;
    final causing = scrubbed.indexOf('Causing statement');
    if (causing >= 0) {
      final parameters = scrubbed.indexOf(', parameters: ', causing);
      if (parameters >= 0) {
        scrubbed = '${scrubbed.substring(0, parameters)}, parameters: <hidden>';
      }
    }
    for (final arg in args) {
      if (arg is String && arg.length >= minScrubbedLength) {
        scrubbed = scrubbed.replaceAll(arg, '<argument>');
      }
    }
    return scrubbed;
  }

  /// The shortest string argument hidden from an error's text.
  static const int minScrubbedLength = 4;

  static String _describe(Object error) {
    try {
      return error.toString();
    } catch (_) {
      return '<${error.runtimeType}>';
    }
  }

  static Object? _arg(Object? value) => switch (value) {
        Uint8List() => '<${value.length} bytes>',
        String() => _cut(value, defaultArgumentMaxLength),
        _ => value,
      };

  static String _cut(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}
