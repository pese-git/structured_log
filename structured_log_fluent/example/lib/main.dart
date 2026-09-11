// A runnable demo: wires structured_log into structured_log_flutter's
// LogBuffer/LogViewerController and embeds FluentLogViewerPage. Run with
// `flutter run` from within this package.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

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
    return FluentApp(
      title: 'structured_log_fluent example',
      theme: FluentThemeData(accentColor: Colors.blue),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      themeMode: ThemeMode.system,
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
    return ScaffoldPage(
      header: const PageHeader(title: Text('structured_log_fluent example')),
      content: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Button(
              onPressed: () => log.info(
                'user_login',
                context: {'category': 'application', 'user_id': 42},
              ),
              child: const Text('Log an info event'),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () => log.error(
                'payment_failed',
                context: {'category': 'application', 'error': 'timeout'},
              ),
              child: const Text('Log an error event'),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () => log.info(
                'acp_request_sent',
                context: {'category': 'protocol', 'method': 'tools/call'},
              ),
              child: const Text('Log a protocol event'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                FluentPageRoute<void>(
                  builder: (_) => FluentLogViewerPage(controller: controller),
                ),
              ),
              child: const Text('Open log viewer (full screen)'),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () => Navigator.of(context).push(
                FluentPageRoute<void>(
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

/// Shows [FluentLogViewer] docked in a side panel next to other app
/// content — the "embeddable widget" use case, as opposed to
/// [FluentLogViewerPage] owning the whole screen.
class EmbeddedDemoPage extends StatelessWidget {
  const EmbeddedDemoPage({required this.controller, super.key});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Embedded log viewer demo'),
        commandBar: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: Center(
              child: Text('The rest of the app goes here.'),
            ),
          ),
          const Divider(direction: Axis.vertical),
          // The toolbar (search + category + level dropdowns + pause/clear)
          // needs roughly this much width to lay out without overflowing.
          SizedBox(
            width: 900,
            child: FluentLogViewer(controller: controller),
          ),
        ],
      ),
    );
  }
}
