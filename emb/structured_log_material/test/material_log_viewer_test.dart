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

/// Pumps [MaterialLogViewer] embedded inside an ordinary widget tree — no
/// [Scaffold]/[AppBar]/[Navigator.push] of its own — at a width below the
/// master-detail breakpoint, so it's in its default mobile-style mode
/// (list + modal bottom sheet on tap), exactly the "drop it into existing
/// page chrome" use case it exists for. The wide/master-detail layout is
/// covered separately in material_log_viewer_responsive_test.dart.
///
/// Wrapped in a bare [Material] (not a [Scaffold]) — Material widgets like
/// [TextField]/[InkWell]/[ChoiceChip] need *some* Material ancestor to
/// paint ink on, same as any real host app would already provide via its
/// own Scaffold; a [Material] here supplies exactly that without adding
/// page chrome of its own.
Future<void> _pumpEmbedded(
  WidgetTester tester,
  LogViewerController controller,
) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Row(
          children: [
            const SizedBox(width: 1, child: Text('')),
            Expanded(child: MaterialLogViewer(controller: controller)),
          ],
        ),
      ),
    ),
  );
}

/// Finds a [Text] with [text] that is a descendant of the currently open
/// [LogEntryDetailSheet] — the underlying list stays mounted (just visually
/// covered) while a modal bottom sheet is shown, so an unscoped
/// `find.text(...)` can match the same value twice.
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

  testWidgets(
      'renders alongside other content with no page chrome of '
      'its own (no AppBar title, no Scaffold)', (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.info);
    await _pumpEmbedded(tester, controller);

    expect(tester.takeException(), isNull);
    expect(find.text('a'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  group('list', () {
    testWidgets('newest capture appears above older ones', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      buffer.capture(_entry(event: 'b'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      final aTop = tester.getTopLeft(find.text('a')).dy;
      final bTop = tester.getTopLeft(find.text('b')).dy;
      expect(bTop, lessThan(aTop));
    });

    testWidgets('a row without category shows no category tag', (tester) async {
      buffer.capture(_entry(event: 'no_category'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      expect(find.text('no_category'), findsOneWidget);
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
      await _pumpEmbedded(tester, controller);

      expect(find.text('network'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('typing in the search field updates the controller and list',
        (tester) async {
      buffer.capture(_entry(event: 'payment_failed'), LogLevel.error);
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      await tester.enterText(find.byType(TextField), 'payment');
      await tester.pumpAndSettle();

      expect(controller.searchQuery, 'payment');
      expect(find.text('payment_failed'), findsOneWidget);
      expect(find.text('user_login'), findsNothing);
    });
  });

  group('pause/resume', () {
    testWidgets('toggles the toolbar icon and freezes new entries',
        (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();

      expect(controller.paused, isTrue);
      expect(find.byTooltip('Resume'), findsOneWidget);

      buffer.capture(_entry(event: 'b'), LogLevel.info);
      await tester.pumpAndSettle();
      expect(find.text('b'), findsNothing);
    });
  });

  group('clear all', () {
    testWidgets('the clear action empties the list', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpEmbedded(tester, controller);
      expect(find.text('a'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear all'));
      await tester.pumpAndSettle();

      expect(find.text('a'), findsNothing);
      expect(buffer.entries.value, isEmpty);
    });
  });

  group('category filter', () {
    testWidgets(
        'appears and filters the list once two or more categories are '
        'present', (tester) async {
      buffer.capture(
        _entry(event: 'app_event', category: 'application'),
        LogLevel.info,
      );
      buffer.capture(
        _entry(event: 'proto_event', category: 'protocol'),
        LogLevel.info,
      );
      await _pumpEmbedded(tester, controller);

      expect(find.byType(LogCategoryChips), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'protocol'));
      await tester.pumpAndSettle();

      expect(controller.categoryFilter, 'protocol');
      expect(find.text('proto_event'), findsOneWidget);
      expect(find.text('app_event'), findsNothing);
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
      await _pumpEmbedded(tester, controller);

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
      await _pumpEmbedded(tester, controller);

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
      await _pumpEmbedded(tester, controller);

      expect(find.text('No logs yet'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets(
        'a filter that matches nothing shows a reset action, and resetting '
        'brings entries back', (tester) async {
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

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
}
