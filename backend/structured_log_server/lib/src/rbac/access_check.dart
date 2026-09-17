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

/// Whether [roles] may list the role-assignment table without a
/// `scope_type`+`scope_id` filter — a bare `subject_id` filter or no filter
/// at all (the Edit User dialog, "grants held by this user"): `admin` only,
/// unconditionally. Reading a specific scope's own list has a wider rule,
/// [canReadRoleAssignmentsForScope]; *creating*/*revoking* one has a wider
/// rule too, [canCreateOrRevokeRoleAssignment] — this function no longer
/// gates those (Этап 4, 4.3).
bool canManageRoleAssignments(List<EffectiveRole> roles) =>
    isGlobalAdmin(roles);

/// Whether [roles] may create or revoke a `RoleAssignment` with
/// `role: targetRole` on ([scopeType], [scopeId]) — the full rule
/// (`design.md` "Delivery Phases", Этап 4, 4.3; `specs/log-server-rbac`,
/// requirement «Правила выдачи и отзыва ролей ограничены ролью и областью
/// выдающего», specified from the very first pass): `admin` without
/// restriction; `owner` of group `G` only for `targetRole ∈ {owner, user}`
/// on `scope ∈ {group:G, project ∈ G}`; `user` never. [enclosingGroupId] is
/// required to authorize a `project` scope, the same convention as
/// [canRead]/[canWrite].
///
/// [scopeId] is `null` only for `scopeType: ScopeType.global` — an `owner`
/// never qualifies there, since a `group`-scoped `EffectiveRole` cannot
/// cover the global scope (`_covers` has no case that does).
bool canCreateOrRevokeRoleAssignment(
  List<EffectiveRole> roles, {
  required Role targetRole,
  required ScopeType scopeType,
  int? scopeId,
  int? enclosingGroupId,
}) {
  if (isGlobalAdmin(roles)) return true;
  if (targetRole != Role.owner && targetRole != Role.user) return false;
  return roles.any((r) {
    if (r.role != Role.owner || r.scopeType != ScopeType.group) return false;
    return switch (scopeType) {
      ScopeType.group => r.scopeId == scopeId,
      ScopeType.project => r.scopeId == enclosingGroupId,
      ScopeType.global => false,
    };
  });
}

/// Whether [roles] may *read* the role-assignment list for the group/project
/// at ([scopeType], [scopeId]) — the «Доступ» section on
/// `GroupDetailPage`/`ProjectDetailPage` (уточнение 17.09.2026): `admin`
/// unconditionally, or the `owner` of that specific scope. Separate from
/// [canManageRoleAssignments] on purpose — an owner may now see who else
/// has a role on their own group/project without being able to grant or
/// revoke one (4.3a keeps that `admin`-only) — even though today the boolean
/// it computes happens to equal [canWrite]'s.
bool canReadRoleAssignmentsForScope(
  List<EffectiveRole> roles, {
  required ScopeType scopeType,
  required int scopeId,
  int? enclosingGroupId,
}) =>
    canWrite(
      roles,
      targetType: scopeType,
      targetId: scopeId,
      enclosingGroupId: enclosingGroupId,
    );

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
