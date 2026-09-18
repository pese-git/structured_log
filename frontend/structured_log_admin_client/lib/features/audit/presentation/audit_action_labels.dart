import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/audit_dto.dart';

/// What each action is called in the interface language, and how loudly it should read.
///
/// **The table shows the wire value, not this name** — `AuditLog.dc.html` draws
/// `project.blocked` in the tag, and that is deliberate rather than an
/// oversight: it is the string the reader filters by, the string the API
/// documents, and the string they will quote in an incident report. A journal
/// whose displayed vocabulary differs from its queryable one makes those three
/// things three different conversations.
///
/// The localized name is what the filter menu offers and what the tag says on
/// hover, because a menu of twenty-five identifiers is not scannable.
///
/// Both switches are exhaustive over [AuditAction], which is the point: adding
/// an action to the client's copy of the server's set without deciding what it
/// is called and how alarming it looks does not compile.
String auditActionLabel(
  AppLocalizations l10n,
  AuditAction action,
) => switch (action) {
  AuditAction.userCreated => l10n.auditActionUserCreated,
  AuditAction.userUpdated => l10n.auditActionUserUpdated,
  AuditAction.userBlocked => l10n.auditActionUserBlocked,
  AuditAction.userUnblocked => l10n.auditActionUserUnblocked,
  AuditAction.userDeleted => l10n.auditActionUserDeleted,
  AuditAction.groupCreated => l10n.auditActionGroupCreated,
  AuditAction.teamCreated => l10n.auditActionTeamCreated,
  AuditAction.teamMemberAdded => l10n.auditActionTeamMemberAdded,
  AuditAction.teamMemberRemoved => l10n.auditActionTeamMemberRemoved,
  AuditAction.projectCreated => l10n.auditActionProjectCreated,
  AuditAction.projectQuotaUpdated => l10n.auditActionProjectQuotaUpdated,
  AuditAction.projectBlocked => l10n.auditActionProjectBlocked,
  AuditAction.projectUnblocked => l10n.auditActionProjectUnblocked,
  AuditAction.secretKeyCreated => l10n.auditActionSecretKeyCreated,
  AuditAction.secretKeyRevoked => l10n.auditActionSecretKeyRevoked,
  AuditAction.roleAssignmentCreated => l10n.auditActionRoleAssignmentCreated,
  AuditAction.roleAssignmentRevoked => l10n.auditActionRoleAssignmentRevoked,
  AuditAction.passwordChanged => l10n.auditActionPasswordChanged,
  AuditAction.passwordResetConfirmed => l10n.auditActionPasswordResetConfirmed,
  AuditAction.emailVerified => l10n.auditActionEmailVerified,
  AuditAction.authLoginSucceeded => l10n.auditActionAuthLoginSucceeded,
  AuditAction.authLoginFailed => l10n.auditActionAuthLoginFailed,
  AuditAction.authLoggedOut => l10n.auditActionAuthLoggedOut,
  AuditAction.authThrottled => l10n.auditActionAuthThrottled,
  AuditAction.auditPurged => l10n.auditActionAuditPurged,
};

/// How the tag is coloured.
///
/// Taken from the artboard where it draws one, and decided here where it does
/// not. The rule is what the record means to someone scanning the column, not
/// whether the verb sounds destructive: losing access reads red, regaining it
/// green, and everything an administrator does in the course of the day stays
/// quiet so that the red ones are visible at all.
AdminStatusTone auditActionTone(AuditAction action) => switch (action) {
  AuditAction.userBlocked ||
  AuditAction.userDeleted ||
  AuditAction.projectBlocked ||
  AuditAction.secretKeyRevoked ||
  AuditAction.authLoginFailed => AdminStatusTone.error,

  AuditAction.userUnblocked ||
  AuditAction.projectUnblocked => AdminStatusTone.success,

  // Not a refusal and not an act — the server saying it stopped answering.
  AuditAction.authThrottled => AdminStatusTone.warning,

  AuditAction.userCreated ||
  AuditAction.userUpdated ||
  AuditAction.groupCreated ||
  AuditAction.teamCreated ||
  AuditAction.teamMemberAdded ||
  AuditAction.teamMemberRemoved ||
  AuditAction.projectCreated ||
  AuditAction.projectQuotaUpdated ||
  AuditAction.secretKeyCreated ||
  AuditAction.roleAssignmentCreated ||
  AuditAction.roleAssignmentRevoked ||
  AuditAction.passwordChanged ||
  AuditAction.passwordResetConfirmed ||
  AuditAction.emailVerified ||
  AuditAction.authLoginSucceeded ||
  AuditAction.authLoggedOut ||
  AuditAction.auditPurged => AdminStatusTone.neutral,
};

/// What each kind of target is called.
String auditTargetTypeLabel(AppLocalizations l10n, AuditTargetType type) =>
    switch (type) {
      AuditTargetType.user => l10n.auditTargetUser,
      AuditTargetType.group => l10n.auditTargetGroup,
      AuditTargetType.team => l10n.auditTargetTeam,
      AuditTargetType.project => l10n.auditTargetProject,
      AuditTargetType.secretKey => l10n.auditTargetSecretKey,
      AuditTargetType.roleAssignment => l10n.auditTargetRoleAssignment,
      AuditTargetType.auth => l10n.auditTargetAuth,
      AuditTargetType.audit => l10n.auditTargetAudit,
    };

/// The target cell: what was acted on, as far as this client can tell.
///
/// Only the type and the id travel in a record — there is no endpoint that
/// resolves either to a name in this stage — so the cell says `проект #7` and
/// not `проект: staging-sandbox` as the artboard draws it. Showing the id is
/// honest; inventing a lookup for it would not be, and guessing a name from a
/// list the reader may not be allowed to see would be worse.
String auditTargetText(AppLocalizations l10n, AuditEntryDto entry) {
  final type = AuditTargetType.fromWire(entry.targetType);
  final name = type == null
      ? entry.targetType
      : auditTargetTypeLabel(l10n, type);
  final targetId = entry.targetId;
  return targetId == null ? name : l10n.auditTargetWithId(name, targetId);
}

/// Who acted, in words.
///
/// A record with no actor is not a record with a missing field: a login attempt
/// under a username that does not exist, a throttled request and the server's
/// own purge pass genuinely have nobody behind them. Each says so, and **no
/// request goes out to resolve a name** — there is no account to resolve
/// (`specs/admin-client-audit-log`).
///
/// A real actor is shown by id for the same reason the target is: this stage
/// has no endpoint that turns a user id into a name.
({String text, bool absent}) auditActorText(
  AppLocalizations l10n,
  AuditEntryDto entry,
) {
  final actorUserId = entry.actorUserId;
  if (actorUserId != null) return (text: '#$actorUserId', absent: false);

  if (entry.metadata['unknown_user'] == true) {
    return (text: l10n.auditActorUnknownUser, absent: true);
  }
  return (text: l10n.auditActorServer, absent: true);
}
