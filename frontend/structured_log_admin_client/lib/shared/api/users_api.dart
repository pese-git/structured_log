import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import 'dto/user_dto.dart';

part 'users_api.g.dart';

/// `/v1/users`. Administrators only — the server refuses anyone else on
/// every method here.
@RestApi()
abstract class UsersApi {
  factory UsersApi(Dio dio, {String baseUrl}) = _UsersApi;

  /// Cursor-paginated, oldest-first by `id` descending — see [UserPageDto].
  /// [username] narrows by substring, for the grant-target search picker
  /// (design.md, уточнение 17.09.2026) — same idiom as `?name=` on
  /// `GroupsApi`/`ProjectsApi`.
  @GET('/v1/users')
  Future<UserPageDto> list({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
    @Query('username') String? username,
  });

  /// No `email` field on this client (`CreateUserRequestDto`). The server
  /// always sets `must_change_password: true` on the returned account.
  @POST('/v1/users')
  Future<UserDto> create(@Body() CreateUserRequestDto body);

  @PATCH('/v1/users/{id}')
  Future<UserDto> update(@Path('id') int id, @Body() UpdateUserRequestDto body);

  /// `is_active: false`, sessions revoked immediately.
  @POST('/v1/users/{id}/block')
  Future<UserDto> block(@Path('id') int id);

  /// Refused with `409 deleted_account` if the target was deleted rather
  /// than blocked.
  @POST('/v1/users/{id}/unblock')
  Future<UserDto> unblock(@Path('id') int id);

  /// `:id == the caller` is refused with `400 self_deletion_requires_me` —
  /// self-deletion goes through `DELETE /v1/users/me` instead, which this
  /// screen does not offer (it manages other accounts, not the caller's
  /// own).
  @DELETE('/v1/users/{id}')
  Future<void> delete(@Path('id') int id);
}

/// `/v1/role-assignments`. Reduced to this stage's scope: `admin` only,
/// `subject_type: "user"` only (`role_assignments_route.dart`, 4.3a/5.6a).
@RestApi()
abstract class RoleAssignmentsApi {
  factory RoleAssignmentsApi(Dio dio, {String baseUrl}) = _RoleAssignmentsApi;

  @POST('/v1/role-assignments')
  Future<RoleAssignmentDto> create(@Body() CreateRoleAssignmentRequestDto body);

  @DELETE('/v1/role-assignments/{id}')
  Future<void> delete(@Path('id') int id);

  /// Filtered by exactly one of [subjectId] (Edit User dialog's grant list)
  /// or [scopeType]+[scopeId] (a group/project's «Доступ» section) — never
  /// called with neither, which would dump the whole table.
  @GET('/v1/role-assignments')
  Future<RoleAssignmentPageDto> list({
    @Query('subject_id') int? subjectId,
    @Query('scope_type') String? scopeType,
    @Query('scope_id') int? scopeId,
  });
}
