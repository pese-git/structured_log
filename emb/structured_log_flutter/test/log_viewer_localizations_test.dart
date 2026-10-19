import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

List<Object?> _fields(LogViewerLabels l) => [
      l.searchHint,
      l.pause,
      l.resume,
      l.clear,
      l.levelFilterLabel,
      l.allCategories,
      l.pageTitle,
      l.emptyTitle,
      l.emptyMessage,
      l.noMatchesTitle,
      l.noMatchesMessage,
      l.clearFilters,
      l.contextHeading,
      l.copyContext,
      l.close,
      l.backToList,
    ];

/// Resolves [labels] under a [Localizations] for [locale], with the
/// delegate registered only when [withDelegate] is set.
Future<LogViewerLabels> _resolve(
  WidgetTester tester,
  LogViewerLabels labels, {
  Locale locale = const Locale('ru'),
  bool withDelegate = true,
}) async {
  late LogViewerLabels resolved;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: [
        DefaultWidgetsLocalizations.delegate,
        if (withDelegate) LogViewerLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          resolved = LogViewerLocalizations.resolve(context, labels);
          return const SizedBox();
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  group('LogViewerLocalizations.delegate', () {
    test('Russian sets every label', () async {
      final ru = await LogViewerLocalizations.delegate.load(const Locale('ru'));

      expect(_fields(ru.labels), everyElement(isNotNull));
      expect(ru.labels.levelFilterLabel!(null), 'Все');
      expect(ru.labels.levelFilterLabel!(LogLevel.warning), 'Warning+');
    });

    test('English leaves every label to the skin', () async {
      final en = await LogViewerLocalizations.delegate.load(const Locale('en'));

      expect(_fields(en.labels), everyElement(isNull));
    });

    test('supports en and ru by language code only', () {
      const delegate = LogViewerLocalizations.delegate;

      expect(delegate.isSupported(const Locale('ru', 'RU')), isTrue);
      expect(delegate.isSupported(const Locale('en', 'GB')), isTrue);
      expect(delegate.isSupported(const Locale('de')), isFalse);
    });

    test('loads synchronously', () {
      final future = LogViewerLocalizations.delegate.load(const Locale('ru'));

      expect(future, isA<SynchronousFuture<LogViewerLocalizations>>());
    });
  });

  group('LogViewerLocalizations.resolve', () {
    testWidgets('an explicit label wins over the delegate, field by field',
        (tester) async {
      final resolved =
          await _resolve(tester, const LogViewerLabels(pause: 'Стоп'));

      expect(resolved.pause, 'Стоп');
      expect(resolved.resume, 'Продолжить');
      expect(resolved.searchHint, LogViewerLocalizations.russian.searchHint);
    });

    testWidgets('without the delegate the given labels come back as they are',
        (tester) async {
      final resolved = await _resolve(
        tester,
        const LogViewerLabels(pause: 'Стоп'),
        withDelegate: false,
      );

      expect(resolved.pause, 'Стоп');
      expect(resolved.resume, isNull);
      expect(LogViewerLocalizations.of(tester.element(find.byType(SizedBox))),
          isNull);
    });

    testWidgets('English through the delegate keeps skin defaults',
        (tester) async {
      final resolved = await _resolve(
        tester,
        const LogViewerLabels(),
        locale: const Locale('en'),
      );

      expect(_fields(resolved), everyElement(isNull));
    });
  });
}
