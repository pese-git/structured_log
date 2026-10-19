import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

Map<String, dynamic> _entry(String event, {String? category}) => {
      'event': event,
      'level': 'info',
      'timestamp': '2026-01-01T12:00:00.000',
      if (category != null) 'category': category,
      'user_id': 7,
    };

String _levelMarker(LogLevel? level) => 'L:level:${level?.name ?? 'all'}';

/// Every field set to a marker, so a test can tell a label that came from
/// here from a skin default.
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

/// Every English label the Material skin draws by itself.
const _englishDefaults = [
  'Search events, categories…',
  'Pause',
  'Resume',
  'Clear all',
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
  'Copy context',
  'Close',
];

const _levelDefaults = ['Debug+', 'Info+', 'Warning+', 'Error+'];

void _expectNoEnglishDefaults({bool levelNamesTranslated = true}) {
  for (final text in _englishDefaults) {
    if (!levelNamesTranslated && _levelDefaults.contains(text)) continue;
    expect(find.text(text), findsNothing, reason: text);
    expect(find.byTooltip(text), findsNothing, reason: text);
  }
}

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
        if (clipboardFails) {
          throw PlatformException(code: 'unavailable');
        }
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
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [
          LogViewerLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: page
            ? MaterialLogViewerPage(
                controller: controller,
                labels: labels,
                onContextCopied: onContextCopied,
              )
            : Material(
                child: MaterialLogViewer(
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
      captureTwoCategories();
      await pump(tester, page: true);

      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Search events, categories…'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byTooltip('Clear all'), findsOneWidget);
      expect(find.text('All'), findsNWidgets(2));
      expect(find.text('Debug+'), findsOneWidget);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(find.text('CONTEXT'), findsOneWidget);
      expect(find.text('Copy context'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('every label of the toolbar, filters and sheet is replaced',
        (tester) async {
      captureTwoCategories();
      await pump(tester, labels: _markers, page: true);

      expect(find.text('L:pageTitle'), findsOneWidget);
      expect(find.text('L:searchHint'), findsOneWidget);
      expect(find.byTooltip('L:pause'), findsOneWidget);
      expect(find.byTooltip('L:clear'), findsOneWidget);
      expect(find.text('L:allCategories'), findsOneWidget);
      expect(find.text(_levelMarker(null)), findsOneWidget);

      await tester.tap(find.byTooltip('L:pause'));
      await tester.pump();
      expect(find.byTooltip('L:resume'), findsOneWidget);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(find.text('L:contextHeading'), findsOneWidget);
      expect(find.text('L:copyContext'), findsOneWidget);
      expect(find.text('L:close'), findsOneWidget);
      _expectNoEnglishDefaults();
    });

    testWidgets('the wide detail panel takes its labels too', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(tester, labels: _markers, width: 1400);

      for (final level in [
        null,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]) {
        expect(find.text(_levelMarker(level)), findsOneWidget);
      }

      expect(find.text('L:contextHeading'), findsOneWidget);
      expect(find.text('L:copyContext'), findsOneWidget);
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
        MaterialApp(
          home: Material(
            child: LogCategoryChips(
              controller: controller,
              allLabel: 'X',
              labels: const LogViewerLabels(allCategories: 'Y'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('X'), findsOneWidget);
      expect(find.text('Y'), findsNothing);
    });
  });

  group('LogViewerLocalizations.delegate', () {
    testWidgets('Russian comes from the delegate, the sheet included',
        (tester) async {
      captureTwoCategories();
      await pump(tester, locale: const Locale('ru'), page: true);

      const ru = LogViewerLocalizations.russian;
      expect(find.text(ru.pageTitle!), findsOneWidget);
      expect(find.text(ru.searchHint!), findsOneWidget);
      expect(find.byTooltip(ru.pause!), findsOneWidget);
      expect(find.text(ru.allCategories!), findsOneWidget);
      expect(find.text('Все'), findsOneWidget);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(find.text(ru.copyContext!), findsOneWidget);
      expect(find.text(ru.close!), findsOneWidget);
      // Level names are identifiers and stay as they are in Russian.
      _expectNoEnglishDefaults(levelNamesTranslated: false);
      expect(tester.takeException(), isNull);
    });

    for (final width in [360.0, 700.0]) {
      testWidgets('Russian fits a $width-wide window', (tester) async {
        captureTwoCategories();
        await pump(tester, locale: const Locale('ru'), width: width);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('a').first);
        await tester.pumpAndSettle();
        expect(
          find.text(LogViewerLocalizations.russian.copyContext!),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('explicit labels win over the delegate field by field',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(
        tester,
        locale: const Locale('ru'),
        labels: const LogViewerLabels(searchHint: 'Найти'),
      );

      expect(find.text('Найти'), findsOneWidget);
      expect(
        find.byTooltip(LogViewerLocalizations.russian.pause!),
        findsOneWidget,
      );
    });

    testWidgets('English through the delegate keeps the skin wording',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(tester, locale: const Locale('en'));

      expect(find.text('Search events, categories…'), findsOneWidget);
    });
  });

  group('onContextCopied', () {
    testWidgets('is called once with the entry after a successful copy',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy context'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(copied, hasLength(1));
      expect(copied.single['event'], 'a');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the wide panel reports the copy too', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add, width: 1400);

      await tester.tap(find.text('Copy context'));
      await tester.pumpAndSettle();

      expect(copied.single['event'], 'a');
    });

    testWidgets('a failed copy is reported, not confirmed', (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      clipboardFails = true;
      final copied = <Map<String, dynamic>>[];
      await pump(tester, onContextCopied: copied.add, width: 1400);

      await tester.tap(find.text('Copy context'));
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
      expect(tester.takeException(), isA<PlatformException>());
    });

    testWidgets('without a callback the copy still happens, unconfirmed',
        (tester) async {
      buffer.capture(_entry('a'), LogLevel.info);
      await pump(tester, width: 1400);

      await tester.tap(find.text('Copy context'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
