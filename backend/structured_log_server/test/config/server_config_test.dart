import 'package:structured_log_server/src/config/config_resolver.dart';
import 'package:structured_log_server/src/auth/token_settings.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:test/test.dart';

/// Every `ServerConfig` field, by the kebab-case `ParamSpec.name` that
/// backs it. Kept by hand (not derived via reflection — this package
/// avoids `dart:mirrors`) specifically so that adding a field to
/// [ServerConfig] without a matching entry here — or vice versa — fails
/// this test loudly, rather than only surfacing as a silent `null` at
/// runtime (`log-server-config`: "каждое поле ServerConfig присутствует в
/// декларации параметров").
const _expectedParamNames = {
  'db-backend',
  'db-path',
  'db-postgres-host',
  'db-postgres-port',
  'db-postgres-database',
  'db-postgres-username',
  'db-postgres-password',
  'db-postgres-pool-size',
  'db-postgres-ssl-mode',
  'http-host',
  'http-port',
  'jwt-secret',
  'jwt-issuer',
  'max-ingest-body-bytes',
  'retention-purge-interval-seconds',
  'bootstrap-admin-enabled',
  'bootstrap-admin-username',
  'bootstrap-admin-password',
  'log-level',
  'log-file',
  'log-format',
  'log-max-file-bytes',
  'log-max-files',
  'rate-limit-enabled',
  'rate-limit-bucket-capacity',
  'rate-limit-refill-per-minute',
  'rate-limit-max-keys',
  'trusted-proxy-hops',
  'sse-heartbeat-interval-seconds',
  'max-live-subscriptions-per-user',
  'max-live-subscriptions',
  'cors-allowed-origins',
  'audit-retention-days',
  'auth-event-retention-days',
  'audit-purge-batch-size',
  'db-read-pool-size',
};

void main() {
  test('serverConfigParams has exactly the expected set of param names', () {
    final actual = serverConfigParams.map((s) => s.name).toSet();
    expect(actual, _expectedParamNames);
    expect(serverConfigParams, hasLength(_expectedParamNames.length));
  });

  test('every param name is unique', () {
    final names = serverConfigParams.map((s) => s.name).toList();
    expect(names.toSet(), hasLength(names.length));
  });

  test('every param has a non-empty description (for --help)', () {
    for (final spec in serverConfigParams) {
      expect(
        spec.description.trim(),
        isNotEmpty,
        reason: '${spec.name} has no description',
      );
    }
  });

  test('every param name is kebab-case', () {
    final kebabCase = RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$');
    for (final spec in serverConfigParams) {
      expect(
        kebabCase.hasMatch(spec.name),
        isTrue,
        reason: '${spec.name} is not kebab-case',
      );
    }
  });

  test(
    'ServerConfig.fromResolved consumes every resolved value without a typo\'d key',
    () {
      final result = ConfigResolver(serverConfigParams).parse([], {
        'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
        'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
      }, command: commandServe);
      expect(result.outcome, ConfigParseOutcome.success);

      final config = ServerConfig.fromResolved(result.values!);
      expect(config.dbPath, '/tmp/db.sqlite');
      expect(config.jwtSecret, 'test-secret-long-enough-for-the-policy');
      expect(config.httpPort, 8080);
      expect(config.bootstrapAdminEnabled, isTrue);
      expect(config.rateLimitEnabled, isTrue);
      expect(config.logLevel, 'info');
    },
  );

  group('jwt-secret has to be long enough to key HMAC-SHA256', () {
    ConfigParseResult parseWith(String secret) =>
        ConfigResolver(serverConfigParams).parse([], {
          'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
          'STRUCTURED_LOG_JWT_SECRET': secret,
        }, command: commandServe);

    test('a short one stops startup instead of being accepted', () {
      final result = parseWith('hunter2');

      expect(result.outcome, ConfigParseOutcome.errors);
      expect(result.errors.single, contains('STRUCTURED_LOG_JWT_SECRET'));
      expect(result.errors.single, contains('$minJwtSecretBytes'));
    });

    test('the complaint does not carry the secret it is about', () {
      const secret = 'hunter2';
      final result = parseWith(secret);

      expect(
        result.errors.single,
        isNot(contains(secret)),
        reason:
            'configuration errors are printed to the console and end up in '
            'deployment logs; the value must not travel with the complaint '
            '(`log-server-config`)',
      );
    });

    test('one long enough is accepted', () {
      final result = parseWith('x' * minJwtSecretBytes);

      expect(result.outcome, ConfigParseOutcome.success);
      expect(
        ServerConfig.fromResolved(result.values!).jwtSecret,
        'x' * minJwtSecretBytes,
      );
    });

    test('create-admin is held to it too, when one is set', () {
      final result = ConfigResolver(serverConfigParams).parse([], {
        'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
        'STRUCTURED_LOG_JWT_SECRET': 'hunter2',
      }, command: commandCreateAdmin);

      expect(
        result.outcome,
        ConfigParseOutcome.errors,
        reason:
            'the command does not sign anything, so this is strictness for '
            'its own sake — but it is the same deployment\'s secret, `serve` '
            'would refuse it moments later, and saying so at the first '
            'command that reads the environment is the earlier, clearer '
            'failure. It also matches bootstrap-admin-password, whose '
            'validator applies to both commands alike',
      );
    });

    test('create-admin without a secret at all is still fine', () {
      final result = ConfigResolver(serverConfigParams).parse([], {
        'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
      }, command: commandCreateAdmin);

      expect(
        result.outcome,
        ConfigParseOutcome.success,
        reason:
            'the rule is about a secret that was set, never a reason to '
            'demand one the command does not need',
      );
    });
  });

  test('the live-stream ceilings have defaults and can be turned off', () {
    final defaults = ConfigResolver(serverConfigParams).parse([], {
      'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
      'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
    }, command: commandServe);
    final config = ServerConfig.fromResolved(defaults.values!);
    expect(config.maxLiveSubscriptionsPerUser, 10);
    expect(config.maxLiveSubscriptions, 1000);

    final off = ConfigResolver(serverConfigParams).parse([], {
      'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
      'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
      'STRUCTURED_LOG_MAX_LIVE_SUBSCRIPTIONS_PER_USER': '0',
      'STRUCTURED_LOG_MAX_LIVE_SUBSCRIPTIONS': '0',
    }, command: commandServe);
    expect(off.outcome, ConfigParseOutcome.success);
    final unlimited = ServerConfig.fromResolved(off.values!);
    expect(unlimited.maxLiveSubscriptionsPerUser, 0);
    expect(
      unlimited.maxLiveSubscriptions,
      0,
      reason: 'zero is how an operator says "no ceiling", not an error',
    );
  });

  test('a negative live-stream ceiling is a configuration error', () {
    final result = ConfigResolver(serverConfigParams).parse([], {
      'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
      'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
      'STRUCTURED_LOG_MAX_LIVE_SUBSCRIPTIONS': '-1',
    }, command: commandServe);

    expect(result.outcome, ConfigParseOutcome.errors);
  });

  test('create-admin only requires db-path, not jwt-secret', () {
    final result = ConfigResolver(serverConfigParams).parse([], {
      'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
    }, command: commandCreateAdmin);
    expect(result.outcome, ConfigParseOutcome.success);
    final config = ServerConfig.fromResolved(result.values!);
    expect(config.jwtSecret, isNull);
  });

  group('db-backend', () {
    ConfigParseResult resolve(
      List<String> args, {
      String command = commandServe,
      Map<String, String> extraEnv = const {},
    }) => ConfigResolver(serverConfigParams).parse(args, {
      'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
      ...extraEnv,
    }, command: command);

    test('defaults to sqlite, unchanged from before this setting existed', () {
      final result = resolve(['--db-path=/tmp/x.db']);
      expect(result.outcome, ConfigParseOutcome.success);
      final config = ServerConfig.fromResolved(result.values!);
      expect(config.dbBackend, 'sqlite');
      expect(config.dbPath, '/tmp/x.db');
    });

    test('an unknown backend is a configuration error', () {
      expect(
        resolve(['--db-backend=mysql', '--db-path=/tmp/x.db']).outcome,
        ConfigParseOutcome.errors,
      );
    });

    test('sqlite: db-path is required, PostgreSQL settings are not', () {
      expect(
        resolve(['--db-backend=sqlite']).outcome,
        ConfigParseOutcome.errors,
        reason: 'db-path missing',
      );
      final result = resolve(['--db-backend=sqlite', '--db-path=/tmp/x.db']);
      expect(result.outcome, ConfigParseOutcome.success);
    });

    test(
      'postgres: host/database/username/password are required, db-path is not',
      () {
        final missingHost = resolve(
          [
            '--db-backend=postgres',
            '--db-postgres-database=d',
            '--db-postgres-username=u',
          ],
          extraEnv: {'STRUCTURED_LOG_DB_POSTGRES_PASSWORD': 'p'},
        );
        expect(missingHost.outcome, ConfigParseOutcome.errors);

        final missingPassword = resolve([
          '--db-backend=postgres',
          '--db-postgres-host=h',
          '--db-postgres-database=d',
          '--db-postgres-username=u',
        ]);
        expect(missingPassword.outcome, ConfigParseOutcome.errors);

        final complete = resolve(
          [
            '--db-backend=postgres',
            '--db-postgres-host=h',
            '--db-postgres-database=d',
            '--db-postgres-username=u',
          ],
          extraEnv: {'STRUCTURED_LOG_DB_POSTGRES_PASSWORD': 'p'},
        );
        expect(complete.outcome, ConfigParseOutcome.success);
        final config = ServerConfig.fromResolved(complete.values!);
        expect(config.dbPath, isNull);
        expect(config.dbPostgresHost, 'h');
        expect(config.dbPostgresDatabase, 'd');
        expect(config.dbPostgresUsername, 'u');
        expect(config.dbPostgresPassword, 'p');
        expect(config.dbPostgresPort, 5432, reason: 'default');
        expect(config.dbPostgresPoolSize, 10, reason: 'default');
        expect(config.dbPostgresSslMode, 'require', reason: 'default');
      },
    );

    test('create-admin follows the same backend-dependent requirements', () {
      final withoutDbPath = resolve(
        [
          '--db-backend=postgres',
          '--db-postgres-host=h',
          '--db-postgres-database=d',
          '--db-postgres-username=u',
        ],
        command: commandCreateAdmin,
        extraEnv: {'STRUCTURED_LOG_DB_POSTGRES_PASSWORD': 'p'},
      );
      expect(
        withoutDbPath.outcome,
        ConfigParseOutcome.success,
        reason: 'create-admin does not need --db-path under postgres',
      );
    });

    test('an invalid db-postgres-ssl-mode is a configuration error', () {
      expect(
        resolve(
          [
            '--db-backend=postgres',
            '--db-postgres-host=h',
            '--db-postgres-database=d',
            '--db-postgres-username=u',
            '--db-postgres-ssl-mode=bogus',
          ],
          extraEnv: {'STRUCTURED_LOG_DB_POSTGRES_PASSWORD': 'p'},
        ).outcome,
        ConfigParseOutcome.errors,
      );
    });

    test('db-read-pool-size warns, but does not fail, under postgres', () {
      final result = resolve(
        [
          '--db-backend=postgres',
          '--db-postgres-host=h',
          '--db-postgres-database=d',
          '--db-postgres-username=u',
          '--db-read-pool-size=4',
        ],
        extraEnv: {'STRUCTURED_LOG_DB_POSTGRES_PASSWORD': 'p'},
      );
      expect(result.outcome, ConfigParseOutcome.success);
      expect(result.warnings, contains(contains('--db-read-pool-size')));
    });

    test(
      'db-read-pool-size at its default draws no warning under postgres',
      () {
        final result = resolve(
          [
            '--db-backend=postgres',
            '--db-postgres-host=h',
            '--db-postgres-database=d',
            '--db-postgres-username=u',
          ],
          extraEnv: {'STRUCTURED_LOG_DB_POSTGRES_PASSWORD': 'p'},
        );
        expect(result.warnings, isEmpty);
      },
    );

    test('db-read-pool-size draws no warning under sqlite even when set', () {
      final result = resolve(['--db-path=/tmp/x.db', '--db-read-pool-size=4']);
      expect(result.warnings, isEmpty);
    });
  });

  group('audit retention', () {
    ({ConfigParseOutcome outcome, ServerConfig? config}) resolve(
      List<String> args,
    ) {
      final result = ConfigResolver(serverConfigParams).parse(args, {
        'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
        'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
      }, command: commandServe);
      return (
        outcome: result.outcome,
        config: result.values == null
            ? null
            : ServerConfig.fromResolved(result.values!),
      );
    }

    test('both periods are unset by default', () {
      final config = resolve([]).config!;

      expect(config.auditRetentionDays, isNull);
      expect(config.authEventRetentionDays, isNull);
      expect(
        config.auditPurgeBatchSize,
        500,
        reason: 'the chunk has a default; the periods deliberately do not',
      );
    });

    test('the flags are the ones the operations guide documents', () {
      final config = resolve([
        '--audit-retention-days=365',
        '--auth-event-retention-days=30',
        '--audit-purge-batch-size=100',
      ]).config!;

      expect(config.auditRetentionDays, 365);
      expect(config.authEventRetentionDays, 30);
      expect(config.auditPurgeBatchSize, 100);
    });

    test('a period of zero is a configuration error, not a setting', () {
      // Zero days means "delete everything on the next pass", which is never
      // what someone typing a retention meant. Refused with the rest of the
      // configuration, before the port opens.
      expect(
        resolve(['--audit-retention-days=0']).outcome,
        ConfigParseOutcome.errors,
      );
    });

    test('a negative period is refused too', () {
      expect(
        resolve(['--auth-event-retention-days=-1']).outcome,
        ConfigParseOutcome.errors,
      );
    });

    test('a chunk size of zero is refused, rather than looping forever', () {
      expect(
        resolve(['--audit-purge-batch-size=0']).outcome,
        ConfigParseOutcome.errors,
      );
    });
  });

  group('db-read-pool-size', () {
    ConfigParseResult resolve(List<String> args) =>
        ConfigResolver(serverConfigParams).parse(args, {
          'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
        }, command: commandServe);

    test('defaults to two readers', () {
      final result = resolve(['--db-path=/tmp/x.db']);
      expect(ServerConfig.fromResolved(result.values!).dbReadPoolSize, 2);
    });

    test('zero is allowed and means no readers', () {
      final result = resolve(['--db-path=/tmp/x.db', '--db-read-pool-size=0']);
      expect(ServerConfig.fromResolved(result.values!).dbReadPoolSize, 0);
    });

    test('a negative or absurdly large size is refused', () {
      for (final value in ['-1', '17']) {
        expect(
          resolve([
            '--db-path=/tmp/x.db',
            '--db-read-pool-size=$value',
          ]).outcome,
          ConfigParseOutcome.errors,
          reason: value,
        );
      }
    });
  });

  group('cors-allowed-origins', () {
    ServerConfig resolve(List<String> args) {
      final result = ConfigResolver(serverConfigParams).parse(args, {
        'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
        'STRUCTURED_LOG_JWT_SECRET': 'test-secret-long-enough-for-the-policy',
      }, command: commandServe);
      return ServerConfig.fromResolved(result.values!);
    }

    test('unset means CORS is off — an empty set', () {
      expect(resolve([]).corsAllowedOrigins, isEmpty);
    });

    test('a comma-separated list becomes a trimmed set', () {
      final config = resolve([
        '--cors-allowed-origins=http://a.test, http://b.test',
      ]);
      expect(config.corsAllowedOrigins, {'http://a.test', 'http://b.test'});
    });

    test('a trailing comma does not produce a blank origin', () {
      final config = resolve(['--cors-allowed-origins=http://a.test,']);
      expect(config.corsAllowedOrigins, {'http://a.test'});
    });
  });
}
