import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

Map<String, dynamic> _entry({
  required String event,
  String level = 'info',
  Map<String, dynamic>? extra,
}) {
  return {
    'event': event,
    'level': level,
    'timestamp': '2026-01-01T12:00:00.000',
    ...?extra,
  };
}

/// Pumps [FluentLogViewer] constrained to [width] — simulating it being
/// docked in a side panel (or a narrow window) of that width, rather than
/// resizing the whole test surface.
Future<void> _pumpAtWidth(
  WidgetTester tester,
  LogViewerController controller,
  double width,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 700,
          child: FluentLogViewer(controller: controller),
        ),
      ),
    ),
  );
}

Finder _inList(String text) => find.descendant(
      of: find.byType(LogEntryTile),
      matching: find.text(text),
    );

Finder _inDetailPane(String text) => find.descendant(
      of: find.byType(LogEntryDetailPane),
      matching: find.text(text),
    );

void main() {
  late LogBuffer buffer;
  late LogViewerController controller;

  setUp(() {
    buffer = LogBuffer();
    controller = LogViewerController(buffer);
  });

  tearDown(() => controller.dispose());

  group('toolbar', () {
    testWidgets('lays out in one row above the toolbar breakpoint',
        (tester) async {
      await _pumpAtWidth(tester, controller, 900);

      expect(tester.takeException(), isNull);
      final searchTop = tester.getTopLeft(find.byType(TextBox)).dy;
      final levelTop = tester.getTopLeft(find.byType(ComboBox<LogLevel?>)).dy;
      // Same row: near-identical tops, modulo each control's own internal
      // padding/border (a couple of px) — not the ~40px a wrapped second
      // row would put between them.
      expect(searchTop, closeTo(levelTop, 4));
    });

    testWidgets('wraps onto a second row below the toolbar breakpoint',
        (tester) async {
      await _pumpAtWidth(tester, controller, 500);

      expect(tester.takeException(), isNull);
      final searchTop = tester.getTopLeft(find.byType(TextBox)).dy;
      final levelTop = tester.getTopLeft(find.byType(ComboBox<LogLevel?>)).dy;
      expect(levelTop, greaterThan(searchTop));
    });
  });

  group('master-detail', () {
    testWidgets(
        'shows the list and detail pane side by side above the '
        'master-detail breakpoint', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpAtWidth(tester, controller, 900);

      expect(tester.takeException(), isNull);
      expect(find.byType(LogEntryTile), findsOneWidget);
      expect(find.byType(LogEntryDetailPane), findsOneWidget);
    });

    testWidgets(
        'shows only the list below the master-detail breakpoint, with no '
        'detail pane until an entry is tapped', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpAtWidth(tester, controller, 500);

      expect(tester.takeException(), isNull);
      expect(_inList('a'), findsOneWidget);
      expect(find.byType(LogEntryDetailPane), findsNothing);
    });

    testWidgets(
        'tapping an entry below the breakpoint replaces the list with its '
        'detail, and the back button returns to the list', (tester) async {
      buffer.capture(
        _entry(event: 'payment_failed', extra: {'error': 'timeout'}),
        LogLevel.error,
      );
      await _pumpAtWidth(tester, controller, 500);

      await tester.tap(find.text('payment_failed'));
      await tester.pumpAndSettle();

      expect(find.byType(LogEntryTile), findsNothing);
      expect(_inDetailPane('payment_failed'), findsOneWidget);
      expect(_inDetailPane('timeout'), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.back));
      await tester.pumpAndSettle();

      expect(_inList('payment_failed'), findsOneWidget);
      expect(find.byType(LogEntryDetailPane), findsNothing);
    });

    testWidgets(
        'clearing all while a detail is open below the breakpoint returns '
        'to the (now empty) list', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpAtWidth(tester, controller, 500);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(_inDetailPane('a'), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();

      expect(find.byType(LogEntryDetailPane), findsNothing);
      expect(find.text('No logs yet'), findsOneWidget);
    });
  });
}
