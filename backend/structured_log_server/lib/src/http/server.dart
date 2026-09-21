import 'package:cherrypick/cherrypick.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:structured_log/structured_log.dart';

import '../audit/audit_module.dart';
import '../audit/audit_writer.dart';
import '../auth/auth_module.dart';
import '../auth/identity_provider.dart';
import '../auth/token_settings.dart';
import '../config/server_config.dart';
import '../errors.dart';
import '../rbac/rbac_module.dart';
import '../live/log_broadcast.dart';
import '../storage/database.dart';
import '../storage/storage_module.dart';
import 'app_module.dart';
import 'cors_middleware.dart';
import 'http_settings.dart';
import 'logging_middleware.dart';
import 'principal_middleware.dart';
import 'rate_limit_middleware.dart';
import 'routes/audit_log_route.dart';
import 'routes/auth_route.dart';
import 'routes/change_password_route.dart';
import 'routes/groups_route.dart';
import 'routes/log_stream_route.dart';
import 'routes/logs_route.dart';
import 'routes_module.dart';
import 'routes/projects_route.dart';
import 'routes/role_assignments_route.dart';
import 'routes/secret_keys_route.dart';
import 'routes/teams_route.dart';
import 'routes/users_route.dart';

/// The name of the scope the real server's graph lives in, under the helper's
/// root (`CherryPick.openScope(scopeName: serverScopeName)`).
const serverScopeName = 'server';

/// Opens the scope that holds the server's object graph, declared by the
/// modules (`app_module.dart` and the `*_module.dart` beside each feature).
///
/// By default a scope of its own for every call, not the global root: tests
/// build many, each on a database of its own, and they must not see each other's
/// objects. The real server passes [into] — the scope it opened through
/// `CherryPick.openScope` and closes at shutdown — so the process's graph lives
/// where the helper's global observer and cycle detection reach it.
Scope openServerScope(
  StructuredLogDatabase db, {
  required String signingSecret,
  required String issuer,
  LogBroadcast? broadcast,
  Duration sseHeartbeatInterval = defaultSseHeartbeat,
  ServerConfig? config,
  Scope? into,
}) =>
    (into ?? Scope(null, observer: SilentCherryPickObserver()))
      ..installModules([
        AppModule(
          db: db,
          tokens: TokenSettings(signingSecret: signingSecret, issuer: issuer),
          http: HttpSettings(
            trustedProxyHops: config?.trustedProxyHops ?? 0,
            maxIngestBodyBytes:
                config?.maxIngestBodyBytes ?? defaultMaxIngestBodyBytes,
            sseHeartbeatInterval: sseHeartbeatInterval,
          ),
          auditRetention: AuditRetention(
            auditRetentionDays: config?.auditRetentionDays,
            authEventRetentionDays: config?.authEventRetentionDays,
          ),
          // Owned by the caller when it needs to close it (the CLI
          // entrypoint); otherwise one per handler, which is what tests want.
          broadcast: broadcast ?? LogBroadcast(),
        ),
        $RbacModule(),
        $AuditModule(),
        $AuthModule(),
        $StorageModule(),
        $RoutesModule(),
      ]);

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

  /// Where the object graph is installed; see [openServerScope].
  Scope? scope,
}) {
  final graph = openServerScope(
    db,
    signingSecret: signingSecret,
    issuer: issuer,
    broadcast: broadcast,
    sseHeartbeatInterval: sseHeartbeatInterval,
    config: config,
    into: scope,
  );

  final audit = graph.resolve<AuditWriter>();
  final identityProvider = graph.resolve<IdentityProvider>();

  // Resolved here, all of them, so a route that cannot be built fails the
  // moment the handler is built — in every test that builds one, and at startup
  // in the real server — not on the first request that would have used it.
  final featureRouters = <Router>[
    graph.resolve<AuditLogRoutes>().router,
    graph.resolve<AuthRoutes>().router,
    graph.resolve<ChangePasswordRoutes>().router,
    graph.resolve<LogRoutes>().router,
    graph.resolve<LogStreamRoutes>().router,
    graph.resolve<GroupRoutes>().router,
    graph.resolve<TeamRoutes>().router,
    graph.resolve<ProjectRoutes>().router,
    graph.resolve<SecretKeyRoutes>().router,
    graph.resolve<UserRoutes>().router,
    graph.resolve<RoleAssignmentRoutes>().router,
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
