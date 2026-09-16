import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/audit_dto.dart';
import '../application/query_audit_log.dart';
import '../domain/audit_filter.dart';

part 'audit_cubit.freezed.dart';

@freezed
abstract class AuditState with _$AuditState {
  const factory AuditState({
    @Default(true) bool loading,

    /// Another page is on its way. Separate from [loading] so the records
    /// already on screen stay there while it arrives — a reader who has
    /// scrolled into last week should not be sent back to a spinner.
    @Default(false) bool loadingMore,

    @Default(<AuditEntryDto>[]) List<AuditEntryDto> entries,
    @Default(AuditFilter()) AuditFilter filter,

    /// The cursor for the next, older page; `null` once the server says there
    /// is nothing older.
    String? cursor,

    ApiFailure? failure,

    /// The server's configured retention, as the last page reported it.
    /// `null` means no limit, which is also the default before anything has
    /// loaded — so the screen shows these only once [loaded] is true.
    int? auditRetentionDays,
    int? authEventRetentionDays,

    /// Whether a page has ever come back. Tells "nothing is configured" from
    /// "nothing has been read yet", which otherwise look identical.
    @Default(false) bool loaded,
  }) = _AuditState;

  const AuditState._();

  bool get hasMore => cursor != null;

  /// Loaded, and there is nothing in it.
  bool get isEmpty => !loading && entries.isEmpty && failure == null;

  /// Whether the empty result should be explained by retention rather than by
  /// the filters.
  ///
  /// Only when the reader asked for a range that starts before what the server
  /// keeps: then "ничего не найдено" would be a lie by omission — the events
  /// may well have happened and simply been deleted
  /// (`specs/admin-client-audit-log`). Any other empty result is about the
  /// filters, and saying "these are gone" about records that were never there
  /// would be the same mistake in the other direction.
  bool get isEmptyByRetention {
    if (!isEmpty || !loaded) return false;
    final from = filter.from;
    if (from == null) return false;

    final days = _shortestRetention;
    if (days == null) return false;
    return from.isBefore(DateTime.now().subtract(Duration(days: days)));
  }

  /// The earlier of the two cutoffs — whichever period expires first is the one
  /// that can have removed what the reader is looking for.
  int? get _shortestRetention {
    final admin = auditRetentionDays;
    final auth = authEventRetentionDays;
    if (admin == null) return auth;
    if (auth == null) return admin;
    return admin < auth ? admin : auth;
  }
}

/// The audit screen's state: one query, its page, and the filters that produced
/// it.
///
/// A `Cubit` rather than a `Bloc`, unlike the log feed next door: there is no
/// subscription to open and close here, and "the filter changed" is a plain
/// method call rather than a transition that has to be ordered against a live
/// stream.
class AuditCubit extends Cubit<AuditState> {
  final QueryAuditLog _query;

  AuditCubit(this._query) : super(const AuditState());

  /// Reads the newest page for the current filter, from the beginning.
  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    final result = await _query.first(filter: state.filter);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loading: false,
          loaded: true,
          entries: page.items,
          cursor: page.nextCursor,
          auditRetentionDays: page.auditRetentionDays,
          authEventRetentionDays: page.authEventRetentionDays,
          failure: null,
        ),
      ),
    );
  }

  /// Replaces the filter and starts over.
  ///
  /// Always from the first page: the cursor belongs to the query that produced
  /// it, and continuing it across a changed filter would page through a
  /// question nobody asked (`specs/admin-client-audit-log`).
  Future<void> applyFilter(AuditFilter filter) async {
    if (filter == state.filter) return;
    emit(state.copyWith(filter: filter, cursor: null, entries: const []));
    await load();
  }

  Future<void> clearFilters() => applyFilter(const AuditFilter());

  /// Appends the next, older page.
  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (cursor == null || state.loadingMore || state.loading) return;

    emit(state.copyWith(loadingMore: true));
    final result = await _query.more(cursor: cursor, filter: state.filter);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loadingMore: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loadingMore: false,
          entries: [...state.entries, ...page.items],
          cursor: page.nextCursor,
          auditRetentionDays: page.auditRetentionDays,
          authEventRetentionDays: page.authEventRetentionDays,
        ),
      ),
    );
  }
}
