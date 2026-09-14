import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

Map<String, dynamic> _entry({
  required String event,
  String level = 'info',
  String timestamp = '2026-01-01T12:00:00.000',
}) {
  return {'event': event, 'level': level, 'timestamp': timestamp};
}

/// [MaterialLogViewerPage] itself is now a thin [Scaffold]/[AppBar] wrapper
/// around [MaterialLogViewer] — its own behavior is just the title (and the
/// back button [AppBar] shows automatically when pushed); everything else
/// (list, filters, search, pause/clear, the mobile bottom sheet vs. wide
/// master-detail split) is [MaterialLogViewer]'s and is covered in
/// material_log_viewer_test.dart / material_log_viewer_responsive_test.dart.
///
/// Pumped at a narrow width (below the master-detail breakpoint) so these
/// smoke tests exercise the same mobile-style default a bare `flutter test`
/// surface would otherwise land right on the edge of.
Future<void> _pump(
  WidgetTester tester,
  LogViewerController controller, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData.light(useMaterial3: true),
      home: MaterialLogViewerPage(controller: controller),
    ),
  );
}

void main() {
  late LogBuffer buffer;
  late LogViewerController controller;

  setUp(() {
    buffer = LogBuffer();
    controller = LogViewerController(buffer);
  });

  tearDown(() => controller.dispose());

  testWidgets('wraps MaterialLogViewer with a "Logs" app bar title',
      (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.text('Logs'), findsOneWidget);
    expect(find.byType(MaterialLogViewer), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('a back button pops the page when it was pushed', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MaterialLogViewerPage(controller: controller),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialLogViewerPage), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialLogViewerPage), findsNothing);
  });

  testWidgets('renders without error under a dark theme', (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.warning);
    await _pump(tester, controller, brightness: Brightness.dark);

    expect(tester.takeException(), isNull);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
  });
}
