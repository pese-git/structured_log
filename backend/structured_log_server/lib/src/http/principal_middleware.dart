import 'package:shelf/shelf.dart';

import '../auth/hashing.dart';
import '../auth/identity_provider.dart';
import '../auth/principal.dart';
import '../errors.dart';
import '../storage/database.dart';

const _contextKey = 'structured_log_server.principal';

/// The single point that reads `Authorization: Bearer <...>`
/// (`log-server-auth`). Resolves the credential into a [Principal] and always
/// calls the wrapped handler — it never answers on its own.
///
/// Rejecting here is not an option: `GET /healthz` and `POST`/`DELETE
/// /v1/auth/token` are already served without authentication, and the spec
/// adds `/v1/auth/register`, `/v1/auth/password-reset` and
/// `/v1/auth/verify-email` to that list. A rejecting middleware would have to
/// carry a list of public paths, putting routing knowledge back into the auth
/// layer — the very thing collapsing the two old per-route middlewares into
/// this one removes. Endpoints state their own requirement instead, through
/// [PrincipalRequest.requireUser] / [PrincipalRequest.requireProject].
///
/// A value carrying [projectSecretKeyPrefix] is looked up against
/// `project_secret_keys`; anything else is offered to [provider] as an access
/// token. Neither path is tried twice, so an unauthenticated flood costs at
/// most one indexed lookup *or* one signature check, never both.
Middleware principalMiddleware(
  IdentityProvider provider,
  StructuredLogDatabase db,
) {
  return (Handler innerHandler) {
    return (Request request) async {
      final principal = await _resolve(provider, db, request);
      return innerHandler(request.change(context: {_contextKey: principal}));
    };
  };
}

Future<Principal> _resolve(
  IdentityProvider provider,
  StructuredLogDatabase db,
  Request request,
) async {
  final header = request.headers['authorization'];
  const scheme = 'Bearer ';
  if (header == null || !header.startsWith(scheme)) {
    return const AnonymousPrincipal();
  }
  final token = header.substring(scheme.length);

  if (token.startsWith(projectSecretKeyPrefix)) {
    final key = await (db.select(
      db.projectSecretKeys,
    )..where((t) => t.keyHash.equals(hashToken(token)))).getSingleOrNull();
    if (key == null || key.revokedAt != null) {
      return const AnonymousPrincipal();
    }
    return ProjectPrincipal(key.projectId);
  }

  final identity = await provider.verifyAccessToken(token);
  return identity == null
      ? const AnonymousPrincipal()
      : UserPrincipal(identity);
}

/// Reads the [Principal] [principalMiddleware] resolved for this request, and
/// asserts what a handler requires of it.
///
/// The `require*` accessors are where 401 comes from now — thrown as an
/// [ApiError], rendered by `errorHandlingMiddleware`, exactly like the
/// authorization checks (`log-server-rbac`) that already live inside handlers.
extension PrincipalRequest on Request {
  /// The resolved principal, or [AnonymousPrincipal] if this request never
  /// passed through [principalMiddleware] — an unwired route must read as
  /// unauthenticated, not throw something the error envelope can't render.
  Principal get principal =>
      context[_contextKey] as Principal? ?? const AnonymousPrincipal();

  /// Requires a user access token, returning the verified identity.
  ///
  /// Throws 401 for any other principal, and 403 `must_change_password` when
  /// the account still holds a temporary password
  /// (`log-server-forced-password-change`). Set [allowTemporaryPassword] on
  /// the handful of endpoints the spec exempts — `POST
  /// /v1/auth/change-password` is the only one implemented so far; `DELETE
  /// /v1/users/me` joins it later, while the token endpoints aren't
  /// user-authenticated routes at all. The exemption sits in the handler that
  /// *is* the exception, rather than in a list of paths in another file.
  VerifiedIdentity requireUser({bool allowTemporaryPassword = false}) {
    final self = principal;
    if (self is! UserPrincipal) {
      throw ApiError.unauthorized(
        'Missing, invalid, expired, or revoked access token.',
      );
    }
    if (self.identity.mustChangePassword && !allowTemporaryPassword) {
      throw ApiError.mustChangePassword();
    }
    return self.identity;
  }

  /// Requires a project secret key, returning the project it resolved to.
  /// Throws 401 for any other principal — including a perfectly valid access
  /// token, which does not authenticate log ingestion.
  int requireProject() {
    final self = principal;
    if (self is! ProjectPrincipal) {
      throw ApiError.unauthorized(
        'Missing, invalid, or revoked project secret key.',
      );
    }
    return self.projectId;
  }
}
