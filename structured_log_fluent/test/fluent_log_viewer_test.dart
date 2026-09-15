import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

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

/// Pumps [FluentLogViewer] embedded inside an ordinary widget tree — no
/// [ScaffoldPage], no `Navigator.push` — exactly the "drop it into existing
/// page chrome" use case it exists for, as opposed to [FluentLogViewerPage]
/// owning the whole screen.
Future<void> _pumpEmbedded(
  WidgetTester tester,
  LogViewerController controller,
) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    FluentApp(
      home: Row(
        children: [
          const SizedBox(width: 200, child: Text('host sidebar')),
          Expanded(child: FluentLogViewer(controller: controller)),
        ],
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
      'its own (no ScaffoldPage title, no back button)', (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.info);
    await _pumpEmbedded(tester, controller);

    expect(tester.takeException(), isNull);
    expect(find.text('host sidebar'), findsOneWidget);
    expect(_inList('a'), findsOneWidget);
    expect(find.text('Logs'), findsNothing);
    expect(find.byIcon(FluentIcons.back), findsNothing);
  });

  group('list', () {
    testWidgets('newest capture appears above older ones', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      buffer.capture(_entry(event: 'b'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      final aTop = tester.getTopLeft(_inList('a')).dy;
      final bTop = tester.getTopLeft(_inList('b')).dy;
      expect(bTop, lessThan(aTop));
    });

    testWidgets('a row with category shows the category tag', (tester) async {
      buffer.capture(
        _entry(event: 'has_category', category: 'network'),
        LogLevel.info,
      );
      await _pumpEmbedded(tester, controller);

      expect(_inList('network'), findsOneWidget);
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

      expect(find.byType(ComboBox<String?>), findsOneWidget);

      await tester.tap(find.byType(ComboBox<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('protocol').last);
      await tester.pumpAndSettle();

      expect(controller.categoryFilter, 'protocol');
      expect(_inList('proto_event'), findsOneWidget);
      expect(find.text('app_event'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('typing in the search box updates the controller and list',
        (tester) async {
      buffer.capture(_entry(event: 'payment_failed'), LogLevel.error);
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      await tester.enterText(find.byType(TextBox), 'payment');
      await tester.pumpAndSettle();

      expect(controller.searchQuery, 'payment');
      expect(_inList('payment_failed'), findsOneWidget);
      expect(find.text('user_login'), findsNothing);
    });
  });

  group('pause/resume', () {
    testWidgets('toggles the toolbar icon and freezes new entries',
        (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      expect(find.byIcon(FluentIcons.pause), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.pause));
      await tester.pumpAndSettle();

      expect(controller.paused, isTrue);
      expect(find.byIcon(FluentIcons.play), findsOneWidget);

      buffer.capture(_entry(event: 'b'), LogLevel.info);
      await tester.pumpAndSettle();
      expect(find.text('b'), findsNothing);
    });
  });

  group('clear all', () {
    testWidgets('empties the list and the detail pane', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pumpEmbedded(tester, controller);
      expect(find.byType(LogEntryDetailPane), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();

      expect(find.text('a'), findsNothing);
      expect(find.byType(LogEntryDetailPane), findsNothing);
      expect(buffer.entries.value, isEmpty);
    });
  });

  group('master-detail selection', () {
    testWidgets('the detail pane defaults to the newest entry', (tester) async {
      buffer.capture(
          _entry(event: 'a', extra: {'tag': 'first'}), LogLevel.info);
      buffer.capture(
        _entry(event: 'payment_failed', extra: {'error': 'timeout'}),
        LogLevel.error,
      );
      await _pumpEmbedded(tester, controller);

      expect(_inDetailPane('error'), findsOneWidget);
      expect(_inDetailPane('timeout'), findsOneWidget);
    });

    testWidgets('selecting another row updates the detail pane',
        (tester) async {
      buffer.capture(
          _entry(event: 'a', extra: {'tag': 'first-value'}), LogLevel.info);
      buffer.capture(
          _entry(event: 'b', extra: {'tag': 'second-value'}), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      // 'b' (newest) is shown by default; select 'a' instead.
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(_inDetailPane('first-value'), findsOneWidget);
      expect(_inList('a'), findsOneWidget); // still in the list
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('the copy action copies the context as text to the clipboard',
        (tester) async {
      buffer.capture(
        _entry(event: 'payment_failed', extra: {'error': 'timeout'}),
        LogLevel.error,
      );
      await _pumpEmbedded(tester, controller);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(clipboardText, contains('error: timeout'));
    });
  });

  group('empty state', () {
    testWidgets('an empty buffer shows "No logs yet" with no reset action',
        (tester) async {
      await _pumpEmbedded(tester, controller);

      expect(find.text('No logs yet'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
      expect(find.byType(LogEntryDetailPane), findsNothing);
    });

    testWidgets(
        'a filter that matches nothing shows a reset action, and resetting '
        'brings entries back', (tester) async {
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pumpEmbedded(tester, controller);

      controller.levelFilter = LogLevel.critical;
      await tester.pumpAndSettle();

      expect(find.text('No results found'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(controller.levelFilter, isNull);
      expect(_inList('user_login'), findsOneWidget);
    });
  });
}
