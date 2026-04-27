import 'dart:io';

import 'package:structured_log/structured_log.dart';

void main() {
  // Basic usage
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});

  // With bound context
  final boundLog = getLogger().bind({'request_id': 'abc-123'});
  boundLog.info('processing_request');
  boundLog.warning('slow_query', context: {'duration_ms': 1500});

  // Chaining bind
  final userLog = boundLog.bind({'user_id': 42});
  userLog.info('user_action', context: {'action': 'purchase'});
  userLog.error('payment_failed', context: {'error': 'timeout'});

  // File output
  StructlogConfiguration.configure(
    output: fileOutput('logs/app.log'),
  );

  final fileLog = getLogger();
  fileLog.info('logged to file');
  fileLog.error('error in file');

  print('Logs written to logs/app.log');
  print(File('logs/app.log').readAsStringSync());

  // Rotating file output
  StructlogConfiguration.configure(
    output: rotatingFileOutput('logs/rotating.log', maxSizeBytes: 1024),
  );

  final rotatingLog = getLogger();
  for (var i = 0; i < 100; i++) {
    rotatingLog.info('iteration', context: {'i': i});
  }

  print('Rotating logs:');
  print('logs/rotating.log exists: ${File('logs/rotating.log').existsSync()}');
  print(
      'logs/rotating.log.0 exists: ${File('logs/rotating.log.0').existsSync()}');
}
