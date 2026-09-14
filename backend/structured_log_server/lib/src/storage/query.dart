import 'package:drift/drift.dart';

import 'database.dart';

/// Severity order for `LogQuery.minLevel` — matches `LogLevel` in
/// `package:structured_log`. Not reusable as a dependency (the server has
/// no dependency on `structured_log`'s enum type), so re-declared as the
/// same fixed set of level names.
const List<String> logLevelOrder = [
  'trace',
  'debug',
  'info',
  'warning',
  'error',
  'critical',
];

/// A filter + pagination request for [LogStore.query].
///
/// [projectIds] is the already-authorized, already-unblocked scope to query
/// — resolving `project_id`/`group_id` from the request into this list, and
/// checking RBAC/`is_blocked`, is the caller's job (`log-server-api`,
/// `log-server-rbac`), not the storage layer's.
class LogQuery {
  final List<int> projectIds;
  final String? minLevel;
  final String? category;
  final String? logger;
  final DateTime? from;
  final DateTime? to;
  final String? sessionId;
  final String? requestId;
  final int? connectionGeneration;
  final String? toolCallId;
  final String? messageId;
  final String? operationId;
  final String? q;
  final Map<String, String> contextEquals;
  final int limit;

  /// The `id` of the last entry on the previous page. `null` starts from
  /// the newest matching entry (`log-server-api`: no cursor → descending by
  /// `id`).
  final int? cursor;

  const LogQuery({
    required this.projectIds,
    this.minLevel,
    this.category,
    this.logger,
    this.from,
    this.to,
    this.sessionId,
    this.requestId,
    this.connectionGeneration,
    this.toolCallId,
    this.messageId,
    this.operationId,
    this.q,
    this.contextEquals = const {},
    this.limit = 50,
    this.cursor,
  })  : assert(projectIds.length > 0, 'projectIds must not be empty'),
        assert(limit > 0, 'limit must be positive');
}

/// One page of [LogQuery] results. [nextCursor] is the `id` to pass back as
/// [LogQuery.cursor] for the next (older) page — `null` once [entries] is
/// empty.
class LogQueryPage {
  final List<LogEntry> entries;
  final int? nextCursor;

  const LogQueryPage({required this.entries, required this.nextCursor});
}

/// Renders [LogQuery] into a `SELECT * FROM log_entries ...` statement and
/// its bound variables. `LIKE`/`json_extract` conditions aren't expressible
/// through drift's typed query builder (`design.md` decision 3), so the
/// whole query is assembled as one raw statement instead of mixing builder
/// and `customSelect` fragments.
({String sql, List<Variable<Object>> variables}) buildLogQuerySql(
  LogQuery query,
) {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];

  conditions.add(
    'project_id IN (${List.filled(query.projectIds.length, '?').join(', ')})',
  );
  variables.addAll(query.projectIds.map(Variable.withInt));

  final minLevel = query.minLevel;
  if (minLevel != null) {
    final atOrAbove = logLevelOrder.sublist(logLevelOrder.indexOf(minLevel));
    conditions.add(
      'level IN (${List.filled(atOrAbove.length, '?').join(', ')})',
    );
    variables.addAll(atOrAbove.map(Variable.withString));
  }

  if (query.category != null) {
    conditions.add('category = ?');
    variables.add(Variable.withString(query.category!));
  }

  if (query.logger != null) {
    conditions.add('logger = ?');
    variables.add(Variable.withString(query.logger!));
  }

  if (query.from != null) {
    conditions.add('timestamp >= ?');
    variables.add(Variable.withDateTime(query.from!));
  }

  if (query.to != null) {
    conditions.add('timestamp <= ?');
    variables.add(Variable.withDateTime(query.to!));
  }

  if (query.sessionId != null) {
    conditions.add('session_id = ?');
    variables.add(Variable.withString(query.sessionId!));
  }

  if (query.requestId != null) {
    conditions.add('request_id = ?');
    variables.add(Variable.withString(query.requestId!));
  }

  if (query.connectionGeneration != null) {
    conditions.add('connection_generation = ?');
    variables.add(Variable.withInt(query.connectionGeneration!));
  }

  if (query.toolCallId != null) {
    conditions.add('tool_call_id = ?');
    variables.add(Variable.withString(query.toolCallId!));
  }

  if (query.messageId != null) {
    conditions.add('message_id = ?');
    variables.add(Variable.withString(query.messageId!));
  }

  if (query.operationId != null) {
    conditions.add('operation_id = ?');
    variables.add(Variable.withString(query.operationId!));
  }

  if (query.q != null) {
    conditions.add(
        '(event LIKE ? ESCAPE \'\\\' OR context_json LIKE ? ESCAPE \'\\\')');
    final pattern = '%${_escapeLike(query.q!)}%';
    variables.add(Variable.withString(pattern));
    variables.add(Variable.withString(pattern));
  }

  for (final entry in query.contextEquals.entries) {
    conditions.add('CAST(json_extract(context_json, ?) AS TEXT) = ?');
    variables.add(Variable.withString('\$.${entry.key}'));
    variables.add(Variable.withString(entry.value));
  }

  if (query.cursor != null) {
    conditions.add('id < ?');
    variables.add(Variable.withInt(query.cursor!));
  }

  variables.add(Variable.withInt(query.limit));

  final sql = 'SELECT * FROM log_entries '
      'WHERE ${conditions.join(' AND ')} '
      'ORDER BY id DESC '
      'LIMIT ?';

  return (sql: sql, variables: variables);
}

/// Escapes `%`/`_`/the escape character itself for use inside a `LIKE`
/// pattern with `ESCAPE '\'`.
String _escapeLike(String input) {
  return input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}
