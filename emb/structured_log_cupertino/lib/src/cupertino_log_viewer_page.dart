import 'package:flutter/cupertino.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'cupertino_log_viewer.dart';

/// A ready-to-use Cupertino (iOS-style) full-screen log viewer for
/// `structured_log`, built on a [LogViewerController].
///
/// A thin [CupertinoPageScaffold] wrapper around [CupertinoLogViewer]: a
/// navigation bar titled "Logs" and, when pushed via `Navigator` (e.g. with
/// [CupertinoPageRoute], as below), a back button —
/// [CupertinoNavigationBar] shows that automatically, the same as
/// [CupertinoPageScaffold]'s own pages do. Use [CupertinoLogViewer] directly
/// instead when embedding the log viewer inside existing page chrome (a
/// tab, a side panel, ...) rather than as its own screen.
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
/// runApp(CupertinoApp(
///   home: CupertinoLogViewerPage(controller: controller),
/// ));
/// ```
class CupertinoLogViewerPage extends StatelessWidget {
  const CupertinoLogViewerPage({
    required this.controller,
    this.labels = const LogViewerLabels(),
    this.onContextCopied,
    super.key,
  });

  /// The controller this screen reads from and mutates in response to user
  /// input (search, level/category filter, pause, clear, selection).
  final LogViewerController controller;

  /// The labels to show instead of the English defaults — the title
  /// ([LogViewerLabels.pageTitle]) here, the rest in [CupertinoLogViewer].
  final LogViewerLabels labels;

  /// See [CupertinoLogViewer.onContextCopied].
  final void Function(Map<String, dynamic> entry)? onContextCopied;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          LogViewerLocalizations.resolve(context, labels).pageTitle ?? 'Logs',
        ),
      ),
      // The default bar is translucent, so the scaffold lays the page out
      // behind it and only reports its height as MediaQuery padding; without
      // this the toolbar would sit under the bar, out of reach.
      child: SafeArea(
        child: CupertinoLogViewer(
          controller: controller,
          labels: labels,
          onContextCopied: onContextCopied,
        ),
      ),
    );
  }
}
