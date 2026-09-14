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
/// There is no route table here: every path lives in a `@Route` annotation on
/// the handler that serves it, and `shelf_router_generator` turns each route
/// class into a `Router`. This assembles those routers and nothing else.
///
/// They are all mounted at `/` rather than on distinct prefixes, because the
/// paths don't decompose by prefix — `POST /v1/groups/<groupId>/projects`
/// belongs to [ProjectRoutes] while `/v1/groups` belongs to [GroupRoutes],
/// and `/v1/projects/<id>` is split across two classes. A mounted `Router`
/// that matches nothing returns the `Router.routeNotFound` sentinel, so the
/// outer router simply continues down the list; order carries no meaning.
///
/// Authentication is one [Pipeline] stage: [principalMiddleware] resolves the
/// `Authorization: Bearer <...>` header every scheme shares into a
/// `Principal` and hands the request on without judging it
/// (`log-server-auth`). Each handler then states what it needs —
/// `request.requireUser()` or `request.requireProject()` — which is what lets
/// `GET` and `POST /v1/logs` want different credentials, and what makes
/// mounting safe: nothing wrapping a mounted router can answer 401 before
/// that router has decided the request isn't its own.
///
/// `test/http/route_auth_matrix_test.dart` enumerates every route with the
/// principal it requires and asserts it rejects the wrong one; a route added
/// without a `require*` call fails it.
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

  final featureRouters = <Router>[
    AuthRoutes(tokenService).router,
    ChangePasswordRoutes(db).router,
    LogRoutes(db, authorizer, logStore).router,
    GroupRoutes(db, authorizer).router,
    ProjectRoutes(db, authorizer).router,
    SecretKeyRoutes(db, authorizer).router,
  ];

  final router = Router();
  for (final featureRouter in featureRouters) {
    router.mount('/', featureRouter.call);
  }

  return const Pipeline()
      .addMiddleware(errorHandlingMiddleware())
      .addMiddleware(principalMiddleware(identityProvider, db))
      .addHandler(router.call);
}
