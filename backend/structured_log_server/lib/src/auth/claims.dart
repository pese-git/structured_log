import '../rbac/authorizer.dart';
import '../storage/database.dart';
import 'identity_provider.dart';

/// The `roles`/`tv` snapshot embedded in a freshly issued access token
/// (`log-server-auth`). Both `grant_type=password` and
/// `grant_type=refresh_token` resolve this fresh on every issuance — never
/// copied forward from a previous token — so a client that refreshes after
/// a 401 immediately sees its current rights (`design.md` decision 10).
class TokenClaims {
  final List<EffectiveRole> roles;
  final int tokenVersion;

  const TokenClaims({required this.roles, required this.tokenVersion});
}

class ClaimsResolver {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;

  ClaimsResolver(this._db, this._authorizer);

  /// Resolves [userId]'s current effective roles and `token_version`. The
  /// caller (token issuance) is expected to have already confirmed
  /// [userId] exists.
  Future<TokenClaims> resolve(int userId) async {
    final roles = await _authorizer.effectiveRoles(userId);
    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(userId)))
        .getSingle();
    return TokenClaims(roles: roles, tokenVersion: user.tokenVersion);
  }
}
