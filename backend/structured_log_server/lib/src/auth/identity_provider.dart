/// One effective right a user holds — either granted to them directly, or
/// inherited through membership in a team that was granted it
/// (`log-server-rbac`). `scopeId` is `null` exactly when `scopeType` is
/// `ScopeType.global`.
class EffectiveRole {
  final Role role;
  final ScopeType scopeType;
  final int? scopeId;

  const EffectiveRole({
    required this.role,
    required this.scopeType,
    this.scopeId,
  }) : assert(
          (scopeType == ScopeType.global) == (scopeId == null),
          'scopeId must be null iff scopeType is global',
        );

  @override
  bool operator ==(Object other) =>
      other is EffectiveRole &&
      other.role == role &&
      other.scopeType == scopeType &&
      other.scopeId == scopeId;

  @override
  int get hashCode => Object.hash(role, scopeType, scopeId);

  @override
  String toString() =>
      'EffectiveRole(role: $role, scopeType: $scopeType, scopeId: $scopeId)';
}

enum Role { admin, owner, user }

enum ScopeType { global, group, project }

/// The outcome of successfully verifying a bearer access token
/// (`IdentityProvider.verifyAccessToken`).
///
/// [roles] is the effective-rights snapshot the token itself carries, if
/// its issuer embeds one (`log-server-auth` — the local, JWT-based
/// provider always does). When `null`, authorization middleware resolves
/// effective roles from storage instead (`log-server-rbac`) rather than
/// requiring every `IdentityProvider` implementation to supply its own.
class VerifiedIdentity {
  final int userId;
  final String username;
  final List<EffectiveRole>? roles;

  const VerifiedIdentity({
    required this.userId,
    required this.username,
    this.roles,
  });
}

/// Verifies a bearer access token without committing callers to any one
/// token format or issuance mechanism — the built-in implementation is
/// JWT-based (`LocalIdentityProvider`), but this boundary lets it be
/// swapped for an external OIDC provider without changing RBAC/HTTP code
/// (`design.md`).
abstract class IdentityProvider {
  /// Returns the verified identity for [bearerToken], or `null` if it is
  /// missing, malformed, expired, or otherwise no longer valid.
  Future<VerifiedIdentity?> verifyAccessToken(String bearerToken);
}
