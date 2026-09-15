import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import 'dto/log_dto.dart';

part 'logs_api.g.dart';

/// `GET /v1/logs`.
///
/// `GET /v1/logs/stream` is deliberately **not** here: SSE is a long-lived
/// body parsed frame by frame, not one typed response, and retrofit's model
/// does not describe it. It is written by hand on the same `Dio` instance
/// (design.md decision 37, implemented in section 22).
@RestApi()
abstract class LogsApi {
  factory LogsApi(Dio dio, {String baseUrl}) = _LogsApi;

  /// Exactly one scope per query — a project or a group, never both and never
  /// an aggregate across several (`specs/log-server-api`).
  ///
  /// `cursor` is the `next_cursor` of the previous page. Changing any filter
  /// invalidates it: the caller starts from the first page again rather than
  /// paging a query that no longer matches.
  ///
  /// `level` is a **floor**, not an exact match — `level=warning` returns
  /// warnings and everything above them.
  ///
  /// `search` runs as `LIKE` over the event and the raw stored JSON, so it
  /// matches key names as well as values: `q=status_code` finds every entry
  /// carrying that field whatever its value.
  ///
  /// [contextFilters] carries equality filters on arbitrary context keys.
  /// Build it with [contextQuery] rather than by hand — the server reads them
  /// under a `context.` prefix, and a key without it is silently ignored
  /// rather than refused.
  @GET('/v1/logs')
  Future<LogPageDto> query({
    @Query('project_id') int? projectId,
    @Query('group_id') int? groupId,
    @Query('level') String? level,
    @Query('category') String? category,
    @Query('logger') String? logger,
    @Query('session_id') String? sessionId,
    @Query('request_id') String? requestId,
    @Query('connection_generation') int? connectionGeneration,
    @Query('tool_call_id') String? toolCallId,
    @Query('message_id') String? messageId,
    @Query('operation_id') String? operationId,
    @Query('q') String? search,
    @Query('from') String? from,
    @Query('to') String? to,
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
    @Queries() Map<String, dynamic>? contextFilters,
  });
}

/// Prefixes arbitrary context keys the way `GET /v1/logs` expects them.
///
/// ```dart
/// api.query(projectId: 42, contextFilters: contextQuery({'user_id': '7'}));
/// // → GET /v1/logs?project_id=42&context.user_id=7
/// ```
///
/// Kept out of the interface because retrofit generates its members; a helper
/// declared there would be overwritten.
Map<String, dynamic> contextQuery(Map<String, String> byKey) => {
  for (final entry in byKey.entries) 'context.${entry.key}': entry.value,
};
