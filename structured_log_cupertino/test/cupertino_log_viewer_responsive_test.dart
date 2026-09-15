import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

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

/// Pumps [CupertinoLogViewer] constrained to [width] — simulating it being
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
    CupertinoApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 700,
          child: CupertinoLogViewer(controller: controller),
        ),
      ),
    ),
  );
}

void main() {
  late LogBuffer buffer;
  late LogViewerController controller;
  String? clipboardText;

  setUp(() {
    buffer = LogBuffer();
    controller = LogViewerController(buffer);
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return {'text': clipboardText};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('below the master-detail breakpoint', () {
    testWidgets('shows only the list, pushing a screen on tap', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpAtWidth(tester, controller, 500);

      expect(tester.takeException(), isNull);
      expect(find.byType(LogEntryDetailPanel), findsNothing);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(find.byType(LogEntryDetailPanel), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    });
  });

  group('at or above the master-detail breakpoint', () {
    testWidgets(
        'shows the list and a detail panel side by side, defaulting to the '
        'newest entry', (tester) async {
      buffer.capture(
          _entry(event: 'a', extra: {'tag': 'first'}), LogLevel.info);
      buffer.capture(
        _entry(event: 'payment_failed', extra: {'error': 'timeout'}),
        LogLevel.error,
      );
      await _pumpAtWidth(tester, controller, 900);

      expect(tester.takeException(), isNull);
      expect(find.byType(LogEntryDetailPanel), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LogEntryDetailPanel),
          matching: find.text('payment_failed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(LogEntryDetailPanel),
          matching: find.text('timeout'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row updates the panel instead of pushing a screen',
        (tester) async {
      buffer.capture(
          _entry(event: 'a', extra: {'tag': 'first-value'}), LogLevel.info);
      buffer.capture(
          _entry(event: 'b', extra: {'tag': 'second-value'}), LogLevel.info);
      await _pumpAtWidth(tester, controller, 900);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoNavigationBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LogEntryDetailPanel),
          matching: find.text('first-value'),
        ),
        findsOneWidget,
      );
      // 'b' stays visible in the list — the panel doesn't cover it.
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('the copy action on the panel copies its context',
        (tester) async {
      buffer.capture(
        _entry(event: 'payment_failed', extra: {'error': 'timeout'}),
        LogLevel.error,
      );
      await _pumpAtWidth(tester, controller, 900);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(clipboardText, contains('error: timeout'));
    });

    testWidgets(
        'clearing all while a panel is open returns to the '
        '(now empty) list', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpAtWidth(tester, controller, 900);
      expect(find.byType(LogEntryDetailPanel), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.delete));
      await tester.pumpAndSettle();

      expect(find.byType(LogEntryDetailPanel), findsNothing);
      expect(find.text('No logs yet'), findsOneWidget);
    });
  });
}
