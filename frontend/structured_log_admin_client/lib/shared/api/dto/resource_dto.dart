import 'package:freezed_annotation/freezed_annotation.dart';

part 'resource_dto.freezed.dart';
part 'resource_dto.g.dart';

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
