import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/log_browser/application/load_scopes.dart';
import 'package:structured_log_admin_client/features/log_browser/application/query_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_browser_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_browser_cubit.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_browser_page.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/log_dto.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

class _FakeRepository implements LogBrowserRepository {
  final calls = <({LogScope scope, LogFilter filter, String? cursor})>[];
  List<LogEntryDto> entries = [];

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

Widget _host(LogBrowserCubit cubit) => FluentApp(
  theme: AdminTheme.light(),
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: BlocProvider.value(value: cubit, child: const LogBrowserPage()),
  ),
);

void main() {
  late _FakeRepository repository;
  late LogBrowserCubit cubit;

  setUp(() {
    repository = _FakeRepository();
    cubit = LogBrowserCubit(
      loadScopes: LoadScopes(repository),
      queryLogs: QueryLogs(repository),
    );
  });

  tearDown(() => cubit.close());

  void useWideSurface(WidgetTester tester) {
    // The screen is a master/detail split at the artboard's width; the
    // default 800 leaves the detail pane nothing to sit in.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the selector stands in place of the list, and queries nothing', (
    tester,
  ) async {
    useWideSurface(tester);
    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Выберите область'), findsOneWidget);
    expect(find.text('payments'), findsOneWidget);
    expect(find.text('acme'), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  testWidgets('choosing a scope loads the feed', (tester) async {
    useWideSurface(tester);
    repository.entries = [_entry()];

    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('payments'));
    await tester.pumpAndSettle();

    expect(repository.calls.single.scope, isA<ProjectScope>());
    expect(
      find.text('Webhook delivery failed after 3 attempts'),
      findsOneWidget,
    );
    expect(find.text('ERR'), findsOneWidget);
  });

  testWidgets('level and search combine into one request', (tester) async {
    useWideSurface(tester);
    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('payments'));
    await tester.pumpAndSettle();
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

  testWidgets('an entry opens in full, context beside the standard fields', (
    tester,
  ) async {
    useWideSurface(tester);
    repository.entries = [_entry()];

    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('payments'));
    await tester.pumpAndSettle();
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
    useWideSurface(tester);

    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('payments'));
    await tester.pumpAndSettle();
    expect(find.text('Записей пока нет'), findsOneWidget);

    await tester.enterText(find.byType(TextBox).first, 'nothing matches this');
    await tester.tap(find.text('Найти'));
    await tester.pumpAndSettle();

    expect(find.text('Ничего не найдено'), findsOneWidget);
  });
}
