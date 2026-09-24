import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../audit/audit_writer.dart';
import '../auth/identity_provider.dart';
import '../auth/token_service.dart';
import '../live/log_broadcast.dart';
import '../live/subscription_limit.dart';
import '../rbac/authorizer.dart';
import '../storage/database.dart';
import '../storage/log_store.dart';
import 'http_settings.dart';
import 'routes/audit_log_route.dart';
import 'routes/auth_route.dart';
import 'routes/change_password_route.dart';
import 'routes/groups_route.dart';
import 'routes/log_stream_route.dart';
import 'routes/logs_route.dart';
import 'routes/projects_route.dart';
import 'routes/role_assignments_route.dart';
import 'routes/secret_keys_route.dart';
import 'routes/teams_route.dart';
import 'routes/users_route.dart';

part 'routes_module.module.cherrypick.g.dart';

/// Every route class, built from what the other modules bind. `buildHandler`
/// mounts their routers and nothing else.
@module()
abstract class RoutesModule extends Module {
  @singleton()
  @provide()
  AuditLogRoutes auditLogRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditRetention retention,
  ) => AuditLogRoutes(db, authorizer, retention: retention);

  @singleton()
  @provide()
  AuthRoutes authRoutes(TokenService tokens, HttpSettings http) =>
      AuthRoutes(tokens, trustedProxyHops: http.trustedProxyHops);

  @singleton()
  @provide()
  ChangePasswordRoutes changePasswordRoutes(
    StructuredLogDatabase db,
    AuditWriter audit,
  ) => ChangePasswordRoutes(db, audit);

  @singleton()
  @provide()
  LogRoutes logRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    LogStore logStore,
    LogBroadcast broadcast,
    HttpSettings http,
  ) => LogRoutes(
    db,
    authorizer,
    logStore,
    broadcast,
    maxBodyBytes: http.maxIngestBodyBytes,
  );

  @singleton()
  @provide()
  LogStreamRoutes logStreamRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    LogStore logStore,
    LogBroadcast broadcast,
    IdentityProvider identityProvider,
    HttpSettings http,
  ) => LogStreamRoutes(
    db,
    authorizer,
    logStore,
    broadcast,
    identityProvider,
    heartbeatInterval: http.sseHeartbeatInterval,
    limiter: SubscriptionLimiter(
      perUser: http.maxLiveSubscriptionsPerUser,
      total: http.maxLiveSubscriptions,
    ),
  );

  @singleton()
  @provide()
  GroupRoutes groupRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditWriter audit,
  ) => GroupRoutes(db, authorizer, audit);

  @singleton()
  @provide()
  TeamRoutes teamRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditWriter audit,
  ) => TeamRoutes(db, authorizer, audit);

  @singleton()
  @provide()
  ProjectRoutes projectRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditWriter audit,
  ) => ProjectRoutes(db, authorizer, audit);

  @singleton()
  @provide()
  SecretKeyRoutes secretKeyRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditWriter audit,
  ) => SecretKeyRoutes(db, authorizer, audit);

  @singleton()
  @provide()
  UserRoutes userRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditWriter audit,
  ) => UserRoutes(db, authorizer, audit);

  @singleton()
  @provide()
  RoleAssignmentRoutes roleAssignmentRoutes(
    StructuredLogDatabase db,
    Authorizer authorizer,
    AuditWriter audit,
  ) => RoleAssignmentRoutes(db, authorizer, audit);
}
