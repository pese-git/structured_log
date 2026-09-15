import '../../../shared/api/logs_api.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';

/// Scope and filters as `GET /v1/logs` and `GET /v1/logs/stream` spell them.
///
/// Both endpoints take the same parameters, and the live subscription is only
/// correct if it is opened with exactly the ones the page query used — a
/// stream narrower or wider than the list would deliver entries the list would
/// never have shown, or drop ones it would (`specs/admin-client-log-browser`).
///
/// `GET /v1/logs` reaches the server through the generated `LogsApi`, which
/// spells these names itself, so this function is not the only copy. The two
/// are held together by a test that puts the same scope and filter through
/// both and compares the query the server would see
/// (`test/features/log_browser/log_query_params_test.dart`).
///
/// Paging (`cursor`, `limit`) is deliberately absent: it belongs to the list,
/// not to the subscription.
Map<String, dynamic> logQueryParameters({
  required LogScope scope,
  required LogFilter filter,

  /// Only the stream takes it: the id of the last entry already delivered, so
  /// the server replays the gap between the first page and the subscription
  /// (`log-server-live-stream`).
  int? sinceId,
}) {
  final params = <String, dynamic>{
    'project_id': switch (scope) {
      ProjectScope(:final id) => id,
      GroupScope() => null,
    },
    'group_id': switch (scope) {
      GroupScope(:final id) => id,
      ProjectScope() => null,
    },
    'level': filter.minLevel,
    'category': filter.category,
    'logger': filter.logger,
    'session_id': filter.sessionId,
    'request_id': filter.requestId,
    'connection_generation': filter.connectionGeneration,
    'tool_call_id': filter.toolCallId,
    'message_id': filter.messageId,
    'operation_id': filter.operationId,
    'q': filter.search,
    // UTC, as the server parses it. Sending local time would move the window
    // by the reader's offset without saying so.
    'from': filter.from?.toUtc().toIso8601String(),
    'to': filter.to?.toUtc().toIso8601String(),
    'since_id': sinceId,
    ...contextQuery(filter.context),
  };
  params.removeWhere((_, value) => value == null);
  return params;
}
