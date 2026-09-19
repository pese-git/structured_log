import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../application/manage_resources.dart';

part 'groups_cubit.freezed.dart';

@freezed
abstract class GroupsState with _$GroupsState {
  const factory GroupsState({
    @Default(true) bool loading,
    @Default(<GroupDto>[]) List<GroupDto> groups,

    /// Where the next page of groups starts; `null` once the last one is in.
    String? cursor,
    @Default(false) bool loadingMore,

    /// A create is in flight. Separate from [loading] so the list stays on
    /// screen while the dialog works.
    @Default(false) bool creating,

    ApiFailure? failure,

    /// Why the last create was refused, kept apart from [failure] so the
    /// dialog shows it and the page does not.
    ApiFailure? createFailure,

    /// Set once a create succeeds, so the dialog can close itself.
    @Default(false) bool created,
  }) = _GroupsState;

  const GroupsState._();

  /// Loaded, and there is nothing in it — as opposed to still loading, or
  /// having failed, which the screen says differently.
  bool get isEmpty => !loading && groups.isEmpty && failure == null;

  bool get hasMore => cursor != null;
}

class GroupsCubit extends Cubit<GroupsState> {
  final ManageGroups _groups;

  /// The server's own default, passed explicitly so a reader of this file
  /// does not have to know it to follow [loadMore].
  static const _pageSize = 50;

  GroupsCubit(this._groups) : super(const GroupsState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    final result = await _groups.list(limit: _pageSize);
    if (isClosed) return;
    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loading: false,
          groups: page.items,
          cursor: page.nextCursor,
          failure: null,
        ),
      ),
    );
  }

  /// The next, older page, appended to what is shown.
  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (cursor == null || state.loadingMore || state.loading) return;

    emit(state.copyWith(loadingMore: true));
    final result = await _groups.list(limit: _pageSize, cursor: cursor);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loadingMore: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loadingMore: false,
          groups: [...state.groups, ...page.items],
          cursor: page.nextCursor,
        ),
      ),
    );
  }

  Future<void> create(String name) async {
    if (state.creating) return;
    emit(state.copyWith(creating: true, createFailure: null, created: false));
    final result = await _groups.create(name);
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(creating: false, createFailure: failure)),
      (_) async {
        emit(state.copyWith(creating: false, created: true));
        // The list is re-read rather than appended to: the server decides
        // what this caller may see, and a group created by an administrator
        // is not automatically one they would be shown.
        await load();
      },
    );
  }

  /// Clears the one-shot flags the dialog watches, after it has acted on
  /// them.
  void dialogClosed() =>
      emit(state.copyWith(created: false, createFailure: null));
}
