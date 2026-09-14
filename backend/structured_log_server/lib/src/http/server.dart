import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/claims.dart';
import '../auth/local_identity_provider.dart';
import '../auth/token_service.dart';
import '../errors.dart';
import '../rbac/authorizer.dart';
import '../storage/database.dart';
import '../storage/log_store.dart';
import 'principal_middleware.dart';
import 'routes/auth_route.dart';
import 'routes/change_password_route.dart';
import 'routes/groups_route.dart';
import 'routes/logs_route.dart';
import 'routes/projects_route.dart';
import 'routes/secret_keys_route.dart';

/// Builds the full `shelf` [Handler] for the server.
///
/// Authentication is one [Pipeline] stage, not a per-route wrapper:
/// [principalMiddleware] resolves the `Authorization: Bearer <...>` header
/// every scheme shares into a `Principal` and hands the request on without
/// judging it (`log-server-auth`). Each handler then states what it needs —
/// `request.requireUser()` or `request.requireProject()` — which is what makes
/// the two schemes able to share `/v1/logs`, where `GET` wants an access token
/// and `POST` wants a project secret key.
///
/// So the route table below says only "method + path → handler". What guards
/// what is no longer visible here; `test/http/route_auth_matrix_test.dart`
/// enumerates every route and asserts it rejects the wrong principal, and any
/// route added without a `require*` call fails it.
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

  final router = Router()
    // Auth — public; TokenService checks its own credentials/tokens.
    ..post('/v1/auth/token', (req) => issueToken(tokenService, req))
    ..delete('/v1/auth/token', (req) => revokeToken(tokenService, req))
    ..post('/v1/auth/change-password', (req) => changePassword(db, req))
    // Log ingestion (project secret key) / query (access token) — same path,
    // different methods, different principals.
    ..post('/v1/logs', (req) => ingestLogs(db, logStore, req))
    ..get('/v1/logs', (req) => queryLogs(db, authorizer, logStore, req))
    // Management API.
    ..post('/v1/groups', (req) => createGroup(db, authorizer, req))
    ..get('/v1/groups', (req) => listGroups(db, authorizer, req))
    ..post(
      '/v1/groups/<groupId>/projects',
      (req) => createProject(db, authorizer, req),
    )
    ..patch(
      '/v1/projects/<id>',
      (req) => updateProjectQuota(db, authorizer, req),
    )
    ..get('/v1/projects/<id>', (req) => getProject(db, authorizer, req))
    ..post(
      '/v1/projects/<id>/secret-keys',
      (req) => createSecretKey(db, authorizer, req),
    )
    ..get(
      '/v1/projects/<id>/secret-keys',
      (req) => listSecretKeys(db, authorizer, req),
    )
    ..delete(
      '/v1/projects/<id>/secret-keys/<keyId>',
      (req) => revokeSecretKey(db, authorizer, req),
    )
    // Health — public.
    ..get('/healthz', healthCheck);

  return const Pipeline()
      .addMiddleware(errorHandlingMiddleware())
      .addMiddleware(principalMiddleware(identityProvider, db))
      .addHandler(router.call);
}
