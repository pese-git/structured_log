// A minimal, UI-free demonstration of wiring structured_log into
// structured_log_flutter's headless log-viewer core. A concrete UI package
// (e.g. structured_log_material) would listen to `controller` instead of
// printing here.
//
// Not runnable via plain `dart run`: package:flutter/foundation.dart pulls
// in dart:ui transitively even though this package uses no widgets, and
// dart:ui is only available through Flutter's own tooling/engine (`flutter
// run`, `flutter test`), not the standalone Dart VM. The exact wiring shown
// here is covered by test/log_buffer_test.dart's "capture plugs directly
// into a LogSink as its output" test, run via `flutter test`.
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

void main() {
  final buffer = LogBuffer(capacity: 200);
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'console', output: coloredConsoleOutput),
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
  log.warning('slow_query', context: {'duration_ms': 1500});
  log.error('payment_failed', context: {'error': 'timeout'});

  print('\nAll captured: ${controller.visibleEntries.length}');

  controller.levelFilter = LogLevel.warning;
  print('Warning and above: ${controller.visibleEntries.length}');

  controller.searchQuery = 'payment';
  print('Matching "payment": ${controller.visibleEntries.length}');
}
