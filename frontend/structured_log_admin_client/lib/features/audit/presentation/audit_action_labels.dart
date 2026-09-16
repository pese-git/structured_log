import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/audit_dto.dart';

/// What each action is called in Russian, and how loudly it should read.
///
/// **The table shows the wire value, not this name** — `AuditLog.dc.html` draws
/// `project.blocked` in the tag, and that is deliberate rather than an
/// oversight: it is the string the reader filters by, the string the API
/// documents, and the string they will quote in an incident report. A journal
/// whose displayed vocabulary differs from its queryable one makes those three
/// things three different conversations.
///
/// The Russian name is what the filter menu offers and what the tag says on
/// hover, because a menu of twenty-five identifiers is not scannable.
///
/// Both switches are exhaustive over [AuditAction], which is the point: adding
/// an action to the client's copy of the server's set without deciding what it
/// is called and how alarming it looks does not compile.
String auditActionLabel(AuditAction action) => switch (action) {
  AuditAction.userCreated => 'Пользователь создан',
  AuditAction.userUpdated => 'Пользователь изменён',
  AuditAction.userBlocked => 'Пользователь заблокирован',
  AuditAction.userUnblocked => 'Пользователь разблокирован',
  AuditAction.userDeleted => 'Пользователь удалён',
  AuditAction.groupCreated => 'Группа создана',
  AuditAction.teamCreated => 'Команда создана',
  AuditAction.teamMemberAdded => 'Участник добавлен в команду',
  AuditAction.teamMemberRemoved => 'Участник исключён из команды',
  AuditAction.projectCreated => 'Проект создан',
  AuditAction.projectQuotaUpdated => 'Квота проекта изменена',
  AuditAction.projectBlocked => 'Проект заблокирован',
  AuditAction.projectUnblocked => 'Проект разблокирован',
  AuditAction.secretKeyCreated => 'Секретный ключ создан',
  AuditAction.secretKeyRevoked => 'Секретный ключ отозван',
  AuditAction.roleAssignmentCreated => 'Роль выдана',
  AuditAction.roleAssignmentRevoked => 'Роль отозвана',
  AuditAction.passwordChanged => 'Пароль изменён',
  AuditAction.passwordResetConfirmed => 'Пароль восстановлен',
  AuditAction.emailVerified => 'Email подтверждён',
  AuditAction.authLoginSucceeded => 'Вход выполнен',
  AuditAction.authLoginFailed => 'Неудачная попытка входа',
  AuditAction.authLoggedOut => 'Выход',
  AuditAction.authThrottled => 'Запросы ограничены',
  AuditAction.auditPurged => 'Очистка аудита',
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
String auditTargetTypeLabel(AuditTargetType type) => switch (type) {
  AuditTargetType.user => 'пользователь',
  AuditTargetType.group => 'группа',
  AuditTargetType.team => 'команда',
  AuditTargetType.project => 'проект',
  AuditTargetType.secretKey => 'ключ',
  AuditTargetType.roleAssignment => 'назначение роли',
  AuditTargetType.auth => 'аутентификация',
  AuditTargetType.audit => 'аудит',
};

/// The target cell: what was acted on, as far as this client can tell.
///
/// Only the type and the id travel in a record — there is no endpoint that
/// resolves either to a name in this stage — so the cell says `проект #7` and
/// not `проект: staging-sandbox` as the artboard draws it. Showing the id is
/// honest; inventing a lookup for it would not be, and guessing a name from a
/// list the reader may not be allowed to see would be worse.
String auditTargetText(AuditEntryDto entry) {
  final type = AuditTargetType.fromWire(entry.targetType);
  final name = type == null ? entry.targetType : auditTargetTypeLabel(type);
  return entry.targetId == null ? name : '$name #${entry.targetId}';
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
({String text, bool absent}) auditActorText(AuditEntryDto entry) {
  final actorUserId = entry.actorUserId;
  if (actorUserId != null) return (text: '#$actorUserId', absent: false);

  if (entry.metadata['unknown_user'] == true) {
    return (text: 'учётной записи не существует', absent: true);
  }
  return (text: 'сервер', absent: true);
}
