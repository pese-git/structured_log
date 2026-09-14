import 'package:shelf/shelf.dart';

import '../auth/hashing.dart';
import '../storage/database.dart';
import 'json_response.dart';

const _contextKey = 'structured_log_server.authenticatedProjectId';

/// Reads the project id [projectKeyMiddleware] resolved for this request.
/// Only meaningful downstream of that middleware.
extension AuthenticatedProjectRequest on Request {
  int get authenticatedProjectId => context[_contextKey]! as int;
}

/// Project-secret-key auth middleware for `POST /v1/logs`
/// (`log-server-auth`): resolves `Authorization: Bearer <project-secret-key>`
/// to a `project_id` via `project_secret_keys`, returning 401 for a missing
/// header or a key that doesn't match/is revoked — a separate, simpler path
/// from [authMiddleware]'s JWT verification, not through [IdentityProvider].
Middleware projectKeyMiddleware(StructuredLogDatabase db) {
  return (Handler innerHandler) {
    return (Request request) async {
      final header = request.headers['authorization'];
      const prefix = 'Bearer ';
      if (header == null || !header.startsWith(prefix)) {
        return jsonError(401, 'unauthorized', 'Missing project secret key.');
      }

      final hash = hashToken(header.substring(prefix.length));
      final key = await (db.select(
        db.projectSecretKeys,
      )..where((t) => t.keyHash.equals(hash)))
          .getSingleOrNull();

      if (key == null || key.revokedAt != null) {
        return jsonError(
          401,
          'unauthorized',
          'Invalid or revoked project secret key.',
        );
      }

      return innerHandler(
        request.change(context: {_contextKey: key.projectId}),
      );
    };
  };
}
