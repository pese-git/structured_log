import 'package:shelf/shelf.dart';

import '../auth/identity_provider.dart';
import 'json_response.dart';

const _contextKey = 'structured_log_server.verifiedIdentity';

/// Reads the [VerifiedIdentity] [authMiddleware] attached to this request.
/// Only meaningful downstream of that middleware — every route it wraps is
/// guaranteed to have one (the middleware itself returns 401 otherwise).
extension VerifiedIdentityRequest on Request {
  VerifiedIdentity get verifiedIdentity =>
      context[_contextKey]! as VerifiedIdentity;
}

/// JWT bearer-auth middleware for management endpoints and `GET /v1/logs`
/// (`log-server-auth`): verifies `Authorization: Bearer <access-token>`
/// through [provider], returning 401 for a missing header or an invalid/
/// expired/revoked token before the wrapped handler ever runs.
Middleware authMiddleware(IdentityProvider provider) {
  return (Handler innerHandler) {
    return (Request request) async {
      final header = request.headers['authorization'];
      const prefix = 'Bearer ';
      if (header == null || !header.startsWith(prefix)) {
        return jsonError(401, 'unauthorized', 'Missing bearer access token.');
      }

      final identity = await provider.verifyAccessToken(
        header.substring(prefix.length),
      );
      if (identity == null) {
        return jsonError(
          401,
          'unauthorized',
          'Invalid, expired, or revoked access token.',
        );
      }

      return innerHandler(
        request.change(context: {_contextKey: identity}),
      );
    };
  };
}
