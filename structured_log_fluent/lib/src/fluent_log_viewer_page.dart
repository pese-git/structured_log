import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'fluent_log_viewer.dart';

/// A ready-to-use Fluent UI (WinUI-style) full-screen log viewer for
/// `structured_log`, built on a [LogViewerController].
///
/// A thin [ScaffoldPage] wrapper around [FluentLogViewer]: a title ("Logs")
/// and, when pushed via `Navigator` (e.g. with `FluentPageRoute`, as below),
/// a back button — omitted when this widget is the navigator root. Use
/// [FluentLogViewer] directly instead when embedding the log viewer inside
/// existing page chrome (a `Flyout`, a side panel, a tab, ...) rather than
/// as its own screen.
///
/// Wire it up by giving the same [LogViewerController] to both this widget
/// and a [LogSink] that feeds it:
///
/// ```dart
/// final buffer = LogBuffer();
/// final controller = LogViewerController(buffer);
///
/// StructlogConfiguration.configure(sinks: [
///   LogSink(name: 'viewer', output: buffer.capture),
/// ]);
///
/// runApp(FluentApp(
///   home: FluentLogViewerPage(controller: controller),
/// ));
/// ```
class FluentLogViewerPage extends StatelessWidget {
  const FluentLogViewerPage({required this.controller, super.key});

  /// The controller this screen reads from and mutates in response to user
  /// input (search, level filter, pause, clear, selection).
  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        child: Row(
          children: [
            if (Navigator.canPop(context)) ...[
              IconButton(
                icon: const Icon(FluentIcons.back),
                onPressed: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 8),
            ],
            Text('Logs', style: theme.typography.title),
          ],
        ),
      ),
      content: FluentLogViewer(controller: controller),
    );
  }
}
