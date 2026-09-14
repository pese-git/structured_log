import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// Severity order for [LogFilter.minLevel] — matches `LogLevel` in
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

/// Which entries a caller wants, independent of *where* they come from.
///
/// The same filter has to be applied two ways: as a SQL `WHERE` clause over
/// stored rows (`GET /v1/logs`) and as an in-memory predicate over a single
/// row that was just accepted (`GET /v1/logs/stream`). Both are derived from
/// this one object — [appendConditions] and [matches] sit next to each other
/// field by field, precisely so the live stream cannot quietly drift away
/// from what the historical query would have returned (`design.md`
/// decision 29).
///
/// Scope (`project_id`/`group_id`) is deliberately not part of this: it is
/// resolved and authorized before any filtering happens, and it is what
/// decides *whether* a caller may see a row at all rather than which rows
/// they asked for.
class LogFilter {
  /// Minimum severity, inclusive. One of [logLevelOrder]; anything else is a
  /// caller error and must be rejected before constructing the filter (see
  /// [isValidLevel]).
  final String? minLevel;
  final String? category;
  final String? logger;
  final String? sessionId;
  final String? requestId;
  final int? connectionGeneration;
  final String? toolCallId;
  final String? messageId;
  final String? operationId;

  /// Free-text search over the event text and the serialized context
  /// (`log-server-api`).
  final String? q;

  /// `context.<key>=<value>` equality checks against the entry's context.
  final Map<String, String> contextEquals;

  const LogFilter({
    this.minLevel,
    this.category,
    this.logger,
    this.sessionId,
    this.requestId,
    this.connectionGeneration,
    this.toolCallId,
    this.messageId,
    this.operationId,
    this.q,
    this.contextEquals = const {},
  });

  /// Whether [level] names a severity this server knows. Callers parsing
  /// user input check this first: an unknown level is a `400`, not an
  /// empty result set and not a crash. It can't be an assert on the
  /// constructor — that would make the constructor non-const, and a const
  /// empty filter is what "no filtering" is.
  static bool isValidLevel(String level) => logLevelOrder.contains(level);

  /// Appends this filter's SQL conditions to [conditions] and their bound
  /// values to [variables]. Kept in the same order as [matches]'s checks.
  void appendConditions(
    List<String> conditions,
    List<Variable<Object>> variables,
  ) {
    final minLevel = this.minLevel;
    if (minLevel != null) {
      final floor = logLevelOrder.indexOf(minLevel);
      if (floor < 0) {
        // Unreachable through HTTP — parseLogFilter answers 400 first. Left
        // explicit so internal misuse fails by name instead of as a
        // RangeError from the sublist below.
        throw ArgumentError.value(minLevel, 'minLevel', 'unknown log level');
      }
      final atOrAbove = logLevelOrder.sublist(floor);
      conditions.add(
        'level IN (${List.filled(atOrAbove.length, '?').join(', ')})',
      );
      variables.addAll(atOrAbove.map(Variable.withString));
    }

    if (category != null) {
      conditions.add('category = ?');
      variables.add(Variable.withString(category!));
    }

    if (logger != null) {
      conditions.add('logger = ?');
      variables.add(Variable.withString(logger!));
    }

    if (sessionId != null) {
      conditions.add('session_id = ?');
      variables.add(Variable.withString(sessionId!));
    }

    if (requestId != null) {
      conditions.add('request_id = ?');
      variables.add(Variable.withString(requestId!));
    }

    if (connectionGeneration != null) {
      conditions.add('connection_generation = ?');
      variables.add(Variable.withInt(connectionGeneration!));
    }

    if (toolCallId != null) {
      conditions.add('tool_call_id = ?');
      variables.add(Variable.withString(toolCallId!));
    }

    if (messageId != null) {
      conditions.add('message_id = ?');
      variables.add(Variable.withString(messageId!));
    }

    if (operationId != null) {
      conditions.add('operation_id = ?');
      variables.add(Variable.withString(operationId!));
    }

    if (q != null) {
      conditions.add(
        "(event LIKE ? ESCAPE '\\' OR context_json LIKE ? ESCAPE '\\')",
      );
      final pattern = '%${escapeLike(q!)}%';
      variables.add(Variable.withString(pattern));
      variables.add(Variable.withString(pattern));
    }

    for (final entry in contextEquals.entries) {
      conditions.add('CAST(json_extract(context_json, ?) AS TEXT) = ?');
      variables.add(Variable.withString('\$.${entry.key}'));
      variables.add(Variable.withString(entry.value));
    }
  }

  /// Whether [entry] satisfies this filter — the in-memory counterpart of
  /// [appendConditions], checking the same fields in the same order.
  ///
  /// Mirrors SQL's three-valued logic where it matters: a `NULL` column
  /// never equals a requested value, so an entry without a `category` does
  /// not match a `category` filter.
  bool matches(LogEntry entry) {
    final minLevel = this.minLevel;
    if (minLevel != null) {
      final floor = logLevelOrder.indexOf(minLevel);
      final actual = logLevelOrder.indexOf(entry.level);
      // An entry whose level this server doesn't know can't be ordered
      // against the floor; SQL's `level IN (...)` wouldn't match it either.
      if (actual < 0 || actual < floor) return false;
    }

    if (category != null && entry.category != category) return false;
    if (logger != null && entry.logger != logger) return false;
    if (sessionId != null && entry.sessionId != sessionId) return false;
    if (requestId != null && entry.requestId != requestId) return false;
    if (connectionGeneration != null &&
        entry.connectionGeneration != connectionGeneration) {
      return false;
    }
    if (toolCallId != null && entry.toolCallId != toolCallId) return false;
    if (messageId != null && entry.messageId != messageId) return false;
    if (operationId != null && entry.operationId != operationId) return false;

    final q = this.q;
    if (q != null) {
      // SQLite's LIKE is case-insensitive for ASCII, so the predicate is
      // too. The two diverge for non-ASCII text, where SQLite compares
      // case-sensitively and Dart's toLowerCase does not — erring toward
      // delivering an entry the historical query would have missed, rather
      // than withholding one it would have returned.
      final needle = q.toLowerCase();
      final matchesText = entry.event.toLowerCase().contains(needle) ||
          entry.contextJson.toLowerCase().contains(needle);
      if (!matchesText) return false;
    }

    if (contextEquals.isNotEmpty) {
      final context = _decodeContext(entry.contextJson);
      for (final wanted in contextEquals.entries) {
        final value = context[wanted.key];
        // Absent or JSON null: `json_extract` yields NULL, and `NULL = ?`
        // is never true.
        if (value == null) return false;
        if (_asSqlText(value) != wanted.value) return false;
      }
    }

    return true;
  }

  static Map<String, Object?> _decodeContext(String contextJson) {
    try {
      final decoded = jsonDecode(contextJson);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  /// How `CAST(json_extract(...) AS TEXT)` renders a JSON value: strings
  /// come out unquoted, objects and arrays as their JSON text, and booleans
  /// as `1`/`0` — SQLite has no boolean type, so `json_extract` yields an
  /// integer and `context.flagged=true` matches nothing while
  /// `context.flagged=1` matches. Surprising, but the filter's job is to
  /// agree with the stored query, not to improve on it.
  static String _asSqlText(Object value) {
    if (value is String) return value;
    if (value is bool) return value ? '1' : '0';
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString();
  }
}

/// Escapes `%`/`_`/the escape character itself for use inside a `LIKE`
/// pattern with `ESCAPE '\'`.
String escapeLike(String input) {
  return input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}
