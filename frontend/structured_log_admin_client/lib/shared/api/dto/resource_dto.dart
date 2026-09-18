import 'package:freezed_annotation/freezed_annotation.dart';

part 'resource_dto.freezed.dart';
part 'resource_dto.g.dart';

/// Every collection the server returns arrives wrapped: `{"items": [...]}`,
/// never a bare array (`groups_route.dart`, `projects_route.dart`,
/// `secret_keys_route.dart`, and `GET /v1/logs`, which adds `next_cursor` to
/// the same shape).
///
/// One envelope class per collection rather than a generic `Items<T>`:
/// `retrofit` needs a concrete `fromJson` per method, and a generic one costs
/// `genericArgumentFactories` plumbing on every call site to save three
/// four-line classes.
///
/// These exist because their absence was a real defect: the list methods were
/// declared as `Future<List<GroupDto>>`, dio's cast of a `Map` to a `List`
/// threw, and the client reported it as "the server is unreachable" — with
/// the server answering 200. Nothing caught it because no test put the
/// server's actual body through this layer.

@freezed
abstract class GroupDto with _$GroupDto {
  const factory GroupDto({
    required int id,
    required String name,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _GroupDto;

  factory GroupDto.fromJson(Map<String, dynamic> json) =>
      _$GroupDtoFromJson(json);
}

@freezed
abstract class CreateGroupRequestDto with _$CreateGroupRequestDto {
  const factory CreateGroupRequestDto({required String name}) =
      _CreateGroupRequestDto;

  factory CreateGroupRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateGroupRequestDtoFromJson(json);
}

@freezed
abstract class TeamDto with _$TeamDto {
  const factory TeamDto({
    required int id,
    @JsonKey(name: 'group_id') required int groupId,
    required String name,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _TeamDto;

  factory TeamDto.fromJson(Map<String, dynamic> json) =>
      _$TeamDtoFromJson(json);
}

@freezed
abstract class CreateTeamRequestDto with _$CreateTeamRequestDto {
  const factory CreateTeamRequestDto({required String name}) =
      _CreateTeamRequestDto;

  factory CreateTeamRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateTeamRequestDtoFromJson(json);
}

/// A team's member, as `GET /v1/teams/{id}/members` returns it — just enough
/// to show and pick one, not a full [UserDto]: whoever manages a team's
/// composition (an `owner`, not necessarily `admin`) has no general right to
/// read arbitrary user accounts, only to know who is in their own team
/// (`teams_route.dart`).
@freezed
abstract class TeamMemberDto with _$TeamMemberDto {
  const factory TeamMemberDto({
    @JsonKey(name: 'user_id') required int userId,
    required String username,
  }) = _TeamMemberDto;

  factory TeamMemberDto.fromJson(Map<String, dynamic> json) =>
      _$TeamMemberDtoFromJson(json);
}

/// `POST /v1/teams/{id}/members`.
@freezed
abstract class AddTeamMemberRequestDto with _$AddTeamMemberRequestDto {
  const factory AddTeamMemberRequestDto({
    @JsonKey(name: 'user_id') required int userId,
  }) = _AddTeamMemberRequestDto;

  factory AddTeamMemberRequestDto.fromJson(Map<String, dynamic> json) =>
      _$AddTeamMemberRequestDtoFromJson(json);
}

@freezed
abstract class ProjectDto with _$ProjectDto {
  const factory ProjectDto({
    required int id,
    @JsonKey(name: 'group_id') required int groupId,
    required String name,
    @JsonKey(name: 'retention_days') required int retentionDays,

    /// `null` means the quota is unset — unlimited, not zero.
    @JsonKey(name: 'max_entries') int? maxEntries,
    @JsonKey(name: 'max_bytes') int? maxBytes,
    @JsonKey(name: 'is_blocked') required bool isBlocked,
    @JsonKey(name: 'created_at') required DateTime createdAt,

    /// Present only where the server computes usage — the project detail
    /// endpoint, not the list.
    @JsonKey(name: 'entry_count') int? entryCount,
    @JsonKey(name: 'total_bytes') int? totalBytes,
  }) = _ProjectDto;

  factory ProjectDto.fromJson(Map<String, dynamic> json) =>
      _$ProjectDtoFromJson(json);
}

@freezed
abstract class CreateProjectRequestDto with _$CreateProjectRequestDto {
  const factory CreateProjectRequestDto({
    required String name,

    /// Required by the server: a project with no retention would keep every
    /// entry forever (`specs/log-server-quotas`).
    @JsonKey(name: 'retention_days') required int retentionDays,
    @JsonKey(name: 'max_entries', includeIfNull: false) int? maxEntries,
    @JsonKey(name: 'max_bytes', includeIfNull: false) int? maxBytes,
  }) = _CreateProjectRequestDto;

  factory CreateProjectRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateProjectRequestDtoFromJson(json);
}

/// `PATCH /v1/projects/{id}` — the quota, replaced wholesale.
///
/// Nulls are **sent**, not omitted, and that is the whole point of a separate
/// class from [CreateProjectRequestDto]. The server distinguishes "leave this
/// alone" from "make this unlimited" by whether the key is present at all
/// (`projects_route.dart` reads `body.containsKey`), so a form that clears a
/// limit has to put `null` on the wire. `includeIfNull: false`, which the
/// create request uses, would silently mean "unchanged" here.
@freezed
abstract class UpdateProjectQuotaRequestDto
    with _$UpdateProjectQuotaRequestDto {
  const factory UpdateProjectQuotaRequestDto({
    @JsonKey(name: 'retention_days') required int retentionDays,
    @JsonKey(name: 'max_entries') required int? maxEntries,
    @JsonKey(name: 'max_bytes') required int? maxBytes,
  }) = _UpdateProjectQuotaRequestDto;

  factory UpdateProjectQuotaRequestDto.fromJson(Map<String, dynamic> json) =>
      _$UpdateProjectQuotaRequestDtoFromJson(json);
}

@freezed
abstract class SecretKeyDto with _$SecretKeyDto {
  const factory SecretKeyDto({
    required int id,
    @JsonKey(name: 'project_id') required int projectId,
    required String label,
    @JsonKey(name: 'created_at') required DateTime createdAt,

    /// Set once the key is revoked; the row stays so the audit trail keeps
    /// its subject.
    @JsonKey(name: 'revoked_at') DateTime? revokedAt,

    /// The key itself, returned **only** in the response that created it and
    /// never again. Whatever shows it must warn that closing the dialog loses
    /// it (`specs/log-server-api`).
    String? secret,
  }) = _SecretKeyDto;

  factory SecretKeyDto.fromJson(Map<String, dynamic> json) =>
      _$SecretKeyDtoFromJson(json);
}

@freezed
abstract class CreateSecretKeyRequestDto with _$CreateSecretKeyRequestDto {
  const factory CreateSecretKeyRequestDto({required String label}) =
      _CreateSecretKeyRequestDto;

  factory CreateSecretKeyRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateSecretKeyRequestDtoFromJson(json);
}

@freezed
abstract class GroupListDto with _$GroupListDto {
  const factory GroupListDto({@Default(<GroupDto>[]) List<GroupDto> items}) =
      _GroupListDto;

  factory GroupListDto.fromJson(Map<String, dynamic> json) =>
      _$GroupListDtoFromJson(json);
}

@freezed
abstract class ProjectListDto with _$ProjectListDto {
  const factory ProjectListDto({
    @Default(<ProjectDto>[]) List<ProjectDto> items,
  }) = _ProjectListDto;

  factory ProjectListDto.fromJson(Map<String, dynamic> json) =>
      _$ProjectListDtoFromJson(json);
}

@freezed
abstract class SecretKeyListDto with _$SecretKeyListDto {
  const factory SecretKeyListDto({
    @Default(<SecretKeyDto>[]) List<SecretKeyDto> items,
  }) = _SecretKeyListDto;

  factory SecretKeyListDto.fromJson(Map<String, dynamic> json) =>
      _$SecretKeyListDtoFromJson(json);
}

@freezed
abstract class TeamListDto with _$TeamListDto {
  const factory TeamListDto({@Default(<TeamDto>[]) List<TeamDto> items}) =
      _TeamListDto;

  factory TeamListDto.fromJson(Map<String, dynamic> json) =>
      _$TeamListDtoFromJson(json);
}

@freezed
abstract class TeamMemberListDto with _$TeamMemberListDto {
  const factory TeamMemberListDto({
    @Default(<TeamMemberDto>[]) List<TeamMemberDto> items,
  }) = _TeamMemberListDto;

  factory TeamMemberListDto.fromJson(Map<String, dynamic> json) =>
      _$TeamMemberListDtoFromJson(json);
}
