import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import 'dto/audit_dto.dart';

part 'audit_api.g.dart';

/// `GET /v1/audit-log`.
///
/// Administrators only — the server answers 403 to anyone else, and that is the
/// authority. The screen hides the section from a caller whose token carries no
/// global admin role, but only so as not to offer something that would be
/// refused; it never decides access itself.
@RestApi()
abstract class AuditApi {
  factory AuditApi(Dio dio, {String baseUrl}) = _AuditApi;

  /// Every filter narrows the same question, and they combine: "what did this
  /// account do to that project last Tuesday" is one query.
  ///
  /// [action] must be one of the server's closed set. An unknown value is
  /// refused with 400 rather than answered with an empty page — in a journal
  /// whose job is answering "did this happen", a typo that reads as "nothing
  /// happened" is the one wrong answer that matters.
  ///
  /// [cursor] is the `next_cursor` of the previous page; changing any filter
  /// invalidates it, so the screen starts from the first page again rather than
  /// paging a query that no longer matches.
  @GET('/v1/audit-log')
  Future<AuditPageDto> query({
    @Query('actor_user_id') int? actorUserId,
    @Query('action') String? action,
    @Query('target_type') String? targetType,
    @Query('target_id') int? targetId,
    @Query('from') String? from,
    @Query('to') String? to,
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });
}
