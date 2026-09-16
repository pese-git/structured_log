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

  runApp(ExampleApp(controller: controller));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({required this.controller, super.key});

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
      home: DemoHome(controller: controller),
    );
  }
}

class DemoHome extends StatelessWidget {
  const DemoHome({required this.controller, super.key});

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
              onPressed: () => log.info(
                'user_login',
                context: {'category': 'application', 'user_id': 42},
              ),
              child: const Text('Log an info event'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => log.error(
                'payment_failed',
                context: {'category': 'application', 'error': 'timeout'},
              ),
              child: const Text('Log an error event'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => log.info(
                'acp_request_sent',
                context: {'category': 'protocol', 'method': 'tools/call'},
              ),
              child: const Text('Log a protocol event'),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MaterialLogViewerPage(controller: controller),
                ),
              ),
              child: const Text('Open log viewer (full screen)'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EmbeddedDemoPage(controller: controller),
                ),
              ),
              child: const Text('Open embedded log viewer demo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [MaterialLogViewer] docked in a side panel next to other app
/// content — the "embeddable widget" use case, as opposed to
/// [MaterialLogViewerPage] owning the whole screen.
class EmbeddedDemoPage extends StatelessWidget {
  const EmbeddedDemoPage({required this.controller, super.key});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Embedded log viewer demo')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: Center(child: Text('The rest of the app goes here.')),
          ),
          const VerticalDivider(width: 1),
          // Expanded (not a fixed-width SizedBox) so this panel's width
          // tracks the window — that's what exercises MaterialLogViewer's
          // own responsive toolbar/master-detail breakpoints as you resize,
          // instead of a rigid width just overflowing once the window
          // narrows past it.
          Expanded(
            flex: 2,
            child: MaterialLogViewer(controller: controller),
          ),
        ],
      ),
    );
  }
}
