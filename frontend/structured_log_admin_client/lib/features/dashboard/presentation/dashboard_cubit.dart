import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../resources/application/manage_resources.dart';

part 'dashboard_cubit.freezed.dart';

@freezed
abstract class DashboardState with _$DashboardState {
  const factory DashboardState({
    @Default(true) bool loading,
    @Default(<GroupDto>[]) List<GroupDto> groups,

    /// At most [DashboardCubit.projectCardCount], each with `entryCount`
    /// filled in for the usage bar.
    @Default(<ProjectDto>[]) List<ProjectDto> projects,
    ApiFailure? failure,
  }) = _DashboardState;
}

/// Every group the caller administers, and a handful of projects across them
/// — `Main.dc.html`, the `admin` variant (`DashboardPage`'s doc comment
/// explains why the other two roles the mockup draws are not built).
class DashboardCubit extends Cubit<DashboardState> {
  final ManageGroups _groups;
  final ManageProjects _projects;

  DashboardCubit(this._groups, this._projects) : super(const DashboardState());

  /// How many project cards the mockup draws.
  static const projectCardCount = 3;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    final groupsResult = await _groups.list();
    final projectsResult = await _projects.search();
    if (isClosed) return;

    await groupsResult.match(
      (failure) async => emit(state.copyWith(loading: false, failure: failure)),
      (groups) async {
        final candidates = projectsResult.getOrElse((_) => const []);
        final projects = await _withUsage(
          candidates.take(projectCardCount).toList(),
        );
        if (isClosed) return;
        emit(
          state.copyWith(
            loading: false,
            groups: groups,
            projects: projects,
            failure: null,
          ),
        );
      },
    );
  }

  /// Re-fetches each project one at a time — the list endpoint carries no
  /// usage counters, only [ManageProjects.get] does (same reasoning as
  /// `ProjectDetailPage`). Falls back to the list version of a project that
  /// fails to load its own detail, same as [GroupDetailCubit]'s secondary
  /// sections degrade rather than failing the whole screen.
  Future<List<ProjectDto>> _withUsage(List<ProjectDto> projects) {
    return Future.wait([
      for (final project in projects)
        _projects.get(project.id).then((r) => r.getOrElse((_) => project)),
    ]);
  }
}
