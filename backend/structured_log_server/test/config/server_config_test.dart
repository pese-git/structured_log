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
      final result = ConfigResolver(serverConfigParams).parse(
        [],
        {
          'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite',
          'STRUCTURED_LOG_JWT_SECRET': 'test-secret',
        },
        command: commandServe,
      );
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
    final result = ConfigResolver(serverConfigParams).parse(
      [],
      {'STRUCTURED_LOG_DB_PATH': '/tmp/db.sqlite'},
      command: commandCreateAdmin,
    );
    expect(result.outcome, ConfigParseOutcome.success);
    final config = ServerConfig.fromResolved(result.values!);
    expect(config.jwtSecret, isNull);
  });
}
