import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

Map<String, dynamic> _entry(String event, {String? category}) => {
      'event': event,
      'level': 'info',
      'timestamp': '2026-01-01T12:00:00.000',
      if (category != null) 'category': category,
      'user_id': 7,
    };

String _levelMarker(LogLevel? level) => 'L:level:${level?.name ?? 'all'}';

final _markers = LogViewerLabels(
  searchHint: 'L:searchHint',
  pause: 'L:pause',
  resume: 'L:resume',
  clear: 'L:clear',
  levelFilterLabel: _levelMarker,
  allCategories: 'L:allCategories',
  pageTitle: 'L:pageTitle',
  emptyTitle: 'L:emptyTitle',
  emptyMessage: 'L:emptyMessage',
  noMatchesTitle: 'L:noMatchesTitle',
  noMatchesMessage: 'L:noMatchesMessage',
  clearFilters: 'L:clearFilters',
  contextHeading: 'L:contextHeading',
  copyContext: 'L:copyContext',
  close: 'L:close',
  backToList: 'L:backToList',
);

/// Every English label the Fluent skin draws by itself.
const _englishDefaults = [
  'Search',
  'Pause',
  'Resume',
  'Clear all',
  'All levels',
  'Debug and above',
  'Info and above',
  'Warning and above',
  'Error and above',
  'All types',
  'Logs',
  'No logs yet',
  'Logs will appear here as soon as your app emits its first event.',
  'No results found',
  'No log entries match the current filter.',
  'Clear filters',
  'CONTEXT',
  'Copy',
  'Back to list',
];

/// A Fluent [Tooltip] with [message] — `find.byTooltip` only knows the
/// Material one.
Finder _tooltip(String message) =>
    find.byWidgetPredicate((w) => w is Tooltip && w.message == message);

void _expectNoEnglishDefaults() {
  for (final text in _englishDefaults) {
    expect(find.text(text), findsNothing, reason: text);
    expect(_tooltip(text), findsNothing, reason: text);
  }
}

Finder _inDetailPane(String text) => find.descendant(
      of: find.byType(LogEntryDetailPane),
      matching: find.text(text),
    );

void main() {
  late LogBuffer buffer;
  late LogViewerController controller;
  late List<MethodCall> clipboardCalls;
  late bool clipboardFails;

  setUp(() {
    buffer = LogBuffer();
    controller = LogViewerController(buffer);
    clipboardCalls = [];
    clipboardFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardCalls.add(call);
        if (clipboardFails) throw PlatformException(code: 'unavailable');
      }
      return null;
    });
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(
    WidgetTester tester, {
    LogViewerLabels labels = const LogViewerLabels(),
    void Function(Map<String, dynamic> entry)? onContextCopied,
    double width = 1200,
    Locale? locale,
    bool page = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [
          LogViewerLocalizations.delegate,
          FluentLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: page
            ? FluentLogViewerPage(
                controller: controller,
                labels: labels,
                onContextCopied: onContextCopied,
              )
            : FluentLogViewer(
                controller: controller,
                labels: labels,
                onContextCopied: onContextCopied,
              ),
      ),
    );
    await tester.pump();
  }

  void captureTwoCategories() {
    buffer
      ..capture(_entry('a', category: 'net'), LogLevel.info)
      ..capture(_entry('b', category: 'db'), LogLevel.info);
  }

  group('labels', () {
    testWidgets('without labels the English defaults stay', (tester) async {
      captureTwoCategories();
      await pump(tester, page: true);

      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(_tooltip('Pause'), findsOneWidget);
      expect(_tooltip('Clear all'), findsOneWidget);
      expect(find.text('All levels'), findsOneWidget);
      expect(find.text('All types'), findsOneWidget);
      expect(_inDetailPane('CONTEXT'), findsOneWidget);
      expect(_inDetailPane('Copy'), findsOneWidget);
    });

    testWidgets('every label of the toolbar, filters and pane is replaced',
        (tester) async {
      captureTwoCategories();
      await pump(tester, labels: _markers, page: true);

      expect(find.text('L:pageTitle'), findsOneWidget);
      expect(find.text('L:searchHint'), findsOneWidget);
      expect(_tooltip('L:pause'), findsOneWidget);
      expect(_tooltip('L:clear'), findsOneWidget);
      expect(find.text('L:allCategories'), findsOneWidget);
      expect(_inDetailPane('L:contextHeading'), findsOneWidget);
      expect(_inDetailPane('L:copyContext'), findsOneWidget);

      await tester.tap(find.text(_levelMarker(null)));
      await tester.pumpAndSettle();
      for (final level in [
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]) {
        expect(find.text(_levelMarker(level)), findsOneWidget);
      }
      _expectNoEnglishDefaults();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(_tooltip('L:pause'));
      await tester.pump();
      expect(_tooltip('L:resume'), findsOneWidget);
      // Let the tooltip's show/hide timers run out.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the narrow layout labels its back button', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(tester, labels: _markers, width: 500);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(_tooltip('L:backToList'), findsOneWidget);
      expect(_inDetailPane('L:copyContext'), findsOneWidget);
      _expectNoEnglishDefaults();
    });

    testWidgets('both empty states are replaced', (tester) async {
      await pump(tester, labels: _markers);
      expect(find.text('L:emptyTitle'), findsOneWidget);
      expect(find.text('L:emptyMessage'), findsOneWidget);
      _expectNoEnglishDefaults();

      buffer.capture(_entry('a'), LogLevel.info);
      controller.searchQuery = 'nothing matches this';
      await tester.pump();
      expect(find.text('L:noMatchesTitle'), findsOneWidget);
      expect(find.text('L:noMatchesMessage'), findsOneWidget);
      expect(find.text('L:clearFilters'), findsOneWidget);
      _expectNoEnglishDefaults();
    });

    testWidgets('an explicit allLabel wins over labels', (tester) async {
      captureTwoCategories();
      await tester.pumpWidget(
        FluentApp(
          home: LogCategoryComboBox(
            controller: controller,
            allLabel: 'X',
            labels: const LogViewerLabels(allCategories: 'Y'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('X'), findsOneWidget);
      expect(find.text('Y'), findsNothing);
    });
  });

  group('LogViewerLocalizations.delegate', () {
    testWidgets('Russian comes from the delegate, the pane included',
        (tester) async {
      captureTwoCategories();
      await pump(tester, locale: const Locale('ru'), page: true);

      const ru = LogViewerLocalizations.russian;
      expect(find.text(ru.pageTitle!), findsOneWidget);
      expect(find.text(ru.searchHint!), findsOneWidget);
      expect(_tooltip(ru.pause!), findsOneWidget);
      expect(find.text(ru.allCategories!), findsOneWidget);
      expect(find.text('Все'), findsOneWidget);
      expect(_inDetailPane(ru.copyContext!), findsOneWidget);
      _expectNoEnglishDefaults();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Russian fits a 360-wide window, the detail pane included',
        (tester) async {
      captureTwoCategories();
      await pump(tester, locale: const Locale('ru'), width: 360);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(_inDetailPane(LogViewerLocalizations.russian.copyContext!),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explicit labels win over the delegate field by field',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(
        tester,
        locale: const Locale('ru'),
        labels: const LogViewerLabels(searchHint: 'Найти'),
      );

      expect(find.text('Найти'), findsOneWidget);
      expect(_tooltip(LogViewerLocalizations.russian.pause!), findsOneWidget);
    });
  });

  group('onContextCopied', () {
    testWidgets('is called once with the entry after a successful copy',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add);

      await tester.tap(_inDetailPane('Copy'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(copied.single['event'], 'a');
    });

    testWidgets('a failed copy is reported, not confirmed', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      clipboardFails = true;
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add);

      await tester.tap(_inDetailPane('Copy'));
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
      expect(tester.takeException(), isA<PlatformException>());
    });
  });
}
