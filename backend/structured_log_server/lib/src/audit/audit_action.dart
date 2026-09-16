/// Every action the audit log is allowed to record.
///
/// A closed set, and that is the whole point of it (`specs/log-server-audit`).
/// An audit log whose vocabulary is whatever string a call site happened to
/// pass cannot be filtered — `GET /v1/audit-log?action=...` only means
/// something if the reader can know what the values are — and a typo becomes a
/// record nobody will ever find again, in the one journal whose job is to still
/// be answerable years later.
///
/// **Nineteen of these twenty-five have no caller yet**, because the endpoints
/// that perform them do not exist: users, teams, role assignments, blocking,
/// password reset, email verification (`design.md` "Delivery Phases", Этап 2,
/// *Частично*). They are declared anyway. The set has to be whole from the
/// start or the two guards that key off it stop meaning anything: the
/// classification check in `action_classes.dart` can only be exhaustive over
/// what it can see, and the wire-string check can only compare a full list
/// against the spec's full list. A value with no caller is a promise about
/// naming; a value missing from the set is a hole in it.
enum AuditAction {
  // Accounts.
  userCreated('user.created'),
  userUpdated('user.updated'),
  userBlocked('user.blocked'),
  userUnblocked('user.unblocked'),
  userDeleted('user.deleted'),

  // Tenancy.
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

  // Credentials.
  passwordChanged('password.changed'),
  passwordResetConfirmed('password.reset_confirmed'),
  emailVerified('email.verified'),

  // Authentication. Their own retention period, and their own rule about
  // transactions — see `action_classes.dart`.
  authLoginSucceeded('auth.login_succeeded'),
  authLoginFailed('auth.login_failed'),
  authLoggedOut('auth.logged_out'),
  authThrottled('auth.throttled'),

  // The log accounting for its own deletions.
  auditPurged('audit.purged');

  const AuditAction(this.wire);

  /// What goes in the `action` column, and what a reader filters by. Spelled
  /// out rather than derived from the enum name: `secret_key.created` is not a
  /// mechanical transform of `secretKeyCreated` that anyone would agree on, and
  /// the column is a contract with every stored row ever written.
  final String wire;

  /// The action a stored row names, or `null` if the value is not one this
  /// server writes.
  ///
  /// `null` rather than a throw: a row can predate a rename, or arrive from a
  /// database an older build wrote, and a reader that crashes on one unfamiliar
  /// row is worse at its job than one that shows the rest.
  static AuditAction? fromWire(String wire) {
    for (final action in AuditAction.values) {
      if (action.wire == wire) return action;
    }
    return null;
  }
}

/// What an audit record points at.
///
/// `target_type` is `NOT NULL` in storage, so every action needs one — including
/// the four that have no resource to point at. The spec states the value for
/// the administrative actions and is silent for the rest, so these four are
/// decided here and written down where the code can be read:
///
/// - a login, a logout and a failed attempt name the account they were about
///   ([user]) — with a null `target_id` when the account does not exist, which
///   is the only honest answer and is not the same as having no target;
/// - a throttled request names [auth], because the thing that was refused is
///   the endpoint, not a resource — the subject may be an address rather than
///   an account;
/// - a purge pass names [audit], the journal it trimmed.
enum AuditTargetType {
  user('user'),
  group('group'),
  team('team'),
  project('project'),
  secretKey('secret_key'),
  roleAssignment('role_assignment'),
  auth('auth'),
  audit('audit');

  const AuditTargetType(this.wire);

  final String wire;
}
