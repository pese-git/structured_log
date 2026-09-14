@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Runs `bin/server.dart` as a real OS process — `log-server-config`'s
/// "config from environment, overridden by an argument" priority only
/// really proves itself once a genuinely separate process resolves
/// `Platform.environment` on its own, not through a value handed to it in
/// the same isolate.
void main() {
  test(
    'the server process starts from env config, an argument overrides the port, '
    'and it answers GET /healthz',
    () async {
      final dir =
          Directory.systemTemp.createTempSync('server_integration_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/test.sqlite';

      // Pick a free port by briefly binding to port 0.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start('dart', [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=$dbPath',
        '--http-port=$port', // overrides STRUCTURED_LOG_HTTP_PORT below
      ], environment: {
        'STRUCTURED_LOG_JWT_SIGNING_SECRET': 'integration-test-secret',
        'STRUCTURED_LOG_HTTP_PORT':
            '0', // would bind an ephemeral port if honored
        'STRUCTURED_LOG_BOOTSTRAP_ADMIN_ENABLED': 'false',
      });
      addTearDown(() {
        process.kill(ProcessSignal.sigterm);
      });

      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      final ready = stdoutLines.firstWhere(
        (line) => line.contains('Listening on'),
      );
      await ready.timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw StateError('server did not report ready in time'),
      );

      final client = HttpClient();
      final httpRequest = await client.get('localhost', port, '/healthz');
      final httpResponse = await httpRequest.close();
      final body = await httpResponse.transform(utf8.decoder).join();
      client.close();
      expect(httpResponse.statusCode, 200);
      expect(jsonDecode(body), {'status': 'ok'});

      process.kill(ProcessSignal.sigterm);
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 10));
      expect(exitCode, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
