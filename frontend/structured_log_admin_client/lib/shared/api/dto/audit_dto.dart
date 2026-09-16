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

/// The closed set of actions the server records (`specs/log-server-audit`).
///
/// A copy of the server's own enum, down to the member names, and deliberately
/// a copy: this package talks to `structured_log_server` over HTTP like any
/// other consumer and shares no code with it. What keeps the two honest is that
/// the server refuses an `action` outside its set with 400 — so a value here
/// that the server does not know fails loudly on the first request rather than
/// silently matching nothing.
///
/// An enum rather than the list of strings this started as, because the screen
/// has to name each of these in Russian, and a map from strings would let a new
/// action arrive with no label and be rendered as a raw wire value. As an enum
/// the label switch is exhaustive, so adding a member here without giving it a
/// name does not compile (`presentation/audit_action_labels.dart`).
///
/// Nineteen of the twenty-five have no caller on the server yet — the endpoints
/// that perform them do not exist (`design.md` "Delivery Phases", Этап 2,
/// *Частично*). They are declared anyway, for the same reason the server
/// declares them: a set that is not whole cannot be filtered against.
enum AuditAction {
  userCreated('user.created'),
  userUpdated('user.updated'),
  userBlocked('user.blocked'),
  userUnblocked('user.unblocked'),
  userDeleted('user.deleted'),

  groupCreated('group.created'),
  teamCreated('team.created'),
  teamMemberAdded('team.member_added'),
  teamMemberRemoved('team.member_removed'),
  projectCreated('project.created'),
  projectQuotaUpdated('project.quota_updated'),
  projectBlocked('project.blocked'),
  projectUnblocked('project.unblocked'),
  secretKeyCreated('secret_key.created'),
  secretKeyRevoked('secret_key.revoked'),
  roleAssignmentCreated('role_assignment.created'),
  roleAssignmentRevoked('role_assignment.revoked'),

  passwordChanged('password.changed'),
  passwordResetConfirmed('password.reset_confirmed'),
  emailVerified('email.verified'),

  authLoginSucceeded('auth.login_succeeded'),
  authLoginFailed('auth.login_failed'),
  authLoggedOut('auth.logged_out'),
  authThrottled('auth.throttled'),

  auditPurged('audit.purged');

  const AuditAction(this.wire);

  /// What travels in `action`, spelled out rather than derived from the member
  /// name — exactly as the server spells it.
  final String wire;

  /// The four the server keeps under its own, shorter retention period, and the
  /// ones a reader most often wants to see apart from administrative acts.
  bool get isAuthEvent =>
      this == authLoginSucceeded ||
      this == authLoginFailed ||
      this == authLoggedOut ||
      this == authThrottled;

  /// The action a record names, or `null` if this build does not know the
  /// value.
  ///
  /// `null` rather than a throw, for the same reason the server returns null: a
  /// record can come from a newer server than this bundle was built against,
  /// and a reader that crashes on one unfamiliar row is worse at its job than
  /// one that shows the rest. The screen renders such a record with its raw
  /// wire value — an audit log may not hide a record it fails to recognise.
  static AuditAction? fromWire(String wire) {
    for (final action in AuditAction.values) {
      if (action.wire == wire) return action;
    }
    return null;
  }
}

/// What an audit record points at — the server's `target_type`, which is
/// `NOT NULL` for every record, including the ones with no resource behind
/// them.
///
/// A copy of the server's enum, for the same reason and with the same caveat as
/// [AuditAction]: it is the filter menu's vocabulary, and a value this build
/// does not know comes back as `null` rather than as a crash.
enum AuditTargetType {
  user('user'),
  group('group'),
  team('team'),
  project('project'),
  secretKey('secret_key'),
  roleAssignment('role_assignment'),

  /// A throttled request: what was refused is the endpoint, not a resource.
  auth('auth'),

  /// A purge pass, naming the journal it trimmed.
  audit('audit');

  const AuditTargetType(this.wire);

  final String wire;

  static AuditTargetType? fromWire(String wire) {
    for (final type in AuditTargetType.values) {
      if (type.wire == wire) return type;
    }
    return null;
  }
}
