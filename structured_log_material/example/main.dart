// A runnable demo: wires structured_log into structured_log_flutter's
// LogBuffer/LogViewerController and embeds MaterialLogViewerPage. Run with
// `flutter run` from within this package.
import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

void main() {
  final buffer = LogBuffer(capacity: 500);
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'console', output: coloredConsoleOutput),
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  runApp(_ExampleApp(controller: controller));
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp({required this.controller});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'structured_log_material example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: _DemoHome(controller: controller),
    );
  }
}

class _DemoHome extends StatelessWidget {
  const _DemoHome({required this.controller});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final log = getLogger('demo');
    return Scaffold(
      appBar: AppBar(title: const Text('structured_log_material example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => log.info('user_login', context: {'user_id': 42}),
              child: const Text('Log an info event'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () =>
                  log.error('payment_failed', context: {'error': 'timeout'}),
              child: const Text('Log an error event'),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MaterialLogViewerPage(controller: controller),
                ),
              ),
              child: const Text('Open log viewer'),
            ),
          ],
        ),
      ),
    );
  }
}
