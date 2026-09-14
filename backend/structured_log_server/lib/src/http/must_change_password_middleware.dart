import 'package:shelf/shelf.dart';

import 'auth_middleware.dart';
import 'json_response.dart';

/// Gates every JWT-authenticated route except `POST /v1/auth/change-password`
/// while `VerifiedIdentity.mustChangePassword` is set
/// (`log-server-forced-password-change`). Applied downstream of
/// [authMiddleware] (`request.verifiedIdentity` must already be set) and
/// upstream of a route's own authorization check — a temporary password
/// blocks everything, not just the "wrong role" case.
///
/// `DELETE /v1/users/me`, `POST /v1/auth/token` (`grant_type=refresh_token`),
/// and `DELETE /v1/auth/token` are the spec's other allowed exceptions —
/// none of them sit behind this middleware in the first place (self-
/// deletion isn't in Stage 1; the token endpoints aren't JWT-authenticated
/// routes at all), so there is nothing further to exempt here.
Middleware mustChangePasswordMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.verifiedIdentity.mustChangePassword) {
        return jsonError(
          403,
          'must_change_password',
          'This account must change its password before continuing.',
        );
      }
      return innerHandler(request);
    };
  };
}
