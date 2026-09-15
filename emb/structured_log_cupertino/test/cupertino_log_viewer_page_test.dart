import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

Map<String, dynamic> _entry({
  required String event,
  String level = 'info',
  String timestamp = '2026-01-01T12:00:00.000',
}) {
  return {'event': event, 'level': level, 'timestamp': timestamp};
}

/// [CupertinoLogViewerPage] itself is now a thin [CupertinoPageScaffold]
/// wrapper around [CupertinoLogViewer] — its own behavior is just the
/// navigation bar title (and the back button [CupertinoNavigationBar] shows
/// automatically when pushed); everything else (list, filters, search,
/// pause/clear, the mobile push-navigation vs. wide master-detail split) is
/// [CupertinoLogViewer]'s and is covered in cupertino_log_viewer_test.dart /
/// cupertino_log_viewer_responsive_test.dart.
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
    CupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      home: CupertinoLogViewerPage(controller: controller),
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

  testWidgets('wraps CupertinoLogViewer with a "Logs" navigation bar title',
      (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.text('Logs'), findsOneWidget);
    expect(find.byType(CupertinoLogViewer), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('a back button pops the page when it was pushed', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        CupertinoLogViewerPage(controller: controller),
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

    expect(find.byType(CupertinoLogViewerPage), findsOneWidget);
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);

    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoLogViewerPage), findsNothing);
  });

  testWidgets('renders without error under a dark theme', (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.warning);
    await _pump(tester, controller, brightness: Brightness.dark);

    expect(tester.takeException(), isNull);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
  });
}
