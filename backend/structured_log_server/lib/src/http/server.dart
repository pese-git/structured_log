import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/claims.dart';
import '../auth/local_identity_provider.dart';
import '../auth/token_service.dart';
import '../errors.dart';
import '../rbac/authorizer.dart';
import '../storage/database.dart';
import '../storage/log_store.dart';
import 'auth_middleware.dart';
import 'must_change_password_middleware.dart';
import 'project_key_middleware.dart';
import 'routes/auth_route.dart';
import 'routes/change_password_route.dart';
import 'routes/groups_route.dart';
import 'routes/logs_route.dart';
import 'routes/projects_route.dart';
import 'routes/secret_keys_route.dart';

/// Builds the full `shelf` [Handler] for the server: every route this
/// Stage 1 slice implements, each wrapped with the auth middleware its own
/// scheme requires (`log-server-auth`'s two independent auth paths — JWT
/// bearer for management/query endpoints, project secret key for
/// ingestion — can't share one blanket [Pipeline] middleware since they
/// apply to different routes, including different methods on the same
/// path: `GET /v1/logs` vs. `POST /v1/logs`).
Handler buildHandler(
  StructuredLogDatabase db, {
  required String signingSecret,
  required String issuer,
}) {
  final authorizer = Authorizer(db);
  final claimsResolver = ClaimsResolver(db, authorizer);
  final tokenService = TokenService(
    db,
    claimsResolver,
    signingSecret: signingSecret,
    issuer: issuer,
  );
  final identityProvider = LocalIdentityProvider(
    db,
    signingSecret: signingSecret,
    issuer: issuer,
  );
  final logStore = DriftLogStore(db);
  final jwtAuth = authMiddleware(identityProvider);
  final passwordChangeGate = mustChangePasswordMiddleware();
  // Every JWT route except change-password itself sits behind both auth
  // and the forced-password-change gate — a temporary password must not
  // unlock anything else first (log-server-forced-password-change).
  Handler jwtAuthGated(Handler handler) => jwtAuth(passwordChangeGate(handler));
  final projectKeyAuth = projectKeyMiddleware(db);

  final router = Router()
    // Auth — no per-route middleware; TokenService checks its own
    // credentials/tokens (log-server-auth).
    ..post('/v1/auth/token', (req) => issueToken(tokenService, req))
    ..delete('/v1/auth/token', (req) => revokeToken(tokenService, req))
    // Allowed even with a temporary password — it's how you clear the flag.
    ..post(
      '/v1/auth/change-password',
      jwtAuth((req) => changePassword(db, req)),
    )
    // Log ingestion (project secret key) / query (JWT) — same paths,
    // different methods, different auth schemes.
    ..post(
      '/v1/logs',
      projectKeyAuth((req) => ingestLogs(db, logStore, req)),
    )
    ..get(
      '/v1/logs',
      jwtAuthGated((req) => queryLogs(db, authorizer, logStore, req)),
    )
    // Management API (JWT).
    ..post(
      '/v1/groups',
      jwtAuthGated((req) => createGroup(db, authorizer, req)),
    )
    ..get(
      '/v1/groups',
      jwtAuthGated((req) => listGroups(db, authorizer, req)),
    )
    ..post(
      '/v1/groups/<groupId>/projects',
      jwtAuthGated((req) => createProject(db, authorizer, req)),
    )
    ..patch(
      '/v1/projects/<id>',
      jwtAuthGated((req) => updateProjectQuota(db, authorizer, req)),
    )
    ..get(
      '/v1/projects/<id>',
      jwtAuthGated((req) => getProject(db, authorizer, req)),
    )
    ..post(
      '/v1/projects/<id>/secret-keys',
      jwtAuthGated((req) => createSecretKey(db, authorizer, req)),
    )
    ..get(
      '/v1/projects/<id>/secret-keys',
      jwtAuthGated((req) => listSecretKeys(db, authorizer, req)),
    )
    ..delete(
      '/v1/projects/<id>/secret-keys/<keyId>',
      jwtAuthGated((req) => revokeSecretKey(db, authorizer, req)),
    )
    // Health — no authentication.
    ..get('/healthz', healthCheck);

  return const Pipeline()
      .addMiddleware(errorHandlingMiddleware())
      .addHandler(router.call);
}
