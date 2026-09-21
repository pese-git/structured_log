import 'package:structured_log_server/src/config/config_resolver.dart';
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
  'db-path',
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
        'STRUCTURED_LOG_JWT_SECRET': 'test-secret',
      }, command: commandServe);
      expect(result.outcome, ConfigParseOutcome.success);

      final config = ServerConfig.fromResolved(result.values!);
      expect(config.dbPath, '/tmp/db.sqlite');
      expect(config.jwtSecret, 'test-secret');
      expect(config.httpPort, 8080);
      expect(config.bootstrapAdminEnabled, isTrue);
      expect(config.rateLimitEnabled, isTrue);
      expect(config.logLevel, 'info');
    },
  );

  test('create-admin only requires db-path, not jwt-secret', () {
    final result = ConfigResolver(serverConfigParams).parse([], {
      'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
    }, command: commandCreateAdmin);
    expect(result.outcome, ConfigParseOutcome.success);
    final config = ServerConfig.fromResolved(result.values!);
    expect(config.jwtSecret, isNull);
  });

  group('audit retention', () {
    ({ConfigParseOutcome outcome, ServerConfig? config}) resolve(
      List<String> args,
    ) {
      final result = ConfigResolver(serverConfigParams).parse(args, {
        'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
        'STRUCTURED_LOG_JWT_SECRET': 'test-secret',
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
          'STRUCTURED_LOG_JWT_SECRET': 'secret',
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
        'STRUCTURED_LOG_JWT_SECRET': 'test-secret',
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
