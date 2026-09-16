import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/api/dto/log_dto.dart';
import '../application/load_scopes.dart';
import '../application/query_logs.dart';
import '../application/watch_logs.dart';
import '../domain/live_feed_event.dart';
import '../domain/log_scope.dart';
import 'log_feed_event.dart';
import 'log_feed_state.dart';

/// The log screen's one state holder: the list, its pagination, and the live
/// subscription that keeps it at the newest entry.
///
/// **One holder, not two**, even though the screen has two halves. "The filter
/// changed" has to reset the page, close the subscription and open a new one
/// as a single move (`specs/admin-client-log-browser`); split across two
/// objects that move would live in the widget that owns both, which is the
/// one place in this repository that has repeatedly been left unwired.
///
/// Two rules keep the asynchrony honest, and both matter:
///
/// - Only [_reload] and [_loadOlder] await anything. Every other handler is
///   synchronous, so the transitions of decision 30 cannot interleave with
///   each other — no event transformer is needed to make that true.
/// - Both of those, and the live subscription, are stamped with
///   [_generation]. A page that was superseded while in flight, and an entry
///   from a subscription that has since been replaced, are both dropped by
///   comparing it. Without that, a slow answer for the previous filter lands
///   on top of the current one.
class LogFeedBloc extends Bloc<LogFeedEvent, LogFeedState> {
  final LoadScopes _loadScopes;
  final QueryLogs _queryLogs;
  final WatchLogs _watchLogs;

  /// How many entries an explicit pause may bank before the oldest are
  /// dropped and resuming reloads instead (decision 30).
  ///
  /// Ten pages' worth. Large enough that an ordinary pause — read an entry,
  /// resume — never overflows on a busy project, small enough that a feed left
  /// paused overnight cannot grow without bound, which is the same reason
  /// `HttpLogOutput` caps its own buffer.
  final int pauseBufferLimit;

  /// Bumped by anything that invalidates in-flight work: a new scope, a new
  /// filter, a reload. Answers and live entries stamped with an older value
  /// are discarded.
  int _generation = 0;

  StreamSubscription<LiveFeedEvent>? _live;

  /// Entries delivered while paused, oldest first. Capped at
  /// [pauseBufferLimit]; the count and the overflow flag are mirrored into
  /// [FeedPaused] so the screen can say what is waiting.
  final _paused = <LogEntryDto>[];
  var _pauseOverflowed = false;

  LogFeedBloc({
    required LoadScopes loadScopes,
    required QueryLogs queryLogs,
    required WatchLogs watchLogs,
    this.pauseBufferLimit = 500,
  }) : _loadScopes = loadScopes,
       _queryLogs = queryLogs,
       _watchLogs = watchLogs,
       super(const LogFeedState()) {
    on<LogFeedStarted>(_onStarted);
    on<LogFeedScopeSelected>(_onScopeSelected);
    on<LogFeedScopeCleared>(_onScopeCleared);
    on<LogFeedFilterChanged>(_onFilterChanged);
    on<LogFeedOlderRequested>(_onOlderRequested);
    on<LogFeedReloadRequested>(_onReloadRequested);
    on<LogFeedEntrySelected>(_onEntrySelected);
    on<LogFeedScrolledToBottom>(_onScrolledToBottom);
    on<LogFeedScrolledAwayFromBottom>(_onScrolledAwayFromBottom);
    on<LogFeedPauseRequested>(_onPauseRequested);
    on<LogFeedResumeRequested>(_onResumeRequested);
    on<LogFeedLiveEntryArrived>(_onLiveEntryArrived);
    on<LogFeedLiveEnded>(_onLiveEnded);
    on<LogFeedLiveFailed>(_onLiveFailed);
  }

  @override
  Future<void> close() {
    unawaited(_live?.cancel());
    _live = null;
    return super.close();
  }

  Future<void> _onStarted(
    LogFeedStarted event,
    Emitter<LogFeedState> emit,
  ) async {
    final result = await _loadScopes();
    result.match(
      (failure) =>
          emit(state.copyWith(loadingOptions: false, failure: failure)),
      (options) => emit(
        state.copyWith(loadingOptions: false, options: options, failure: null),
      ),
    );
  }

  /// Picks the one scope to read. Choosing the same one again is ignored, so
  /// re-selecting from a menu does not throw away a loaded list and restart
  /// the subscription.
  Future<void> _onScopeSelected(
    LogFeedScopeSelected event,
    Emitter<LogFeedState> emit,
  ) async {
    if (state.scope == event.scope) return;
    emit(state.copyWith(scope: event.scope, selectedEntryId: null));
    await _reload(emit);
  }

  void _onScopeCleared(LogFeedScopeCleared event, Emitter<LogFeedState> emit) {
    _invalidate();
    emit(
      LogFeedState(
        options: state.options,
        loadingOptions: false,
        filter: state.filter,
      ),
    );
  }

  Future<void> _onFilterChanged(
    LogFeedFilterChanged event,
    Emitter<LogFeedState> emit,
  ) async {
    if (state.filter == event.filter) return;
    emit(state.copyWith(filter: event.filter, selectedEntryId: null));
    await _reload(emit);
  }

  Future<void> _onReloadRequested(
    LogFeedReloadRequested event,
    Emitter<LogFeedState> emit,
  ) => _reload(emit);

  /// Fetches the page before the oldest one held and puts it on top.
  ///
  /// Cursor-based, so two calls cannot return overlapping entries the way an
  /// offset would once new entries have arrived.
  Future<void> _onOlderRequested(
    LogFeedOlderRequested event,
    Emitter<LogFeedState> emit,
  ) => _loadOlder(emit);

  void _onEntrySelected(
    LogFeedEntrySelected event,
    Emitter<LogFeedState> emit,
  ) => emit(state.copyWith(selectedEntryId: event.entryId));

  void _onScrolledToBottom(
    LogFeedScrolledToBottom event,
    Emitter<LogFeedState> emit,
  ) {
    // An explicit pause outranks the scroll position: arriving back at the
    // bottom must not quietly undo a pause the reader asked for.
    if (state.mode.isPaused) return;
    if (state.mode is FeedFollowing) return;
    emit(state.copyWith(mode: const LogFeedMode.following()));
  }

  void _onScrolledAwayFromBottom(
    LogFeedScrolledAwayFromBottom event,
    Emitter<LogFeedState> emit,
  ) {
    if (state.mode is! FeedFollowing) return;
    emit(state.copyWith(mode: const LogFeedMode.scrolledUp()));
  }

  void _onPauseRequested(
    LogFeedPauseRequested event,
    Emitter<LogFeedState> emit,
  ) {
    if (state.mode.isPaused) return;
    _paused.clear();
    _pauseOverflowed = false;
    emit(state.copyWith(mode: const LogFeedMode.paused()));
  }

  Future<void> _onResumeRequested(
    LogFeedResumeRequested event,
    Emitter<LogFeedState> emit,
  ) async {
    if (!state.mode.isPaused) return;

    if (_pauseOverflowed) {
      // A buffer that dropped entries cannot be flushed into the list without
      // leaving a hole in it. Reloading the newest page and resubscribing from
      // there shows less, but nothing false (decision 30).
      _paused.clear();
      _pauseOverflowed = false;
      emit(state.copyWith(mode: const LogFeedMode.following()));
      await _reload(emit);
      return;
    }

    final flushed = [...state.entries, ..._paused];
    _paused.clear();
    emit(state.copyWith(entries: flushed, mode: const LogFeedMode.following()));
  }

  void _onLiveEntryArrived(
    LogFeedLiveEntryArrived event,
    Emitter<LogFeedState> emit,
  ) {
    final entry = event.entry;
    // The catch-up replay after a reconnect can overlap what is already held.
    // Ids are the server's and it delivers them strictly increasing, so the
    // newest one held is the whole of the comparison — no scan, and exact
    // rather than heuristic.
    final newest = _newestHeldId;
    if (newest != null && entry.id <= newest) return;

    switch (state.mode) {
      case FeedPaused():
        _paused.add(entry);
        if (_paused.length > pauseBufferLimit) {
          _paused.removeAt(0);
          _pauseOverflowed = true;
        }
        emit(
          state.copyWith(
            mode: LogFeedMode.paused(
              buffered: _paused.length,
              overflowed: _pauseOverflowed,
            ),
          ),
        );
      case FeedScrolledUp(:final unseen):
        // Appended, not withheld: the reader is above the fold, so the entry
        // is simply out of view. The counter is what offers the way back.
        emit(
          state.copyWith(
            entries: [...state.entries, entry],
            mode: LogFeedMode.scrolledUp(unseen: unseen + 1),
          ),
        );
      case FeedFollowing():
        emit(state.copyWith(entries: [...state.entries, entry]));
    }
  }

  void _onLiveEnded(LogFeedLiveEnded event, Emitter<LogFeedState> emit) =>
      emit(state.copyWith(liveEndReason: event.reason));

  void _onLiveFailed(LogFeedLiveFailed event, Emitter<LogFeedState> emit) =>
      emit(state.copyWith(failure: event.failure));

  /// The newest page for the current scope and filter, plus a fresh
  /// subscription from its newest entry.
  Future<void> _reload(Emitter<LogFeedState> emit) async {
    final scope = state.scope;
    if (scope == null) return;

    _invalidate();
    final generation = _generation;

    emit(
      state.copyWith(
        loading: true,
        // Cleared with the request, not when it answers: leaving the previous
        // scope's entries on screen while another scope loads shows one
        // scope's logs under another's name.
        entries: const [],
        nextCursor: null,
        mode: const LogFeedMode.following(),
        liveEndReason: null,
        failure: null,
      ),
    );

    final result = await _queryLogs(scope: scope, filter: state.filter);
    if (isClosed || generation != _generation) return;

    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (page) {
        final entries = _chronological(page.entries);
        emit(
          state.copyWith(
            loading: false,
            entries: entries,
            nextCursor: page.nextCursor,
            failure: null,
          ),
        );
        // Only now, and with the newest id in hand: the server replays
        // everything committed between this page and the subscription, so the
        // gap between the two requests loses nothing and repeats nothing
        // (`log-server-live-stream`).
        _openLive(
          scope: scope,
          generation: generation,
          sinceId: entries.isEmpty ? null : entries.last.id,
        );
      },
    );
  }

  Future<void> _loadOlder(Emitter<LogFeedState> emit) async {
    if (!state.canLoadMore) return;
    final scope = state.scope;
    if (scope == null) return;

    final generation = _generation;
    emit(state.copyWith(loadingMore: true));
    final result = await _queryLogs(
      scope: scope,
      filter: state.filter,
      cursor: state.nextCursor,
    );
    if (isClosed || generation != _generation) return;

    result.match(
      (failure) => emit(state.copyWith(loadingMore: false, failure: failure)),
      (page) {
        final older = _chronological(page.entries);
        final held = {for (final entry in state.entries) entry.id};
        emit(
          state.copyWith(
            loadingMore: false,
            // Prepended, and de-duplicated by id. `GET /v1/logs` answers
            // newest-first and its cursor walks backwards in time, while the
            // feed reads as a history — so each page is flipped and goes
            // above what is already there, without moving it.
            entries: [
              ...older.where((entry) => !held.contains(entry.id)),
              ...state.entries,
            ],
            nextCursor: page.nextCursor,
            failure: null,
          ),
        );
      },
    );
  }

  void _openLive({
    required LogScope scope,
    required int generation,
    int? sinceId,
  }) {
    _live = _watchLogs(scope: scope, filter: state.filter, sinceId: sinceId)
        .listen((event) {
          // The subscription outlives the await that opened it, so its own
          // generation is the only thing that says whether it is still the
          // current one.
          if (isClosed || generation != _generation) return;
          switch (event) {
            case LiveFeedEntry(:final entry):
              add(LogFeedEvent.liveEntryArrived(entry));
            case LiveFeedEnded(:final reason):
              add(LogFeedEvent.liveEnded(reason));
            case LiveFeedFailed(:final failure):
              add(LogFeedEvent.liveFailed(failure));
          }
        });
  }

  /// The newest entry id held anywhere — in the list, or waiting out a pause.
  ///
  /// `null` only before the first page has landed, where the subscription has
  /// nothing to be newer than.
  int? get _newestHeldId {
    if (_paused.isNotEmpty) return _paused.last.id;
    if (state.entries.isNotEmpty) return state.entries.last.id;
    return null;
  }

  /// Retires everything in flight: the live subscription, the pause buffer,
  /// and any page request that has not answered yet.
  ///
  /// Synchronous, and the cancel is deliberately not awaited. What makes the
  /// old subscription harmless is the generation, not the teardown — its
  /// events are dropped the moment this returns — so waiting for a socket to
  /// close before redrawing would only delay the screen. It also has to be
  /// synchronous for a second reason: an `await` here puts the `emit` that
  /// follows it a turn later than a widget test's `pumpAndSettle` will wait,
  /// and the screen appears not to react at all.
  void _invalidate() {
    _generation++;
    final live = _live;
    _live = null;
    unawaited(live?.cancel());
    _paused.clear();
    _pauseOverflowed = false;
  }

  /// Server order (newest first) into reading order (oldest first).
  ///
  /// Kept in one place because getting it wrong is invisible until someone
  /// reads a list of timestamps and finds them counting down.
  static List<LogEntryDto> _chronological(List<LogEntryDto> page) =>
      page.reversed.toList();
}
