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

    /// The groups shown are the newest few, not all of them; this says
    /// whether the groups screen has more to offer.
    @Default(false) bool moreGroups,

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

  /// How many group cards the overview shows. The dashboard is a glance, not
  /// the list: the groups screen pages through the rest.
  static const groupCardCount = 6;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    // Only as many as there are cards: the server's newest first, and no
    // request for the rest of the table to throw most of it away.
    final groupsResult = await _groups.list(limit: groupCardCount);
    final projectsResult = await _projects.search(limit: projectCardCount);
    if (isClosed) return;

    await groupsResult.match(
      (failure) async => emit(state.copyWith(loading: false, failure: failure)),
      (groups) async {
        final candidates = projectsResult.match(
          (_) => const <ProjectDto>[],
          (page) => page.items,
        );
        final projects = await _withUsage(candidates);
        if (isClosed) return;
        emit(
          state.copyWith(
            loading: false,
            groups: groups.items,
            moreGroups: groups.hasMore,
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
