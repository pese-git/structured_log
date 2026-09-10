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

Future<void> _pump(
  WidgetTester tester,
  LogViewerController controller, {
  Brightness brightness = Brightness.light,
}) async {
  // The default 800x600 test surface is too narrow for the command bar
  // (search box + level dropdown + two buttons) to lay out without pushing
  // items outside the viewport — widen it, matching this being a
  // desktop-oriented skin (see design.md).
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

/// Finds a [Text] with [text] that is a descendant of [LogEntryTile] — the
/// selected entry's event/category text is shown both in its list row and
/// (as the title/context) in the always-visible detail pane next to it
/// (it's a split view, not a modal), so an unscoped `find.text(...)` can
/// match both. Use this to assert on the list row specifically.
Finder _inList(String text) => find.descendant(
      of: find.byType(LogEntryTile),
      matching: find.text(text),
    );

/// Finds a [Text] with [text] that is a descendant of [LogEntryDetailPane]
/// — see [_inList] for why an unscoped `find.text(...)` can be ambiguous.
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

  group('list', () {
    testWidgets('newest capture appears above older ones', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      buffer.capture(_entry(event: 'b'), LogLevel.info);
      await _pump(tester, controller);

      final aTop = tester.getTopLeft(_inList('a')).dy;
      final bTop = tester.getTopLeft(_inList('b')).dy;
      expect(bTop, lessThan(aTop));
    });

    testWidgets('a row without category shows no category tag', (tester) async {
      buffer.capture(_entry(event: 'no_category'), LogLevel.info);
      await _pump(tester, controller);

      expect(_inList('no_category'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LogEntryTile),
          matching: find.byType(Text),
        ),
        // level badge, event, time — no fourth Text for a category tag.
        findsNWidgets(3),
      );
    });

    testWidgets('a row with category shows the category tag', (tester) async {
      buffer.capture(
        _entry(event: 'has_category', category: 'network'),
        LogLevel.info,
      );
      await _pump(tester, controller);

      expect(_inList('network'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('typing in the search box updates the controller and list',
        (tester) async {
      buffer.capture(_entry(event: 'payment_failed'), LogLevel.error);
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pump(tester, controller);

      await tester.enterText(find.byType(TextBox), 'payment');
      await tester.pumpAndSettle();

      expect(controller.searchQuery, 'payment');
      expect(_inList('payment_failed'), findsOneWidget);
      expect(find.text('user_login'), findsNothing);
    });
  });

  group('pause/resume', () {
    testWidgets('toggles the header icon and freezes new entries',
        (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.info);
      await _pump(tester, controller);

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
      await _pump(tester, controller);
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
      await _pump(tester, controller);

      expect(_inDetailPane('error'), findsOneWidget);
      expect(_inDetailPane('timeout'), findsOneWidget);
    });

    testWidgets('selecting another row updates the detail pane',
        (tester) async {
      buffer.capture(
          _entry(event: 'a', extra: {'tag': 'first-value'}), LogLevel.info);
      buffer.capture(
          _entry(event: 'b', extra: {'tag': 'second-value'}), LogLevel.info);
      await _pump(tester, controller);

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
      await _pump(tester, controller);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(clipboardText, contains('error: timeout'));
    });
  });

  group('empty state', () {
    testWidgets('an empty buffer shows "No logs yet" with no reset action',
        (tester) async {
      await _pump(tester, controller);

      expect(find.text('No logs yet'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
      expect(find.byType(LogEntryDetailPane), findsNothing);
    });

    testWidgets(
        'a filter that matches nothing shows a reset action, and resetting '
        'brings entries back', (tester) async {
      buffer.capture(_entry(event: 'user_login'), LogLevel.info);
      await _pump(tester, controller);

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

  group('theming', () {
    testWidgets('renders without error under a dark theme', (tester) async {
      buffer.capture(_entry(event: 'a'), LogLevel.warning);
      await _pump(tester, controller, brightness: Brightness.dark);

      expect(tester.takeException(), isNull);
      expect(find.text('Logs'), findsOneWidget);
      expect(_inList('a'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('no back button when the page is the navigator root',
        (tester) async {
      await _pump(tester, controller);

      expect(find.byIcon(FluentIcons.back), findsNothing);
    });

    testWidgets('a back button pops the page when it was pushed',
        (tester) async {
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
  });
}
