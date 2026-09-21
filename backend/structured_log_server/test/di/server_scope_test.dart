import 'package:cherrypick/cherrypick.dart';
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/claims.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/auth/local_identity_provider.dart';
import 'package:structured_log_server/src/auth/token_service.dart';
import 'package:structured_log_server/src/auth/token_settings.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/http_settings.dart';
import 'package:structured_log_server/src/http/routes/audit_log_route.dart';
import 'package:structured_log_server/src/http/routes/auth_route.dart';
import 'package:structured_log_server/src/http/routes/change_password_route.dart';
import 'package:structured_log_server/src/http/routes/groups_route.dart';
import 'package:structured_log_server/src/http/routes/log_stream_route.dart';
import 'package:structured_log_server/src/http/routes/logs_route.dart';
import 'package:structured_log_server/src/http/routes/projects_route.dart';
import 'package:structured_log_server/src/http/routes/role_assignments_route.dart';
import 'package:structured_log_server/src/http/routes/secret_keys_route.dart';
import 'package:structured_log_server/src/http/routes/teams_route.dart';
import 'package:structured_log_server/src/http/routes/users_route.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:test/test.dart';

ServerConfig _config({
  int maxIngestBodyBytes = 1024 * 1024,
  int trustedProxyHops = 0,
  int? auditRetentionDays,
}) => ServerConfig(
  dbPath: ':memory:',
  httpHost: 'localhost',
  httpPort: 0,
  jwtSecret: 'test-secret',
  jwtIssuer: 'test',
  maxIngestBodyBytes: maxIngestBodyBytes,
  retentionPurgeIntervalSeconds: 3600,
  bootstrapAdminEnabled: false,
  bootstrapAdminUsername: 'root',
  bootstrapAdminPassword: null,
  logLevel: 'info',
  logFile: null,
  logFormat: 'json',
  logMaxFileBytes: 1024,
  logMaxFiles: 1,
  rateLimitEnabled: false,
  rateLimitBucketCapacity: 10,
  rateLimitRefillPerMinute: 60,
  rateLimitMaxKeys: 1000,
  trustedProxyHops: trustedProxyHops,
  sseHeartbeatIntervalSeconds: 30,
  auditRetentionDays: auditRetentionDays,
);

void main() {
  late StructuredLogDatabase db;

  setUp(() => db = StructuredLogDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Scope open({
    LogBroadcast? broadcast,
    ServerConfig? config,
    Duration heartbeat = defaultSseHeartbeat,
  }) => openServerScope(
    db,
    signingSecret: 'secret',
    issuer: 'test',
    broadcast: broadcast,
    sseHeartbeatInterval: heartbeat,
    config: config,
  );

  // A module that never resolves is a feature that is tested and inert
  // (`project_optional_wiring_hazard`): the generator reads the modules, not the
  // graph, so a type nobody binds passes `analyze` and the build and fails on
  // the first `resolve`. `buildHandler` resolves the routes, so every handler
  // test covers those; this covers the rest, and pins what each one is.
  group('the scope resolves everything the modules declare', () {
    test('the values it is given', () {
      final scope = open();

      expect(scope.resolve<StructuredLogDatabase>(), same(db));
      expect(scope.resolve<TokenSettings>().issuer, 'test');
      expect(scope.resolve<HttpSettings>(), isNotNull);
      expect(scope.resolve<AuditRetention>(), isNotNull);
      expect(scope.resolve<LogBroadcast>(), isNotNull);
    });

    test('the services, behind the types consumers depend on', () {
      final scope = open();

      expect(scope.resolve<Authorizer>(), isNotNull);
      expect(scope.resolve<AuditWriter>(), isNotNull);
      expect(scope.resolve<ClaimsResolver>(), isNotNull);
      expect(scope.resolve<TokenService>(), isNotNull);
      expect(scope.resolve<IdentityProvider>(), isA<LocalIdentityProvider>());
      expect(scope.resolve<LogStore>(), isA<DriftLogStore>());
    });

    test('every route class', () {
      final scope = open();

      expect(scope.resolve<AuditLogRoutes>(), isNotNull);
      expect(scope.resolve<AuthRoutes>(), isNotNull);
      expect(scope.resolve<ChangePasswordRoutes>(), isNotNull);
      expect(scope.resolve<LogRoutes>(), isNotNull);
      expect(scope.resolve<LogStreamRoutes>(), isNotNull);
      expect(scope.resolve<GroupRoutes>(), isNotNull);
      expect(scope.resolve<TeamRoutes>(), isNotNull);
      expect(scope.resolve<ProjectRoutes>(), isNotNull);
      expect(scope.resolve<SecretKeyRoutes>(), isNotNull);
      expect(scope.resolve<UserRoutes>(), isNotNull);
      expect(scope.resolve<RoleAssignmentRoutes>(), isNotNull);
    });
  });

  group('sharing', () {
    test('a service is one object however many routes ask for it', () {
      final scope = open();

      expect(scope.resolve<Authorizer>(), same(scope.resolve<Authorizer>()));
      expect(scope.resolve<AuditWriter>(), same(scope.resolve<AuditWriter>()));
      expect(scope.resolve<LogRoutes>(), same(scope.resolve<LogRoutes>()));
    });

    test('the broadcast the caller passes is the one the routes get', () {
      final broadcast = LogBroadcast();
      final scope = open(broadcast: broadcast);

      expect(scope.resolve<LogBroadcast>(), same(broadcast));
    });

    test('two handlers do not share a scope', () {
      final first = open();
      final second = open();

      expect(
        first.resolve<LogBroadcast>(),
        isNot(same(second.resolve<LogBroadcast>())),
      );
      expect(
        first.resolve<LogRoutes>(),
        isNot(same(second.resolve<LogRoutes>())),
      );
    });
  });

  group('into a scope the caller opened', () {
    tearDown(CherryPick.closeRootScope);

    test(
      'installs the graph there, and closing that scope takes it down',
      () async {
        final mine = CherryPick.openScope(scopeName: serverScopeName);

        final scope = openServerScope(
          db,
          signingSecret: 'secret',
          issuer: 'test',
          into: mine,
        );

        expect(scope, same(mine));
        expect(scope.resolve<Authorizer>(), isNotNull);

        await CherryPick.closeScope(scopeName: serverScopeName);

        expect(scope.tryResolve<Authorizer>(), isNull);
      },
    );

    test('a handler built into it answers from that scope', () async {
      final mine = CherryPick.openScope(scopeName: serverScopeName);

      final handler = buildHandler(
        db,
        signingSecret: 'secret',
        issuer: 'test',
        scope: mine,
      );

      final response = await handler(
        Request('GET', Uri.parse('http://x/healthz')),
      );
      expect(response.statusCode, 200);
      expect(mine.resolve<LogRoutes>(), isNotNull);
    });
  });

  group('what configuration reaches', () {
    test('without a config, routes behave as they did unconfigured', () {
      final scope = open();

      expect(
        scope.resolve<LogRoutes>().maxBodyBytes,
        defaultMaxIngestBodyBytes,
      );
      expect(
        scope.resolve<LogStreamRoutes>().heartbeatInterval,
        defaultSseHeartbeat,
      );
      expect(scope.resolve<HttpSettings>().trustedProxyHops, 0);
    });

    test(
      'the body cap and the heartbeat come from the config and the call',
      () {
        final scope = open(
          config: _config(maxIngestBodyBytes: 4096, trustedProxyHops: 2),
          heartbeat: const Duration(seconds: 7),
        );

        expect(scope.resolve<LogRoutes>().maxBodyBytes, 4096);
        expect(
          scope.resolve<LogStreamRoutes>().heartbeatInterval,
          const Duration(seconds: 7),
        );
        expect(scope.resolve<HttpSettings>().trustedProxyHops, 2);
      },
    );

    test('retention comes from the config', () {
      final scope = open(config: _config(auditRetentionDays: 30));

      expect(scope.resolve<AuditRetention>().auditRetentionDays, 30);
      expect(scope.resolve<AuditRetention>().authEventRetentionDays, isNull);
    });
  });
}
