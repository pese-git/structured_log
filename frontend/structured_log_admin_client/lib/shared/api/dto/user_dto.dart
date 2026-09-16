import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_dto.freezed.dart';
part 'user_dto.g.dart';

/// A user account, as `POST`/`GET`/`PATCH /v1/users` and the block/unblock
/// actions return it.
///
/// [email]/[emailVerifiedAt] are always `null` in this stage: nothing on the
/// client or the server writes them yet — email verification is a later
/// stage (`design.md` "Delivery Phases", Этап 3 excludes it explicitly).
/// Carried anyway, rather than left off the model, so the wire shape does not
/// change out from under this class when they do land.
@freezed
abstract class UserDto with _$UserDto {
  const factory UserDto({
    required int id,
    required String username,
    @JsonKey(name: 'display_name') String? displayName,
    String? email,
    @JsonKey(name: 'email_verified_at') DateTime? emailVerifiedAt,
    @JsonKey(name: 'must_change_password') required bool mustChangePassword,
    @JsonKey(name: 'is_active') required bool isActive,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
    @JsonKey(name: 'is_primary_admin') required bool isPrimaryAdmin,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _UserDto;

  const UserDto._();

  factory UserDto.fromJson(Map<String, dynamic> json) =>
      _$UserDtoFromJson(json);

  bool get isDeleted => deletedAt != null;

  /// Blocked, and not already deleted — deletion subsumes blocking on the
  /// wire (`is_active` is `false` either way), and the two read as different
  /// things on screen (`docs/architecture/rbac-and-lifecycle.md`).
  bool get isBlocked => !isActive && !isDeleted;
}

/// `POST /v1/users`. No `email` field — see [UserDto].
@freezed
abstract class CreateUserRequestDto with _$CreateUserRequestDto {
  const factory CreateUserRequestDto({
    required String username,
    required String password,
    @JsonKey(name: 'display_name', includeIfNull: false) String? displayName,
  }) = _CreateUserRequestDto;

  factory CreateUserRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateUserRequestDtoFromJson(json);
}

/// `PATCH /v1/users/{id}`.
///
/// [displayName] always goes on the wire, including as `null` to clear it —
/// the server tells "leave this alone" from "clear it" by whether the key is
/// present at all (same convention as `UpdateProjectQuotaRequestDto`), and
/// the caller always has a value to send: the edit dialog pre-fills the
/// field with what is there now. [password], in contrast, really is
/// optional — "not changing it" is the ordinary case, so it is omitted
/// rather than sent as `null` (which the server would not accept anyway:
/// there is no "clear the password").
@freezed
abstract class UpdateUserRequestDto with _$UpdateUserRequestDto {
  const factory UpdateUserRequestDto({
    @JsonKey(name: 'display_name') required String? displayName,
    @JsonKey(includeIfNull: false) String? password,
  }) = _UpdateUserRequestDto;

  factory UpdateUserRequestDto.fromJson(Map<String, dynamic> json) =>
      _$UpdateUserRequestDtoFromJson(json);
}

/// One page of `GET /v1/users` — cursor-paginated, unlike the flat
/// `{"items": [...]}` groups/projects/keys use (same shape as
/// `AuditPageDto`).
@freezed
abstract class UserPageDto with _$UserPageDto {
  const factory UserPageDto({
    @Default(<UserDto>[]) List<UserDto> items,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _UserPageDto;

  factory UserPageDto.fromJson(Map<String, dynamic> json) =>
      _$UserPageDtoFromJson(json);
}

/// A `RoleAssignment`, as `POST /v1/role-assignments` returns it.
///
/// There is no `GET /v1/role-assignments` in this stage — the server has no
/// listing endpoint — so this client can offer granting a role but cannot
/// show what a user already holds.
@freezed
abstract class RoleAssignmentDto with _$RoleAssignmentDto {
  const factory RoleAssignmentDto({
    required int id,
    @JsonKey(name: 'subject_type') required String subjectType,
    @JsonKey(name: 'subject_id') required int subjectId,
    required String role,
    @JsonKey(name: 'scope_type') required String scopeType,
    @JsonKey(name: 'scope_id') int? scopeId,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _RoleAssignmentDto;

  factory RoleAssignmentDto.fromJson(Map<String, dynamic> json) =>
      _$RoleAssignmentDtoFromJson(json);
}

/// `POST /v1/role-assignments`.
///
/// [subjectType] is always sent as `"user"` by this client — the server
/// refuses `"team"` outright in this stage (`role_assignments_route.dart`,
/// 4.3a) — and [subjectId] is always the user the grant dialog was opened
/// from. [scopeId] is omitted when [scopeType] is `"global"`, the same rule
/// `CreateProjectRequestDto` uses for an absent quota field.
@freezed
abstract class CreateRoleAssignmentRequestDto
    with _$CreateRoleAssignmentRequestDto {
  const factory CreateRoleAssignmentRequestDto({
    @JsonKey(name: 'subject_type') required String subjectType,
    @JsonKey(name: 'subject_id') required int subjectId,
    required String role,
    @JsonKey(name: 'scope_type') required String scopeType,
    @JsonKey(name: 'scope_id', includeIfNull: false) int? scopeId,
  }) = _CreateRoleAssignmentRequestDto;

  factory CreateRoleAssignmentRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateRoleAssignmentRequestDtoFromJson(json);
}
