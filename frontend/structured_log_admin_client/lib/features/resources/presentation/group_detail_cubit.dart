import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../application/manage_resources.dart';

part 'group_detail_cubit.freezed.dart';

@freezed
abstract class GroupDetailState with _$GroupDetailState {
  const factory GroupDetailState({
    @Default(true) bool loading,
    @Default(<ProjectDto>[]) List<ProjectDto> projects,
    @Default(false) bool creating,
    ApiFailure? failure,
    ApiFailure? createFailure,
    @Default(false) bool created,
  }) = _GroupDetailState;

  const GroupDetailState._();

  bool get isEmpty => !loading && projects.isEmpty && failure == null;
}

/// One group's projects.
///
/// Teams and role assignments are on the artboard beside them and are not
/// here: the server has no endpoints for either in this stage
/// (design.md «Delivery Phases»), so a screen offering them would be offering
/// nothing.
class GroupDetailCubit extends Cubit<GroupDetailState> {
  final ManageProjects _projects;
  final int groupId;

  GroupDetailCubit({required ManageProjects projects, required this.groupId})
    : _projects = projects,
      super(const GroupDetailState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    final result = await _projects.inGroup(groupId);
    if (isClosed) return;
    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (projects) => emit(
        state.copyWith(loading: false, projects: projects, failure: null),
      ),
    );
  }

  Future<void> create({
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  }) async {
    if (state.creating) return;
    emit(state.copyWith(creating: true, createFailure: null, created: false));
    final result = await _projects.create(
      groupId: groupId,
      name: name,
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(creating: false, createFailure: failure)),
      (_) async {
        emit(state.copyWith(creating: false, created: true));
        await load();
      },
    );
  }

  void dialogClosed() =>
      emit(state.copyWith(created: false, createFailure: null));
}
