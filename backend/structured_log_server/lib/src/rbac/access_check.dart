import '../auth/identity_provider.dart';
import 'authorizer.dart';

/// The effective roles to authorize a request with: the JWT's own snapshot
/// when the `IdentityProvider` supplied one, otherwise resolved fresh from
/// storage (`log-server-auth`/`log-server-rbac` — the fallback path for an
/// `IdentityProvider` implementation that returns `VerifiedIdentity.roles:
/// null`, `design.md` decision 10).
Future<List<EffectiveRole>> resolveRoles(
  Authorizer authorizer,
  VerifiedIdentity identity,
) {
  final roles = identity.roles;
  if (roles != null) return Future.value(roles);
  return authorizer.effectiveRoles(identity.userId);
}

bool isGlobalAdmin(List<EffectiveRole> roles) {
  return roles.any(
    (r) => r.role == Role.admin && r.scopeType == ScopeType.global,
  );
}

bool _covers(
  EffectiveRole role, {
  required ScopeType targetType,
  required int targetId,
  int? enclosingGroupId,
}) {
  switch (role.scopeType) {
    case ScopeType.global:
      return true;
    case ScopeType.group:
      if (targetType == ScopeType.group) return role.scopeId == targetId;
      if (targetType == ScopeType.project) {
        return role.scopeId == enclosingGroupId;
      }
      return false;
    case ScopeType.project:
      return targetType == ScopeType.project && role.scopeId == targetId;
  }
}

/// Whether [roles] grants read access (`admin`/`owner`/`user`, any of the
/// three) to the resource at ([targetType], [targetId]) — [enclosingGroupId]
/// is required when [targetType] is `ScopeType.project`, so a group-scoped
/// grant on that project's group is recognized too (`log-server-rbac`:
/// "грант на уровне группы покрывает... проекты").
bool canRead(
  List<EffectiveRole> roles, {
  required ScopeType targetType,
  required int targetId,
  int? enclosingGroupId,
}) {
  return roles.any(
    (r) => _covers(
      r,
      targetType: targetType,
      targetId: targetId,
      enclosingGroupId: enclosingGroupId,
    ),
  );
}

/// Whether [roles] may create/revoke a `RoleAssignment`, in this stage's
/// reduced scope (`design.md` "Delivery Phases", Этап 3, 4.3a): only
/// `admin`, unconditionally.
///
/// The full rule (4.3) — an `owner` granting `owner`/`user` within their own
/// group — needs an existing group with an `owner` before it can grant
/// anything in it, which is circular for the group a bootstrap admin hasn't
/// delegated yet; it belongs to the stage that also adds `subject_type:
/// team`, not this one.
bool canManageRoleAssignments(List<EffectiveRole> roles) =>
    isGlobalAdmin(roles);

/// Whether [roles] grants write access (`admin`/`owner` only, not `user`)
/// to the resource at ([targetType], [targetId]).
bool canWrite(
  List<EffectiveRole> roles, {
  required ScopeType targetType,
  required int targetId,
  int? enclosingGroupId,
}) {
  return roles.any(
    (r) =>
        (r.role == Role.admin || r.role == Role.owner) &&
        _covers(
          r,
          targetType: targetType,
          targetId: targetId,
          enclosingGroupId: enclosingGroupId,
        ),
  );
}
