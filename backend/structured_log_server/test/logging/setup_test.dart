import 'dart:io';

import 'package:structured_log/structured_log.dart';
import 'package:structured_log_server/src/config/config_resolver.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/logging/setup.dart';
import 'package:test/test.dart';

ServerConfig configWith({
  String logLevel = 'info',
  String? logFile,
  String logFormat = 'console',
  int logMaxFileBytes = 1024,
  int logMaxFiles = 3,
}) {
  return ServerConfig(
    dbPath: ':memory:',
    httpHost: 'localhost',
    httpPort: 0,
    jwtSecret: 'secret-value',
    jwtIssuer: 'test',
    maxIngestBodyBytes: 1024,
    retentionPurgeIntervalSeconds: 3600,
    bootstrapAdminEnabled: false,
    bootstrapAdminUsername: 'root',
    bootstrapAdminPassword: null,
    logLevel: logLevel,
    logFile: logFile,
    logFormat: logFormat,
    logMaxFileBytes: logMaxFileBytes,
    logMaxFiles: logMaxFiles,
    rateLimitEnabled: true,
    rateLimitBucketCapacity: 10,
    rateLimitRefillPerMinute: 10,
    rateLimitMaxKeys: 100,
    trustedProxyHops: 0,
    sseHeartbeatIntervalSeconds: 30,
    // No ceiling, so these fixtures behave exactly as
    // they did before live subscriptions had one.
    maxLiveSubscriptionsPerUser: 0,
    maxLiveSubscriptions: 0,
  );
}

void main() {
  tearDown(StructlogConfiguration.reset);

  group('parseLogLevel', () {
    test('accepts every level name', () {
      for (final level in LogLevel.values) {
        expect(parseLogLevel(level.name), level);
      }
    });

    test('falls back to info rather than throwing', () {
      // Refusing to start over a misspelled log level would be a worse
      // failure than logging a little more than asked.
      expect(parseLogLevel('verbose'), LogLevel.info);
      expect(parseLogLevel(''), LogLevel.info);
    });
  });

  group('configureServerLogging', () {
    test('installs a single sink at the configured level', () {
      configureServerLogging(configWith(logLevel: 'warning'));

      final sinks = StructlogConfiguration.current.sinks;
      expect(sinks, hasLength(1));
      expect(sinks.single.minLevel, LogLevel.warning);
    });

    test('writes to a rotating file when one is configured', () async {
      final dir = Directory.systemTemp.createTempSync('logging_setup_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/server.log';

      final logging = configureServerLogging(configWith(logFile: path));
      logging.logger.info('server.started', context: {'port': 8080});
      await logging.flush();

      final written = File(path).readAsStringSync();
      expect(written, contains('server.started'));
      expect(written, contains('8080'));
      expect(
        written.trim().split('\n'),
        hasLength(1),
        reason: 'one JSON object per line, not indented',
      );
    });

    test('flush is safe when no file is configured', () async {
      final logging = configureServerLogging(configWith());
      await logging.flush();
    });

    test('a level below the threshold is not written', () async {
      final dir = Directory.systemTemp.createTempSync('logging_level_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/server.log';

      final logging = configureServerLogging(
        configWith(logFile: path, logLevel: 'error'),
      );
      logging.logger.info('ignored.event');
      logging.logger.error('kept.event');
      await logging.flush();

      final written = File(path).readAsStringSync();
      expect(written, isNot(contains('ignored.event')));
      expect(written, contains('kept.event'));
    });
  });

  group('maskedConfigContext', () {
    test('masks secrets and keeps everything else', () {
      final outcome = ConfigResolver(serverConfigParams).parse(
        ['--http-port=9000', '--db-path=/tmp/x.sqlite'],
        {'STRUCTURED_LOG_JWT_SECRET': 'do-not-log-me-and-long-enough-to-start'},
        command: 'serve',
      );
      expect(outcome.values, isNotNull, reason: '${outcome.errors}');

      final context = maskedConfigContext(serverConfigParams, outcome.values!);

      expect(context['jwt_secret'], '***');
      expect(
        context.values.join(' '),
        isNot(contains('do-not-log-me-and-long-enough-to-start')),
        reason: 'the point of the whole function',
      );
      expect(context['http_port'], 9000, reason: 'non-secrets stay readable');
      expect(context['log_level'], isNotNull);
    });

    test('an unset secret reads as null, not as a mask', () {
      final outcome = ConfigResolver(serverConfigParams).parse(
        ['--db-path=/tmp/x.sqlite'],
        {'STRUCTURED_LOG_JWT_SECRET': 'irrelevant-but-long-enough-to-start'},
        command: 'serve',
      );
      expect(outcome.values, isNotNull, reason: '${outcome.errors}');

      final context = maskedConfigContext(serverConfigParams, outcome.values!);
      expect(context['bootstrap_admin_password'], isNull);
    });
  });
}
