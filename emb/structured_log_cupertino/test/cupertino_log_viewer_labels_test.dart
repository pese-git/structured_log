import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

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

/// Every English label the Cupertino skin draws by itself.
const _englishDefaults = [
  'Search events, categories…',
  'All',
  'Debug+',
  'Info+',
  'Warning+',
  'Error+',
  'Logs',
  'No logs yet',
  'Logs will appear here as soon as your app emits its first event.',
  'No logs match the current filter',
  'Try a different search term, or clear the active filters to see '
      'everything.',
  'Clear filters',
  'CONTEXT',
  'Copy',
];

const _levelDefaults = ['Debug+', 'Info+', 'Warning+', 'Error+'];

void _expectNoEnglishDefaults({bool levelNamesTranslated = true}) {
  for (final text in _englishDefaults) {
    if (!levelNamesTranslated && _levelDefaults.contains(text)) continue;
    expect(find.text(text), findsNothing, reason: text);
  }
}

Finder _inDetailPanel(String text) => find.descendant(
      of: find.byType(LogEntryDetailPanel),
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
    double width = 500,
    Locale? locale,
    bool page = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CupertinoApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [
          LogViewerLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: page
            ? CupertinoLogViewerPage(
                controller: controller,
                labels: labels,
                onContextCopied: onContextCopied,
              )
            : CupertinoPageScaffold(
                child: CupertinoLogViewer(
                  controller: controller,
                  labels: labels,
                  onContextCopied: onContextCopied,
                ),
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
      final semantics = tester.ensureSemantics();
      captureTwoCategories();
      await pump(tester, page: true);

      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Search events, categories…'), findsOneWidget);
      expect(find.text('All'), findsNWidgets(2));
      expect(find.text('Error+'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.bySemanticsLabel('Clear all'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('every label of the toolbar and filters is replaced',
        (tester) async {
      captureTwoCategories();
      await pump(tester, labels: _markers, page: true, width: 1400);

      expect(find.text('L:pageTitle'), findsOneWidget);
      expect(find.text('L:searchHint'), findsOneWidget);
      expect(find.text('L:allCategories'), findsOneWidget);
      for (final level in [
        null,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]) {
        expect(find.text(_levelMarker(level)), findsOneWidget);
      }
      expect(_inDetailPanel('L:contextHeading'), findsOneWidget);
      expect(_inDetailPanel('L:copyContext'), findsOneWidget);
      _expectNoEnglishDefaults();
    });

    testWidgets('the icon-only buttons get semantics labels', (tester) async {
      final semantics = tester.ensureSemantics();
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(tester, labels: _markers);

      expect(find.bySemanticsLabel('L:pause'), findsOneWidget);
      expect(find.bySemanticsLabel('L:clear'), findsOneWidget);

      controller.paused = true;
      await tester.pump();
      expect(find.bySemanticsLabel('L:resume'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the pushed detail screen takes its labels', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(tester, labels: _markers);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(_inDetailPanel('L:contextHeading'), findsOneWidget);
      expect(_inDetailPanel('L:copyContext'), findsOneWidget);
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
        CupertinoApp(
          home: LogCategoryFilterBar(
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
    testWidgets('Russian comes from the delegate, the pushed screen included',
        (tester) async {
      captureTwoCategories();
      await pump(tester, locale: const Locale('ru'), page: true);

      const ru = LogViewerLocalizations.russian;
      expect(find.text(ru.pageTitle!), findsOneWidget);
      expect(find.text(ru.searchHint!), findsOneWidget);
      expect(find.text(ru.allCategories!), findsOneWidget);
      expect(find.text('Все'), findsOneWidget);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(_inDetailPanel(ru.copyContext!), findsOneWidget);
      expect(_inDetailPanel(ru.contextHeading!), findsOneWidget);
      _expectNoEnglishDefaults(levelNamesTranslated: false);
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
      expect(find.text(LogViewerLocalizations.russian.allCategories!),
          findsNothing); // one category only: the bar hides itself
      expect(find.text('Все'), findsOneWidget);
    });

    testWidgets('long Russian labels fit a 360-wide phone', (tester) async {
      captureTwoCategories();
      await pump(
        tester,
        locale: const Locale('ru'),
        labels: LogViewerLabels(
          levelFilterLabel: (level) =>
              level == null ? 'Все уровни' : '${level.name} и выше',
        ),
        width: 360,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Все уровни'), findsOneWidget);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('onContextCopied', () {
    testWidgets('is called once with the entry from the pushed screen',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.tap(_inDetailPanel('Copy'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(copied.single['event'], 'a');
    });

    testWidgets('a failed copy is reported, not confirmed', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      clipboardFails = true;
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add, width: 1400);

      await tester.tap(_inDetailPanel('Copy'));
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
      expect(tester.takeException(), isA<PlatformException>());
    });
  });
}
