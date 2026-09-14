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
  })  : _signingKey = SecretKey(signingSecret),
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
    )..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null || user.tokenVersion != tv) return null;

    final roles = <EffectiveRole>[];
    for (final entry in rawRoles) {
      if (entry is! Map) return null;
      final role = Role.values.byName(entry['role'] as String);
      final scopeType = ScopeType.values.byName(entry['scope_type'] as String);
      roles.add(
        EffectiveRole(
          role: role,
          scopeType: scopeType,
          scopeId: entry['scope_id'] as int?,
        ),
      );
    }

    return VerifiedIdentity(
      userId: userId,
      username: username,
      roles: roles,
      mustChangePassword: user.mustChangePassword,
    );
  }
}
