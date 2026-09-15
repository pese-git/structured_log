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
  @GET('/v1/logs')
  Future<LogPageDto> query({
    @Query('project_id') int? projectId,
    @Query('group_id') int? groupId,
    @Query('level') String? level,
    @Query('category') String? category,
    @Query('logger') String? logger,
    @Query('q') String? search,
    @Query('from') String? from,
    @Query('to') String? to,
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });
}
