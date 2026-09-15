import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/log_browser/application/load_scopes.dart';
import 'package:structured_log_admin_client/features/log_browser/application/query_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_browser_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_browser_cubit.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/log_dto.dart';

LogEntryDto _entry(int id) => LogEntryDto(
  id: id,
  projectId: 1,
  receivedAt: DateTime.utc(2026, 9, 15, 9, id),
  event: 'event-$id',
  level: 'info',
  context: const {},
);

/// The server answers newest-first, so a page is built descending.
List<LogEntryDto> _page(Iterable<int> ids) =>
    ids.map(_entry).toList()..sort((a, b) => b.id.compareTo(a.id));

class _FakeRepository implements LogBrowserRepository {
  Either<ApiFailure, ScopeOptions> scopes = right(
    const ScopeOptions(
      groups: [GroupScope(id: 7, name: 'acme')],
      projects: [ProjectScope(id: 1, name: 'payments')],
    ),
  );

  /// Queued answers, taken in order; the last one repeats once exhausted.
  final answers = <Either<ApiFailure, LogPage>>[];
  final calls = <({LogScope scope, LogFilter filter, String? cursor})>[];

  /// Completes each query only when released, so a test can land two
  /// responses out of order.
  Completer<void>? gate;

  @override
  Future<Either<ApiFailure, ScopeOptions>> loadScopes() async => scopes;

  @override
  Future<Either<ApiFailure, LogPage>> query({
    required LogScope scope,
    required LogFilter filter,
    String? cursor,
    int limit = 50,
  }) async {
    calls.add((scope: scope, filter: filter, cursor: cursor));
    if (gate != null) await gate!.future;
    if (answers.isEmpty) {
      return right((entries: <LogEntryDto>[], nextCursor: null));
    }
    return answers.length == 1 ? answers.first : answers.removeAt(0);
  }
}

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

  test('nothing is queried before a scope is chosen', () async {
    await cubit.start();

    expect(cubit.state.options, isNotNull);
    expect(cubit.state.hasScope, isFalse);
    expect(
      repository.calls,
      isEmpty,
      reason: 'the selector stands in place of the list until it is used',
    );
  });

  test('choosing a scope loads the newest page, oldest entry first', () async {
    repository.answers.add(right((entries: _page([1, 2, 3]), nextCursor: '1')));
    await cubit.start();

    await cubit.selectScope(const LogScope.project(id: 1, name: 'payments'));

    expect(repository.calls.single.cursor, isNull);
    expect(
      cubit.state.entries.map((e) => e.id),
      [1, 2, 3],
      reason: 'the server answers newest-first; the feed reads as a history',
    );
    expect(cubit.state.nextCursor, '1');
  });

  test('an older page goes above, without repeating an entry', () async {
    repository.answers
      ..add(right((entries: _page([4, 5, 6]), nextCursor: '4')))
      ..add(right((entries: _page([1, 2, 3]), nextCursor: null)));
    await cubit.start();
    await cubit.selectScope(const LogScope.project(id: 1, name: 'payments'));

    await cubit.loadMore();

    expect(cubit.state.entries.map((e) => e.id), [1, 2, 3, 4, 5, 6]);
    expect(repository.calls.last.cursor, '4');
    expect(
      cubit.state.canLoadMore,
      isFalse,
      reason: 'a null cursor is the beginning of the log',
    );
  });

  test('changing a filter starts again from the newest page', () async {
    repository.answers.add(right((entries: _page([1, 2]), nextCursor: '1')));
    await cubit.start();
    await cubit.selectScope(const LogScope.group(id: 7, name: 'acme'));
    await cubit.loadMore();
    repository.calls.clear();

    await cubit.applyFilter(const LogFilter(minLevel: 'warning'));

    expect(repository.calls.single.cursor, isNull);
    expect(repository.calls.single.filter.minLevel, 'warning');
  });

  test('re-selecting the same scope does not throw the list away', () async {
    repository.answers.add(right((entries: _page([1]), nextCursor: null)));
    await cubit.start();
    const scope = LogScope.project(id: 1, name: 'payments');
    await cubit.selectScope(scope);

    await cubit.selectScope(scope);

    expect(repository.calls, hasLength(1));
  });

  test('a superseded answer does not overwrite a newer one', () async {
    await cubit.start();
    repository.gate = Completer<void>();
    repository.answers
      ..add(right((entries: _page([1]), nextCursor: null)))
      ..add(right((entries: _page([9]), nextCursor: null)));

    // Two requests in flight; the first is released last.
    final first = cubit.selectScope(const LogScope.project(id: 1, name: 'a'));
    final second = cubit.selectScope(const LogScope.project(id: 2, name: 'b'));
    repository.gate!.complete();
    await Future.wait([first, second]);

    expect(
      cubit.state.scope,
      const LogScope.project(id: 2, name: 'b'),
      reason: 'the newer selection wins',
    );
    expect(cubit.state.entries.map((e) => e.id), [9]);
  });

  test('a failed query is surfaced and leaves no stale entries', () async {
    repository.answers
      ..add(right((entries: _page([1, 2]), nextCursor: null)))
      ..add(left(const ApiFailure.forbidden(code: 'forbidden')));
    await cubit.start();
    await cubit.selectScope(const LogScope.project(id: 1, name: 'payments'));

    await cubit.selectScope(const LogScope.project(id: 2, name: 'other'));

    expect(cubit.state.failure, isA<ForbiddenFailure>());
    expect(
      cubit.state.entries,
      isEmpty,
      reason: 'one scope\'s entries must not sit under another scope\'s name',
    );
  });

  test('selecting an entry resolves it out of the current page', () async {
    repository.answers.add(right((entries: _page([1, 2]), nextCursor: null)));
    await cubit.start();
    await cubit.selectScope(const LogScope.project(id: 1, name: 'payments'));

    cubit.select(2);
    expect(cubit.state.selectedEntry?.id, 2);

    cubit.select(null);
    expect(cubit.state.selectedEntry, isNull);
  });
}
