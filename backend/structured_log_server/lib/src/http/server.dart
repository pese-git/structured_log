import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:structured_log/structured_log.dart';

import '../audit/audit_writer.dart';
import '../auth/claims.dart';
import '../auth/local_identity_provider.dart';
import '../auth/token_service.dart';
import '../config/server_config.dart';
import '../errors.dart';
import '../rbac/authorizer.dart';
import '../live/log_broadcast.dart';
import '../storage/database.dart';
import '../storage/log_store.dart';
import 'cors_middleware.dart';
import 'logging_middleware.dart';
import 'principal_middleware.dart';
import 'rate_limit_middleware.dart';
import 'routes/audit_log_route.dart';
import 'routes/auth_route.dart';
import 'routes/change_password_route.dart';
import 'routes/groups_route.dart';
import 'routes/log_stream_route.dart';
import 'routes/logs_route.dart';
import 'routes/projects_route.dart';
import 'routes/role_assignments_route.dart';
import 'routes/secret_keys_route.dart';
import 'routes/users_route.dart';

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
  LogBroadcast? broadcast,
  Duration sseHeartbeatInterval = defaultSseHeartbeat,
  ServerConfig? config,
  DateTime Function()? clock,
  BoundLogger? logger,
}) {
  final authorizer = Authorizer(db);
  // One writer, handed to every route that mutates something. It holds no
  // state of its own — what makes a record atomic with its mutation is the
  // transaction the caller is already inside, not the writer
  // (`audit_writer.dart`).
  final audit = AuditWriter(db);
  final claimsResolver = ClaimsResolver(db, authorizer);
  final tokenService = TokenService(
    db,
    claimsResolver,
    audit,
    signingSecret: signingSecret,
    issuer: issuer,
  );
  final identityProvider = LocalIdentityProvider(
    db,
    signingSecret: signingSecret,
    issuer: issuer,
  );
  final logStore = DriftLogStore(db);
  // Owned by the caller when it needs to close it (the CLI entrypoint);
  // otherwise one per handler, which is what tests want.
  final logBroadcast = broadcast ?? LogBroadcast();

  final featureRouters = <Router>[
    AuditLogRoutes(
      db,
      authorizer,
      retention: AuditRetention(
        auditRetentionDays: config?.auditRetentionDays,
        authEventRetentionDays: config?.authEventRetentionDays,
      ),
    ).router,
    AuthRoutes(
      tokenService,
      trustedProxyHops: config?.trustedProxyHops ?? 0,
    ).router,
    ChangePasswordRoutes(db, audit).router,
    LogRoutes(db, authorizer, logStore, logBroadcast).router,
    LogStreamRoutes(
      db,
      authorizer,
      logStore,
      logBroadcast,
      identityProvider,
      heartbeatInterval: sseHeartbeatInterval,
    ).router,
    GroupRoutes(db, authorizer, audit).router,
    ProjectRoutes(db, authorizer, audit).router,
    SecretKeyRoutes(db, authorizer, audit).router,
    UserRoutes(db, authorizer, audit).router,
    RoleAssignmentRoutes(db, authorizer, audit).router,
  ];

  final router = Router();
  for (final featureRouter in featureRouters) {
    router.mount('/', featureRouter.call);
  }

  var pipeline = const Pipeline();
  // Outermost, so the status it records is the one the client received —
  // including responses the error middleware below it rendered. Absent in
  // tests that build a handler without a logger, which keeps their output
  // to the assertions.
  if (logger != null) {
    pipeline = pipeline.addMiddleware(requestLoggingMiddleware(logger));
  }
  // Ahead of error handling, rate limiting and principal resolution: a
  // matching preflight is answered here and never reaches any of them, and a
  // real request's `Access-Control-Allow-Origin` has to land on whatever
  // response those stages produce — including an error one. Off entirely
  // when no config is supplied, and a no-op when its origin list is empty
  // (`specs/log-server-api`).
  if (config != null) {
    pipeline = pipeline.addMiddleware(
      corsMiddleware(config.corsAllowedOrigins),
    );
  }
  pipeline = pipeline.addMiddleware(errorHandlingMiddleware());
  // Ahead of authentication: throttling by address must not depend on the
  // request being understood, and a rejected one should cost nothing beyond
  // a bucket lookup. Skipped entirely when no config is supplied — route
  // tests build a handler without one.
  if (config != null) {
    pipeline = pipeline.addMiddleware(
      rateLimitMiddleware(config, clock: clock, audit: audit),
    );
  }

  return pipeline
      .addMiddleware(principalMiddleware(identityProvider, db))
      .addHandler(router.call);
}
