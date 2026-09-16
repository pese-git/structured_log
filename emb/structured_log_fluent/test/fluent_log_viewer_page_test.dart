import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

Finder _inList(String text) => find.descendant(
      of: find.byType(LogEntryTile),
      matching: find.text(text),
    );

Map<String, dynamic> _entry({
  required String event,
  String level = 'info',
  String timestamp = '2026-01-01T12:00:00.000',
}) {
  return {'event': event, 'level': level, 'timestamp': timestamp};
}

/// [FluentLogViewerPage] itself is now a thin [ScaffoldPage] wrapper around
/// [FluentLogViewer] — its own behavior is just the title and back button;
/// everything else (list, filters, search, pause/clear, selection, empty
/// state) is [FluentLogViewer]'s and is covered in fluent_log_viewer_test.dart.
Future<void> _pump(
  WidgetTester tester,
  LogViewerController controller, {
  Brightness brightness = Brightness.light,
}) async {
  // The default 800x600 test surface is too narrow for the toolbar (search
  // box + dropdowns + two buttons) to lay out without pushing items outside
  // the viewport — widen it, matching this being a desktop-oriented skin.
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    FluentApp(
      theme: FluentThemeData(brightness: Brightness.light),
      darkTheme: FluentThemeData(brightness: Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: FluentLogViewerPage(controller: controller),
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

  testWidgets(
      'wraps FluentLogViewer with a "Logs" title and no back '
      'button when it is the navigator root', (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.text('Logs'), findsOneWidget);
    expect(find.byType(FluentLogViewer), findsOneWidget);
    expect(find.byIcon(FluentIcons.back), findsNothing);
    expect(_inList('a'), findsOneWidget);
  });

  testWidgets('a back button pops the page when it was pushed', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) => Button(
            onPressed: () => Navigator.of(context).push(
              FluentPageRoute<void>(
                builder: (_) => FluentLogViewerPage(controller: controller),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(FluentLogViewerPage), findsOneWidget);
    expect(find.byIcon(FluentIcons.back), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.back));
    await tester.pumpAndSettle();

    expect(find.byType(FluentLogViewerPage), findsNothing);
  });

  testWidgets('renders without error under a dark theme', (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.warning);
    await _pump(tester, controller, brightness: Brightness.dark);

    expect(tester.takeException(), isNull);
    expect(find.text('Logs'), findsOneWidget);
  });
}
