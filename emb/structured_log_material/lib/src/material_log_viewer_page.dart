import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'material_log_viewer.dart';

/// A ready-to-use Material 3 full-screen log viewer for `structured_log`,
/// built on a [LogViewerController].
///
/// A thin [Scaffold]/[AppBar] wrapper around [MaterialLogViewer] (title
/// "Logs"; a back button is shown automatically by [AppBar] when this is
/// pushed via `Navigator`). Use [MaterialLogViewer] directly instead when
/// embedding the log viewer inside existing page chrome (a tab, a side
/// panel, a dialog, ...) rather than as its own screen.
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
/// // Push it, or embed it as a tab/page in your own navigation:
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => MaterialLogViewerPage(controller: controller),
/// ));
/// ```
class MaterialLogViewerPage extends StatelessWidget {
  const MaterialLogViewerPage({required this.controller, super.key});

  /// The controller this screen reads from and mutates in response to user
  /// input (search, level/category filter, pause, clear, selection).
  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logs')),
      body: MaterialLogViewer(controller: controller),
    );
  }
}
