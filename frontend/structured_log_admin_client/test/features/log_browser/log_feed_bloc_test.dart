import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/log_browser/application/load_scopes.dart';
import 'package:structured_log_admin_client/features/log_browser/application/query_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/application/watch_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/live_feed_event.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_browser_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_feed_bloc.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_feed_event.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_feed_state.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/log_dto.dart';

LogEntryDto _entry(int id) => LogEntryDto(
  id: id,
  projectId: 1,
  receivedAt: DateTime.utc(2026, 9, 15, 9, id % 60),
  event: 'event-$id',
  level: 'info',
  context: const {},
);

/// The server answers newest-first, so a page is built descending.
List<LogEntryDto> _page(Iterable<int> ids) =>
    ids.map(_entry).toList()..sort((a, b) => b.id.compareTo(a.id));

const _payments = LogScope.project(id: 1, name: 'payments');
const _acme = LogScope.group(id: 7, name: 'acme');

/// One subscription the bloc opened, and whether it is still held.
class _Watch {
  final LogScope scope;
  final LogFilter filter;
  final int? sinceId;

  late final StreamController<LiveFeedEvent> controller;
  var cancelled = false;

  _Watch(this.scope, this.filter, this.sinceId) {
    controller = StreamController<LiveFeedEvent>(
      onCancel: () => cancelled = true,
    );
  }

  void deliver(int id) => controller.add(LiveFeedEvent.entry(_entry(id)));
}

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
  final watches = <_Watch>[];

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

  @override
  Stream<LiveFeedEvent> watch({
    required LogScope scope,
    required LogFilter filter,
    int? sinceId,
  }) {
    final watch = _Watch(scope, filter, sinceId);
    watches.add(watch);
    return watch.controller.stream;
  }
}

void main() {
  late _FakeRepository repository;
  late LogFeedBloc bloc;

  setUp(() {
    repository = _FakeRepository();
    bloc = LogFeedBloc(
      loadScopes: LoadScopes(repository),
      queryLogs: QueryLogs(repository),
      watchLogs: WatchLogs(repository),
      // Small enough to overflow deliberately in a test, and the same code
      // path as the shipped 500.
      pauseBufferLimit: 3,
    );
  });

  tearDown(() => bloc.close());

  /// Waits for the first state that satisfies [predicate].
  ///
  /// A bloc answers through its event queue, so "the handler has run" is only
  /// observable as a state — and asserting on `bloc.state` after an arbitrary
  /// delay is the flaky way to do it.
  Future<LogFeedState> until(bool Function(LogFeedState) predicate) async {
    if (predicate(bloc.state)) return bloc.state;
    return bloc.stream
        .firstWhere(predicate)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('no state matched: ${bloc.state}'),
        );
  }

  /// Lets the event queue drain when the assertion is that *nothing* changed.
  Future<void> quiet() => Future<void>.delayed(Duration.zero);

  Future<void> loadFirstPage({
    List<int> ids = const [1, 2, 3],
    String? cursor,
    LogScope scope = _payments,
  }) async {
    repository.answers.add(right((entries: _page(ids), nextCursor: cursor)));
    bloc.add(const LogFeedEvent.started());
    await until((state) => !state.loadingOptions);
    bloc.add(LogFeedEvent.scopeSelected(scope));
    await until((state) => state.entries.isNotEmpty);
    // The fake repeats its last answer once the queue runs dry, so a test
    // that queues the *next* page has to start from an empty queue.
    repository.answers.clear();
  }

  group('paging and filters', () {
    test('nothing is queried before a scope is chosen', () async {
      bloc.add(const LogFeedEvent.started());
      await until((state) => !state.loadingOptions);

      expect(bloc.state.options, isNotNull);
      expect(bloc.state.hasScope, isFalse);
      expect(
        repository.calls,
        isEmpty,
        reason: 'the selector stands in place of the list until it is used',
      );
      expect(repository.watches, isEmpty);
    });

    test(
      'choosing a scope loads the newest page, oldest entry first',
      () async {
        await loadFirstPage(cursor: '1');

        expect(repository.calls.single.cursor, isNull);
        expect(
          bloc.state.entries.map((e) => e.id),
          [1, 2, 3],
          reason:
              'the server answers newest-first; the feed reads as a history',
        );
        expect(bloc.state.nextCursor, '1');
      },
    );

    test('an older page goes above, without repeating an entry', () async {
      await loadFirstPage(ids: [4, 5, 6], cursor: '4');

      repository.answers.add(
        right((entries: _page([1, 2, 3]), nextCursor: null)),
      );
      bloc.add(const LogFeedEvent.olderRequested());
      await until((state) => state.entries.length == 6);

      expect(bloc.state.entries.map((e) => e.id), [1, 2, 3, 4, 5, 6]);
      expect(repository.calls.last.cursor, '4');
      expect(
        bloc.state.canLoadMore,
        isFalse,
        reason: 'a null cursor is the beginning of the log',
      );
    });

    test(
      'an older page overlapping the live edge is not shown twice',
      () async {
        // The subscription appended 4 while the older page was in flight, and
        // that page carries it too.
        await loadFirstPage(ids: [2, 3], cursor: '2');
        repository.watches.single.deliver(4);
        await until((state) => state.entries.length == 3);

        repository.answers.add(
          right((entries: _page([1, 2, 3, 4]), nextCursor: null)),
        );
        bloc.add(const LogFeedEvent.olderRequested());
        await until((state) => state.entries.length == 4);

        expect(bloc.state.entries.map((e) => e.id), [1, 2, 3, 4]);
      },
    );

    test('changing a filter restarts the page and the subscription', () async {
      await loadFirstPage(cursor: '1');
      final first = repository.watches.single;
      repository.calls.clear();

      repository.answers.add(right((entries: _page([9]), nextCursor: null)));
      bloc.add(
        const LogFeedEvent.filterChanged(LogFilter(minLevel: 'warning')),
      );
      await until((state) => state.entries.map((e) => e.id).contains(9));

      expect(repository.calls.single.cursor, isNull);
      expect(repository.calls.single.filter.minLevel, 'warning');
      expect(
        first.cancelled,
        isTrue,
        reason: 'the old subscription is closed before a new one opens',
      );
      expect(repository.watches, hasLength(2));
      expect(repository.watches.last.filter.minLevel, 'warning');
    });

    test('an entry from a superseded subscription is ignored', () async {
      await loadFirstPage(cursor: '1');
      final first = repository.watches.single;

      repository.answers.add(right((entries: _page([9]), nextCursor: null)));
      bloc.add(const LogFeedEvent.filterChanged(LogFilter(minLevel: 'error')));
      await until((state) => state.entries.map((e) => e.id).contains(9));

      first.deliver(99);
      await quiet();

      expect(
        bloc.state.entries.map((e) => e.id),
        isNot(contains(99)),
        reason: "the old subscription's events must not mix into the new one",
      );
    });

    test('re-selecting the same scope does not throw the list away', () async {
      await loadFirstPage();

      bloc.add(const LogFeedEvent.scopeSelected(_payments));
      await quiet();

      expect(repository.calls, hasLength(1));
      expect(repository.watches, hasLength(1));
    });

    test('a superseded answer does not overwrite a newer one', () async {
      bloc.add(const LogFeedEvent.started());
      await until((state) => !state.loadingOptions);

      repository.gate = Completer<void>();
      repository.answers
        ..add(right((entries: _page([1]), nextCursor: null)))
        ..add(right((entries: _page([9]), nextCursor: null)));

      bloc.add(const LogFeedEvent.scopeSelected(_payments));
      bloc.add(const LogFeedEvent.scopeSelected(_acme));
      repository.gate!.complete();
      await until((state) => state.entries.isNotEmpty);

      expect(bloc.state.scope, _acme, reason: 'the newer selection wins');
      expect(bloc.state.entries.map((e) => e.id), [9]);
    });

    test('a failed query is surfaced and leaves no stale entries', () async {
      await loadFirstPage();
      repository.answers.add(
        left(const ApiFailure.forbidden(code: 'forbidden')),
      );

      bloc.add(const LogFeedEvent.scopeSelected(_acme));
      await until((state) => state.failure != null);

      expect(bloc.state.failure, isA<ForbiddenFailure>());
      expect(
        bloc.state.entries,
        isEmpty,
        reason: "one scope's entries must not sit under another scope's name",
      );
    });

    test('selecting an entry resolves it out of the current page', () async {
      await loadFirstPage(ids: [1, 2]);

      bloc.add(const LogFeedEvent.entrySelected(2));
      await until((state) => state.selectedEntryId == 2);
      expect(bloc.state.selectedEntry?.id, 2);

      bloc.add(const LogFeedEvent.entrySelected(null));
      await until((state) => state.selectedEntryId == null);
      expect(bloc.state.selectedEntry, isNull);
    });

    test('clearing the scope drops the list and the subscription', () async {
      await loadFirstPage();
      final watch = repository.watches.single;

      bloc.add(const LogFeedEvent.scopeCleared());
      await until((state) => !state.hasScope);

      expect(bloc.state.entries, isEmpty);
      expect(watch.cancelled, isTrue);
      expect(
        bloc.state.options,
        isNotNull,
        reason: 'the selector is what stands in the list\'s place',
      );
    });
  });

  group('following the live edge', () {
    test('the subscription starts where the first page ended', () async {
      await loadFirstPage(ids: [1, 2, 3]);

      expect(repository.watches, hasLength(1));
      expect(
        repository.watches.single.sinceId,
        3,
        reason: 'the newest entry held — the server replays the gap after it',
      );
      expect(repository.watches.single.scope, _payments);
    });

    test('a new entry is appended while following', () async {
      await loadFirstPage(ids: [1, 2]);

      repository.watches.single.deliver(3);
      await until((state) => state.entries.length == 3);

      expect(bloc.state.entries.last.id, 3);
      expect(bloc.state.mode, const LogFeedMode.following());
    });

    test('a replayed entry already held is not appended twice', () async {
      await loadFirstPage(ids: [1, 2, 3]);

      // A reconnect replays from `since_id`, and the catch-up can overlap.
      repository.watches.single
        ..deliver(3)
        ..deliver(4);
      await until((state) => state.entries.length == 4);
      await quiet();

      expect(bloc.state.entries.map((e) => e.id), [1, 2, 3, 4]);
    });

    test(
      'scrolled up, entries are counted instead of chasing the reader',
      () async {
        await loadFirstPage(ids: [1, 2]);

        bloc.add(const LogFeedEvent.scrolledAwayFromBottom());
        await until((state) => state.mode is FeedScrolledUp);
        repository.watches.single
          ..deliver(3)
          ..deliver(4);
        await until((state) => state.pendingCount == 2);

        expect(bloc.state.entries.map((e) => e.id), [
          1,
          2,
          3,
          4,
        ], reason: 'appended below the fold, not withheld');
        expect(bloc.state.mode, const LogFeedMode.scrolledUp(unseen: 2));
      },
    );

    test('returning to the live edge clears the count', () async {
      await loadFirstPage(ids: [1]);
      bloc.add(const LogFeedEvent.scrolledAwayFromBottom());
      await until((state) => state.mode is FeedScrolledUp);
      repository.watches.single.deliver(2);
      await until((state) => state.pendingCount == 1);

      bloc.add(const LogFeedEvent.scrolledToBottom());
      await until((state) => state.mode is FeedFollowing);

      expect(bloc.state.pendingCount, 0);
    });
  });

  group('pause and resume', () {
    test('the visible list does not change while paused', () async {
      await loadFirstPage(ids: [1, 2]);

      bloc.add(const LogFeedEvent.pauseRequested());
      await until((state) => state.mode.isPaused);
      repository.watches.single
        ..deliver(3)
        ..deliver(4);
      await until((state) => state.pendingCount == 2);

      expect(bloc.state.entries.map((e) => e.id), [1, 2]);
      expect(
        repository.watches.single.cancelled,
        isFalse,
        reason: 'the subscription stays open through a pause (decision 30)',
      );
    });

    test('resuming shows what arrived, in order', () async {
      await loadFirstPage(ids: [1, 2]);
      bloc.add(const LogFeedEvent.pauseRequested());
      await until((state) => state.mode.isPaused);
      repository.watches.single
        ..deliver(3)
        ..deliver(4);
      await until((state) => state.pendingCount == 2);

      bloc.add(const LogFeedEvent.resumeRequested());
      await until((state) => state.mode is FeedFollowing);

      expect(bloc.state.entries.map((e) => e.id), [1, 2, 3, 4]);
      expect(
        repository.watches,
        hasLength(1),
        reason: 'an ordinary resume reuses the subscription it never closed',
      );
    });

    test('an overflowed buffer reloads instead of showing a gap', () async {
      await loadFirstPage(ids: [1, 2]);
      bloc.add(const LogFeedEvent.pauseRequested());
      await until((state) => state.mode.isPaused);

      // One past the limit of 3: the oldest waiting entry is dropped.
      for (final id in [3, 4, 5, 6]) {
        repository.watches.single.deliver(id);
      }
      await until(
        (state) =>
            state.mode ==
            const LogFeedMode.paused(buffered: 3, overflowed: true),
      );

      repository.answers.add(right((entries: _page([5, 6]), nextCursor: null)));
      bloc.add(const LogFeedEvent.resumeRequested());
      await until((state) => state.entries.map((e) => e.id).contains(6));

      expect(bloc.state.mode, const LogFeedMode.following());
      expect(bloc.state.entries.map((e) => e.id), [
        5,
        6,
      ], reason: 'the newest page, not a list with a hole in it');
      expect(repository.watches, hasLength(2));
      expect(repository.watches.last.sinceId, 6);
    });

    test(
      'arriving back at the bottom does not undo an explicit pause',
      () async {
        await loadFirstPage(ids: [1]);
        bloc.add(const LogFeedEvent.pauseRequested());
        await until((state) => state.mode.isPaused);

        bloc.add(const LogFeedEvent.scrolledToBottom());
        await quiet();

        expect(bloc.state.mode.isPaused, isTrue);
      },
    );
  });

  group('a subscription the server ends', () {
    test('a terminal reason is surfaced rather than swallowed', () async {
      await loadFirstPage();

      repository.watches.single.controller.add(
        const LiveFeedEvent.ended('project_blocked'),
      );
      await until((state) => state.liveEndReason != null);

      expect(bloc.state.liveEndReason, 'project_blocked');
      expect(
        bloc.state.entries,
        isNotEmpty,
        reason: 'only the live half stopped; the list keeps what it held',
      );
    });

    test('a refusal to open one becomes a failure', () async {
      await loadFirstPage();

      repository.watches.single.controller.add(
        const LiveFeedEvent.failed(ApiFailure.forbidden(code: 'forbidden')),
      );
      await until((state) => state.failure != null);

      expect(bloc.state.failure, isA<ForbiddenFailure>());
    });
  });
}
