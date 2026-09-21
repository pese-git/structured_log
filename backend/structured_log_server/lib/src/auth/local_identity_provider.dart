import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../storage/database.dart';
import 'identity_provider.dart';

/// Verifies access tokens issued by [TokenService]
/// (`lib/src/auth/token_service.dart`) — JWT signature/expiry, then a
/// `token_version` point-lookup so already-revoked rights stop being
/// accepted immediately, even though the JWT itself is still technically
/// unexpired (`log-server-auth`).
class LocalIdentityProvider implements IdentityProvider {
  final StructuredLogDatabase _db;
  final SecretKey _signingKey;
  final String _issuer;

  LocalIdentityProvider(
    this._db, {
    required String signingSecret,
    required String issuer,
  }) : _signingKey = SecretKey(signingSecret),
       _issuer = issuer;

  @override
  Future<VerifiedIdentity?> verifyAccessToken(String bearerToken) async {
    final jwt = JWT.tryVerify(bearerToken, _signingKey, issuer: _issuer);
    if (jwt == null) return null;

    final payload = jwt.payload;
    if (payload is! Map) return null;

    final userId = int.tryParse(jwt.subject ?? '');
    final tv = payload['tv'];
    final username = payload['preferred_username'];
    final rawRoles = payload['roles'];
    if (userId == null ||
        tv is! int ||
        username is! String ||
        rawRoles is! List) {
      return null;
    }

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(userId))).getSingleOrNull();
    if (user == null || user.tokenVersion != tv) return null;

    final roles = <EffectiveRole>[];
    for (final entry in rawRoles) {
      final role = _parseRole(entry);
      // A claim this build cannot read makes the whole token unusable. Which
      // rights it was meant to carry is not something to guess at, and the
      // alternative — an exception out of a `byName` lookup — reached the
      // client as a 500 for a request that is simply unauthenticated.
      if (role == null) return null;
      roles.add(role);
    }

    return VerifiedIdentity(
      userId: userId,
      username: username,
      roles: roles,
      mustChangePassword: user.mustChangePassword,
    );
  }

  /// One `roles` claim entry, or `null` if it is not a shape this build issues:
  /// not a map, an unknown role or scope type (a name removed or renamed in
  /// another release), or a scope id that is not an integer.
  static EffectiveRole? _parseRole(Object? entry) {
    if (entry is! Map) return null;
    final role = entry['role'];
    final scopeType = entry['scope_type'];
    final scopeId = entry['scope_id'];
    if (role is! String || scopeType is! String) return null;
    if (scopeId != null && scopeId is! int) return null;

    final parsedRole = Role.values.asNameMap()[role];
    final parsedScope = ScopeType.values.asNameMap()[scopeType];
    if (parsedRole == null || parsedScope == null) return null;
    return EffectiveRole(
      role: parsedRole,
      scopeType: parsedScope,
      scopeId: scopeId as int?,
    );
  }
}
