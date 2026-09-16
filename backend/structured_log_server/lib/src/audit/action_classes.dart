import 'audit_action.dart';

/// Which retention period an action falls under (`design.md` decision 46).
///
/// Two classes, because they are two kinds of data. Administrative mutations
/// are few, stay valuable for years, and carry nothing but resource
/// identifiers. Authentication events are orders of magnitude more numerous,
/// are produced by unauthenticated traffic nobody here controls, and carry
/// `client_ip`/`user_agent` — personal data, for which keeping it a long time
/// is an obligation rather than an advantage. One period cannot serve both.
///
/// Only the authentication class is enumerated. The administrative class is
/// everything else, derived rather than listed, so that a new action joins a
/// class by existing rather than by someone remembering to add it to a second
/// list — and so the two lists cannot disagree, which a pair of literal sets
/// eventually does.
const authEventActions = <AuditAction>{
  AuditAction.authLoginSucceeded,
  AuditAction.authLoginFailed,
  AuditAction.authLoggedOut,
  AuditAction.authThrottled,
};

/// Whether [action] is an authentication event, and so kept for
/// `authEventRetentionDays` rather than `auditRetentionDays`.
bool isAuthEvent(AuditAction action) => authEventActions.contains(action);

/// Whether [action] is an administrative action.
///
/// The complement of [isAuthEvent] by construction. `audit.purged` lands here,
/// which is deliberate: the record of a purge is the kind of fact an operator
/// needs long after the rows it describes are gone.
bool isAdminAction(AuditAction action) => !isAuthEvent(action);

/// Whether the record MUST share a transaction with the thing it describes.
///
/// True for administrative actions: a mutation that rolled back and an audit
/// record that survived it would be a claim about something that never
/// happened (`specs/log-server-audit`). False for authentication events and for
/// the purge record — a refused login, a throttled request and a deletion pass
/// have no resource mutation to be atomic with, so requiring one would mean
/// inventing a transaction whose only member is the record itself.
bool requiresEnclosingTransaction(AuditAction action) =>
    isAdminAction(action) && action != AuditAction.auditPurged;
