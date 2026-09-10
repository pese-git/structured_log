import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

Map<String, dynamic> _entry({
  required String event,
  String level = 'info',
  String? category,
  String timestamp = '2026-01-01T12:00:00.000',
  Map<String, dynamic>? extra,
}) {
  return {
    'event': event,
    'level': level,
    'timestamp': timestamp,
    if (category != null) 'category': category,
    ...?extra,
  };
}

Future<void> _pump(
  WidgetTester tester,
  LogViewerController controller, {
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData.light(useMaterial3: true),
      home: MaterialLogViewerPage(controller: controller),
    ),
  );
}

/// Finds a [Text] with [text] that is a descendant of the currently open
/// [LogEntryDetailSheet] — the underlying list stays mounted (just visually
/// covered) while a modal bottom sheet is shown, so an unscoped
/// `find.text(...)` can match the same value twice (e.g. a category shown
/// both as the row's tag and as a context value in the sheet).
Finder _inDetailSheet(String text) => find.descendant(
      of: find.byType(LogEntryDetailSheet),
      matching: find.text(text),
    );

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

  group('list', () {
    testWidgets('newest capture appears above older ones', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      buffer.capture(_entry(event: 'b'), LogLevel.info);
      await _pump(tester, controller);

      final aTop = tester.getTopLeft(find.text('a')).dy;
      final bTop = tester.getTopLeft(find.text('b')).dy;
      expect(bTop, lessThan(aTop));
    });

    testWidgets('a row without category shows no category tag', (tester) async {
      buffer.capture(_entry(event: 'no_category'), LogLevel.info);
      await _pump(tester, controller);

      expect(find.text('no_category'), findsOneWidget);
      // Only the event and the formatted time are rendered as text — no
      // third Text widget for a category tag.
      expect(
        find.descendant(
          of: find.byType(LogEntryTile),
          matching: find.byType(Text),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('a row with category shows the category tag', (tester) async {
      buffer.capture(
          _entry(event: 'has_category', category: 'network'), LogLevel.info);
      await _pump(tester, controller);

      expect(find.text('network'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('typing in the search field updates the controller and list',
        (tester) async {
      buffer.capture(_entry(event: 'payment_failed'), LogLevel.error);
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pump(tester, controller);

      await tester.enterText(find.byType(TextField), 'payment');
      await tester.pumpAndSettle();

      expect(controller.searchQuery, 'payment');
      expect(find.text('payment_failed'), findsOneWidget);
      expect(find.text('user_login'), findsNothing);
    });
  });

  group('clear all', () {
    testWidgets('the clear action empties the list', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pump(tester, controller);
      expect(find.text('a'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear all'));
      await tester.pumpAndSettle();

      expect(find.text('a'), findsNothing);
      expect(buffer.entries.value, isEmpty);
    });
  });

  group('detail sheet', () {
    testWidgets('tapping a row opens a sheet with its full context',
        (tester) async {
      buffer.capture(
        _entry(
          event: 'payment_failed',
          category: 'payments',
          extra: {'error': 'timeout', 'order_id': 'ord_9182'},
        ),
        LogLevel.error,
      );
      await _pump(tester, controller);

      await tester.tap(find.byType(LogEntryTile));
      await tester.pumpAndSettle();

      expect(find.byType(LogEntryDetailSheet), findsOneWidget);
      expect(_inDetailSheet('category'), findsOneWidget);
      expect(_inDetailSheet('payments'), findsOneWidget);
      expect(_inDetailSheet('error'), findsOneWidget);
      expect(_inDetailSheet('timeout'), findsOneWidget);
      expect(_inDetailSheet('order_id'), findsOneWidget);
      expect(_inDetailSheet('ord_9182'), findsOneWidget);
    });

    testWidgets('the copy action copies context as text to the clipboard',
        (tester) async {
      buffer.capture(
        _entry(event: 'payment_failed', extra: {'error': 'timeout'}),
        LogLevel.error,
      );
      await _pump(tester, controller);

      await tester.tap(find.byType(LogEntryTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy context'));
      await tester.pumpAndSettle();

      expect(clipboardText, contains('error: timeout'));
    });
  });

  group('empty state', () {
    testWidgets('an empty buffer shows "no logs yet" with no reset action',
        (tester) async {
      await _pump(tester, controller);

      expect(find.text('No logs yet'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets(
        'a filter that matches nothing shows a reset action, and resetting '
        'brings entries back', (tester) async {
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pump(tester, controller);

      controller.levelFilter = LogLevel.critical;
      await tester.pumpAndSettle();

      expect(find.text('No logs match the current filter'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(controller.levelFilter, isNull);
      expect(find.text('user_login'), findsOneWidget);
    });
  });

  group('theming', () {
    testWidgets('renders without error under a dark theme', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.warning);
      await _pump(tester, controller, brightness: Brightness.dark);

      expect(tester.takeException(), isNull);
      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
    });
  });
}
