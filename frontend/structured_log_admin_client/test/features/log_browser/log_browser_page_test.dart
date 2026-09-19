import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/log_browser/application/load_scopes.dart';
import 'package:structured_log_admin_client/features/log_browser/application/query_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/application/watch_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/live_feed_event.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_browser_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_browser_page.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_feed_bloc.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/log_dto.dart';

import '../../support/localized_app.dart';

class _FakeRepository implements LogBrowserRepository {
  final calls = <({LogScope scope, LogFilter filter, String? cursor})>[];
  List<LogEntryDto> entries = [];

  /// The one live subscription the screen opens, so a test can deliver an
  /// entry into it.
  StreamController<LiveFeedEvent>? live;

  @override
  Future<Either<ApiFailure, ScopeOptions>> loadMoreScopes({
    required bool groups,
    required String cursor,
  }) async => right(const ScopeOptions());

  @override
  Future<Either<ApiFailure, ScopeOptions>> loadScopes() async => right(
    const ScopeOptions(
      groups: [GroupScope(id: 7, name: 'acme')],
      projects: [ProjectScope(id: 1, name: 'payments')],
    ),
  );

  @override
  Future<Either<ApiFailure, LogPage>> query({
    required LogScope scope,
    required LogFilter filter,
    String? cursor,
    int limit = 50,
  }) async {
    calls.add((scope: scope, filter: filter, cursor: cursor));
    return right((entries: entries, nextCursor: null));
  }

  @override
  Stream<LiveFeedEvent> watch({
    required LogScope scope,
    required LogFilter filter,
    int? sinceId,
  }) {
    final controller = StreamController<LiveFeedEvent>();
    live = controller;
    return controller.stream;
  }
}

LogEntryDto _entry() => LogEntryDto(
  id: 918273,
  projectId: 1,
  receivedAt: DateTime.utc(2026, 9, 15, 9, 12, 55),
  event: 'Webhook delivery failed after 3 attempts',
  level: 'error',
  category: 'webhooks',
  requestId: 'req-9f2c',
  context: const {'webhook_url': 'https://example.test/hooks', 'attempt': 3},
);

LogEntryDto _live(int id) => LogEntryDto(
  id: id,
  projectId: 1,
  receivedAt: DateTime.utc(2026, 9, 15, 9, 20),
  event: 'Payment captured',
  level: 'info',
  context: const {},
);

Widget _host(LogFeedBloc bloc, {Locale locale = const Locale('ru')}) =>
    localizedApp(
      locale: locale,
      home: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: BlocProvider.value(value: bloc, child: const LogBrowserPage()),
      ),
    );

void main() {
  late _FakeRepository repository;
  late LogFeedBloc bloc;

  setUp(() => repository = _FakeRepository());

  // Not awaited. `Bloc.close()` never completes inside `testWidgets` on this
  // Flutter/bloc pair — it hangs waiting on its own event controller under the
  // test's fake clock, and a bare two-line bloc does the same, so this is the
  // harness rather than anything here. Awaiting it hangs the whole file.
  tearDown(() => unawaited(bloc.close()));

  /// Builds the bloc **inside the test body**, which is not a style choice.
  ///
  /// A `Bloc` constructed in `setUp` belongs to the zone `setUp` ran in, and
  /// the events a widget adds from inside `testWidgets` are then never
  /// processed: the screen sits on its first state forever and `pumpAndSettle`
  /// runs out of patience. A `Cubit` has no event stream and does not care,
  /// which is why this only appeared when section 22 turned one into the
  /// other.
  LogFeedBloc makeBloc() => bloc = LogFeedBloc(
    loadScopes: LoadScopes(repository),
    queryLogs: QueryLogs(repository),
    watchLogs: WatchLogs(repository),
    pauseBufferLimit: 2,
  );

  void useWideSurface(WidgetTester tester) {
    // The screen is a master/detail split at the artboard's width; the
    // default 800 leaves the detail pane nothing to sit in.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void useNarrowSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    useWideSurface(tester);
    await tester.pumpWidget(_host(makeBloc()));
    await tester.pumpAndSettle();
  }

  /// Opens the screen on a scope, with whatever [repository] is set to answer.
  Future<void> openFeed(WidgetTester tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('payments'));
    await tester.pumpAndSettle();
  }

  testWidgets('the selector stands in place of the list, and queries nothing', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Выберите область'), findsOneWidget);
    expect(find.text('payments'), findsOneWidget);
    expect(find.text('acme'), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  testWidgets('choosing a scope loads the feed', (tester) async {
    repository.entries = [_entry()];

    await openFeed(tester);

    expect(repository.calls.single.scope, isA<ProjectScope>());
    expect(
      find.text('Webhook delivery failed after 3 attempts'),
      findsOneWidget,
    );
    expect(find.text('ERR'), findsOneWidget);
    expect(find.text('Проект: payments'), findsOneWidget);
  });

  testWidgets('level and search combine into one request', (tester) async {
    await openFeed(tester);
    repository.calls.clear();

    await tester.enterText(find.byType(TextBox).first, 'webhook');
    await tester.tap(find.text('Любой уровень'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Найти'));
    await tester.pumpAndSettle();

    final last = repository.calls.last;
    expect(last.filter.search, 'webhook');
    expect(last.filter.minLevel, isNotNull);
    expect(
      repository.calls.where((c) => c.filter.search == 'webhook'),
      hasLength(1),
      reason: 'one request carrying both, not one per control',
    );
  });

  testWidgets('a time-range bound narrows the query, and clears', (
    tester,
  ) async {
    await openFeed(tester);
    repository.calls.clear();

    final before = DateTime.now();
    await tester.tap(find.text('С: любое'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    expect(repository.calls.last.filter.from, isNotNull);
    expect(
      repository.calls.last.filter.from!.difference(before).inMinutes.abs(),
      lessThanOrEqualTo(1),
      reason:
          'applying without changing the picker keeps its own default — '
          'the current time',
    );
    expect(find.text('С: любое'), findsNothing);

    await tester.tap(find.textContaining('С: '));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Любое время'));
    await tester.pumpAndSettle();

    expect(repository.calls.last.filter.from, isNull);
    expect(find.text('С: любое'), findsOneWidget);
  });

  testWidgets(
    'a correlation id narrows the query, and shows as a removable chip',
    (tester) async {
      await openFeed(tester);
      repository.calls.clear();

      await tester.tap(find.text('+ correlation id'));
      await tester.pumpAndSettle();

      // The dialog defaults to the first field the enum declares —
      // session_id — so typing a value and confirming is enough for the
      // common case. The dialog's own field is the second TextBox: the
      // first is the feed's own search box, still mounted behind it.
      await tester.enterText(find.byType(TextBox).last, 'sess-42');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();

      expect(repository.calls.last.filter.sessionId, 'sess-42');
      expect(find.text('session_id: sess-42'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(HoverButton, 'session_id: sess-42'),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.calls.last.filter.sessionId, isNull);
      expect(find.text('session_id: sess-42'), findsNothing);
    },
  );

  testWidgets(
    'connection_generation only submits once the typed value is a number',
    (tester) async {
      await openFeed(tester);

      await tester.tap(find.text('+ correlation id'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is ComboBox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('connection_generation').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextBox).last, 'not-a-number');
      await tester.pumpAndSettle();
      expect(
        find.text('Значение должно быть числом'),
        findsOneWidget,
        reason:
            'the field is not a string, unlike every other correlation '
            'id — the dialog says so rather than sending a query the server '
            'would refuse to parse',
      );
      expect(
        tester
            .widget<Button>(find.widgetWithText(Button, 'Добавить'))
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextBox).last, '7');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();

      expect(repository.calls.last.filter.connectionGeneration, 7);
      expect(find.text('connection_generation: 7'), findsOneWidget);
    },
  );

  testWidgets('an entry opens in full, context beside the standard fields', (
    tester,
  ) async {
    repository.entries = [_entry()];

    await openFeed(tester);
    await tester.tap(find.text('Webhook delivery failed after 3 attempts'));
    await tester.pumpAndSettle();

    expect(find.text('СТАНДАРТНЫЕ ПОЛЯ'), findsOneWidget);
    expect(find.text('КОНТЕКСТ'), findsOneWidget);
    // Correlation is a standard field; what the application bound is context.
    expect(find.text('request_id'), findsOneWidget);
    expect(find.text('webhook_url'), findsOneWidget);
    expect(find.text('attempt'), findsOneWidget);
  });

  testWidgets('an empty result says so differently with a filter on', (
    tester,
  ) async {
    await openFeed(tester);
    expect(find.text('Записей пока нет'), findsOneWidget);

    await tester.enterText(find.byType(TextBox).first, 'nothing matches this');
    await tester.tap(find.text('Найти'));
    await tester.pumpAndSettle();

    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('changing the scope goes back to the selector', (tester) async {
    repository.entries = [_entry()];
    await openFeed(tester);

    await tester.tap(find.text('Изменить область'));
    await tester.pumpAndSettle();

    expect(find.text('Выберите область'), findsOneWidget);
    expect(
      find.text('Webhook delivery failed after 3 attempts'),
      findsNothing,
      reason: 'the previous scope\'s entries do not survive the change',
    );
  });

  testWidgets('a live entry lands at the end of the feed', (tester) async {
    repository.entries = [_entry()];
    await openFeed(tester);

    repository.live!.add(LiveFeedEvent.entry(_live(918274)));
    await tester.pumpAndSettle();

    expect(find.text('Payment captured'), findsOneWidget);
    expect(find.text('В реальном времени'), findsOneWidget);
    expect(
      find.text('Лента в реальном времени — новые записи появляются снизу'),
      findsOneWidget,
    );
  });

  testWidgets('pausing freezes the list and says what is waiting', (
    tester,
  ) async {
    repository.entries = [_entry()];
    await openFeed(tester);

    await tester.tap(find.text('Пауза'));
    await tester.pumpAndSettle();
    repository.live!.add(LiveFeedEvent.entry(_live(918274)));
    await tester.pumpAndSettle();

    expect(find.text('Payment captured'), findsNothing);
    expect(find.text('На паузе'), findsOneWidget);
    expect(find.text('Лента на паузе · накоплено 1 запись'), findsOneWidget);

    await tester.tap(find.text('Возобновить').first);
    await tester.pumpAndSettle();

    expect(find.text('Payment captured'), findsOneWidget);
  });

  testWidgets('an overflowed pause offers a reload, not a partial list', (
    tester,
  ) async {
    repository.entries = [_entry()];
    await openFeed(tester);

    await tester.tap(find.text('Пауза'));
    await tester.pumpAndSettle();
    for (final id in [1, 2, 3]) {
      repository.live!.add(LiveFeedEvent.entry(_live(918274 + id)));
    }
    await tester.pumpAndSettle();

    expect(find.text('Пауза длилась слишком долго'), findsOneWidget);
    expect(find.text('Перезагрузить и продолжить'), findsOneWidget);
  });

  testWidgets('a subscription the server ends is reported, list intact', (
    tester,
  ) async {
    repository.entries = [_entry()];
    await openFeed(tester);

    repository.live!.add(const LiveFeedEvent.ended('project_blocked'));
    await tester.pumpAndSettle();

    expect(find.text('Живая трансляция остановлена'), findsOneWidget);
    expect(
      find.text('Webhook delivery failed after 3 attempts'),
      findsOneWidget,
    );
  });

  group('narrow', () {
    testWidgets('the detail replaces the feed instead of squeezing beside it', (
      tester,
    ) async {
      repository.entries = [_entry()];
      useNarrowSurface(tester);
      await tester.pumpWidget(_host(makeBloc()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('payments'));
      await tester.pumpAndSettle();

      // No detail pane standing empty beside the list — there is no room for
      // one, so the list has the pane to itself.
      expect(find.text('Выберите запись'), findsNothing);
      expect(
        find.text('Webhook delivery failed after 3 attempts'),
        findsOneWidget,
      );

      await tester.tap(find.text('Webhook delivery failed after 3 attempts'));
      await tester.pumpAndSettle();

      expect(find.text('СТАНДАРТНЫЕ ПОЛЯ'), findsOneWidget);
      expect(find.text('К ленте'), findsOneWidget);

      await tester.tap(find.text('К ленте'));
      await tester.pumpAndSettle();

      expect(find.text('СТАНДАРТНЫЕ ПОЛЯ'), findsNothing);
      expect(
        find.text('Webhook delivery failed after 3 attempts'),
        findsOneWidget,
        reason: 'back goes to the feed, not out of the screen',
      );
    });

    testWidgets('wide, both halves are on screen at once', (tester) async {
      repository.entries = [_entry()];
      await openFeed(tester);

      expect(
        find.text('Выберите запись'),
        findsOneWidget,
        reason: 'the detail pane is there, waiting, when there is room for it',
      );
      expect(find.text('К ленте'), findsNothing);
    });
  });

  group('english', () {
    testWidgets('the selector and the feed chrome read in English', (
      tester,
    ) async {
      repository.entries = [_entry()];
      useWideSurface(tester);
      await tester.pumpWidget(_host(makeBloc(), locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Choose a scope'), findsOneWidget);
      expect(find.text('Выберите область'), findsNothing);

      await tester.tap(find.text('payments'));
      await tester.pumpAndSettle();

      expect(find.text('Project: payments'), findsOneWidget);
      expect(find.text('Any level'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Select an entry'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Найти'), findsNothing);
    });

    testWidgets('the pause strip pluralises in English', (tester) async {
      repository.entries = [_entry()];
      useWideSurface(tester);
      await tester.pumpWidget(_host(makeBloc(), locale: const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('payments'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      repository.live!.add(LiveFeedEvent.entry(_live(918274)));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Feed paused · 1 entry buffered'), findsOneWidget);
    });
  });
}
