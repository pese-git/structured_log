// A runnable demo: wires structured_log into structured_log_flutter's
// LogBuffer/LogViewerController and embeds CupertinoLogViewerPage. Run with
// `flutter run` from within this package.
import 'package:flutter/cupertino.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

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
    return CupertinoApp(
      title: 'structured_log_cupertino example',
      theme: const CupertinoThemeData(),
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
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('structured_log_cupertino example'),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton.filled(
                onPressed: () => log.info(
                  'user_login',
                  context: {'category': 'application', 'user_id': 42},
                ),
                child: const Text('Log an info event'),
              ),
              const SizedBox(height: 12),
              CupertinoButton.filled(
                onPressed: () => log.error(
                  'payment_failed',
                  context: {'category': 'application', 'error': 'timeout'},
                ),
                child: const Text('Log an error event'),
              ),
              const SizedBox(height: 12),
              CupertinoButton.filled(
                onPressed: () => log.info(
                  'acp_request_sent',
                  context: {'category': 'protocol', 'method': 'tools/call'},
                ),
                child: const Text('Log a protocol event'),
              ),
              const SizedBox(height: 24),
              CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => CupertinoLogViewerPage(
                      controller: controller,
                    ),
                  ),
                ),
                child: const Text('Open log viewer (full screen)'),
              ),
              const SizedBox(height: 4),
              CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => EmbeddedDemoPage(controller: controller),
                  ),
                ),
                child: const Text('Open embedded log viewer demo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [CupertinoLogViewer] docked in a side panel next to other app
/// content — the "embeddable widget" use case, as opposed to
/// [CupertinoLogViewerPage] owning the whole screen.
class EmbeddedDemoPage extends StatelessWidget {
  const EmbeddedDemoPage({required this.controller, super.key});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Embedded log viewer demo'),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(
              child: Center(child: Text('The rest of the app goes here.')),
            ),
            Container(
              width: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            // Expanded (not a fixed-width SizedBox) so this panel's width
            // tracks the window — that's what exercises CupertinoLogViewer's
            // own responsive toolbar/master-detail breakpoints as you
            // resize, instead of a rigid width just overflowing once the
            // window narrows past it.
            Expanded(
              flex: 2,
              child: CupertinoLogViewer(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}
