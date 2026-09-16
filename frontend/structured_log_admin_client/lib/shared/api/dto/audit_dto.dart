import 'package:freezed_annotation/freezed_annotation.dart';

part 'audit_dto.freezed.dart';
part 'audit_dto.g.dart';

/// One audit record as `GET /v1/audit-log` returns it.
///
/// Generated, unlike `LogEntryDto` next door, and the difference is worth
/// knowing: a log entry arrives with its context spread across the top level of
/// the object, so the split between an entry's own fields and the application's
/// has to be written by hand. An audit record keeps its [metadata] in a nested
/// object, so there is nothing to disentangle.
///
/// [actorUserId] is null for an event with nobody behind it — a login attempt
/// under a username that does not exist, a throttled request, the server's own
/// purge pass. That is a fact about the event rather than a missing field, and
/// the screen says so in words instead of showing an empty id.
@freezed
abstract class AuditEntryDto with _$AuditEntryDto {
  const factory AuditEntryDto({
    required int id,
    required String action,
    @JsonKey(name: 'target_type') required String targetType,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'actor_user_id') int? actorUserId,
    @JsonKey(name: 'target_id') int? targetId,

    /// Whatever the action needed a reader to know later: the halves of a
    /// quota change, the address a login came from, the reason it was refused.
    /// Free-form by design — the server writes no schema for it, and the screen
    /// renders whatever keys it finds.
    @Default(<String, dynamic>{}) Map<String, dynamic> metadata,
  }) = _AuditEntryDto;

  factory AuditEntryDto.fromJson(Map<String, dynamic> json) =>
      _$AuditEntryDtoFromJson(json);
}

/// One page of `GET /v1/audit-log`.
///
/// An envelope class, like every other collection in this API — never a bare
/// array. That was a real defect once: a list method declared as
/// `Future<List<...>>` made dio's cast throw, and the screen reported a
/// working server as unreachable (`resource_dto.dart`).
///
/// The two retention periods travel with the page rather than from an endpoint
/// of their own, because the question they answer arrives with the result: a
/// reader looking at an empty range needs to know whether it is simply outside
/// what the server keeps. `null` means no limit — records are kept
/// indefinitely, which is the default.
@freezed
abstract class AuditPageDto with _$AuditPageDto {
  const factory AuditPageDto({
    @Default(<AuditEntryDto>[]) List<AuditEntryDto> items,

    /// Pass back as `cursor` for the next, older page. `null` once there is
    /// nothing older left — the server says so rather than letting a reader
    /// discover it by asking for an empty page.
    @JsonKey(name: 'next_cursor') String? nextCursor,
    @JsonKey(name: 'audit_retention_days') int? auditRetentionDays,
    @JsonKey(name: 'auth_event_retention_days') int? authEventRetentionDays,
  }) = _AuditPageDto;

  factory AuditPageDto.fromJson(Map<String, dynamic> json) =>
      _$AuditPageDtoFromJson(json);
}
